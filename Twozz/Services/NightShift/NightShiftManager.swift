import SwiftUI

// MARK: - Warmth

/// How warm (toward red) the Night Shift wash goes at full strength. Discrete
/// levels rather than a slider because steppers/pills are the tvOS-native,
/// remote-friendly idiom (raw sliders are awkward on the Siri Remote).
enum NightShiftWarmth: String, CaseIterable, Identifiable, Codable {
  case warm
  case warmer
  case warmest

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .warm: return "Warm"
    case .warmer: return "Warmer"
    case .warmest: return "Warmest"
    }
  }

  /// The hue the wash tends toward — gentle amber through deep ember red.
  var color: Color {
    switch self {
    case .warm: return Color(red: 1.00, green: 0.62, blue: 0.28)
    case .warmer: return Color(red: 1.00, green: 0.45, blue: 0.18)
    case .warmest: return Color(red: 1.00, green: 0.30, blue: 0.12)
    }
  }
}

// MARK: - Strength

/// The peak opacity the wash reaches in the dead of night.
enum NightShiftStrength: String, CaseIterable, Identifiable, Codable {
  case subtle
  case medium
  case strong
  case max

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .subtle: return "Subtle"
    case .medium: return "Medium"
    case .strong: return "Strong"
    case .max: return "Max"
    }
  }

  var peakOpacity: Double {
    switch self {
    case .subtle: return 0.12
    case .medium: return 0.22
    case .strong: return 0.34
    case .max: return 0.48
    }
  }
}

// MARK: - Manager

/// Owns the Night Shift settings and computes the live warm-wash color the
/// overlay paints. Like `ThemeManager`, it persists its selections to
/// `UserDefaults` and broadcasts changes via `@Observable`; a one-minute timer
/// nudges `tick` so the intensity re-evaluates as the evening progresses.
@MainActor
@Observable
final class NightShiftManager {
  /// How long the wash takes to fade fully in after sunset / fully out before
  /// sunrise. Mirrors the gentle ramp f.lux/Night Shift use.
  private static let transition: TimeInterval = 90 * 60

  var isEnabled: Bool {
    didSet { UserDefaults.standard.set(isEnabled, forKey: PersistenceKey.nightShiftEnabled) }
  }

  var regionID: String {
    didSet { UserDefaults.standard.set(regionID, forKey: PersistenceKey.nightShiftRegion) }
  }

  var warmth: NightShiftWarmth {
    didSet { UserDefaults.standard.set(warmth.rawValue, forKey: PersistenceKey.nightShiftWarmth) }
  }

  var strength: NightShiftStrength {
    didSet { UserDefaults.standard.set(strength.rawValue, forKey: PersistenceKey.nightShiftStrength) }
  }

  /// Bumped by the timer so time-derived values recompute. Reading it in a
  /// computed property is what ties the overlay's redraw to the clock.
  private var tick: Date = .init()
  private var timer: Timer?

  init() {
    let defaults = UserDefaults.standard
    isEnabled = defaults.bool(forKey: PersistenceKey.nightShiftEnabled)
    regionID = defaults.string(forKey: PersistenceKey.nightShiftRegion)
      ?? NightShiftRegion.guessFromCurrentTimeZone().id
    warmth = defaults.string(forKey: PersistenceKey.nightShiftWarmth)
      .flatMap(NightShiftWarmth.init(rawValue:)) ?? .warmer
    strength = defaults.string(forKey: PersistenceKey.nightShiftStrength)
      .flatMap(NightShiftStrength.init(rawValue:)) ?? .medium

    let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.tick = Date() }
    }
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  // MARK: Resolved values

  var region: NightShiftRegion {
    NightShiftRegion.region(id: regionID) ?? NightShiftRegion.guessFromCurrentTimeZone()
  }

  /// 0…1 ramp for the current moment (0 by day, 1 deep at night).
  var currentIntensity: Double {
    guard isEnabled else { return 0 }
    return intensity(at: tick)
  }

  /// Opacity the overlay should paint the warm tint at right now.
  var currentOpacity: Double {
    currentIntensity * strength.peakOpacity
  }

  /// The warm color resolved at the current intensity — fully transparent during
  /// the day, ramping to `warmth.color` at `strength.peakOpacity` overnight.
  var currentTint: Color {
    warmth.color.opacity(currentOpacity)
  }

  /// Whether the wash is visibly painting anything right now.
  var isActiveNow: Bool { currentOpacity > 0.001 }

  // MARK: Schedule

  /// Today's sunset and the next sunrise for the selected region, used to show a
  /// human-readable status in Settings.
  func scheduleSummary(now: Date = Date()) -> String {
    let region = self.region
    let tz = region.timeZone
    guard let today = SolarTime.sunriseSunset(
      latitude: region.latitude, longitude: region.longitude, on: now, timeZone: tz
    ) else {
      return "Sunrise/sunset unavailable at this location today."
    }

    let formatter = DateFormatter()
    formatter.timeZone = tz
    formatter.dateFormat = "h:mm a"

    let sunset = formatter.string(from: today.sunset)
    let sunrise = formatter.string(from: today.sunrise)

    if !isEnabled {
      return "Off. \(region.name): sunset \(sunset), sunrise \(sunrise)."
    }
    if isActiveNow {
      let percent = Int((currentIntensity * 100).rounded())
      return "Active now (\(percent)%). \(region.name) sunrise \(sunrise)."
    }
    return "Idle until sunset (\(sunset)) in \(region.name)."
  }

  // MARK: Ramp math

  private func intensity(at date: Date) -> Double {
    let region = self.region
    let tz = region.timeZone
    guard let today = SolarTime.sunriseSunset(
      latitude: region.latitude, longitude: region.longitude, on: date, timeZone: tz
    ) else {
      return 0
    }

    if date < today.sunrise {
      // Pre-dawn: the night began at yesterday's sunset.
      let yesterday = SolarTime.sunriseSunset(
        latitude: region.latitude,
        longitude: region.longitude,
        on: date.addingTimeInterval(-86_400),
        timeZone: tz
      )
      let dusk = yesterday?.sunset ?? today.sunset.addingTimeInterval(-86_400)
      return ramp(now: date, dusk: dusk, dawn: today.sunrise)
    } else if date < today.sunset {
      // Daytime.
      return 0
    } else {
      // After dusk: the night ends at tomorrow's sunrise.
      let tomorrow = SolarTime.sunriseSunset(
        latitude: region.latitude,
        longitude: region.longitude,
        on: date.addingTimeInterval(86_400),
        timeZone: tz
      )
      let dawn = tomorrow?.sunrise ?? today.sunrise.addingTimeInterval(86_400)
      return ramp(now: date, dusk: today.sunset, dawn: dawn)
    }
  }

  /// Triangle-clamped ramp: 0 at `dusk`, up over `transition`, hold at 1, down
  /// over `transition` to 0 at `dawn`. Taking the min of the two legs also
  /// gracefully handles short summer nights shorter than `2 × transition`.
  private func ramp(now: Date, dusk: Date, dawn: Date) -> Double {
    guard now > dusk, now < dawn else { return 0 }
    let up = now.timeIntervalSince(dusk) / Self.transition
    let down = dawn.timeIntervalSince(now) / Self.transition
    return Swift.max(0, Swift.min(1, Swift.min(up, down)))
  }
}
