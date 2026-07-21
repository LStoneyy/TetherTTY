import SwiftUI

struct PlainTerminalView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: PlainTerminalViewModel

    @State private var showKeyboard = false

    let onReconnect: ((TerminalConnectionRequest) -> Void)?
    private let terminal = SSHTerminalView(frame: .zero)

    init(
        request: TerminalConnectionRequest,
        onReconnect: ((TerminalConnectionRequest) -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: PlainTerminalViewModel(request: request))
        self.onReconnect = onReconnect
    }

    var body: some View {
        VStack(spacing: 0) {
            TerminalStatusBar(state: viewModel.state, showKeyboard: $showKeyboard) {
                Task {
                    await viewModel.disconnect()
                    dismiss()
                }
            }

            TerminalViewRepresentable(terminal: terminal)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.04, green: 0.04, blue: 0.08))

            if viewModel.state == .disconnected {
                disconnectedFooter
            }
        }
        .onAppear { wireTerminal() }
        .onChange(of: viewModel.state) { _, newState in
            if newState == .terminalOpen, let session = viewModel.session {
                wireSessionOutput(session)
            }
        }
        .onChange(of: showKeyboard) { _, visible in
            if visible {
                terminal.becomeFirstResponder()
            } else {
                terminal.resignFirstResponder()
            }
        }
        .task {
            await viewModel.connect()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            showKeyboard = false
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            showKeyboard = true
        }
    }

    private func wireTerminal() {
        terminal.onSend = { [weak viewModel] bytes in
            viewModel?.sendBytes(bytes)
        }
    }

    private func wireSessionOutput(_ session: SSHSession?) {
        guard var session else { return }
        var feedCount = 0
        session.onOutput = { [weak terminal] bytes in
            feedCount += 1
            if feedCount <= 5 { print("[Terminal] feed #\(feedCount): \(bytes.count) bytes") }
            terminal?.feed(byteArray: ArraySlice(bytes))
        }
        terminal.onSizeChanged = { cols, rows in
            Task { @MainActor in
                await session.resize(cols: cols, rows: rows)
            }
        }
        let current = terminal.getTerminal()
        if current.cols > 0, current.rows > 0 {
            Task { @MainActor in
                await session.resize(cols: current.cols, rows: current.rows)
            }
        }
    }

    private var disconnectedFooter: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 13))
                    .foregroundStyle(AbyssalTheme.emberWarning)

                Text("Connection closed. Terminal input is no longer live.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(AbyssalTheme.bone.opacity(0.72))
            }

            HStack(spacing: 12) {
                Button {
                    let reconnectRequest = viewModel.makeReconnectRequest()
                    Task { await viewModel.disconnect() }
                    dismiss()
                    onReconnect?(reconnectRequest)
                } label: {
                    Label("Reconnect", systemImage: "arrow.clockwise")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(AbyssalTheme.abyss)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(AbyssalTheme.mintLeaf))
                }

                Button {
                    dismiss()
                } label: {
                    Text("Close")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(AbyssalTheme.pearlAqua)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Capsule().stroke(AbyssalTheme.pearlAqua.opacity(0.42), lineWidth: 1))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(AbyssalTheme.deepSpaceBlue)
    }
}

private struct TerminalStatusBar: View {
    let state: TerminalConnectionState
    @Binding var showKeyboard: Bool
    let close: () -> Void

    var body: some View {
        HStack {
            Circle()
                .fill(tint)
                .frame(width: 9, height: 9)
                .shadow(color: tint.opacity(0.6), radius: 8)

            Text(state.title)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(AbyssalTheme.bone)

            if case .failed(let message) = state {
                Text(message)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(AbyssalTheme.emberWarning)
                    .lineLimit(1)
            }

            Spacer()

            if state == .terminalOpen {
                Button {
                    showKeyboard.toggle()
                } label: {
                    Image(systemName: "keyboard")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(showKeyboard ? AbyssalTheme.mintLeaf : AbyssalTheme.pearlAqua)
                }

                Button("Close", action: close)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(AbyssalTheme.pearlAqua)
            } else {
                Button("Close", action: close)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(AbyssalTheme.pearlAqua)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AbyssalTheme.deepSpaceBlue)
    }

    private var tint: Color {
        switch state {
        case .terminalOpen: AbyssalTheme.mintLeaf
        case .failed: AbyssalTheme.bloodError
        case .disconnected: AbyssalTheme.emberWarning
        default: AbyssalTheme.pacificCyan
        }
    }
}

