import SwiftUI

/// Full-screen channel "launchpad". Opened from the player's avatar button and
/// from the press-and-hold "Go to Channel" action on channel cards.
///
/// It pairs a glanceable header (banner, avatar, identity, live summary) with
/// rows of *actionable* content — top clips, past broadcasts, and an algorithmic
/// "More like this" rail — so the page earns its place on a lean-back TV instead
/// of being a dead info card. tvOS has no browser, so social links are plain text.
struct ChannelPageView: View {
  let target: ChannelPageTarget
  /// Shows the header "Watch Live" button for *this* channel. Disabled when
  /// opened from inside the player (already watching this channel).
  var showsHeaderWatch: Bool = true
  /// Watches a live channel — either this channel (header button) or one picked
  /// from the "More like this" rail. The presenter decides what "watch" means
  /// (open the player, or switch the already-open player to that channel).
  var onWatchChannel: ((FollowedChannel) -> Void)?

  @Environment(\.dismiss) private var dismiss
  @Environment(\.themePalette) private var palette

  @State private var profile: ChannelProfile?
  @State private var isLoadingProfile = true
  @State private var profileFailed = false

  @State private var content: ChannelContent?
  @State private var isLoadingContent = true
  @State private var recommendations: [FollowedChannel] = []
  @State private var isLoadingRecs = true

  @State private var onDemandItem: OnDemandItem?
  @FocusState private var focusedID: String?

  private let bannerHeight: CGFloat = 300
  private let avatarSize: CGFloat = 132
  private let tileWidth: CGFloat = 360
  private let tileMediaHeight: CGFloat = 202

  private var canWatchThisChannel: Bool {
    showsHeaderWatch && onWatchChannel != nil && (profile?.isLive ?? false)
  }

  private var headerName: String {
    profile?.displayName ?? target.displayName ?? target.login
  }

  private var headerAvatarURL: URL? {
    profile?.profileImageURL ?? target.profileImageURL
  }

  var body: some View {
    ZStack {
      LinearGradient(colors: palette.backgroundColors, startPoint: .top, endPoint: .bottom)
        .ignoresSafeArea()

      ScrollView(.vertical, showsIndicators: false) {
        VStack(alignment: .leading, spacing: 34) {
          hero
          broadcastSummary
          clipsRow
          vodsRow
          similarRow
          aboutAndLinks
        }
        .padding(.bottom, 60)
      }
      .scrollClipDisabled()
    }
    .overlay(alignment: .topTrailing) { actionBar }
    .onExitCommand { dismiss() }
    .task(id: target.id) { await loadAll() }
    .fullScreenCover(item: $onDemandItem) { item in
      OnDemandPlayerView(item: item)
        .environment(\.themePalette, palette)
    }
  }

  // MARK: - Action bar (Watch / Close)

  private var actionBar: some View {
    HStack(spacing: 16) {
      if canWatchThisChannel {
        Button {
          if let profile { onWatchChannel?(followedChannel(from: profile)) }
        } label: {
          Label("Watch Live", systemImage: "play.fill")
            .font(.headline)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
        }
        .focused($focusedID, equals: "watch")
      }

      Button {
        dismiss()
      } label: {
        Label("Close", systemImage: "xmark")
          .font(.headline)
          .padding(.horizontal, 22)
          .padding(.vertical, 12)
      }
      .focused($focusedID, equals: "close")
    }
    .padding(.top, 28)
    .padding(.trailing, AppLayout.horizontalPadding)
  }

  // MARK: - Hero

  private var hero: some View {
    ZStack(alignment: .bottomLeading) {
      banner

      LinearGradient(
        colors: [.clear, palette.backgroundColors.last ?? .black],
        startPoint: .center,
        endPoint: .bottom
      )

      HStack(alignment: .bottom, spacing: 24) {
        avatar
        identity
        Spacer(minLength: 0)
      }
      .padding(.horizontal, AppLayout.horizontalPadding)
      .padding(.bottom, 10)
    }
    .frame(height: bannerHeight)
    .frame(maxWidth: .infinity)
  }

  private var banner: some View {
    Group {
      if let bannerURL = profile?.bannerImageURL {
        AsyncImage(url: bannerURL) { image in
          image.resizable().scaledToFill()
        } placeholder: {
          bannerFallback
        }
      } else {
        bannerFallback
      }
    }
    .frame(maxWidth: .infinity, maxHeight: bannerHeight)
    .clipped()
  }

