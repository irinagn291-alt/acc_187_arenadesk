import SwiftUI

struct ThemePalette: Hashable, Sendable {
    let primary: Color
    let primaryMuted: Color
    let background: Color
    let surface: Color
    let surfaceRaised: Color
    let text: Color
    let secondaryText: Color
    let accent: Color
    let warning: Color
    let error: Color
    let divider: Color

    static let dark = ThemePalette(
        primary: Color(hex: 0x7C5CFF),
        primaryMuted: Color(hex: 0x241F3D),
        background: Color(hex: 0x0B0E14),
        surface: Color(hex: 0x151A23),
        surfaceRaised: Color(hex: 0x1D2430),
        text: Color(hex: 0xE6EAF2),
        secondaryText: Color(hex: 0xC2C8D4),
        accent: Color(hex: 0x00D2A0),
        warning: Color(hex: 0xF5A524),
        error: Color(hex: 0xE5484D),
        divider: Color(hex: 0x232A36)
    )
}

enum Theme {
    static let cornerSmall: CGFloat = 10
    static let cornerMedium: CGFloat = 16
    static let cornerLarge: CGFloat = 24

    static let spaceXS: CGFloat = 8
    static let spaceS: CGFloat = 16
    static let spaceM: CGFloat = 24
    static let spaceL: CGFloat = 40

    static func titleFont() -> Font { .title2.weight(.bold) }
    static func headlineFont() -> Font { .headline.weight(.semibold) }
    static func bodyFont() -> Font { .body }
    static func captionFont() -> Font { .caption.weight(.medium) }
    static func monoFont() -> Font { numeral() }

    static func numeral(
        size: Font.TextStyle = .subheadline,
        weight: Font.Weight = .regular
    ) -> Font {
        .system(size, design: .monospaced).weight(weight)
    }

    static func seatStateColor(_ state: SeatState) -> Color {
        switch state {
        case .ready: Color(hex: 0x00D2A0)
        case .occupied: Color(hex: 0x7C5CFF)
        case .reserved: Color(hex: 0x5B7FFF)
        case .cleaning: Color(hex: 0xF5A524)
        case .maintenance: Color(hex: 0xE5484D)
        case .outOfService: Color(hex: 0x5A6373)
        }
    }

    static func healthColor(_ score: Int) -> Color {
        switch HealthBand.band(for: score) {
        case .healthy: Color(hex: 0x00D2A0)
        case .watch: Color(hex: 0xF5A524)
        case .degraded: Color(hex: 0xF5A524).opacity(0.85)
        case .critical: Color(hex: 0xE5484D)
        }
    }

    static func healthBandColor(_ band: HealthBand) -> Color {
        switch band {
        case .healthy: Color(hex: 0x00D2A0)
        case .watch: Color(hex: 0xF5A524)
        case .degraded: Color(hex: 0xF5A524).opacity(0.85)
        case .critical: Color(hex: 0xE5484D)
        }
    }

    static let consoleBottomClearance: CGFloat = 28
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

private struct ThemePaletteKey: EnvironmentKey {
    static let defaultValue = ThemePalette.dark
}

extension EnvironmentValues {
    var themePalette: ThemePalette {
        get { self[ThemePaletteKey.self] }
        set { self[ThemePaletteKey.self] = newValue }
    }
}
