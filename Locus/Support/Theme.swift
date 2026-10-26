import SwiftUI

/// Kladz visual system: midnight surfaces, electric violet actions, and signal-lime highlights.
enum LocusTheme {
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

enum LocusGlassStyle {
    case regular
    case clear
    case interactive
}

/// Liquid Glass on iOS 26+; material fallback earlier.
struct LocusGlassModifier<S: Shape>: ViewModifier {
    var style: LocusGlassStyle
    var shape: S
    var tint: Color?

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(glass, in: shape)
                // Glass draws outside the layout bounds; expand hit-testing to match.
                .contentShape(shape)
        } else {
            content
                .background {
                    shape.fill(.ultraThinMaterial)
                    if let tint {
                        shape.fill(tint.opacity(0.55))
                    }
                }
                .overlay(shape.stroke(LocusTheme.panelStroke, lineWidth: 1))
                .contentShape(shape)
        }
    }

    @available(iOS 26.0, *)
    private var glass: Glass {
        var g: Glass = style == .clear ? .clear : .regular
        if style == .interactive { g = g.interactive() }
        if let tint { g = g.tint(tint) }
        return g
    }
}

extension View {
    func locusGlass<S: Shape>(
        _ style: LocusGlassStyle = .regular,
        tint: Color? = nil,
        in shape: S
    ) -> some View {
        modifier(LocusGlassModifier(style: style, shape: shape, tint: tint))
    }

    func locusGlass(_ style: LocusGlassStyle = .regular, tint: Color? = nil) -> some View {
        locusGlass(style, tint: tint, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
