import Foundation

struct TmuxSessionParser {
    static func parse(_ output: String) -> [TerminalSession] {
        let lines = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return lines.compactMap { line -> TerminalSession? in
            let parts = line.components(separatedBy: "\t")
            guard parts.count == 4 else { return nil }

            let name = parts[0].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }

            let windowCount = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
            let attachedCount = Int(parts[2].trimmingCharacters(in: .whitespaces)) ?? 0

            let created: Date?
            if let timestamp = TimeInterval(parts[3].trimmingCharacters(in: .whitespaces)) {
                created = Date(timeIntervalSince1970: timestamp)
            } else {
                created = nil
            }

            return TerminalSession(
                id: name,
                provider: .tmux(
                    name: name,
                    windowCount: windowCount,
                    attachedCount: attachedCount,
                    created: created
                ),
                displayName: name,
                detail: "\(windowCount) window\(windowCount == 1 ? "" : "s"), \(attachedCount) attached"
            )
        }
    }
}
