import SwiftUI

/// The single, continuous connect journey. One `fullScreenCover` hosts this view and it crossfades
/// between stations as `coordinator.phase` advances — verifying, inline trust, session picker,
/// terminal, or a clean failure — so nothing pops up out of nowhere.
struct ConnectionFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var coordinator: ConnectionFlowCoordinator

    var body: some View {
        content
            .animation(.easeInOut(duration: 0.25), value: coordinator.phase)
    }

    /// Tear down the in-flight attempt and close the whole flow.
    private func dismissFlow() {
        coordinator.cancel()
        dismiss()
    }

    @ViewBuilder
    private var content: some View {
        switch coordinator.phase {
        case .verifyingHostKey:
            ConnectionProgressOverlay(
                symbol: ConnectionPhase.verifyingHostKey.symbol,
                title: ConnectionPhase.verifyingHostKey.title,
                subtitle: coordinator.address,
                onCancel: { dismissFlow() }
            )
            .transition(.opacity)

        case .trustPrompt(let challenge):
            TrustPromptView(
                challenge: challenge,
                onTrust: { coordinator.trustCurrentHost() },
                onCancel: { dismissFlow() }
            )
            .transition(.opacity)

        case .loadingSessions, .openingTerminal:
            // Defensive: these are rendered inside the embedded child views (session picker /
            // terminal), so the coordinator never rests here. Show a neutral station if it does.
            ConnectionProgressOverlay(
                symbol: coordinator.phase.symbol,
                title: coordinator.phase.title,
                subtitle: coordinator.phase.subtitle(address: coordinator.address),
                onCancel: { dismissFlow() }
            )
            .transition(.opacity)

        case .pickingSession:
            if let request = coordinator.activeRequest {
                SessionPickerView(request: request) { selected in
                    coordinator.selectSession(selected)
                }
                .transition(.opacity)
            }

        case .terminal:
            if let request = coordinator.activeRequest {
                PlainTerminalView(request: request) { reconnectRequest in
                    coordinator.requestReconnect(reconnectRequest)
                }
                .transition(.opacity)
            }

        case .failed(let message):
            ConnectionProgressOverlay(
                symbol: ConnectionPhase.failed(message).symbol,
                title: ConnectionPhase.failed(message).title,
                subtitle: message,
                isError: true,
                // A changed host key is a hard stop — offer only Back, never a retry that would
                // just re-block.
                onRetry: message.contains("Host key changed") ? nil : { coordinator.retry() },
                onBack: { dismissFlow() }
            )
            .transition(.opacity)
        }
    }
}

/// Inline trust station (replaces the old alert): a calm card that presents the fingerprint as an
/// expected step of the flow, with a clear warning and explicit Trust / Cancel.
private struct TrustPromptView: View {
    let challenge: HostKeyChallenge
    let onTrust: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            AbyssBackground()

            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .stroke(AbyssalTheme.pearlAqua.opacity(0.42), lineWidth: 1)
                    Circle()
                        .stroke(AbyssalTheme.emberWarning.opacity(0.72), lineWidth: 2)
                        .padding(12)
                    Image(systemName: ConnectionPhase.trustPrompt(challenge).symbol)
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(AbyssalTheme.pearlAqua)
                }
                .frame(width: 96, height: 96)
                .shadow(color: AbyssalTheme.emberWarning.opacity(0.3), radius: 24)

                VStack(spacing: 8) {
                    Text("New host")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(AbyssalTheme.bone)

                    Text("Review the fingerprint before trusting")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(AbyssalTheme.bone.opacity(0.66))
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(challenge.connection.displayAddress)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(AbyssalTheme.pearlAqua)

                    Text(challenge.fingerprint)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(AbyssalTheme.bone.opacity(0.82))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(AbyssCardBackground())

                HStack(spacing: 12) {
                    Button(action: onTrust) {
                        Label("Trust", systemImage: "checkmark.shield")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(AbyssalTheme.abyss)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(AbyssalTheme.mintLeaf))
                    }
                    .buttonStyle(.plain)

                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(AbyssalTheme.pearlAqua)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Capsule().stroke(AbyssalTheme.pearlAqua.opacity(0.42), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(28)
        }
    }
}
