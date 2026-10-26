import SwiftUI

/// Kladz visual system: midnight surfaces, electric violet actions, and signal-lime highlights.
enum KladzTheme {
    /// Primary action and map-route color — vivid violet with strong contrast on dark surfaces.
    static let accent = Color(red: 0.58, green: 0.40, blue: 1.00)
    /// Secondary action / drawn route color — bright signal lime.
    static let accentSecondary = Color(red: 0.78, green: 0.96, blue: 0.32)
    static let danger = Color(red: 1.00, green: 0.30, blue: 0.39)
    static let panelStroke = Color.white.opacity(0.14)
    static let statusGood = Color(red: 0.30, green: 0.91, blue: 0.66)
    static let statusWarn = Color(red: 1.00, green: 0.76, blue: 0.28)
    static let statusBad = Color(red: 1.00, green: 0.30, blue: 0.39)
}

enum KladzGlassStyle {
    case regular
    case clear
    case interactive
}

/// Material-based glass styling, compatible with the Xcode 16 / iOS 18 SDK used in CI.
struct KladzGlassModifier<S: Shape>: ViewModifier {
    var style: KladzGlassStyle
    var shape: S
    var tint: Color?

    func body(content: Content) -> some View {
        content
            .background {
                shape.fill(.ultraThinMaterial)
                if let tint {
                    shape.fill(tint.opacity(style == .clear ? 0.22 : 0.55))
                }
            }
            .overlay {
                shape.stroke(KladzTheme.panelStroke, lineWidth: 1)
            }
            .contentShape(shape)
    }
}

extension View {
    func kladzGlass<S: Shape>(
        _ style: KladzGlassStyle = .regular,
        tint: Color? = nil,
        in shape: S
    ) -> some View {
        modifier(KladzGlassModifier(style: style, shape: shape, tint: tint))
    }

    func kladzGlass(_ style: KladzGlassStyle = .regular, tint: Color? = nil) -> some View {
        kladzGlass(style, tint: tint, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
