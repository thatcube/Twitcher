import Foundation
import Observation

/// Reads a Twitch channel's chat anonymously over IRC-via-WebSocket.
///
/// No login or token required: we connect as a `justinfan` guest, request the
/// `twitch.tv/tags` capability (for display names + colors), and parse PRIVMSG
/// lines into `ChatMessage`s. Sending messages is intentionally out of scope.
@MainActor
@Observable
final class ChatService {
    /// Rolling buffer of the most recent messages (oldest first).
    private(set) var messages: [ChatMessage] = []
    private(set) var isConnected = false
    private(set) var emoteURLs: [String: URL] = [:]

    private let endpoint = URL(string: "wss://irc-ws.chat.twitch.tv:443")!
    private let maxMessages = 250

    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var channel: String?

    /// Connect and join `channel` (case-insensitive). Replaces any existing connection.
    func connect(to channel: String) {
        disconnect()
        let normalized = channel.lowercased()
        self.channel = normalized
        emoteURLs = [:]

        let task = URLSession(configuration: .default).webSocketTask(with: endpoint)
        socket = task
        task.resume()

        send("NICK justinfan\(Int.random(in: 10_000..<99_999))")
        send("CAP REQ :twitch.tv/tags")
        send("JOIN #\(normalized)")

        Task { [weak self] in
            guard let self else { return }
            let catalog = await EmoteCatalogService.shared.catalog(for: normalized)
            guard self.channel == normalized else { return }
            self.emoteURLs = catalog
        }

        receiveTask = Task { [weak self] in await self?.receiveLoop() }
    }

    /// Tear down the connection and clear the buffer.
    func disconnect() {
        receiveTask?.cancel()
        receiveTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        isConnected = false
        messages.removeAll()
        emoteURLs.removeAll()
        channel = nil
    }

    private func send(_ command: String) {
        socket?.send(.string(command + "\r\n")) { _ in }
    }

    private func receiveLoop() async {
        guard let socket else { return }
        while !Task.isCancelled {
            do {
                let frame = try await socket.receive()
                switch frame {
                case .string(let text): handle(text)
                case .data(let data): handle(String(decoding: data, as: UTF8.self))
                @unknown default: break
                }
            } catch {
                isConnected = false
                break
            }
        }
    }

    private func handle(_ raw: String) {
        // A single frame can batch multiple IRC lines.
        for piece in raw.components(separatedBy: "\r\n") where !piece.isEmpty {
            if piece.hasPrefix("PING") {
                send("PONG :tmi.twitch.tv")
                continue
            }
            if piece.contains(" 366 ") {  // end-of-NAMES => join confirmed
                isConnected = true
                continue
            }
            if let message = ChatMessage(ircLine: piece) {
                messages.append(message)
                if messages.count > maxMessages {
                    messages.removeFirst(messages.count - maxMessages)
                }
            }
        }
    }
}
