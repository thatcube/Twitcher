import SwiftUI
import AVKit
import UIKit

/// Hosts an embedded `AVPlayerViewController` with native controls disabled.
/// This keeps custom Twitcher UI while preserving Apple media rendering paths
/// (including subtitle/caption rendering) better than raw AVPlayerLayer.
struct VideoSurface: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspect
        // Keep output mode stable while toggling in-app layouts (chat on/off).
        controller.appliesPreferredDisplayCriteriaAutomatically = false
        controller.view.backgroundColor = .black
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspect
        controller.appliesPreferredDisplayCriteriaAutomatically = false
    }
}

/// Full-screen player for a live channel. Video sits on the left and the chat
/// panel docks to the right at full height (the video shrinks to make room,
/// never overlapping). We use a custom `AVPlayerLayer` surface with our own
/// overlay UI rather than the native player transport — the native controls are
/// VOD/scrubbing-oriented and unsuited to a live, side-by-side chat layout.
/// Controls auto-hide and are revealed by pressing the remote.
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
    @State private var showControls = false
    @State private var captionsOn = UIAccessibility.isClosedCaptioningEnabled
    @State private var streamTitle: String = ""
    @State private var chatDraft: String = ""
    @State private var hideTask: Task<Void, Never>?
    @State private var lastControlFocus: Focusable = .quality

    @FocusState private var focus: Focusable?
    private enum Focusable: Hashable {
        case video, quality, captions, chatToggle, chatInput, errorBack
        case qualityOption(Int)
    }

    private let chatWidth: CGFloat = 460

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            HStack(spacing: 0) {
                videoColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showChat {
                    chatPane
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
            await refreshStreamTitle()
            focus = .video
        }
        .onAppear {
            setIdleTimer(disabled: true)
        }
        .onDisappear {
            hideTask?.cancel()
            player.pause()
            chat.disconnect()
            setIdleTimer(disabled: false)
        }
        .onExitCommand {
            if showQualityPicker {
                showQualityPicker = false
                focus = .quality
                scheduleHide()
            } else if showControls {
                hideControls()
            } else {
                dismiss()
            }
        }
        .onMoveCommand { direction in
            guard !showQualityPicker else { return }

            if !showControls {
                // Directional movement should immediately surface controls and
                // land on chat toggle so moving off chat feels instant.
                revealControls(preferredFocus: .chatToggle)
            } else {
                scheduleHide()
            }
        }
        .onChange(of: focus) { _, newFocus in
            // Keep control navigation deterministic: if tvOS drops focus to nil
            // while controls are visible, immediately restore last valid control.
            guard showControls, !showQualityPicker else { return }

            if let newFocus, isControlFocus(newFocus) {
                lastControlFocus = newFocus
                return
            }

            if newFocus == nil {
                focus = lastControlFocus
            }
        }
    }

    // MARK: - Video + controls

    private var videoColumn: some View {
        ZStack(alignment: .bottom) {
            VideoSurface(player: player)
                .ignoresSafeArea()

            // Only expose the video focus target while controls are hidden.
            // Otherwise, left-edge movement from the control cluster can escape
            // into this invisible target and appear as lost focus.
            if !showControls && !showQualityPicker {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .focusable()
                    .focused($focus, equals: .video)
                    .onTapGesture { revealControls(preferredFocus: .quality) }
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
                        .focused($focus, equals: .errorBack)
                }
                .padding(40)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 24))
            } else if showControls && !showQualityPicker {
                bottomOverlay
                    .transition(.opacity)
            }
        }
    }

    private var bottomOverlay: some View {
        HStack(alignment: .bottom, spacing: 24) {
            Text(streamTitle.isEmpty ? channel : streamTitle)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 860, alignment: .leading)

            Spacer()

            HStack(spacing: 14) {
                Button {
                    showQualityPicker = true
                    hideTask?.cancel()
                } label: {
                    Label("Quality", systemImage: "gauge.with.dots.needle.67percent")
                        .labelStyle(.iconOnly)
                }
                .focused($focus, equals: .quality)
                .onMoveCommand { direction in
                    switch direction {
                    case .left:
                        // Left edge intentionally does nothing.
                        break
                    case .right:
                        focus = .captions
                    default:
                        break
                    }
                }

                Button {
                    captionsOn.toggle()
                    applyCaptions()
                    scheduleHide()
                } label: {
                    Label(captionsOn ? "Captions On" : "Captions Off",
                          systemImage: captionsOn ? "captions.bubble.fill" : "captions.bubble")
                        .labelStyle(.iconOnly)
                }
                .focused($focus, equals: .captions)
                .onMoveCommand { direction in
                    switch direction {
                    case .left:
                        focus = .quality
                    case .right:
                        focus = .chatToggle
                    default:
                        break
                    }
                }

                Button {
                    showChat.toggle()
                    if !showChat, focus == .chatInput {
                        focus = .chatToggle
                    }
                    scheduleHide()
                } label: {
                    Label(showChat ? "Hide Chat" : "Show Chat",
                          systemImage: showChat ? "sidebar.right" : "bubble.left.and.bubble.right.fill")
                        .labelStyle(.iconOnly)
                }
                .focused($focus, equals: .chatToggle)
                .onMoveCommand { direction in
                    switch direction {
                    case .left:
                        focus = .captions
                    case .right:
                        if showChat { focus = .chatInput }
                    default:
                        break
                    }
                }
            }
            .buttonStyle(.bordered)
            .focusSection()
        }
        .padding(.horizontal, 48)
        .padding(.bottom, 42)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.72)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 240)
                .allowsHitTesting(false),
            alignment: .bottom
        )
    }

    // MARK: - Controls visibility

    private func revealControls(preferredFocus: Focusable) {
        guard !showControls else { scheduleHide(); return }
        withAnimation(.easeInOut(duration: 0.2)) { showControls = true }
        focus = preferredFocus
        scheduleHide()
    }

    private func hideControls() {
        hideTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) { showControls = false }
        focus = .video
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard !showQualityPicker else { return }
                guard focus != .chatInput else { return }
                hideControls()
            }
        }
    }

    private func isControlFocus(_ focus: Focusable) -> Bool {
        switch focus {
        case .quality, .captions, .chatToggle, .chatInput:
            return true
        default:
            return false
        }
    }

    private var chatPane: some View {
        VStack(spacing: 0) {
            ChatView(
                channel: channel,
                messages: chat.messages,
                isConnected: chat.isConnected,
                emoteURLs: chat.emoteURLs,
                badgeURLs: chat.badgeURLs
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            chatComposerBar
        }
        .frame(width: chatWidth)
        .frame(maxHeight: .infinity)
    }

    private var chatComposerBar: some View {
        HStack(spacing: 10) {
            TextField("Send a message", text: $chatDraft)
                .textFieldStyle(.plain)
                .focused($focus, equals: .chatInput)
                .onMoveCommand { direction in
                    switch direction {
                    case .left:
                        revealControls(preferredFocus: .chatToggle)
                        focus = .chatToggle
                    default:
                        break
                    }
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(white: 0.07).opacity(0.98))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.15))
                .frame(height: 1)
        }
    }

    // MARK: - Quality picker

    private var qualityPicker: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 8) {
                Text("Quality")
                    .font(.title2).bold()
                    .padding(.bottom, 8)

                ForEach(Array(qualityOptions.enumerated()), id: \.offset) { index, option in
                    Button {
                        selectQuality(at: index)
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
                    .focused($focus, equals: .qualityOption(index))
                }
            }
            .padding(40)
            .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 28))
            .focusSection()
        }
        .onAppear {
            // Move focus into the picker once it's on screen; the underlying
            // control bar is hidden while the picker is open so it can't steal focus.
            let target = qualityOptions.firstIndex(of: preferredQuality) ?? 0
            focus = .qualityOption(target)
        }
    }

    private var qualityOptions: [String] {
        ["Auto"] + (playback?.qualities.map(\.name) ?? [])
    }

    private func selectQuality(at index: Int) {
        guard qualityOptions.indices.contains(index) else { return }
        let option = qualityOptions[index]
        preferredQuality = option
        showQualityPicker = false
        if let url = url(for: option) {
            player.replaceCurrentItem(with: makeItem(url: url))
            player.play()
        }
        focus = .quality
        scheduleHide()
    }

    // MARK: - Loading

    private func load() async {
        isLoading = true
        errorMessage = nil
        streamTitle = ""
        player.appliesMediaSelectionCriteriaAutomatically = true
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

    private func refreshStreamTitle() async {
        if let title = await PlaybackService.streamTitle(for: channel), !title.isEmpty {
            streamTitle = title
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
        let item = AVPlayerItem(asset: asset)
        applyCaptions(to: item, retries: 12)
        return item
    }

    /// Applies the current captions preference to the active item.
    private func applyCaptions() {
        if let item = player.currentItem { applyCaptions(to: item, retries: 12) }
    }

    /// Turns in-band closed captions on or off for a given item. Twitch streams
    /// carry CEA-608 captions in the legible selection group.
    ///
    /// The legible group can appear slightly after playback starts, so we retry
    /// for a short window instead of failing one-shot.
    private func applyCaptions(to item: AVPlayerItem, retries: Int) {
        let wantCaptions = captionsOn
        Task {
            for attempt in 0...retries {
                if let group = try? await item.asset.loadMediaSelectionGroup(for: .legible) {
                    await MainActor.run {
                        guard !group.options.isEmpty else { return }

                        if wantCaptions {
                            let preferred = group.options.first {
                                !$0.hasMediaCharacteristic(.containsOnlyForcedSubtitles)
                            } ?? group.options.first
                            if let option = preferred {
                                item.select(option, in: group)
                            }
                        } else {
                            item.select(nil, in: group)
                        }
                    }
                    return
                }

                if attempt < retries {
                    try? await Task.sleep(for: .milliseconds(350))
                }
            }
        }
    }

    private func setIdleTimer(disabled: Bool) {
        UIApplication.shared.isIdleTimerDisabled = disabled
    }
}
