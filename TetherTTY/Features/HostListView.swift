import SwiftUI

struct HostListView: View {
    private let hosts: [HostSummary] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HeaderView()

                    if hosts.isEmpty {
                        EmptyHostListView()
                    } else {
                        ForEach(hosts) { host in
                            HostCard(host: host)
                        }
                    }

                    StatePreviewStrip()
                }
                .padding(20)
                .padding(.top, 8)
            }
            .background(AbyssBackground())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
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
        }
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

            Button {
            } label: {
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
    let host: HostSummary

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(host.status.tint)
                .frame(width: 10, height: 10)
                .shadow(color: host.status.tint.opacity(0.5), radius: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(host.alias)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(AbyssalTheme.bone)
                Text(host.address)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(AbyssalTheme.bone.opacity(0.58))
            }

            Spacer()

            Image(systemName: host.isFavorite ? "star.fill" : "chevron.right")
                .foregroundStyle(host.isFavorite ? AbyssalTheme.mintLeaf : AbyssalTheme.pacificCyan)
        }
        .padding(18)
        .background(AbyssCardBackground())
    }
}

private struct StatePreviewStrip: View {
    private let states: [(String, Color)] = [
        ("Empty", AbyssalTheme.pacificCyan),
        ("Ready", AbyssalTheme.mintLeaf),
        ("Warning", AbyssalTheme.emberWarning),
        ("Error", AbyssalTheme.bloodError)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("State language")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(AbyssalTheme.bone.opacity(0.62))
                .textCase(.uppercase)
                .tracking(1.2)

            HStack(spacing: 10) {
                ForEach(states, id: \.0) { label, color in
                    Text(label)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Capsule().stroke(color.opacity(0.42), lineWidth: 1))
                }
            }
        }
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
