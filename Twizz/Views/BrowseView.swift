import SwiftUI

// MARK: - BrowseView

struct BrowseView: View {
    let auth: TwitchAuthSession
    let pagePadding: CGFloat
    @Binding var selectedChannel: FollowedChannel?

    @State private var service = BrowseService()
    @State private var selectedCategory: TwitchCategory?

    var body: some View {
        if let category = selectedCategory {
            BrowseStreamsView(
                category: category,
                service: service,
                pagePadding: pagePadding,
                selectedChannel: $selectedChannel,
                onBack: {
                    selectedCategory = nil
                }
            )
        } else {
            BrowseCategoriesView(
                service: service,
                onSelectCategory: { category in
                    selectedCategory = category
                    Task { await service.loadStreams(for: category) }
                }
            )
            .task {
                if service.categories.isEmpty {
                    await service.loadCategories()
                }
            }
        }
    }
}

// MARK: - Categories Grid

private struct BrowseCategoriesView: View {
    let service: BrowseService
    let onSelectCategory: (TwitchCategory) -> Void

    @FocusState private var focusedID: String?

    private let columns = [
        GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 24)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("Browse")
                    .font(.title.weight(.bold))

                if service.isLoadingCategories {
                    ProgressView().scaleEffect(0.85)
                }

                Spacer()

                Button("Refresh") {
                    Task { await service.loadCategories() }
                }
            }

            if let err = service.categoryErrorMessage {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 24) {
                    ForEach(service.categories) { category in
                        let isFocused = focusedID == category.id
                        CategoryCard(
                            category: category,
                            isFocused: isFocused
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                        .focusable(true)
                        .focused($focusedID, equals: category.id)
                        .focusEffectDisabled()
                        .onTapGesture {
                            onSelectCategory(category)
                        }
                        .scaleEffect(isFocused ? 1.07 : 1)
                        .animation(.easeOut(duration: 0.14), value: isFocused)
                        .zIndex(isFocused ? 2 : 0)
                    }
                }
                .padding(.vertical, 8)
            }
            .scrollClipDisabled()
            .focusSection()

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: service.categories) { _, categories in
            if focusedID == nil, let first = categories.first {
                Task {
                    try? await Task.sleep(for: .milliseconds(150))
                    await MainActor.run { focusedID = first.id }
                }
            }
        }
    }
}

// MARK: - Streams for a Category

private struct BrowseStreamsView: View {
    let category: TwitchCategory
    let service: BrowseService
    let pagePadding: CGFloat
    @Binding var selectedChannel: FollowedChannel?
    let onBack: () -> Void

    @FocusState private var focusedStreamID: String?

    private let targetVisibleCards: CGFloat = 4
    private let peekCardFraction: CGFloat = 0.15
    private let focusHorizontalInset: CGFloat = 18
    private let focusVerticalInset: CGFloat = 18
    private let cardCornerRadius: CGFloat = 22
    private let mediaCornerRadius: CGFloat = 18
    private let minMediaWidth: CGFloat = 220
    private let maxMediaWidth: CGFloat = 560
    private let cardSpacing: CGFloat = 24

    var body: some View {
        GeometryReader { proxy in
            let rail = railMetrics(for: proxy.size.width)
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack(spacing: 20) {
                    Button(action: onBack) {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.left")
                            Text("Categories")
                        }
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white.opacity(0.1))
                        )
                    }
                    .buttonStyle(.plain)

