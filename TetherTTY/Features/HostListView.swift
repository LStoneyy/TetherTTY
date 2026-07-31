import SwiftUI

enum TerminalFlowStep: Identifiable, Equatable {
    case sessionPicker(TerminalConnectionRequest)
    case terminal(TerminalConnectionRequest)

    var id: UUID {
        switch self {
        case .sessionPicker(let r): r.id
        case .terminal(let r): r.id
        }
    }
}

struct HostListView: View {
    @StateObject private var viewModel = HostListViewModel()
    @State private var editorDraft: ConnectionDraft?
    @State private var terminalFlow: TerminalFlowStep?
    /// The connection currently being prepared, kept so the progress overlay can show its address
    /// and offer a retry.
    @State private var connectingConnection: Connection?
    /// Handle to the in-flight connect attempt so a new attempt or a cancel can supersede it, and
    /// its stale continuation can bow out without clobbering newer state.
    @State private var connectTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HeaderView()

                    if let errorMessage = viewModel.errorMessage {
                        StatusCard(title: "Vault warning", message: errorMessage, tint: AbyssalTheme.emberWarning)
                    }

                    if viewModel.connections.isEmpty {
                        EmptyHostListView {
                            editorDraft = ConnectionDraft()
                        }
                    } else {
                        ForEach(viewModel.connections) { connection in
                            HostCard(
                                connection: connection,
                                hasPassword: viewModel.hasPassword(for: connection),
                                connect: { startConnect(connection) },
                                edit: { editorDraft = ConnectionDraft(connection: connection) },
                                toggleFavorite: { viewModel.toggleFavorite(connection) },
                                delete: { viewModel.delete(connection) }
                            )
                        }
                    }

                }
                .padding(20)
                .padding(.top, 8)
            }
            .background(AbyssBackground())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editorDraft = ConnectionDraft()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(AbyssalTheme.abyss)
                            .padding(10)
                            .background(Circle().fill(AbyssalTheme.mintLeaf))
                    }
                    .accessibilityLabel("Add Connection")
                }
            }
            .sheet(item: $editorDraft) { draft in
                ConnectionEditorView(initialDraft: draft) { savedDraft in
                    viewModel.save(savedDraft)
                }
            }
            .fullScreenCover(item: $terminalFlow) { step in
                switch step {
                case .sessionPicker(let request):
                    SessionPickerView(request: request) { terminalRequest in
                        self.terminalFlow = .terminal(terminalRequest)
                    }
                case .terminal(let request):
                    PlainTerminalView(
                        request: request,
                        onReconnect: { reconnectRequest in
                            self.terminalFlow = .sessionPicker(reconnectRequest)
                        }
                    )
                }
            }
            .alert(item: $viewModel.hostKeyChallenge) { challenge in
                Alert(
                    title: Text("Trust New Host?"),
                    message: Text("\(challenge.connection.displayAddress) presented fingerprint:\n\n\(challenge.fingerprint)"),
                    primaryButton: .default(Text("Trust")) {
                        if let request = viewModel.trustHostKey(challenge) {
                            terminalFlow = .sessionPicker(request)
                        }
                    },
                    secondaryButton: .cancel {
                        viewModel.cancelHostKeyTrust()
                    }
                )
            }
            .overlay {
                if let phase = viewModel.connectPhase {
                    ConnectionProgressOverlay(
                        symbol: phase.symbol,
                        title: phase.title,
                        subtitle: phase.subtitle(address: connectingConnection?.displayAddress),
                        isError: phase.isFailure,
                        onCancel: phase.isFailure ? nil : { cancelConnect() },
                        onRetry: phase.isFailure ? retryConnect : nil,
                        onBack: phase.isFailure ? { cancelConnect() } : nil
                    )
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.22), value: viewModel.connectPhase)
        }
    }

    private func startConnect(_ connection: Connection) {
        // Supersede any in-flight attempt so its continuation drops out (see the isCancelled guard
        // below) instead of racing this one's `connectingConnection`.
        connectTask?.cancel()
        connectingConnection = connection
        connectTask = Task {
            let request = await viewModel.terminalRequest(for: connection)

            // This attempt was superseded or cancelled while the capture was in flight — the newer
            // attempt (or cancelConnect) now owns the shared state; touch nothing.
            if Task.isCancelled { return }

            if let request {
                connectingConnection = nil
                terminalFlow = .sessionPicker(request)
            } else if viewModel.connectPhase == nil {
                // Trust prompt took over: no overlay to keep alive, no failure to retry.
                connectingConnection = nil
            }
            // Otherwise connectPhase == .failed: keep connectingConnection so Retry can reuse it.
        }
    }

    private func retryConnect() {
        guard let connection = connectingConnection else { return }
        startConnect(connection)
    }

    private func cancelConnect() {
        connectTask?.cancel()
        connectTask = nil
        viewModel.cancelConnect()
        connectingConnection = nil
    }
}

