import SwiftUI

/// Night Shift group: a warm, f.lux-style screen wash that fades in after sunset
/// and out before sunrise, based on the viewer's chosen region. tvOS can't warm
/// the system display, so this tints the app's own content (player included).
struct SettingsNightShiftSection: View {
  @Environment(AppEnvironment.self) private var environment
  private var nightShift: NightShiftManager { environment.nightShift }

  @Environment(\.glassDisabled) private var glassDisabled

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Night Shift")
        .font(.system(size: 32, weight: .bold))
        .accessibilityAddTraits(.isHeader)
        .padding(.bottom, 4)

      Text(nightShift.scheduleSummary())
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.bottom, 20)

      VStack(spacing: 0) {
        enabledRow
          .padding(.vertical, 16)

        if nightShift.isEnabled {
          groupDivider
          regionRow
            .padding(.vertical, 16)

          groupDivider
          warmthRow
            .padding(.vertical, 16)

          groupDivider
          strengthRow
            .padding(.vertical, 16)
        }
      }
      .padding(.horizontal, 28)
      .settingsGlassPanel(disabled: glassDisabled)
    }
  }

  private var groupDivider: some View {
    Divider()
      .overlay(Color.primary.opacity(0.12))
  }

  private var enabledRow: some View {
    SettingRow(
      title: "Night Shift",
      subtitle: "Gradually warm the picture as it gets late, easing back to normal by morning."
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
  }

  private var regionRow: some View {
    SettingRow(
      title: "Location",
      subtitle: "Used to find local sunset and sunrise. No GPS or permissions needed."
    ) {
      Menu {
        Picker("Location", selection: regionSelection) {
          ForEach(NightShiftRegion.sortedCatalog) { region in
            Text(region.name).tag(region.id)
          }
        }
        .pickerStyle(.inline)
      } label: {
        SettingPill(title: nightShift.region.name, isSelected: false, showsMenuIndicator: true)
      }
      .settingsProminentActionButtonStyle()
    }
  }

  private var warmthRow: some View {
    SettingRow(
      title: "Warmth",
      subtitle: "How far toward red the picture shifts at its warmest."
    ) {
      ForEach(NightShiftWarmth.allCases) { level in
        Button {
          nightShift.warmth = level
        } label: {
          SettingPill(title: level.displayName, isSelected: nightShift.warmth == level)
        }
        .settingPillStyle(isSelected: nightShift.warmth == level)
      }
    }
  }

  private var strengthRow: some View {
    SettingRow(
      title: "Strength",
      subtitle: "How strong the warm tint gets in the dead of night."
    ) {
      ForEach(NightShiftStrength.allCases) { level in
        Button {
          nightShift.strength = level
        } label: {
          SettingPill(title: level.displayName, isSelected: nightShift.strength == level)
        }
        .settingPillStyle(isSelected: nightShift.strength == level)
      }
    }
  }

  private var regionSelection: Binding<String> {
    Binding(
      get: { nightShift.regionID },
      set: { nightShift.regionID = $0 }
    )
  }
}
