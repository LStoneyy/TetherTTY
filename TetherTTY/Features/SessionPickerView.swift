import SwiftUI

struct SessionPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: SessionPickerViewModel

    let onSelect: (TerminalConnectionRequest) -> Void

    init(
        request: TerminalConnectionRequest,
        onSelect: @escaping (TerminalConnectionRequest) -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: SessionPickerViewModel(request: request)
        )
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    if viewModel.isLoading {
                        loadingState
                    } else if let errorMessage = viewModel.errorMessage, viewModel.tmuxSessions.isEmpty && viewModel.herdrSessions.isEmpty {
                        errorState(message: errorMessage)
                    } else {
                        if !viewModel.tmuxSessions.isEmpty {
                            sectionHeader(title: "Tmux Sessions")
                            ForEach(viewModel.tmuxSessions) { session in
                                sessionCard(for: session)
                            }
                        }

                        if let diagnostic = viewModel.tmuxDiagnostic {
                            diagnosticBanner(message: diagnostic, provider: "tmux")
                        }

                        if !viewModel.herdrSessions.isEmpty {
                            sectionHeader(title: "Herdr Sessions")
                            ForEach(viewModel.herdrSessions) { session in
                                sessionCard(for: session)
                            }
                        }

                        if let diagnostic = viewModel.herdrDiagnostic {
                            diagnosticBanner(message: diagnostic, provider: "Herdr")
                        }

                        if let herdrError = viewModel.herdrErrorMessage {
                            herdrErrorBanner(message: herdrError)
                        }

                        if viewModel.tmuxSessions.isEmpty && viewModel.herdrSessions.isEmpty {
                            emptyState
                        }

                        plainShellSection
                    }
                }
                .padding(20)
                .padding(.top, 8)
            }
            .background(AbyssBackground())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundStyle(AbyssalTheme.pearlAqua)
                }
            }
        }
        .task {
            await viewModel.fetchSessions()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Session Picker")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(AbyssalTheme.mintLeaf)
                .textCase(.uppercase)
                .tracking(1.8)

            Text("Choose a session")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(AbyssalTheme.bone)

            Text("Select a tmux or Herdr session to attach or open a plain shell.")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(AbyssalTheme.bone.opacity(0.68))
        }
    }

    private var loadingState: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(AbyssalTheme.pearlAqua.opacity(0.42), lineWidth: 1)
                Circle()
                    .stroke(AbyssalTheme.mintLeaf.opacity(0.72), lineWidth: 2)
                    .padding(10)
                Image(systemName: ConnectionPhase.loadingSessions.symbol)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(AbyssalTheme.pearlAqua)
            }
            .frame(width: 72, height: 72)

            ProgressView()
                .tint(AbyssalTheme.pacificCyan)

            VStack(spacing: 6) {
                Text(ConnectionPhase.loadingSessions.title)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(AbyssalTheme.bone)

                if let detail = ConnectionPhase.loadingSessions.detail {
                    Text(detail)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(AbyssalTheme.bone.opacity(0.6))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private func errorState(message: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Discovery failed")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(AbyssalTheme.emberWarning)

            Text(message)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(AbyssalTheme.bone.opacity(0.72))

            sessionCard(for: .plainShellSession)
        }
        .padding(16)
        .background(AbyssCardBackground())
    }

    private func sectionHeader(title: String) -> some View {
        Text(title)
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .foregroundStyle(AbyssalTheme.bone.opacity(0.62))
            .textCase(.uppercase)
            .tracking(1.2)
    }

    private var plainShellSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Fallback")
            sessionCard(for: .plainShellSession)
        }
    }

    private func diagnosticBanner(message: String, provider: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(AbyssalTheme.pacificCyan)

            Text("\(provider): \(message)")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(AbyssalTheme.bone.opacity(0.55))
        }
        .padding(10)
        .background(AbyssCardBackground())
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Text("Keine Sessions gefunden")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(AbyssalTheme.bone.opacity(0.55))

            if viewModel.tmuxDiagnostic != nil || viewModel.herdrDiagnostic != nil {
                Text("Weitere Informationen oben.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(AbyssalTheme.bone.opacity(0.4))
            }

            Button {
                Task { await viewModel.fetchSessions() }
            } label: {
                Label("Erneut versuchen", systemImage: "arrow.clockwise")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(AbyssalTheme.pacificCyan)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func herdrErrorBanner(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12))
                .foregroundStyle(AbyssalTheme.emberWarning)

            Text("Herdr discovery: \(message)")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(AbyssalTheme.bone.opacity(0.62))
        }
        .padding(10)
        .background(AbyssCardBackground())
    }

    private func sessionCard(for session: TerminalSession) -> some View {
        Button {
            let request = viewModel.makeTerminalRequest(for: session)
            onSelect(request)
        } label: {
            HStack(spacing: 14) {
                Circle()
                    .fill(iconTint(for: session))
                    .frame(width: 10, height: 10)
                    .shadow(color: iconTint(for: session).opacity(0.5), radius: 10)

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.displayName)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(AbyssalTheme.bone)

                    Text(session.detail)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(AbyssalTheme.bone.opacity(0.58))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AbyssalTheme.pacificCyan)
            }
            .padding(18)
            .background(AbyssCardBackground())
        }
        .buttonStyle(.plain)
    }

    private func iconTint(for session: TerminalSession) -> Color {
        switch session.provider {
        case .tmux:
            AbyssalTheme.mintLeaf
        case .herdr:
            AbyssalTheme.emberWarning
        case .plainShell:
            AbyssalTheme.pacificCyan
        }
    }
}
