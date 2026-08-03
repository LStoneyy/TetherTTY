import SwiftUI
import SwiftTerm

final class SSHTerminalView: TerminalView, TerminalViewDelegate, UIGestureRecognizerDelegate {
    var onSizeChanged: ((Int, Int) -> Void)?
    var onSend: (([UInt8]) -> Void)?

    private var scrollReconcilePending = false
    private var indirectScrollAccumulator = ScrollTranslationAccumulator()

    private static let terminalBg = UIColor(red: 0.04, green: 0.04, blue: 0.08, alpha: 1.0)
    private static let terminalFg = UIColor(red: 0.95, green: 0.95, blue: 0.90, alpha: 1.0)

    lazy var indirectScrollGesture: UIPanGestureRecognizer = {
        let gesture = UIPanGestureRecognizer(target: self, action: #selector(handleIndirectScroll(_:)))
        gesture.allowedScrollTypesMask = .all
        gesture.delegate = self
        return gesture
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        terminalDelegate = self
        font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        nativeBackgroundColor = Self.terminalBg
        layer.backgroundColor = Self.terminalBg.cgColor
        nativeForegroundColor = Self.terminalFg
        addGestureRecognizer(indirectScrollGesture)
        // Veto a stale text selection the moment a real scroll begins. On the
        // iPhone a swipe that starts on selected text otherwise leaves
        // SwiftTerm's selection-drag machinery extending the selection instead
        // of scrolling — most visible in alternate-buffer sessions (herdr,
        // vim, …). The pan that actually scrolls gets the hook: the inherited
        // native pan in the normal buffer, and the indirect pan in the
        // alternate buffer. Tap selection remains available; pan gestures in
        // the alternate buffer deliberately prioritize scrolling.
        panGestureRecognizer.addTarget(self, action: #selector(handleNativePanBegan(_:)))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.backgroundColor = Self.terminalBg.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        onSend?(Array(data))
    }

    func feedOutput(_ bytes: [UInt8]) {
        feed(byteArray: ArraySlice(bytes))
        scheduleScrollReconcile()
    }

    private func scheduleScrollReconcile() {
        guard !scrollReconcilePending else { return }
        scrollReconcilePending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.scrollReconcilePending = false
            self.reconcileScroll()
        }
    }

    private func reconcileScroll() {
        guard !isTracking, !isDragging, !isDecelerating else { return }
        let yDisp = getTerminal().buffer.yDisp
        scrollTo(row: yDisp, notifyAccessibility: false)
        setNeedsDisplay(bounds)
    }

    // Buffer-aware gesture admission for the indirect-scroll recognizer.
    //
    // UIKit calls `shouldReceive` for every *direct* touch targeting a
    // recognizer; indirect scroll input (trackpad/wheel) carries no `UITouch`,
    // so it never reaches this hook and remains admitted by the custom pan.
    //
    // - Direct touch in the normal buffer is rejected so SwiftTerm's inherited
    //   UIScrollView pan handles native scrolling exclusively and we never
    //   double-scroll.
    // - Direct touch in the alternate buffer (herdr, vim, less, htop, …) is
    //   admitted so the swipe always reaches our translation path: arrow keys
    //   while the terminal is not reporting mouse input, SGR/X10 wheel events
    //   while it is. An admitted alternate-buffer touch also wires SwiftTerm's
    //   competing pans to wait on the indirect pan — the mouse-drag pan when
    //   mouse reporting is active, the selection pan when it is not — so
    //   neither can win the touch before translation runs (see
    //   `makeExtraPansWaitForIndirectScroll`).
    // - Every other recognizer is left unaffected (mirrors UIView's default
    //   acceptance).
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === indirectScrollGesture else {
            return true
        }
        let terminal = getTerminal()
        let mouseActive = terminal.mouseMode != .off
        guard Self.shouldAdmitDirectTouch(isAlternateBuffer: terminal.isCurrentBufferAlternate) else { return false }
        // Direct touch is being admitted (alternate buffer): make SwiftTerm's
        // competing pan wait on the real scroll recognizer.
        Self.makeExtraPansWaitForIndirectScroll(in: self, requireMouseActive: mouseActive)
        return true
    }

