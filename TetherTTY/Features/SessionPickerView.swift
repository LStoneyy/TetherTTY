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
                    } else if let errorMessage = viewModel.errorMessage, tmuxSessions.isEmpty && herdrSessions.isEmpty {
                        errorState(message: errorMessage)
                    } else {
                        if !tmuxSessions.isEmpty {
                            sectionHeader(title: "Tmux Sessions")
                            ForEach(tmuxSessions) { session in
                                sessionCard(for: session)
                            }
                        }

                        if !herdrSessions.isEmpty {
                            sectionHeader(title: "Herdr Sessions")
                            ForEach(herdrSessions) { session in
                                sessionCard(for: session)
                            }
                        }

                        if let herdrError = viewModel.herdrErrorMessage {
                            herdrErrorBanner(message: herdrError)
                        }

                        plainShellSection
                    }
                }
                .padding(20)
                .padding(.top, 8)
            }
            .background(AbyssBackground())
        }
        .task {
            await viewModel.fetchSessions()
        }
    }

    private var tmuxSessions: [TerminalSession] {
        viewModel.sessions.filter {
            if case .tmux = $0.provider { return true }
            return false
        }
    }

    private var herdrSessions: [TerminalSession] {
        viewModel.sessions.filter {
            if case .herdr = $0.provider { return true }
            return false
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
        VStack(spacing: 16) {
            ProgressView()
                .tint(AbyssalTheme.pacificCyan)
            Text("Discovering sessions...")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(AbyssalTheme.bone.opacity(0.66))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
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
