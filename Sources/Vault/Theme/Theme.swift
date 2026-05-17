import SwiftUI

/// Centralised design tokens — colours, palette, spacing constants — so every
/// surface in the app uses the same look. Adjusting a value here ripples
/// through every view consistently.
enum Theme {
    static let accentHex: String = "#7A8FFF"

    static var accent: Color    { Color(hex: accentHex) }
    static var positive: Color  { Color(hex: "#27C39A") }
    static var negative: Color  { Color(hex: "#F0506E") }
    static var warning: Color   { Color(hex: "#E0A458") }
    static var muted: Color     { .secondary }

    /// Couleurs de fond (auto light/dark)
    static var canvas: Color { Color(nsColor: .windowBackgroundColor) }
    static var card: Color   { Color(nsColor: .controlBackgroundColor) }
    static var stroke: Color { Color.primary.opacity(0.07) }

    static let cardCornerRadius: CGFloat = 16
    static let cardPadding: CGFloat = 18

    static let palette: [String] = [
        "#7A8FFF", "#27C39A", "#F0506E", "#E0A458",
        "#B58CFF", "#5AB6E1", "#F08D6A", "#8AC36A",
        "#C28FBE", "#5C7CFA"
    ]
}

extension Color {
    init(hex: String) {
        var clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("#") { clean.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&value)
        let r, g, b, a: Double
        switch clean.count {
        case 6:
            r = Double((value & 0xFF0000) >> 16) / 255
            g = Double((value & 0x00FF00) >> 8)  / 255
            b = Double( value & 0x0000FF)        / 255
            a = 1
        case 8:
            a = Double((value & 0xFF000000) >> 24) / 255
            r = Double((value & 0x00FF0000) >> 16) / 255
            g = Double((value & 0x0000FF00) >> 8)  / 255
            b = Double( value & 0x000000FF)        / 255
        default:
            r = 0.5; g = 0.5; b = 0.5; a = 1
        }
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
