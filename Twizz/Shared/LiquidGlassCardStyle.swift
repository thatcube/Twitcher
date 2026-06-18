import SwiftUI

/// Shared glass card surface used by reusable browsing/channel cards.
/// Keeps focused state legible while adding edge highlights and refraction.
struct TwizzLiquidGlassCardModifier: ViewModifier {
  let cornerRadius: CGFloat
  let isFocused: Bool
  let palette: ThemePalette

  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

    content
      .background {
        if isFocused {
          shape.fill(palette.liftSurface)
        } else {
          shape
            .fill(.ultraThinMaterial)
            .overlay {
              shape.fill(
                LinearGradient(
                  stops: [
                    .init(color: .white.opacity(0.20), location: 0.0),
                    .init(color: .white.opacity(0.08), location: 0.33),
                    .init(color: .clear, location: 1.0),
                  ],
                  startPoint: .topLeading,
                  endPoint: .bottomTrailing
                )
              )
            }
        }
      }
      .overlay {
        shape.strokeBorder(Color.white.opacity(isFocused ? 0.18 : 0.22), lineWidth: 1)
      }
      .overlay {
        shape
          .strokeBorder(
            LinearGradient(
              stops: [
                .init(color: .white.opacity(isFocused ? 0.18 : 0.34), location: 0.0),
                .init(color: .white.opacity(0.06), location: 0.36),
                .init(color: Color.cyan.opacity(isFocused ? 0.05 : 0.14), location: 0.68),
                .init(color: Color.purple.opacity(isFocused ? 0.04 : 0.12), location: 1.0),
              ],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            ),
            lineWidth: 1
          )
          .blur(radius: 0.35)
      }
      .overlay(alignment: .topLeading) {
        Circle()
          .fill(
            LinearGradient(
              colors: [.white.opacity(isFocused ? 0.10 : 0.26), .clear],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
          .frame(width: cornerRadius * 3.2, height: cornerRadius * 3.2)
          .offset(x: -cornerRadius * 0.95, y: -cornerRadius * 0.95)
          .blendMode(.screen)
          .allowsHitTesting(false)
      }
      .clipShape(shape)
  }
}

extension View {
  func twizzLiquidGlassCard(cornerRadius: CGFloat, isFocused: Bool, palette: ThemePalette) -> some View {
    modifier(
      TwizzLiquidGlassCardModifier(
        cornerRadius: cornerRadius,
        isFocused: isFocused,
        palette: palette
      )
    )
  }
}
