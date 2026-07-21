import Foundation

struct HerdrSessionParser {
    static func parse(_ output: String) -> [TerminalSession] {
        let lines = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return lines.compactMap { line -> TerminalSession? in
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 4 else { return nil }

            let kind = parts[0].trimmingCharacters(in: .whitespaces)
            let name = parts[1].trimmingCharacters(in: .whitespaces)
            let status = parts[2].trimmingCharacters(in: .whitespaces)
            let attachCommand = parts[3].trimmingCharacters(in: .whitespaces)

            guard !kind.isEmpty, !name.isEmpty, !attachCommand.isEmpty else { return nil }

            let metadata: String?
            if parts.count >= 5 {
                let raw = parts[4].trimmingCharacters(in: .whitespaces)
                metadata = raw.isEmpty ? nil : raw
            } else {
                metadata = nil
            }

            let id = "herdr-\(kind)-\(name)"

            let detail: String
            if let meta = metadata {
                detail = "\(kind) · \(status) · \(meta)"
            } else {
                detail = "\(kind) · \(status)"
            }

            return TerminalSession(
                id: id,
                provider: .herdr(
                    kind: kind,
                    name: name,
                    status: status,
                    attachCommand: attachCommand,
                    metadata: metadata
                ),
                displayName: name,
                detail: detail
            )
        }
    }
}
