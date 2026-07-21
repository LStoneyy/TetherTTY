import Foundation

struct HerdrSessionParser {
    static func parse(_ output: String) -> [TerminalSession] {
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }

        if let array = json as? [[String: Any]] {
            return array.compactMap(sessionEntry)
        }

        if let dict = json as? [String: Any],
           let array = dict["sessions"] as? [[String: Any]] {
            return array.compactMap(sessionEntry)
        }

        if let names = json as? [String] {
            return names
                .filter { !$0.isEmpty }
                .map { makeSession(name: $0, status: "session", metadata: nil) }
        }

        return []
    }

    private static func sessionEntry(from object: [String: Any]) -> TerminalSession? {
        guard let name = (object["name"] as? String) ?? (object["id"] as? String),
              !name.isEmpty else {
            return nil
        }

        let status = (object["status"] as? String)
            ?? (object["state"] as? String)
            ?? ((object["attached"] as? Bool).map { $0 ? "attached" : "detached" })
            ?? "session"

        let metadata = (object["label"] as? String) ?? (object["title"] as? String)

        return makeSession(name: name, status: status, metadata: metadata)
    }

    private static func makeSession(name: String, status: String, metadata: String?) -> TerminalSession {
        let detail = metadata.map { "session · \(status) · \($0)" } ?? "session · \(status)"
        return TerminalSession(
            id: "herdr-session-\(name)",
            provider: .herdr(
                kind: "session",
                name: name,
                status: status,
                attachCommand: "herdr session attach \(name)",
                metadata: metadata
            ),
            displayName: name,
            detail: detail
        )
    }
}
