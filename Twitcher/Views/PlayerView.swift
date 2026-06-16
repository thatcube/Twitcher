import SwiftUI
import AVKit

/// Full-screen video player for a live channel, with a read-only chat overlay.
/// Resolves the HLS URL via PlaybackService, then plays it with AVPlayer.
struct PlayerView: View {
    let channel: String

    @Environment(\.dismiss) private var dismiss
    @State private var chat = ChatService()
    @State private var player: AVPlayer?
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        ZStack(alignment: .trailing) {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            }

            if isLoading {
                ProgressView("Loading \(channel)…")
                    .font(.title3)
            }

            if let errorMessage {
                VStack(spacing: 24) {
                    Text("Couldn't play \(channel)")
                        .font(.title2).bold()
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                    Button("Back") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
                .padding()
            } else {
                ChatView(channel: channel, messages: chat.messages, isConnected: chat.isConnected)
                    .frame(width: 480)
                    .frame(maxHeight: .infinity)
            }
        }
        .task {
            chat.connect(to: channel)
            await load()
        }
        .onDisappear {
            player?.pause()
            chat.disconnect()
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let url = try await PlaybackService.hlsURL(for: channel)
            // AVURLAsset carries the Twitch headers to every variant/segment request,
            // so adaptive quality switching works across all CDNs.
            let asset = AVURLAsset(
                url: url,
                options: ["AVURLAssetHTTPHeaderFieldsKey": PlaybackService.streamHeaders]
            )
            let item = AVPlayerItem(asset: asset)
            let player = AVPlayer(playerItem: item)
            self.player = player
            player.play()
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}
