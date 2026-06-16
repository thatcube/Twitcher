import SwiftUI
import AVKit

/// Hosts an `AVPlayerLayer` so the video keeps its aspect ratio (letterboxed and
/// centered) inside whatever space the layout gives it — required for the
/// side-by-side video + chat layout.
struct VideoSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerHostView {
        let view = PlayerHostView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ view: PlayerHostView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }
    }

    final class PlayerHostView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

/// Full-screen player for a live channel. Video sits on the left and the chat
/// panel docks to the right at full height (the video shrinks to make room,
/// never overlapping). Includes focusable controls to collapse/expand chat and
/// pick a stream quality that persists across channels.
struct PlayerView: View {
    let channel: String

    @Environment(\.dismiss) private var dismiss
    @AppStorage("preferredQuality") private var preferredQuality = "Auto"

    @State private var chat = ChatService()
    @State private var player = AVPlayer()
    @State private var playback: StreamPlayback?
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var showChat = true
    @State private var showQualityPicker = false

    @FocusState private var focus: Focusable?
    private enum Focusable: Hashable { case chatToggle, quality, exit }

    private let chatWidth: CGFloat = 460

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            HStack(spacing: 0) {
                videoColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showChat {
                    ChatView(channel: channel, messages: chat.messages, isConnected: chat.isConnected)
                        .frame(width: chatWidth)
                        .frame(maxHeight: .infinity)
                        .transition(.move(edge: .trailing))
                }
            }
            .ignoresSafeArea()

            if showQualityPicker {
                qualityPicker
            }
        }
        .task {
            chat.connect(to: channel)
            await load()
        }
        .onDisappear {
            player.pause()
            chat.disconnect()
        }
        .onExitCommand {
            if showQualityPicker {
                showQualityPicker = false
            } else {
                dismiss()
            }
        }
    }

    // MARK: - Video + controls

    private var videoColumn: some View {
        ZStack(alignment: .top) {
            VideoSurface(player: player)
                .ignoresSafeArea()

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
                        .focused($focus, equals: .exit)
                }
                .padding(40)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 24))
            } else {
                controlBar
            }
        }
    }

    private var controlBar: some View {
        HStack(spacing: 20) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { showChat.toggle() }
            } label: {
                Label(showChat ? "Hide Chat" : "Show Chat",
                      systemImage: showChat ? "sidebar.right" : "bubble.left.and.bubble.right")
            }
            .focused($focus, equals: .chatToggle)

            Button {
                showQualityPicker = true
                focus = .quality
            } label: {
                Label("Quality • \(preferredQuality)", systemImage: "gauge.with.dots.needle.67percent")
            }
            .focused($focus, equals: .quality)

            Spacer()

            Button {
                dismiss()
            } label: {
                Label("Exit", systemImage: "xmark")
            }
            .focused($focus, equals: .exit)
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 48)
        .padding(.top, 36)
    }

    // MARK: - Quality picker

    private var qualityPicker: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
                .onTapGesture { showQualityPicker = false }

            VStack(alignment: .leading, spacing: 8) {
                Text("Quality")
                    .font(.title2).bold()
                    .padding(.bottom, 8)

                ForEach(qualityOptions, id: \.self) { option in
                    Button {
                        select(quality: option)
                    } label: {
                        HStack {
                            Text(option)
                            Spacer()
                            if option == preferredQuality {
                                Image(systemName: "checkmark")
                            }
                        }
                        .frame(width: 360)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(40)
            .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 28))
        }
    }

    private var qualityOptions: [String] {
        ["Auto"] + (playback?.qualities.map(\.name) ?? [])
    }

    private func select(quality option: String) {
        preferredQuality = option
        showQualityPicker = false
        if let url = url(for: option) {
            player.replaceCurrentItem(with: makeItem(url: url))
            player.play()
        }
    }

    // MARK: - Loading

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let resolved = try await PlaybackService.resolve(for: channel)
            playback = resolved
            let startURL = url(for: preferredQuality) ?? resolved.master
            player.replaceCurrentItem(with: makeItem(url: startURL))
            player.play()
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    /// Resolves a quality option name to a playable URL. "Auto" (or an unknown
    /// name, e.g. a persisted quality this stream doesn't offer) uses the master
    /// playlist so AVPlayer does adaptive bitrate.
    private func url(for option: String) -> URL? {
        guard let playback else { return nil }
        if option == "Auto" { return playback.master }
        if let match = playback.qualities.first(where: { $0.name == option }) { return match.url }
        return playback.master
    }

    private func makeItem(url: URL) -> AVPlayerItem {
        let asset = AVURLAsset(
            url: url,
            options: ["AVURLAssetHTTPHeaderFieldsKey": PlaybackService.streamHeaders]
        )
        return AVPlayerItem(asset: asset)
    }
}