  private var bannerFallback: some View {
    LinearGradient(
      colors: [Color(red: 0.36, green: 0.25, blue: 0.66), Color(red: 0.20, green: 0.14, blue: 0.42)],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }

  private var avatar: some View {
    Group {
      if let headerAvatarURL {
        AsyncImage(url: headerAvatarURL) { image in
          image.resizable().scaledToFill()
        } placeholder: {
          avatarPlaceholder
        }
      } else {
        avatarPlaceholder
      }
    }
    .frame(width: avatarSize, height: avatarSize)
    .clipShape(Circle())
    .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 4))
    .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
  }

  private var avatarPlaceholder: some View {
    ZStack {
      Circle().fill(.white.opacity(0.16))
      Icon(glyph: .userCircle, size: avatarSize * 0.6)
        .foregroundStyle(.white.opacity(0.85))
    }
  }

  private var identity: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 12) {
        Text(headerName)
          .font(.system(size: 46, weight: .bold))
          .foregroundStyle(.white)
          .lineLimit(1)
          .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
        roleBadge
      }

      HStack(spacing: 18) {
        if let followers = profile?.followerCount {
          statLabel(text: "\(Self.compactCount(followers)) followers", systemImage: "heart.fill")
        }
        if let joined = profile?.createdAt {
          statLabel(text: "Joined \(Self.monthYear(joined))", systemImage: "calendar")
        }
      }
      .foregroundStyle(.white.opacity(0.92))
    }
    .padding(.bottom, 6)
  }

  @ViewBuilder
  private var roleBadge: some View {
    if let profile {
      if profile.isPartner {
        badge(text: "Partner", systemImage: "checkmark.seal.fill", tint: Color(red: 0.58, green: 0.41, blue: 0.96))
      } else if profile.isAffiliate {
        badge(text: "Affiliate", systemImage: "rosette", tint: Color(red: 0.30, green: 0.55, blue: 0.95))
      }
    }
  }

  private func badge(text: String, systemImage: String, tint: Color) -> some View {
    Label(text, systemImage: systemImage)
      .font(.callout.weight(.semibold))
      .foregroundStyle(.white)
      .padding(.horizontal, 14)
      .padding(.vertical, 6)
      .background(Capsule().fill(tint.opacity(0.9)))
  }

  private func statLabel(text: String, systemImage: String) -> some View {
    Label(text, systemImage: systemImage)
      .font(.title3.weight(.medium))
      .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
  }

  // MARK: - Broadcast summary

  @ViewBuilder
  private var broadcastSummary: some View {
    if let profile {
      Group {
        if profile.isLive {
          VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
              liveBadge
              if let viewers = profile.liveViewerCount {
                Text("\(Self.plainCount(viewers)) watching")
                  .font(.headline).foregroundStyle(.secondary)
              }
              if let uptime = Self.uptime(since: profile.liveStartedAt) {
                Text("· \(uptime)").font(.headline).foregroundStyle(.secondary)
              }
            }
            summaryTitleGame(title: profile.liveTitle, game: profile.liveGame)
          }
        } else if profile.lastBroadcastTitle != nil || profile.lastBroadcastGame != nil {
          VStack(alignment: .leading, spacing: 8) {
            Text(lastSeenLabel(profile.lastBroadcastStartedAt))
              .font(.headline).foregroundStyle(.secondary)
            summaryTitleGame(title: profile.lastBroadcastTitle, game: profile.lastBroadcastGame)
          }
        }
      }
      .padding(.horizontal, AppLayout.horizontalPadding)
    } else if isLoadingProfile {
      HStack(spacing: 14) {
        ProgressView()
        Text("Loading channel…").foregroundStyle(.secondary)
      }
      .padding(.horizontal, AppLayout.horizontalPadding)
    } else if profileFailed {
      Text("Couldn't load this channel's details right now.")
        .foregroundStyle(.secondary)
        .padding(.horizontal, AppLayout.horizontalPadding)
    }
  }

  private var liveBadge: some View {
    HStack(spacing: 8) {
      Circle().fill(.red).frame(width: 12, height: 12)
      Text("LIVE").font(.headline.weight(.bold)).foregroundStyle(.red)
    }
  }

  @ViewBuilder
  private func summaryTitleGame(title: String?, game: String?) -> some View {
    if let title, !title.isEmpty {
      Text(title)
        .font(.title2.weight(.semibold))
        .lineLimit(2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    if let game, !game.isEmpty {
      Label(game, systemImage: "gamecontroller.fill")
        .font(.title3).foregroundStyle(.secondary)
    }
  }

  // MARK: - Clips row

  @ViewBuilder
  private var clipsRow: some View {
    if let clips = content?.clips, !clips.isEmpty {
      contentRow(title: "Clips") {
        ForEach(clips) { clip in
          tile(id: "clip-\(clip.slug)") {
            onDemandItem = .clip(slug: clip.slug, title: clip.title)
          } content: {
            mediaTile(
              thumbnail: clip.thumbnailURL,
              badge: Self.shortDuration(clip.durationSeconds),
              title: clip.title,
              subtitle: clipSubtitle(clip)
            )
          }
        }
      }
    } else if isLoadingContent {
      loadingRow(title: "Clips")
    }
  }

  private func clipSubtitle(_ clip: ChannelClip) -> String {
    var parts: [String] = ["\(Self.compactCount(clip.viewCount)) views"]
    if let game = clip.gameName { parts.append(game) }
    return parts.joined(separator: " · ")
  }

  // MARK: - VODs row

  @ViewBuilder
  private var vodsRow: some View {
    if let videos = content?.videos, !videos.isEmpty {
      contentRow(title: "Past Broadcasts") {
        ForEach(videos) { vod in
          tile(id: "vod-\(vod.id)") {
            onDemandItem = .vod(id: vod.id, title: vod.title)
          } content: {
            mediaTile(
              thumbnail: vod.thumbnailURL,
              badge: Self.longDuration(vod.lengthSeconds),
              title: vod.title,
              subtitle: vodSubtitle(vod)
            )
          }
        }
      }
    } else if isLoadingContent {
      loadingRow(title: "Past Broadcasts")
    }
  }

  private func vodSubtitle(_ vod: ChannelVOD) -> String {
    var parts: [String] = []
    if let published = vod.publishedAt { parts.append(Self.relativeDate(published)) }
    parts.append("\(Self.compactCount(vod.viewCount)) views")
    if let game = vod.gameName { parts.append(game) }
    return parts.joined(separator: " · ")
  }

  // MARK: - More like this row

  @ViewBuilder
  private var similarRow: some View {
    if !recommendations.isEmpty {
      VStack(alignment: .leading, spacing: 4) {
        Text("More like this")
          .font(.system(size: 30, weight: .bold))
          .padding(.horizontal, AppLayout.horizontalPadding)

        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 22) {
            ForEach(recommendations) { channel in
              let itemID = "rec-\(channel.id)"
              StreamChannelCard(
                channel: channel,
                isFocused: focusedID == itemID,
                layout: .rail(
                  mediaWidth: tileWidth,
                  mediaHeight: tileMediaHeight,
                  focusHorizontalInset: 12,
                  focusVerticalInset: 12,
                  cardCornerRadius: 16,
                  mediaCornerRadius: 12
                ),
                showsGameName: true
              )
              .contentShape(RoundedRectangle(cornerRadius: 16))
              .focusable(true)
              .focused($focusedID, equals: itemID)
              .focusEffectDisabled()
              .onTapGesture { onWatchChannel?(channel) }
              .accessibilityAddTraits(.isButton)
              .scaleEffect(focusedID == itemID ? 1.04 : 1)
              .animation(.easeOut(duration: 0.14), value: focusedID)
              .zIndex(focusedID == itemID ? 2 : 0)
            }
          }
          .padding(.horizontal, AppLayout.horizontalPadding)
          .padding(.vertical, 12)
        }
        .scrollClipDisabled()
      }
      .focusSection()
    } else if isLoadingRecs && !isLoadingContent {
      loadingRow(title: "More like this")
    }
  }

  // MARK: - About + links

  @ViewBuilder
  private var aboutAndLinks: some View {
    let description = profile?.description
    let links = profile?.socialLinks ?? []
    if (description?.isEmpty == false) || !links.isEmpty {
      VStack(alignment: .leading, spacing: 18) {
        if let description, !description.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Text("About").font(.title3.weight(.bold))
            Text(description)
              .font(.title3).foregroundStyle(.secondary)
              .lineLimit(3)
              .frame(maxWidth: 1100, alignment: .leading)
          }
        }
        if !links.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Text("Links").font(.title3.weight(.bold))
            HStack(spacing: 36) {
              ForEach(links.prefix(5)) { link in
                VStack(alignment: .leading, spacing: 2) {
                  Text(link.title).font(.callout.weight(.semibold))
                  Text(Self.prettyURL(link.url))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
              }
            }
          }
        }
      }
      .padding(.horizontal, AppLayout.horizontalPadding)
      .padding(.top, 4)
    }
  }

  // MARK: - Row scaffolding

  @ViewBuilder
  private func contentRow<Content: View>(
    title: String,
    @ViewBuilder _ tiles: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.system(size: 30, weight: .bold))
        .padding(.horizontal, AppLayout.horizontalPadding)

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(alignment: .top, spacing: 22) {
          tiles()
        }
        .padding(.horizontal, AppLayout.horizontalPadding)
        .padding(.vertical, 12)
      }
      .scrollClipDisabled()
    }
    .focusSection()
  }

  private func loadingRow(title: String) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.system(size: 30, weight: .bold))
      HStack(spacing: 14) {
        ProgressView()
        Text("Loading…").foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, AppLayout.horizontalPadding)
  }

  /// A focusable thumbnail tile (clip or VOD) that triggers `action` on select.
  @ViewBuilder
  private func tile<Content: View>(
    id: String,
    action: @escaping () -> Void,
    @ViewBuilder content: () -> Content
  ) -> some View {
    content()
      .frame(width: tileWidth, alignment: .leading)
      .contentShape(RoundedRectangle(cornerRadius: 14))
      .focusable(true)
      .focused($focusedID, equals: id)
      .focusEffectDisabled()
      .onTapGesture(perform: action)
      .scaleEffect(focusedID == id ? 1.05 : 1)
      .animation(.easeOut(duration: 0.14), value: focusedID)
      .zIndex(focusedID == id ? 2 : 0)
  }

  private func mediaTile(thumbnail: URL?, badge: String?, title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      ZStack(alignment: .bottomTrailing) {
        AsyncImage(url: thumbnail) { image in
          image.resizable().scaledToFill()
        } placeholder: {
          Rectangle().fill(Color.primary.opacity(0.10))
        }
        .frame(width: tileWidth, height: tileMediaHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12))

        if let badge {
          Text(badge)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(.black.opacity(0.75)))
            .padding(10)
        }
      }

      Text(title)
        .font(.headline)
        .foregroundStyle(.primary)
        .lineLimit(1)
      Text(subtitle)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
  }

  // MARK: - Loading

  private func loadAll() async {
    isLoadingProfile = true
    profileFailed = false
    isLoadingContent = true
    isLoadingRecs = true

    async let profileTask = ChannelProfileService.fetch(login: target.login)
    async let contentTask = ChannelContentService.load(login: target.login)

    let loadedProfile = await profileTask
    profile = loadedProfile
    profileFailed = loadedProfile == nil
    isLoadingProfile = false
    if focusedID == nil {
      focusedID = canWatchThisChannel ? "watch" : "close"
    }

    let loadedContent = await contentTask
    content = loadedContent
    isLoadingContent = false

    if let signals = loadedContent?.signals {
      recommendations = await SimilarChannelsEngine.recommend(using: signals)
    }
    isLoadingRecs = false
  }

  private func followedChannel(from profile: ChannelProfile) -> FollowedChannel {
    FollowedChannel(
      id: profile.login,
      login: profile.login,
      displayName: profile.displayName,
      title: profile.liveTitle ?? "",
      gameName: profile.liveGame ?? "Live",
      viewerCount: profile.liveViewerCount,
      thumbnailURL: nil,
      profileImageURL: profile.profileImageURL,
      isLive: profile.isLive
    )
  }

  // MARK: - Formatting helpers

  private func lastSeenLabel(_ date: Date?) -> String {
    guard let date else { return "Offline" }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return "Last live \(formatter.localizedString(for: date, relativeTo: Date()))"
  }

  static func relativeDate(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: Date())
  }

  static func shortDuration(_ seconds: Int) -> String {
    let s = max(0, seconds)
    let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
    if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
    return String(format: "%d:%02d", m, sec)
  }

  static func longDuration(_ seconds: Int) -> String {
    let s = max(0, seconds)
    let h = s / 3600, m = (s % 3600) / 60
    if h > 0 { return "\(h)h \(m)m" }
    return "\(m)m"
  }

  static func compactCount(_ value: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    switch value {
    case 1_000_000...: return trimmed(Double(value) / 1_000_000) + "M"
    case 1_000...: return trimmed(Double(value) / 1_000) + "K"
    default: return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
  }

  static func plainCount(_ value: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
  }

  private static func trimmed(_ value: Double) -> String {
    let rounded = (value * 10).rounded() / 10
    if rounded.truncatingRemainder(dividingBy: 1) == 0 { return String(Int(rounded)) }
    return String(format: "%.1f", rounded)
  }

  static func monthYear(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM yyyy"
    return formatter.string(from: date)
  }

  static func uptime(since start: Date?) -> String? {
    guard let start else { return nil }
    let seconds = max(0, Date().timeIntervalSince(start))
    let hours = Int(seconds) / 3600
    let minutes = (Int(seconds) % 3600) / 60
    if hours > 0 { return "\(hours)h \(minutes)m" }
    return "\(minutes)m"
  }

  static func prettyURL(_ url: String) -> String {
    var result = url
    for prefix in ["https://", "http://", "www."] where result.hasPrefix(prefix) {
      result = String(result.dropFirst(prefix.count))
    }
    if result.hasSuffix("/") { result = String(result.dropLast()) }
    return result
  }
}
