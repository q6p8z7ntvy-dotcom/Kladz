import SwiftUI

/// Kladz visual system: clean paper surfaces, deep ocean blue, and warm amber.
enum KladzTheme {
    static let accent = Color(red: 0.06, green: 0.32, blue: 0.43)
    static let accentSecondary = Color(red: 1.00, green: 0.67, blue: 0.29)
    static let danger = Color(red: 0.82, green: 0.18, blue: 0.22)
    static let panelStroke = Color.black.opacity(0.09)
    static let statusGood = Color(red: 0.08, green: 0.52, blue: 0.36)
    static let statusWarn = Color(red: 0.78, green: 0.45, blue: 0.08)
    static let statusBad = Color(red: 0.82, green: 0.18, blue: 0.22)
}

enum KladzGlassStyle {
    case regular
    case clear
    case interactive
}

struct KladzGlassModifier<S: Shape>: ViewModifier {
    var style: KladzGlassStyle
    var shape: S
    var tint: Color?

    func body(content: Content) -> some View {
        content
            .background {
                shape.fill(.regularMaterial)
                if let tint {
                    shape.fill(tint.opacity(style == .clear ? 0.12 : 0.22))
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
