import SwiftUI

/// A bundled open-source license entry. `resourceName` must match a `.txt` file bundled flat at
/// the app bundle's root (copied from `TetherTTY/Licenses` as individual resources, not as a
/// folder reference) containing the package's verbatim LICENSE text (and, for Apache-2.0
/// packages that ship one, its NOTICE text appended).
struct OpenSourceLicense: Identifiable {
    let id = UUID()
    let name: String
    let licenseType: String
    let resourceName: String
}

enum OpenSourceLicenses {
    /// Every third-party package actually linked into the TetherTTY app binary, plus TetherTTY
    /// itself. `swift-asn1`, `swift-system`, and `swift-argument-parser` are resolved by SwiftPM
    /// (see Package.resolved) but are NOT linked into this app target: nothing in the app's
    /// dependency graph (NIOSSH -> NIOCore/NIOPosix/Crypto/Atomics/DequeModule, SwiftTerm) imports
    /// them, so they are intentionally omitted here.
    static let all: [OpenSourceLicense] = [
        OpenSourceLicense(name: "TetherTTY", licenseType: "Apache-2.0", resourceName: "TetherTTY"),
        OpenSourceLicense(name: "swift-nio-ssh", licenseType: "Apache-2.0", resourceName: "swift-nio-ssh"),
        OpenSourceLicense(name: "swift-nio", licenseType: "Apache-2.0", resourceName: "swift-nio"),
        OpenSourceLicense(name: "swift-crypto", licenseType: "Apache-2.0", resourceName: "swift-crypto"),
        OpenSourceLicense(name: "swift-atomics", licenseType: "Apache-2.0", resourceName: "swift-atomics"),
        OpenSourceLicense(name: "swift-collections", licenseType: "Apache-2.0", resourceName: "swift-collections"),
        OpenSourceLicense(name: "SwiftTerm", licenseType: "MIT", resourceName: "SwiftTerm"),
    ]

    /// Loads the verbatim bundled license text for a given resource name, or `nil` if the
    /// resource is missing from the bundle.
    static func text(forResource resourceName: String, bundle: Bundle = .main) -> String? {
        guard let url = bundle.url(forResource: resourceName, withExtension: "txt") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

private enum AboutLinks {
    static let website = URL(string: "https://tethertty.webcommits.info/")!
    static let privacyPolicy = URL(string: "https://tethertty.webcommits.info/privacy/")!
    static let support = URL(string: "https://tethertty.webcommits.info/support/")!
    static let sourceCode = URL(string: "https://github.com/LStoneyy/TetherTTY")!
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private var versionString: String {
        let bundle = Bundle.main
        let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let buildVersion = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "Version \(shortVersion) (\(buildVersion))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    linksSection

                    licensesSection
                }
                .padding(20)
                .padding(.top, 8)
                .frame(maxWidth: AbyssalTheme.contentMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(AbyssBackground())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(AbyssalTheme.pearlAqua)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .center, spacing: 14) {
            SigilMark()
                .frame(width: 72, height: 72)

            Text("TetherTTY")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(AbyssalTheme.bone)

            Text(versionString)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(AbyssalTheme.bone.opacity(0.6))

            Text("A quiet tether back to your running terminal sessions.")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(AbyssalTheme.bone.opacity(0.72))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var linksSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title: "Links")

            VStack(spacing: 0) {
                linkRow(title: "Website", systemImage: "globe", url: AboutLinks.website)
                Divider().overlay(AbyssalTheme.pearlAqua.opacity(0.12))
                linkRow(title: "Privacy Policy", systemImage: "hand.raised", url: AboutLinks.privacyPolicy)
                Divider().overlay(AbyssalTheme.pearlAqua.opacity(0.12))
                linkRow(title: "Support", systemImage: "questionmark.circle", url: AboutLinks.support)
                Divider().overlay(AbyssalTheme.pearlAqua.opacity(0.12))
                linkRow(title: "Source Code", systemImage: "chevron.left.forwardslash.chevron.right", url: AboutLinks.sourceCode)
            }
            .background(AbyssCardBackground())
        }
    }

    private var licensesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title: "Open Source Licenses")

            VStack(spacing: 0) {
                ForEach(Array(OpenSourceLicenses.all.enumerated()), id: \.element.id) { index, license in
                    if index > 0 {
                        Divider().overlay(AbyssalTheme.pearlAqua.opacity(0.12))
                    }
                    NavigationLink {
                        LicenseDetailView(license: license)
                    } label: {
                        licenseRow(license)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(AbyssCardBackground())
        }
    }

    private func sectionHeader(title: String) -> some View {
        Text(title)
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .foregroundStyle(AbyssalTheme.bone.opacity(0.62))
            .textCase(.uppercase)
            .tracking(1.2)
            .padding(.bottom, 10)
    }

    private func linkRow(title: String, systemImage: String, url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AbyssalTheme.pacificCyan)
                    .frame(width: 24)

                Text(title)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(AbyssalTheme.bone)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AbyssalTheme.bone.opacity(0.4))
            }
            .padding(16)
        }
    }

    private func licenseRow(_ license: OpenSourceLicense) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(license.name)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(AbyssalTheme.bone)
                Text(license.licenseType)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(AbyssalTheme.bone.opacity(0.5))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AbyssalTheme.bone.opacity(0.4))
        }
        .padding(16)
    }
}

private struct LicenseDetailView: View {
    let license: OpenSourceLicense

    var body: some View {
        ScrollView {
            Text(OpenSourceLicenses.text(forResource: license.resourceName) ?? "License text unavailable.")
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(AbyssalTheme.bone.opacity(0.82))
                .textSelection(.enabled)
                .padding(20)
                .frame(maxWidth: AbyssalTheme.contentMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AbyssBackground())
        .navigationTitle(license.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