    /// Pure admission policy for direct touches on the indirect-scroll
    /// recognizer. Indirect scroll events bypass this check entirely (no
    /// `UITouch` is delivered), so they are always admitted by the custom pan.
    /// Any alternate-buffer touch is admitted regardless of mouse mode; the
    /// normal buffer always rejects direct touch so the native pan scrolls
    /// exclusively.
    static func shouldAdmitDirectTouch(isAlternateBuffer: Bool) -> Bool {
        isAlternateBuffer
    }

    /// Whether a pan's `velocity` (points/sec) should be classified as a
    /// vertical scroll. Ties are admitted (`>=`) to bias toward keeping
    /// vertical scrolling reliable. An exact `.zero` velocity is rejected:
    /// `gestureRecognizerShouldBegin` is consulted only as a recognizer
    /// transitions out of `.possible`, where velocity is normally available,
    /// but an exact zero at UIKit startup must not let the pan swallow a tap —
    /// a pan needs movement to be meaningful.
    static func isVerticalScrollVelocity(_ velocity: CGPoint) -> Bool {
        guard velocity != .zero else { return false }
        return abs(velocity.y) >= abs(velocity.x)
    }

    /// Makes SwiftTerm's dynamically-installed pans wait for the
    /// indirect-scroll recognizer to fail before they recognize. SwiftTerm's
    /// pans have no delegate and no failure requirement, so in the alternate
    /// buffer they could otherwise win a direct touch that should scroll,
    /// leaving the indirect pan stuck in `.possible` and the swipe neither
    /// scrolling nor translating to input.
    ///
    /// - `requireMouseActive == true`: mouse reporting owns the touch, so every
    ///   extra pan (SwiftTerm's mouse-drag pan, and any selection pan) is wired
    ///   to yield — the swipe must reach the wheel-translation path.
    /// - `requireMouseActive == false`: the mouse-off path preserves the
    ///   existing active-selection arbitration — only an active selection pan
    ///   is wired, and only while the terminal reports no mouse input, so taps
    ///   and long-press selection are untouched.
    ///
    /// Uses the public `require(toFail:)` API — the only public UIKit
    /// mechanism that guarantees one pan wins over a competing pan.
    ///
    /// Returns the recognizers that were wired, for tests.
    @discardableResult
    static func makeExtraPansWaitForIndirectScroll(in view: SSHTerminalView, requireMouseActive: Bool) -> [UIPanGestureRecognizer] {
        let terminal = view.getTerminal()
        guard terminal.isCurrentBufferAlternate else { return [] }
        if requireMouseActive {
            guard terminal.mouseMode != .off else { return [] }
        } else {
            guard terminal.mouseMode == .off, view.hasActiveSelection else { return [] }
        }
        let candidates = (view.gestureRecognizers ?? [])
            .compactMap { $0 as? UIPanGestureRecognizer }
            .filter { $0 !== view.panGestureRecognizer && $0 !== view.indirectScrollGesture }
        for candidate in candidates {
            candidate.require(toFail: view.indirectScrollGesture)
        }
        return candidates
    }

