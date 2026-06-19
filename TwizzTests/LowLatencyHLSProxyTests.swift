import XCTest

@testable import Twizz

final class LowLatencyHLSProxyTests: XCTestCase {
  private func makeProxy() -> LowLatencyHLSProxy {
    LowLatencyHLSProxy(headers: [:])
  }

  private let source = URL(string: "https://video.example/chunked.m3u8")!

  /// A minimal Twitch-style live media playlist with two real segments and one
  /// prefetch tag. `durations` sets each real segment's `#EXTINF`.
  private func mediaPlaylist(
    mediaSequence: Int,
    segments: [(name: String, duration: Double)],
    prefetch: [String]
  ) -> String {
    var lines = [
      "#EXTM3U",
      "#EXT-X-VERSION:3",
      "#EXT-X-TARGETDURATION:2",
      "#EXT-X-MEDIA-SEQUENCE:\(mediaSequence)",
    ]
    for seg in segments {
      lines.append("#EXTINF:\(String(format: "%.3f", seg.duration)),")
      lines.append("https://video.example/\(seg.name).ts")
    }
    for url in prefetch {
      lines.append("#EXT-X-TWITCH-PREFETCH:https://video.example/\(url).ts")
    }
    return lines.joined(separator: "\n")
  }

  // MARK: - Prefetch promotion

  func testPromotesPrefetchIntoRealSegment() {
    let proxy = makeProxy()
    let playlist = mediaPlaylist(
      mediaSequence: 100,
      segments: [("seg100", 2), ("seg101", 2)],
      prefetch: ["seg102"]
    )
    let out = proxy.rewriteMediaPlaylistForTesting(
      playlist, sourceURL: source, promotePrefetch: true, retainHistory: false)

    XCTAssertFalse(out.contains("#EXT-X-TWITCH-PREFETCH"), "prefetch tag should be rewritten")
    XCTAssertTrue(out.contains("https://video.example/seg102.ts"), "prefetch URL should be promoted")
    XCTAssertTrue(out.contains("https://video.example/seg100.ts"))
  }

  func testPrefetchOmittedWhenPromotionDisabled() {
    let proxy = makeProxy()
    let playlist = mediaPlaylist(
      mediaSequence: 100,
      segments: [("seg100", 2), ("seg101", 2)],
      prefetch: ["seg102"]
    )
    let out = proxy.rewriteMediaPlaylistForTesting(
      playlist, sourceURL: source, promotePrefetch: false, retainHistory: false)

    XCTAssertFalse(out.contains("seg102.ts"), "prefetch should not appear when promotion is off")
    XCTAssertTrue(out.contains("seg101.ts"), "real segments still pass through")
  }

  /// Twitch prefetch tags carry no duration, so the proxy synthesizes one from
  /// the AVERAGE of the real segments (Streamlink's heuristic) — not the last one.
  func testPromotedPrefetchUsesAverageSegmentDuration() {
    let proxy = makeProxy()
    let playlist = mediaPlaylist(
      mediaSequence: 100,
      segments: [("a", 2), ("b", 4)],
      prefetch: ["c"]
    )
    let out = proxy.rewriteMediaPlaylistForTesting(
      playlist, sourceURL: source, promotePrefetch: true, retainHistory: false)

    // (2 + 4) / 2 == 3.000; the naive "last segment" heuristic would give 4.000.
    XCTAssertTrue(
      out.contains("#EXTINF:3.000,\nhttps://video.example/c.ts"),
      "expected averaged 3.000s prefetch duration, got:\n\(out)")
  }

  // MARK: - DVR (Stream Rewind) retention

