import SwiftUI

struct PlainTerminalView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: PlainTerminalViewModel

    let onReconnect: ((TerminalConnectionRequest) -> Void)?

    init(
        request: TerminalConnectionRequest,
        onReconnect: ((TerminalConnectionRequest) -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: PlainTerminalViewModel(request: request))
        self.onReconnect = onReconnect
    }

    private var transcriptText: String {
        if !viewModel.transcript.isEmpty {
            return viewModel.transcript
        }
        switch viewModel.state {
        case .idle, .connecting:
            return "Connecting..."
        case .authenticating:
            return "Authenticating..."
        case .terminalOpen:
            return "Terminal open."
        case .disconnected:
            return "Connection closed."
        case .failed(let message):
            return "Connection failed: \(message)"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TerminalStatusBar(state: viewModel.state) {
                Task {
                    await viewModel.disconnect()
                    dismiss()
                }
            }

            ScrollView {
                Text(transcriptText)
                    .font(.system(size: 14, weight: .regular, design: .monospaced))
                    .foregroundStyle(AbyssalTheme.bone)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .textSelection(.enabled)
            }
            .background(AbyssalTheme.abyss)

            if viewModel.state == .disconnected {
                disconnectedFooter
            } else {
                TerminalInputBar(viewModel: viewModel)
            }
        }
        .background(AbyssalTheme.abyss)
        .task {
            await viewModel.connect()
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

            Button("Close", action: close)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(AbyssalTheme.pearlAqua)
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

private struct TerminalInputBar: View {
    @ObservedObject var viewModel: PlainTerminalViewModel

    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TerminalSpecialKey.allCases) { key in
                        Button(key.rawValue) {
                            viewModel.sendSpecialKey(key)
                        }
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(AbyssalTheme.pearlAqua)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().stroke(AbyssalTheme.pacificCyan.opacity(0.42), lineWidth: 1))
                    }
                }
                .padding(.horizontal, 12)
            }

            HStack(spacing: 10) {
                TextField("Command", text: $viewModel.input)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(AbyssalTheme.bone)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(AbyssalTheme.abyss.opacity(0.72)))

                Button("Send") {
                    Task { await viewModel.sendCurrentInput() }
                }
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(AbyssalTheme.abyss)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Capsule().fill(AbyssalTheme.mintLeaf))
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 10)
        .background(AbyssalTheme.deepSpaceBlue)
    }
}