    // Only the custom pan and SwiftTerm's inherited scroll pan may recognize
    // simultaneously, in either argument order, and only in the alternate
    // buffer. That lets an alternate-buffer direct touch drive the arrow-key
    // translation path while the native pan still tracks it. In the normal
    // buffer it stays false so an indirect trackpad/wheel cannot drive both
    // the native scroll and the custom path at once; every other pairing also
    // stays false (mirroring UIView's default).
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        let nativePan = panGestureRecognizer
        let isNativePair =
            (gestureRecognizer === indirectScrollGesture && otherGestureRecognizer === nativePan) ||
            (gestureRecognizer === nativePan && otherGestureRecognizer === indirectScrollGesture)
        return isNativePair && getTerminal().isCurrentBufferAlternate
    }

    // Begin gate for the indirect-scroll recognizer: only predominantly
    // vertical pans may begin, so a horizontal drag fails the custom pan and
    // SwiftTerm's mouse pan (which waits on it via `require(toFail:)`) can
    // proceed instead — no silent horizontal dead zone. Every unrelated
    // recognizer is left unaffected (mirrors UIView's default acceptance).
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === indirectScrollGesture else {
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }
        return Self.isVerticalScrollVelocity(indirectScrollGesture.velocity(in: self))
    }

    /// Target for the inherited UIScrollView pan — the normal-buffer scroll
    /// path. Gated to `.began` so a swipe that has committed to scrolling
    /// clears any stale text selection (see `clearSelectionForScrollStart`).
    /// The alternate-buffer path clears its selection in
    /// `handleIndirectScroll` instead.
    @objc private func handleNativePanBegan(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .began else { return }
        clearSelectionForScrollStart()
    }

    /// Clears the active text selection if one exists. Internal seam
    /// exercised directly by `SSHTerminalViewScrollTests` — there is no
    /// public way to synthesize the physical touch stream UIKit needs to
    /// drive the real `.began` transition on a recognizer.
    func clearSelectionForScrollStart() {
        if hasActiveSelection {
            clearSelection()
        }
    }

    @objc private func handleIndirectScroll(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            indirectScrollAccumulator.reset()
            // A swipe that commits to scrolling must not keep extending a
            // stale selection, otherwise arrow-key translation fights
            // SwiftTerm's selection-drag state (see `clearSelectionForScrollStart`).
            clearSelectionForScrollStart()
        case .changed:
            let rows = max(1, getTerminal().rows)
            let cellHeight = bounds.height / CGFloat(rows)
            guard cellHeight > 0 else { return }
            let translation = gesture.translation(in: self).y
            gesture.setTranslation(.zero, in: self)
            let lineDelta = indirectScrollAccumulator.consume(translation: translation, cellHeight: cellHeight)
            guard lineDelta != 0 else { return }

            let terminal = getTerminal()
            if terminal.isCurrentBufferAlternate {
                if terminal.mouseMode == .off {
                    // The alternate screen buffer (herdr, vim, less, htop, …) has no local
                    // scrollback, so scrolling it locally does nothing. Without mouse
                    // reporting, translate the scroll into arrow-key presses for the
                    // running full-screen app instead.
                    sendScrollAsArrowKeys(lineDelta: lineDelta, applicationCursor: terminal.applicationCursor)
                } else {
                    // The app is receiving mouse input, so translate the scroll into
                    // SGR/X10 wheel events at the touch location instead.
                    sendScrollAsMouseWheel(lineDelta: lineDelta, location: gesture.location(in: self))
                }
            } else if lineDelta > 0 {
                scrollUp(lines: lineDelta)      // content pulled down → reveal older history
            } else {
                scrollDown(lines: -lineDelta)   // content pushed up → newer
            }
        default:
            indirectScrollAccumulator.reset()
        }
    }

    private func sendScrollAsArrowKeys(lineDelta: Int, applicationCursor: Bool) {
        let bytes = Self.arrowKeySequence(lineDelta: lineDelta, applicationCursor: applicationCursor)
        guard !bytes.isEmpty else { return }
        send(bytes)
    }

    /// Translates a scrolled `lineDelta` (positive = up) into SGR/X10 mouse
    /// wheel events for the running alternate-buffer app. Each event is emitted
    /// at the view-space `location`, repeated by the capped magnitude.
    func sendScrollAsMouseWheel(lineDelta: Int, location: CGPoint) {
        let magnitude = Self.cappedScrollMagnitude(lineDelta)
        guard magnitude > 0 else { return }
        let terminal = getTerminal()
        guard let cell = Self.cellLocation(for: location, in: bounds, cols: terminal.cols, rows: terminal.rows) else {
            return
        }
        let buttonFlags = terminal.encodeButton(button: lineDelta > 0 ? 4 : 5, release: false, shift: false, meta: false, control: false)
        for _ in 0..<magnitude {
            // SwiftTerm's `sendEvent` adds 1 to the 0-based cell itself.
            terminal.sendEvent(buttonFlags: buttonFlags, x: cell.x, y: cell.y)
        }
    }

    /// Computes the 0-based cell (col, row) for a view-space `point`, clamped to
    /// the visible grid. Returns nil when the dimensions or bounds are unusable
    /// (zero or non-finite), so callers can skip emitting.
    static func cellLocation(for point: CGPoint, in bounds: CGRect, cols: Int, rows: Int) -> (x: Int, y: Int)? {
        guard cols > 0, rows > 0,
              bounds.width > 0, bounds.height > 0,
              bounds.width.isFinite, bounds.height.isFinite,
              point.x.isFinite, point.y.isFinite else { return nil }
        let cellWidth = bounds.width / CGFloat(cols)
        let cellHeight = bounds.height / CGFloat(rows)
        let col = min(max(Int(point.x / cellWidth), 0), cols - 1)
        let row = min(max(Int(point.y / cellHeight), 0), rows - 1)
        return (col, row)
    }

    /// Caps a scroll delta's magnitude to 40 events, matching the arrow-key
    /// flood cap. The magnitude is capped by sign before any negation so
    /// extreme values like `Int.min` cannot overflow; a zero delta yields zero.
    static func cappedScrollMagnitude(_ lineDelta: Int) -> Int {
        guard lineDelta != 0 else { return 0 }
        if lineDelta < 0 {
            return lineDelta == Int.min ? 40 : min(-lineDelta, 40)
        }
        return min(lineDelta, 40)
    }

    /// Builds the repeated arrow-key byte stream for a scroll of `lineDelta`
    /// rows (positive = up). The repetition count is capped via
    /// `cappedScrollMagnitude` to avoid flooding on a fast flick.
    static func arrowKeySequence(lineDelta: Int, applicationCursor: Bool) -> [UInt8] {
        let cappedMagnitude = Self.cappedScrollMagnitude(lineDelta)
        guard cappedMagnitude > 0 else { return [] }
        let sequence: [UInt8] = lineDelta > 0
            ? (applicationCursor ? EscapeSequences.moveUpApp : EscapeSequences.moveUpNormal)
            : (applicationCursor ? EscapeSequences.moveDownApp : EscapeSequences.moveDownNormal)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(sequence.count * cappedMagnitude)
        for _ in 0..<cappedMagnitude {
            bytes.append(contentsOf: sequence)
        }
        return bytes
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        onSizeChanged?(newCols, newRows)
    }

    func setTerminalTitle(source: TerminalView, title: String) {}

    func scrolled(source: TerminalView, position: Double) {}

    // SEC-03: OSC 52 lets the remote (or anything echoed to the terminal) write
    // arbitrary content to the system pasteboard. We intentionally do not wire
    // this up to `UIPasteboard` at all — this is a pure no-op.
    func clipboardCopy(source: TerminalView, content: Data) {}

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        guard let url = Self.allowedURL(forLink: link) else { return }
        UIApplication.shared.open(url)
    }

    // SEC-08: only allow opening links whose scheme is exactly `https`
    // (case-insensitive). This rejects `http`, `file`, `javascript:`, `tel:`,
    // and any other custom scheme. Pure and testable without invoking
    // `UIApplication.shared.open`. SwiftTerm already requires an explicit user
    // tap to trigger this, so there is no auto-open concern.
    static func allowedURL(forLink link: String) -> URL? {
        guard let url = URL(string: link), let scheme = url.scheme else { return nil }
        guard scheme.lowercased() == "https" else { return nil }
        return url
    }

    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

    func bell(source: TerminalView) {}

    func clipboardRead(source: TerminalView) -> Data? { nil }

    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
}

