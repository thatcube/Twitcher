import SwiftUI

/// Night Shift group: a warm, f.lux-style screen wash that fades in after sunset
/// and out before sunrise, based on the viewer's chosen region. tvOS can't warm
/// the system display, so this tints the app's own content (player included).
struct SettingsNightShiftSection: View {
  @Environment(AppEnvironment.self) private var environment
  private var nightShift: NightShiftManager { environment.nightShift }

  @Environment(\.glassDisabled) private var glassDisabled

  /// Which control currently holds focus. Focusing either arrow of the Dimness or
  /// Warmth stepper flips the overlay to full strength so each step is visible
  /// live; other controls leave the live schedule untouched.
  private enum NSControl: Hashable {
    case location
    case dimnessDown, dimnessUp
    case warmthDown, warmthUp
    case preview

    /// True for the Dimness/Warmth stepper arrows, which drive the live preview.
    var previewsLive: Bool {
      switch self {
      case .dimnessDown, .dimnessUp, .warmthDown, .warmthUp: return true
      case .location, .preview: return false
      }
    }
  }
  @FocusState private var focusedControl: NSControl?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      SettingRow(
        title: "Night Shift",
        subtitle: nightShift.scheduleSummary()
      ) {
        ForEach([true, false], id: \.self) { on in
          Button {
            nightShift.isEnabled = on
          } label: {
            SettingPill(title: on ? "On" : "Off", isSelected: nightShift.isEnabled == on)
          }
          .settingPillStyle(isSelected: nightShift.isEnabled == on)
        }
      }
      .padding(.vertical, 16)

      if nightShift.isEnabled {
        groupDivider

        HStack(alignment: .bottom, spacing: 32) {
          labeledMenu("Location", value: nightShift.region.name, focus: .location) { regionPicker }

          stepper(
            "Dimness",
            levels: NightShiftDimness.allCases,
            selected: nightShift.dimness,
            display: { $0.displayName },
            down: .dimnessDown,
            up: .dimnessUp,
            commit: { nightShift.dimness = $0 }
          )
          stepper(
            "Warmth",
            levels: NightShiftWarmth.allCases,
            selected: nightShift.warmth,
            display: { $0.displayName },
            down: .warmthDown,
            up: .warmthUp,
            commit: { nightShift.warmth = $0 }
          )

          Spacer(minLength: 24)

          DayNightDial(
            intensity: nightShift.currentIntensity,
            progress: nightShift.previewProgress
          )
          .frame(width: 120, height: 64)

          previewButton
        }
        .padding(.vertical, 16)
        .focusSection()
      }
    }
    .padding(.horizontal, 28)
    .settingsGlassPanel(disabled: glassDisabled)
    .onChange(of: focusedControl) { _, control in
      // Full-strength preview only while a Dimness/Warmth arrow is focused, so the
      // viewer can calibrate at deep-night intensity; it switches off the moment
      // focus moves to Location, the preview button, or off the section entirely.
      nightShift.isPreviewing = control?.previewsLive ?? false
    }
    .onChange(of: nightShift.isEnabled) { _, enabled in
      if !enabled { nightShift.isPreviewing = false }
    }
    .onDisappear {
      nightShift.isPreviewing = false
    }
  }

  /// Compact "fast-forward a day" trigger; the simulated clock replaces the label
  /// while a sweep is running.
  private var previewButton: some View {
    Button {
      nightShift.runDayNightPreview()
    } label: {
      Text(nightShift.previewProgress == nil ? "Preview a day" : nightShift.previewClockText)
        .font(.headline)
        .monospacedDigit()
        .frame(minWidth: 150, alignment: .leading)
    }
    .settingsProminentActionButtonStyle()
    .focused($focusedControl, equals: .preview)
  }

  /// A small inline label paired with its dropdown trigger, used to pack Location,
  /// Dimness, and Warmth onto a single line. `focus` ties the trigger into the
  /// section's focus tracking.
  private func labeledMenu<Content: View>(
    _ label: String,
    value: String,
    focus: NSControl,
    @ViewBuilder picker: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(label)
        .font(.system(size: 24, weight: .semibold))
        .foregroundStyle(.secondary)
      Menu {
        picker()
      } label: {
        SettingPill(title: value, isSelected: false, showsMenuIndicator: true)
      }
      .settingsProminentActionButtonStyle()
      .focused($focusedControl, equals: focus)
    }
  }

  /// A labeled left/right stepper for Dimness/Warmth. Each press of an arrow
  /// commits the next level immediately, so — paired with the full-strength
  /// preview that turns on while an arrow is focused — the overlay updates live as
  /// you step. Stepping is the *select* action; left/right swipes still move focus
  /// between controls as usual, so there's no dropdown to trap focus.
  private func stepper<Level: Hashable>(
    _ label: String,
    levels: [Level],
    selected: Level,
    display: (Level) -> String,
    down: NSControl,
    up: NSControl,
    commit: @escaping (Level) -> Void
  ) -> some View {
    let index = levels.firstIndex(of: selected) ?? 0
    return VStack(alignment: .leading, spacing: 8) {
      Text(label)
        .font(.system(size: 24, weight: .semibold))
        .foregroundStyle(.secondary)
      HStack(spacing: 14) {
        stepArrow(.chevronLeft, focus: down, enabled: index > 0) {
          if index > 0 { commit(levels[index - 1]) }
        }
        Text(display(selected))
          .font(.headline)
          .lineLimit(1)
          .frame(minWidth: 150)
        stepArrow(.chevronRight, focus: up, enabled: index < levels.count - 1) {
          if index < levels.count - 1 { commit(levels[index + 1]) }
        }
      }
    }
  }

  /// One arrow of a stepper. Stays focusable at the ends (so focus — and the live
  /// preview — isn't lost when you reach Min/Max); it just dims and no-ops there.
  private func stepArrow(
    _ glyph: Glyph,
    focus: NSControl,
    enabled: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Icon(glyph: glyph, size: 36)
        .opacity(enabled ? 1 : 0.3)
    }
    .settingsProminentActionButtonStyle()
    .focused($focusedControl, equals: focus)
  }

  private var regionPicker: some View {
    Picker("Location", selection: regionSelection) {
      ForEach(NightShiftRegion.sortedCatalog) { region in
        Text(region.name).tag(region.id)
      }
    }
    .pickerStyle(.inline)
  }

  private var groupDivider: some View {
    Divider()
      .overlay(Color.primary.opacity(0.12))
  }

  private var regionSelection: Binding<String> {
    Binding(
      get: { nightShift.regionID },
      set: { nightShift.regionID = $0 }
    )
  }
}

