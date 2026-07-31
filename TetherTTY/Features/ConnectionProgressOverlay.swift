import SwiftUI

/// A calm, full-bleed progress station shown during the connect flow. Reused everywhere the flow
/// needs to explain what is happening — host-key verification, session discovery, opening the
/// terminal — and to surface a clean failure with retry/back.
///
/// Used both as a `.overlay` over an existing screen (minimal-invasive wiring) and as the content
/// of the unified `ConnectionFlowView`. It carries its own dimmed backdrop so it always reads as a
/// distinct station rather than floating over live content.
struct ConnectionProgressOverlay: View {
    let symbol: String
    let title: String
    var subtitle: String?

    /// When true the spinner is replaced by a warning treatment and retry/back are offered.
    var isError: Bool = false
    /// Shown while working (non-error) if provided.
    var onCancel: (() -> Void)?
    /// Shown in the error state if provided.
    var onRetry: (() -> Void)?
    /// Shown in the error state if provided.
    var onBack: (() -> Void)?

    var body: some View {
        ZStack {
            AbyssBackground()

            VStack(spacing: 22) {
                sigil

                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(AbyssalTheme.bone)
                        .multilineTextAlignment(.center)

                    if let subtitle {
                        Text(subtitle)
                            .font(.system(.subheadline, design: isError ? .rounded : .monospaced))
                            .foregroundStyle(isError ? AbyssalTheme.emberWarning : AbyssalTheme.bone.opacity(0.66))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 32)

                if isError {
                    errorActions
                } else if !isError {
                    workingIndicator
                }
            }
            .padding(28)
        }
    }

    private var sigil: some View {
        ZStack {
            Circle()
                .stroke(AbyssalTheme.pearlAqua.opacity(0.42), lineWidth: 1)
            Circle()
                .stroke((isError ? AbyssalTheme.emberWarning : AbyssalTheme.mintLeaf).opacity(0.72), lineWidth: 2)
                .padding(12)
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(isError ? AbyssalTheme.emberWarning : AbyssalTheme.pearlAqua)
        }
        .frame(width: 96, height: 96)
        .shadow(color: (isError ? AbyssalTheme.emberWarning : AbyssalTheme.pearlAqua).opacity(0.3), radius: 24)
    }

    private var workingIndicator: some View {
        VStack(spacing: 18) {
            ProgressView()
                .tint(AbyssalTheme.pacificCyan)

            if let onCancel {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(AbyssalTheme.pearlAqua)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 9)
                        .background(Capsule().stroke(AbyssalTheme.pearlAqua.opacity(0.42), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var errorActions: some View {
        HStack(spacing: 12) {
            if let onRetry {
                Button(action: onRetry) {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(AbyssalTheme.abyss)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(AbyssalTheme.mintLeaf))
                }
                .buttonStyle(.plain)
            }

            if let onBack {
                Button(action: onBack) {
                    Text("Back")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(AbyssalTheme.pearlAqua)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Capsule().stroke(AbyssalTheme.pearlAqua.opacity(0.42), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
