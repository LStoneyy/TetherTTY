import SwiftUI

enum AbyssalTheme {
    static let abyss = Color(red: 0.02, green: 0.07, blue: 0.08)
    static let deepSpaceBlue = Color(red: 0.09, green: 0.16, blue: 0.23)
    static let darkTeal = Color(red: 0.0, green: 0.26, blue: 0.27)
    static let pacificCyan = Color(red: 0.31, green: 0.54, blue: 0.57)
    static let pearlAqua = Color(red: 0.46, green: 0.87, blue: 0.87)
    static let mintLeaf = Color(red: 0.04, green: 0.74, blue: 0.54)
    static let bone = Color(red: 0.84, green: 0.91, blue: 0.87)
    static let emberWarning = Color(red: 0.76, green: 0.48, blue: 0.29)
    static let bloodError = Color(red: 0.62, green: 0.23, blue: 0.29)

    static let cornerRadius: CGFloat = 24
    static let cardStrokeOpacity = 0.28
}

extension HostStatus {
    var tint: Color {
        switch self {
        case .unknown:
            AbyssalTheme.pacificCyan
        case .reachable:
            AbyssalTheme.mintLeaf
        case .warning:
            AbyssalTheme.emberWarning
        case .failed:
            AbyssalTheme.bloodError
        }
    }
}
