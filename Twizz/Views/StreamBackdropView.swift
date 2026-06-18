import AVFoundation
import SwiftUI

/// Full-screen ambient backdrop driven by the currently focused stream card.
/// Shows a blurred thumbnail immediately, then swaps to a blurred live preview
/// after a short hover delay.
struct StreamBackdropView: View {
  let channel: FollowedChannel?

  @State private var player = AVPlayer()
  @State private var previewTask: Task<Void, Never>?
  @State private var revealVideoTask: Task<Void, Never>?
  @State private var activeChannelID: String?
  @State private var activeThumbnailURL: URL?
  @State private var fallbackThumbnailURL: URL?
  @State private var isShowingVideoPreview = false
  @State private var videoOpacity = 0.0
  @State private var hasConfiguredPlayer = false

  private let channelFade = Animation.easeInOut(duration: 0.45)
  private let videoFade = Animation.easeInOut(duration: 0.55)

  var body: some View {
    ZStack {
      if let thumbnailURL = activeThumbnailURL {
        AsyncImage(url: thumbnailURL) { image in
          image
            .resizable()
            .scaledToFill()
            .onAppear {
              if fallbackThumbnailURL != nil {
                withAnimation(channelFade) {
                  fallbackThumbnailURL = nil
                }
              }
            }
        } placeholder: {
          fallbackThumbnailLayer
        }
        .transition(.opacity)
      } else {
        fallbackThumbnailLayer
      }

      if isShowingVideoPreview {
        VideoSurface(player: player)
          .opacity(videoOpacity)
          .transition(.opacity)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .scaleEffect(1.24)
    .saturation(1.16)
    .blur(radius: 66)
    .overlay {
      LinearGradient(
        colors: [Color.black.opacity(0.5), Color.black.opacity(0.8)],
        startPoint: .top,
        endPoint: .bottom
      )
    }
    .animation(channelFade, value: activeThumbnailURL)
    .animation(channelFade, value: fallbackThumbnailURL)
    .animation(videoFade, value: videoOpacity)
    .allowsHitTesting(false)
    .onAppear {
      configurePlayerIfNeeded()
      activeThumbnailURL = channel?.thumbnailURL
      handleChannelChange(channel)
    }
    .onChange(of: channel?.id) { _, _ in
      handleChannelChange(channel)
    }
    .onDisappear {
      stopPreviewPlayback(clearItem: true)
    }
  }

  @MainActor
  private func configurePlayerIfNeeded() {
    guard !hasConfiguredPlayer else { return }
    player.isMuted = true
    player.actionAtItemEnd = .pause
    player.automaticallyWaitsToMinimizeStalling = true
    hasConfiguredPlayer = true
  }

  @MainActor
  private func handleChannelChange(_ channel: FollowedChannel?) {
    previewTask?.cancel()
    previewTask = nil
    revealVideoTask?.cancel()
    revealVideoTask = nil
    withAnimation(videoFade) {
      videoOpacity = 0
    }
    isShowingVideoPreview = false
    player.pause()
    player.replaceCurrentItem(with: nil)

    guard let channel else {
      activeChannelID = nil
      withAnimation(channelFade) {
        fallbackThumbnailURL = activeThumbnailURL
        activeThumbnailURL = nil
      }
      return
    }

    if activeThumbnailURL != channel.thumbnailURL {
      withAnimation(channelFade) {
        fallbackThumbnailURL = activeThumbnailURL
        activeThumbnailURL = channel.thumbnailURL
      }
    }
    activeChannelID = channel.id
    guard channel.isLive else { return }

    let channelID = channel.id
    let login = channel.login

    previewTask = Task { [channelID, login] in
      do {
        try await Task.sleep(for: .seconds(2))
        guard !Task.isCancelled else { return }
        let sourceURL = try await PlaybackService.hlsURL(for: login)
        guard !Task.isCancelled else { return }
        await MainActor.run {
          guard activeChannelID == channelID else { return }
          startPreviewPlayback(from: sourceURL)
          previewTask = nil
        }
      } catch is CancellationError {
        await MainActor.run {
          previewTask = nil
        }
      } catch {
        await MainActor.run {
          guard activeChannelID == channelID else { return }
          stopPreviewPlayback(clearItem: true)
          previewTask = nil
        }
      }
    }
  }

  @MainActor
  private func startPreviewPlayback(from sourceURL: URL) {
    configurePlayerIfNeeded()
    let asset = AVURLAsset(
      url: sourceURL,
      options: ["AVURLAssetHTTPHeaderFieldsKey": PlaybackService.streamHeaders]
    )
    let item = AVPlayerItem(asset: asset)
    player.replaceCurrentItem(with: item)
    videoOpacity = 0
    isShowingVideoPreview = true
    player.play()
    beginVideoRevealWhenReady(item: item)
  }

  @MainActor
  private func beginVideoRevealWhenReady(item: AVPlayerItem) {
    revealVideoTask?.cancel()
    let channelID = activeChannelID
    revealVideoTask = Task { [channelID] in
      var isReadyToReveal = false
      for _ in 0..<35 {
        try? await Task.sleep(for: .milliseconds(100))
        guard !Task.isCancelled else { return }

        let readiness = await MainActor.run {
          (
            activeChannelID == channelID && player.currentItem === item,
            item.status == .readyToPlay,
            item.isPlaybackLikelyToKeepUp || !item.loadedTimeRanges.isEmpty,
            player.timeControlStatus == .playing
          )
        }

        let (isCurrentItem, isReady, hasBuffer, isPlaying) = readiness
        guard isCurrentItem else { return }
        if isReady && hasBuffer && isPlaying {
          isReadyToReveal = true
          break
        }
      }
      guard isReadyToReveal else { return }
      try? await Task.sleep(for: .milliseconds(260))
      guard !Task.isCancelled else { return }
      await MainActor.run {
        guard activeChannelID == channelID, player.currentItem === item else { return }
        withAnimation(videoFade) {
          videoOpacity = 1
        }
        revealVideoTask = nil
      }
    }
  }

  @MainActor
  private func stopPreviewPlayback(clearItem: Bool) {
    previewTask?.cancel()
    previewTask = nil
    revealVideoTask?.cancel()
    revealVideoTask = nil
    withAnimation(videoFade) {
      videoOpacity = 0
    }
    isShowingVideoPreview = false
    player.pause()
    if clearItem {
      player.replaceCurrentItem(with: nil)
    }
  }

  @ViewBuilder
  private var fallbackThumbnailLayer: some View {
    if let fallbackThumbnailURL {
      AsyncImage(url: fallbackThumbnailURL) { image in
        image
          .resizable()
          .scaledToFill()
      } placeholder: {
        Color.clear
      }
      .transition(.opacity)
    } else {
      Color.clear
    }
  }
}