  func testRetentionGrowsThenSlidesWindow() {
    let proxy = makeProxy()
    let window: Double = 5  // seconds; each segment is 2s

    // First refresh: two 2s segments (4s total) fit under the 5s window.
    _ = proxy.rewriteMediaPlaylistForTesting(
      mediaPlaylist(mediaSequence: 100, segments: [("seg100", 2), ("seg101", 2)], prefetch: []),
      sourceURL: source, promotePrefetch: false, retainHistory: true, windowSeconds: window)

    // Second refresh advances by one segment; total would be 6s, so the oldest
    // (seg100) is evicted and the media sequence advances with it.
    let out = proxy.rewriteMediaPlaylistForTesting(
      mediaPlaylist(mediaSequence: 101, segments: [("seg101", 2), ("seg102", 2)], prefetch: []),
      sourceURL: source, promotePrefetch: false, retainHistory: true, windowSeconds: window)

    XCTAssertFalse(out.contains("seg100.ts"), "oldest segment should be evicted past the window")
    XCTAssertTrue(out.contains("seg101.ts"))
    XCTAssertTrue(out.contains("seg102.ts"))
    XCTAssertTrue(out.contains("#EXT-X-MEDIA-SEQUENCE:101"), "media sequence should advance:\n\(out)")
  }

  // MARK: - Master playlist rewriting

  func testMasterRewriteReroutesVariantAndMediaURIsOntoCustomScheme() {
    let proxy = makeProxy()
    let master = [
      "#EXTM3U",
      "#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"aac\",URI=\"https://video.example/audio.m3u8\"",
      "#EXT-X-STREAM-INF:BANDWIDTH=6000000,RESOLUTION=1920x1080",
      "https://video.example/chunked.m3u8",
    ].joined(separator: "\n")

    let out = proxy.rewriteMasterPlaylistForTesting(master)

    XCTAssertTrue(out.contains("twizz-ll://video.example/chunked.m3u8"))
    XCTAssertTrue(out.contains("URI=\"twizz-ll://video.example/audio.m3u8\""))
    XCTAssertFalse(out.contains("https://video.example/chunked.m3u8"))
  }

  // MARK: - Apple LL-HLS synthesis (experimental)

  /// The synthesized playlist must advertise LL-HLS so AVPlayer engages blocking
  /// reloads: CAN-BLOCK-RELOAD, PART-INF/PART-TARGET, PART-HOLD-BACK, version >= 6.
  func testLLHLSEmitsControlTags() {
    let proxy = makeProxy()
    let playlist = mediaPlaylist(
      mediaSequence: 100,
      segments: [("seg100", 2), ("seg101", 2)],
      prefetch: ["seg102", "seg103"]
    )
    let out = proxy.llhlsSynthesisForTesting(playlist).playlist

    XCTAssertTrue(out.contains("#EXT-X-SERVER-CONTROL:CAN-BLOCK-RELOAD=YES"))
    XCTAssertTrue(out.contains("PART-HOLD-BACK="))
    XCTAssertTrue(out.contains("#EXT-X-PART-INF:PART-TARGET="))
    XCTAssertTrue(out.contains("#EXT-X-VERSION:9"), "LL-HLS requires version >= 6:\n\(out)")
  }

  /// RFC 8216bis 4.4.4.7: PART-HOLD-BACK MUST be at least 3x PART-TARGET. With our
  /// coarse whole-segment parts this lands at ~6s — the crux finding that the
  /// hold-back lever yields no win without sub-second parts.
  func testLLHLSPartHoldBackIsAtLeastThreePartTarget() {
    let proxy = makeProxy()
    let playlist = mediaPlaylist(
      mediaSequence: 100, segments: [("a", 2), ("b", 2)], prefetch: ["c"])
    let out = proxy.llhlsSynthesisForTesting(playlist).playlist

    let partTarget = value(after: "PART-TARGET=", in: out)
    let holdBack = value(after: "PART-HOLD-BACK=", in: out)
    XCTAssertNotNil(partTarget)
    XCTAssertNotNil(holdBack)
    if let pt = partTarget, let hb = holdBack {
      XCTAssertGreaterThanOrEqual(hb, pt * 3 - 0.001, "hold-back must be >= 3x part-target")
    }
  }

