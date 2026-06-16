import Foundation

/// A single chat line parsed from Twitch IRC.
struct ChatMessage: Identifiable {
    let id = UUID()
    let username: String
    /// Twitch user color as a `#RRGGBB` hex string, if the user set one.
    let colorHex: String?
    let text: String
    /// True for `/me` action messages (rendered in the user's color).
    let isAction: Bool
}

extension ChatMessage {
    /// Parse one raw Twitch IRC line (tags + PRIVMSG) into a `ChatMessage`.
    /// Returns `nil` for any non-PRIVMSG line (PING, JOIN, server notices, …).
    init?(ircLine line: String) {
        var rest = Substring(line)
        var tags: [String: String] = [:]

        // Tags section: "@key=value;key=value " (present because we request twitch.tv/tags).
        if rest.first == "@" {
            guard let spaceIdx = rest.firstIndex(of: " ") else { return nil }
            let tagString = rest[rest.index(after: rest.startIndex)..<spaceIdx]
            for pair in tagString.split(separator: ";") {
                let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                if kv.count == 2 {
                    tags[String(kv[0])] = String(kv[1])
                } else if kv.count == 1 {
                    tags[String(kv[0])] = ""
                }
            }
            rest = rest[rest.index(after: spaceIdx)...]
        }

        // Prefix: ":nick!user@host ".
        guard rest.first == ":", let prefixEnd = rest.firstIndex(of: " ") else { return nil }
        let prefix = rest[rest.index(after: rest.startIndex)..<prefixEnd]
        let nickFromPrefix = prefix.split(separator: "!").first.map(String.init) ?? "user"
        rest = rest[rest.index(after: prefixEnd)...]

        // Command: "PRIVMSG #channel :message text".
        let parts = rest.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 3, parts[0] == "PRIVMSG" else { return nil }

        var message = String(parts[2])
        if message.first == ":" { message.removeFirst() }

        // Detect /me actions: "\u{1}ACTION text\u{1}".
        var action = false
        if message.hasPrefix("\u{1}ACTION ") && message.hasSuffix("\u{1}") {
            action = true
            message = String(message.dropFirst("\u{1}ACTION ".count).dropLast())
        }

        let display = tags["display-name"].flatMap { $0.isEmpty ? nil : $0 } ?? nickFromPrefix
        let color = tags["color"].flatMap { $0.isEmpty ? nil : $0 }

        self.username = display
        self.colorHex = color
        self.text = message
        self.isAction = action
    }
}