struct TerminalViewRepresentable: UIViewRepresentable {
    let terminal: SSHTerminalView

    func makeUIView(context: Context) -> SSHTerminalView {
        terminal
    }

    func updateUIView(_ uiView: SSHTerminalView, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: SSHTerminalView, context: Context) -> CGSize? {
        nil
    }
}

/// Accumulates a scroll gesture's sub-cell translation into whole-row deltas,
/// carrying the fractional remainder across events.
struct ScrollTranslationAccumulator {
    private(set) var remainder: CGFloat = 0

    /// Adds `translation` (in points) and returns how many whole `cellHeight`
    /// rows were crossed, keeping the leftover fraction for the next event.
    /// Callers must guarantee a positive, finite `cellHeight` and a finite
    /// `translation` (the live caller guards `cellHeight` and reads
    /// `translation` straight from the gesture recognizer).
    mutating func consume(translation: CGFloat, cellHeight: CGFloat) -> Int {
        precondition(cellHeight > 0 && cellHeight.isFinite && translation.isFinite)
        let accumulated = remainder + translation
        let lineDelta = Int(accumulated / cellHeight)
        remainder = accumulated - CGFloat(lineDelta) * cellHeight
        return lineDelta
    }

    mutating func reset() {
        remainder = 0
    }
}