  /// Segments + already-available prefetches become INDEPENDENT EXT-X-PARTs; the
  /// freshest prefetch becomes the trailing PRELOAD-HINT (the part AVPlayer
  /// pre-requests and the blocking reload holds open).
  func testLLHLSMapsPartsAndPreloadHint() {
    let proxy = makeProxy()
    let playlist = mediaPlaylist(
      mediaSequence: 100,
      segments: [("seg100", 2), ("seg101", 2)],
      prefetch: ["seg102", "seg103"]
    )
    let out = proxy.llhlsSynthesisForTesting(playlist).playlist

    XCTAssertTrue(
      out.contains("#EXT-X-PART:DURATION=2.000,URI=\"https://video.example/seg101.ts\",INDEPENDENT=YES"),
      "recent real segment should get a part line:\n\(out)")
    XCTAssertTrue(
      out.contains("#EXT-X-PART:DURATION=2.000,URI=\"https://video.example/seg102.ts\",INDEPENDENT=YES"),
      "available prefetch should become an EXT-X-PART:\n\(out)")
    XCTAssertTrue(
      out.contains("#EXT-X-PRELOAD-HINT:TYPE=PART,URI=\"https://video.example/seg103.ts\""),
      "freshest prefetch should be the preload hint:\n\(out)")
    // The preload-hint target must NOT also be advertised as an available part.
    XCTAssertFalse(
      out.contains("#EXT-X-PART:DURATION=2.000,URI=\"https://video.example/seg103.ts\""),
      "the hinted part is not yet available:\n\(out)")
    XCTAssertFalse(out.contains("#EXT-X-TWITCH-PREFETCH"), "proprietary tag must be gone")
  }

  /// availableMSN drives blocking-reload satisfaction: last real segment plus each
  /// already-available prefetch part, excluding the held-back preload-hint one.
  func testLLHLSAvailableMSNExcludesPreloadHint() {
    let proxy = makeProxy()
    // mediaSequence 100, two real segments (last real msn = 101), prefetch
    // [seg102 (available part), seg103 (preload hint)] -> available msn = 102.
    let twoHints = proxy.llhlsSynthesisForTesting(
      mediaPlaylist(
        mediaSequence: 100, segments: [("seg100", 2), ("seg101", 2)],
        prefetch: ["seg102", "seg103"])
    ).availableMSN
    XCTAssertEqual(twoHints, 102)

    // A single prefetch is held back entirely as the hint, so nothing past the
    // last real segment is available yet.
    let oneHint = proxy.llhlsSynthesisForTesting(
      mediaPlaylist(
        mediaSequence: 100, segments: [("seg100", 2), ("seg101", 2)], prefetch: ["seg102"])
    ).availableMSN
    XCTAssertEqual(oneHint, 101)
  }

  // MARK: - Blocking-reload query parsing

  func testBlockingReloadTargetParsing() {
    let proxy = makeProxy()
    let withParts = URL(string: "twizz-ll://video.example/chunked.m3u8?_HLS_msn=102&_HLS_part=0")!
    XCTAssertEqual(proxy.blockingReloadTarget(from: withParts)?.msn, 102)
    XCTAssertEqual(proxy.blockingReloadTarget(from: withParts)?.part, 0)

    let msnOnly = URL(string: "twizz-ll://video.example/chunked.m3u8?_HLS_msn=200")!
    XCTAssertEqual(proxy.blockingReloadTarget(from: msnOnly)?.msn, 200)
    XCTAssertEqual(proxy.blockingReloadTarget(from: msnOnly)?.part, 0, "part defaults to 0")

    let plain = URL(string: "twizz-ll://video.example/chunked.m3u8")!
    XCTAssertNil(proxy.blockingReloadTarget(from: plain), "no blocking params -> nil")
  }

  // MARK: - Helpers

  /// Extracts the numeric value immediately following `marker` in `text`.
  private func value(after marker: String, in text: String) -> Double? {
    guard let range = text.range(of: marker) else { return nil }
    let rest = text[range.upperBound...]
    let token = rest.prefix { $0.isNumber || $0 == "." }
    return Double(token)
  }
}