private struct HeaderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("The Loom")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(AbyssalTheme.mintLeaf)
                .textCase(.uppercase)
                .tracking(1.8)

            Text("Choose a tether")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(AbyssalTheme.bone)

            Text("Saved machines will appear here. Pick one to discover live tmux and Herdr sessions before entering a terminal.")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(AbyssalTheme.bone.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct EmptyHostListView: View {
    let addConnection: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                SigilMark()
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text("No tethers yet")
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .foregroundStyle(AbyssalTheme.bone)

                    Text("Add your first SSH connection to begin.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(AbyssalTheme.bone.opacity(0.66))
                }
            }

            Button(action: addConnection) {
                Label("Add Connection", systemImage: "plus")
                    .font(.system(.headline, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(PrimaryAbyssButtonStyle())
        }
        .padding(20)
        .background(AbyssCardBackground())
    }
}

private struct HostCard: View {
    let connection: Connection
    let hasPassword: Bool
    let connect: () -> Void
    let edit: () -> Void
    let toggleFavorite: () -> Void
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Circle()
                    .fill(hasPassword ? AbyssalTheme.mintLeaf : AbyssalTheme.emberWarning)
                    .frame(width: 10, height: 10)
                    .shadow(color: (hasPassword ? AbyssalTheme.mintLeaf : AbyssalTheme.emberWarning).opacity(0.5), radius: 10)

                VStack(alignment: .leading, spacing: 4) {
                    Text(connection.alias)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(AbyssalTheme.bone)
                    Text(connection.displayAddress)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(AbyssalTheme.bone.opacity(0.58))
                }

                Spacer()

                Menu {
                    Button(action: edit) {
                        Label("Edit", systemImage: "pencil")
                    }

                    Button(action: toggleFavorite) {
                        Label(connection.isFavorite ? "Unfavorite" : "Favorite", systemImage: connection.isFavorite ? "star.slash" : "star")
                    }

                    Button(role: .destructive, action: delete) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AbyssalTheme.pacificCyan)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(AbyssalTheme.abyss.opacity(0.42)))
                }
            }

            HStack(spacing: 8) {
                Button(action: connect) {
                    Label("Connect", systemImage: "terminal")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(AbyssalTheme.abyss)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(AbyssalTheme.mintLeaf))
                }

                if connection.isFavorite {
                    Badge(label: "Favorite", systemImage: "star.fill", tint: AbyssalTheme.mintLeaf)
                }

                Badge(
                    label: hasPassword ? "Password stored" : "No password",
                    systemImage: hasPassword ? "key.fill" : "exclamationmark.triangle.fill",
                    tint: hasPassword ? AbyssalTheme.pacificCyan : AbyssalTheme.emberWarning
                )
            }
        }
        .padding(18)
        .background(AbyssCardBackground())
    }
}

private struct Badge: View {
    let label: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(label, systemImage: systemImage)
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Capsule().stroke(tint.opacity(0.36), lineWidth: 1))
    }
}

private struct StatusCard: View {
    let title: String
    let message: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(tint)
            Text(message)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(AbyssalTheme.bone.opacity(0.72))
        }
        .padding(16)
        .background(AbyssCardBackground())
    }
}

struct AbyssCardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: AbyssalTheme.cornerRadius, style: .continuous)
            .fill(AbyssalTheme.deepSpaceBlue.opacity(0.72))
            .overlay {
                RoundedRectangle(cornerRadius: AbyssalTheme.cornerRadius, style: .continuous)
                    .stroke(AbyssalTheme.pearlAqua.opacity(AbyssalTheme.cardStrokeOpacity), lineWidth: 1)
            }
            .shadow(color: AbyssalTheme.abyss.opacity(0.4), radius: 18, y: 12)
    }
}

extension ConnectionDraft: Identifiable {}
