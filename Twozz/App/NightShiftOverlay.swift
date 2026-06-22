import SwiftUI
import UIKit

/// Installs Night Shift's warm wash so it floats above *everything* — including
/// the player and other `fullScreenCover`s — without ever stealing focus.
///
/// Why a separate `UIWindow` rather than a SwiftUI `.overlay`: the player, chat,
/// multiview, and sign-in screens are all presented as full-screen covers, which
/// sit in their own presentation context above `HomeView`'s view tree. An overlay
/// attached inside `HomeView` would be covered by them (and wouldn't tint the
/// video at all). A dedicated passthrough window at a high window level is the one
/// place that reliably sits on top of the whole app, mirroring how the system's
/// own Night Shift covers the entire screen.

// MARK: - Passthrough window

/// A window that never intercepts touches or focus — it only paints. Returning
/// `nil` from `hitTest` keeps the tvOS focus engine from ever routing to it, so
/// it's purely cosmetic.
private final class NightShiftOverlayWindow: UIWindow {
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}

// MARK: - Tint view

/// The SwiftUI content the overlay window hosts: a single warm fill whose color
/// and opacity track the manager. `allowsHitTesting(false)` is belt-and-braces
/// alongside the window's `hitTest` override.
private struct NightShiftTintView: View {
  var manager: NightShiftManager

  var body: some View {
    Rectangle()
      .fill(manager.currentTint)
      .ignoresSafeArea()
      .allowsHitTesting(false)
      .animation(.easeInOut(duration: 0.6), value: manager.currentOpacity)
      .animation(.easeInOut(duration: 0.6), value: manager.warmth)
  }
}

// MARK: - Installer

/// Finds the active window scene and lazily creates the overlay window once,
/// then keeps it alive for the app's lifetime. Lives as a hidden representable
/// inside the root view so it gets a `window` (hence a `windowScene`) to attach
/// to.
private struct NightShiftOverlayInstaller: UIViewRepresentable {
  var manager: NightShiftManager

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeUIView(context: Context) -> UIView {
    let probe = UIView(frame: .zero)
    probe.isHidden = true
    return probe
  }

  func updateUIView(_ uiView: UIView, context: Context) {
    guard context.coordinator.overlayWindow == nil,
          let scene = uiView.window?.windowScene
    else { return }

    let window = NightShiftOverlayWindow(windowScene: scene)
    window.isUserInteractionEnabled = false
    // Above alerts and full-screen covers so the wash covers the whole app.
    window.windowLevel = .alert + 1

    let host = UIHostingController(rootView: NightShiftTintView(manager: manager))
    host.view.backgroundColor = .clear
    host.view.isUserInteractionEnabled = false
    window.rootViewController = host
    window.isHidden = false

    context.coordinator.overlayWindow = window
  }

  final class Coordinator {
    var overlayWindow: UIWindow?
  }
}

extension View {
  /// Attaches the global Night Shift warm-wash overlay window.
  func installNightShiftOverlay(_ manager: NightShiftManager) -> some View {
    background(NightShiftOverlayInstaller(manager: manager))
  }
}
