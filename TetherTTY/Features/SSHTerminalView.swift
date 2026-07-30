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
            if lineDelta != 0 {
                indirectScrollAccumulator -= CGFloat(lineDelta) * cellHeight
                if lineDelta > 0 {
                    scrollUp(lines: lineDelta)      // content pulled down → reveal older history
                } else {
                    scrollDown(lines: -lineDelta)   // content pushed up → newer
                }
            }
        default:
            indirectScrollAccumulator = 0
        }
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        onSizeChanged?(newCols, newRows)
    }

    func setTerminalTitle(source: TerminalView, title: String) {}

    func scrolled(source: TerminalView, position: Double) {}

    func clipboardCopy(source: TerminalView, content: Data) {
        if let str = String(data: content, encoding: .utf8) {
            UIPasteboard.general.string = str
        }
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        if let url = URL(string: link) {
            UIApplication.shared.open(url)
        }
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