                    if let url = category.boxArtURL {
                        AsyncImage(url: url) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            Color.white.opacity(0.08)
                        }
                        .frame(width: 40, height: 53)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.name)
                            .font(.title.weight(.bold))
                        if let viewers = category.viewerCount {
                            Text("\(viewers) watching")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if service.isLoadingStreams {
                        ProgressView().scaleEffect(0.85)
                    }

                    Spacer()
                }
                .focusSection()

                if let err = service.streamsErrorMessage {
                    Text(err)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                if !service.isLoadingStreams && service.categoryStreams.isEmpty && service.streamsErrorMessage == nil {
                    Text("No live streams found for \(category.name) right now.")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: rail.spacing) {
                            ForEach(service.categoryStreams) { channel in
                                let isFocused = focusedStreamID == channel.id
                                BrowseChannelCard(
                                    channel: channel,
                                    isFocused: isFocused,
                                    mediaWidth: rail.mediaWidth,
                                    mediaHeight: rail.mediaHeight,
                                    focusHorizontalInset: focusHorizontalInset,
                                    focusVerticalInset: focusVerticalInset,
                                    cardCornerRadius: cardCornerRadius,
                                    mediaCornerRadius: mediaCornerRadius
                                )
                                .contentShape(RoundedRectangle(cornerRadius: cardCornerRadius))
                                .focusable(true)
                                .focused($focusedStreamID, equals: channel.id)
                                .focusEffectDisabled()
                                .onTapGesture {
                                    selectedChannel = channel
                                }
                                .scaleEffect(isFocused ? 1.07 : 1)
                                .animation(.easeOut(duration: 0.14), value: isFocused)
                                .zIndex(isFocused ? 2 : 0)
                            }
                        }
                        .padding(.vertical, 20)
                    }
                    .scrollClipDisabled()
                    .focusSection()
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onChange(of: service.categoryStreams) { _, streams in
            if let first = streams.first {
                Task {
                    try? await Task.sleep(for: .milliseconds(150))
                    await MainActor.run { focusedStreamID = first.id }
                }
            }
        }
    }

    private func railMetrics(for availableWidth: CGFloat) -> (spacing: CGFloat, mediaWidth: CGFloat, mediaHeight: CGFloat) {
        let width = max(availableWidth, 1)
        let spacing = max(18, min(32, width * 0.012))
        let rawCardWidth = (width - ((targetVisibleCards - 1) * spacing)) / (targetVisibleCards + peekCardFraction)
        let minCardWidth = minMediaWidth + (focusHorizontalInset * 2)
        let maxCardWidth = maxMediaWidth + (focusHorizontalInset * 2)
        let cardWidth = min(max(rawCardWidth, minCardWidth), maxCardWidth)
        let mediaWidth = cardWidth - (focusHorizontalInset * 2)
        let mediaHeight = mediaWidth * 9 / 16
        return (spacing, mediaWidth, mediaHeight)
    }
}

// MARK: - Category Card

private struct CategoryCard: View {
    let category: TwitchCategory
    let isFocused: Bool

    private let cornerRadius: CGFloat = 14
    private let artRatio: CGFloat = 285.0 / 380.0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AsyncImage(url: category.boxArtURL) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                Color.white.opacity(0.08)
            }
            .aspectRatio(artRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius - 2))

            VStack(alignment: .leading, spacing: 4) {
                Text(category.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isFocused ? Color.black.opacity(0.92) : Color.primary)
                    .lineLimit(2)

                if let viewers = category.viewerCount {
                    Text("\(viewers) watching")
                        .font(.caption2)
                        .foregroundStyle(isFocused ? Color.black.opacity(0.6) : Color.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 10)
        }
        .background {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(isFocused ? Color.white : Color.white.opacity(0.07))
        }
    }
}

// MARK: - Browse Channel Card

private struct BrowseChannelCard: View {
    let channel: FollowedChannel
    let isFocused: Bool
    let mediaWidth: CGFloat
    let mediaHeight: CGFloat
    let focusHorizontalInset: CGFloat
    let focusVerticalInset: CGFloat
    let cardCornerRadius: CGFloat
    let mediaCornerRadius: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: channel.thumbnailURL) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Color.white.opacity(0.08)
                }
                .frame(width: mediaWidth, height: mediaHeight)
                .clipShape(RoundedRectangle(cornerRadius: mediaCornerRadius))

                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.82)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: mediaWidth, height: mediaHeight)
                .clipShape(RoundedRectangle(cornerRadius: mediaCornerRadius))

                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    if let viewerCount = channel.viewerCount {
                        Text("\(viewerCount) watching")
                            .font(.caption2)
                            .foregroundStyle(Color.white.opacity(0.78))
                    }
                }
                .padding(12)
            }
            .frame(width: mediaWidth, alignment: .leading)

            Text(channel.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isFocused ? Color.black.opacity(0.92) : Color.primary)
                .lineLimit(1)

            Text(channel.title.isEmpty ? "No title" : channel.title)
                .font(.footnote)
                .foregroundStyle(isFocused ? Color.black.opacity(0.62) : Color.secondary)
                .lineLimit(2)
                .frame(height: 38, alignment: .topLeading)
        }
        .padding(.horizontal, focusHorizontalInset)
        .padding(.vertical, focusVerticalInset)
        .frame(width: mediaWidth + (focusHorizontalInset * 2), alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: cardCornerRadius)
                .fill(isFocused ? Color.white : Color.white.opacity(0.07))
        }
    }
}
