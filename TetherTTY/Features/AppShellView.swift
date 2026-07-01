import SwiftUI

struct AppShellView: View {
    @State private var lockState: AppLockState = .locked

    var body: some View {
        ZStack {
            AbyssBackground()

            switch lockState {
            case .locked:
                LockedVaultView {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        lockState = .unlocked
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            case .unlocked:
                HostListView()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct LockedVaultView: View {
    let unlock: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 16) {
                SigilMark()
                    .frame(width: 96, height: 96)

                VStack(spacing: 8) {
                    Text("TetherTTY")
                        .font(.system(size: 38, weight: .semibold, design: .rounded))
                        .foregroundStyle(AbyssalTheme.bone)

                    Text("A quiet tether back to your running terminal sessions.")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(AbyssalTheme.bone.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }
            }

            Button(action: unlock) {
                Label("Unlock Vault", systemImage: "faceid")
                    .font(.system(.headline, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(PrimaryAbyssButtonStyle())
            .padding(.horizontal, 28)

            Text("Face ID enforcement lands in the vault slice. This shell shows the locked app boundary.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(AbyssalTheme.pacificCyan)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
        }
    }
}

struct AbyssBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                AbyssalTheme.abyss,
                AbyssalTheme.deepSpaceBlue,
                AbyssalTheme.darkTeal.opacity(0.92)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(AbyssalTheme.mintLeaf.opacity(0.16))
                .frame(width: 260, height: 260)
                .blur(radius: 72)
                .offset(x: 96, y: -92)
        }
        .overlay(alignment: .bottomLeading) {
            Circle()
                .fill(AbyssalTheme.pearlAqua.opacity(0.10))
                .frame(width: 240, height: 240)
                .blur(radius: 68)
                .offset(x: -96, y: 82)
        }
        .ignoresSafeArea()
    }
}

struct PrimaryAbyssButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(AbyssalTheme.abyss)
            .background(
                Capsule()
                    .fill(AbyssalTheme.mintLeaf)
                    .shadow(color: AbyssalTheme.mintLeaf.opacity(configuration.isPressed ? 0.18 : 0.42), radius: configuration.isPressed ? 10 : 22)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct SigilMark: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(AbyssalTheme.pearlAqua.opacity(0.42), lineWidth: 1)
            Circle()
                .stroke(AbyssalTheme.mintLeaf.opacity(0.72), lineWidth: 2)
                .padding(14)
            Image(systemName: "terminal")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(AbyssalTheme.pearlAqua)
        }
        .shadow(color: AbyssalTheme.pearlAqua.opacity(0.32), radius: 24)
    }
}
