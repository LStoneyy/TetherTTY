import SwiftUI
import SwiftTerm

final class SSHTerminalView: TerminalView, TerminalViewDelegate {
    var onSizeChanged: ((Int, Int) -> Void)?
    var onSend: (([UInt8]) -> Void)?

    private var scrollReconcilePending = false
    private var indirectScrollAccumulator: CGFloat = 0

    private static let terminalBg = UIColor(red: 0.04, green: 0.04, blue: 0.08, alpha: 1.0)
    private static let terminalFg = UIColor(red: 0.95, green: 0.95, blue: 0.90, alpha: 1.0)

    private lazy var indirectScrollGesture: UIPanGestureRecognizer = {
        let gesture = UIPanGestureRecognizer(target: self, action: #selector(handleIndirectScroll(_:)))
        gesture.allowedScrollTypesMask = .all
        gesture.maximumNumberOfTouches = 0
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

    @objc private func handleIndirectScroll(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            indirectScrollAccumulator = 0
        case .changed:
            let rows = max(1, getTerminal().rows)
            let cellHeight = bounds.height / CGFloat(rows)
            guard cellHeight > 0 else { return }
            indirectScrollAccumulator += gesture.translation(in: self).y
            gesture.setTranslation(.zero, in: self)
            let lineDelta = Int(indirectScrollAccumulator / cellHeight)
            guard lineDelta != 0 else { return }
            indirectScrollAccumulator -= CGFloat(lineDelta) * cellHeight

            let terminal = getTerminal()
            if terminal.isCurrentBufferAlternate {
                // The alternate screen buffer (herdr, vim, less, htop, …) has no local
                // scrollback, so scrolling it locally does nothing. Translate the scroll
                // into arrow-key presses for the running full-screen app instead.
                sendScrollAsArrowKeys(lineDelta: lineDelta, applicationCursor: terminal.applicationCursor)
            } else if lineDelta > 0 {
                scrollUp(lines: lineDelta)      // content pulled down → reveal older history
            } else {
                scrollDown(lines: -lineDelta)   // content pushed up → newer
            }
        default:
            indirectScrollAccumulator = 0
        }
    }

    private func sendScrollAsArrowKeys(lineDelta: Int, applicationCursor: Bool) {
        let count = min(abs(lineDelta), 40)   // cap to avoid flooding on a fast flick
        guard count > 0 else { return }
        let sequence: [UInt8] = lineDelta > 0
            ? (applicationCursor ? EscapeSequences.moveUpApp : EscapeSequences.moveUpNormal)
            : (applicationCursor ? EscapeSequences.moveDownApp : EscapeSequences.moveDownNormal)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(sequence.count * count)
        for _ in 0..<count {
            bytes.append(contentsOf: sequence)
        }
        send(bytes)
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