// MARK: - Day/night preview dial

/// A tiny self-contained sky: a sun arcs across by day and a moon by night, with
/// the sky colour shifting day → sunset → night to mirror the actual Night Shift
/// intensity. `progress` (0…1) places the celestial body horizontally across the
/// simulated day; when nil (idle) it rests mid-arc.
private struct DayNightDial: View {
  /// 0 = full daylight, 1 = deep night. Drives sky colour + sun vs. moon.
  var intensity: Double
  /// 0…1 sweep position; nil when no preview is running.
  var progress: Double?

  private static let dayTop = (0.40, 0.68, 0.95)
  private static let dayBottom = (0.72, 0.86, 0.99)
  private static let duskTop = (0.86, 0.46, 0.30)
  private static let duskBottom = (0.99, 0.72, 0.38)
  private static let nightTop = (0.03, 0.05, 0.14)
  private static let nightBottom = (0.10, 0.13, 0.26)

  var body: some View {
    let p = progress ?? 0.5
    let sky = skyColors()
    GeometryReader { geo in
      let w = geo.size.width
      let h = geo.size.height
      let bodySize = h * 0.34
      let starSize = max(2.0, h * 0.045)
      let x = w * p
      let y = h * (0.84 - 0.58 * sin(.pi * p))
      let isNight = intensity > 0.5
      ZStack {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(
            LinearGradient(colors: [sky.top, sky.bottom], startPoint: .top, endPoint: .bottom)
          )

        if intensity > 0.55 {
          ForEach(Array(Self.stars.enumerated()), id: \.offset) { _, star in
            Circle()
              .fill(.white.opacity(0.75))
              .frame(width: starSize, height: starSize)
              .position(x: w * star.0, y: h * star.1)
          }
        }

        Circle()
          .fill(isNight ? Color(.sRGB, red: 0.92, green: 0.94, blue: 1.0)
                        : Color(.sRGB, red: 1.0, green: 0.86, blue: 0.34))
          .frame(width: bodySize, height: bodySize)
          .shadow(
            color: (isNight ? Color.white : Color(.sRGB, red: 1.0, green: 0.8, blue: 0.3)).opacity(0.6),
            radius: 6
          )
          .position(x: x, y: y)
      }
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    .animation(.linear(duration: 0.06), value: progress)
  }

  private static let stars: [(Double, Double)] = [(0.24, 0.30), (0.55, 0.48), (0.79, 0.26)]

  private func skyColors() -> (top: Color, bottom: Color) {
    let i = max(0, min(1, intensity))
    let top: (Double, Double, Double)
    let bottom: (Double, Double, Double)
    if i <= 0.5 {
      let t = i / 0.5
      top = lerp(Self.dayTop, Self.duskTop, t)
      bottom = lerp(Self.dayBottom, Self.duskBottom, t)
    } else {
      let t = (i - 0.5) / 0.5
      top = lerp(Self.duskTop, Self.nightTop, t)
      bottom = lerp(Self.duskBottom, Self.nightBottom, t)
    }
    return (color(top), color(bottom))
  }

  private func color(_ rgb: (Double, Double, Double)) -> Color {
    Color(.sRGB, red: rgb.0, green: rgb.1, blue: rgb.2)
  }

  private func lerp(
    _ a: (Double, Double, Double),
    _ b: (Double, Double, Double),
    _ t: Double
  ) -> (Double, Double, Double) {
    (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t)
  }
}
