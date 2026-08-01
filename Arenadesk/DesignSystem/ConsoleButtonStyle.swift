import SwiftUI

struct ConsoleButtonStyle: ButtonStyle {
    enum Kind {
        case primary, secondary, ghost, warning
    }

    @Environment(\.themePalette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    var kind: Kind = .primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.captionFont())
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .foregroundStyle(foreground)
            .background(background.opacity(configuration.isPressed ? 0.75 : 1))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
    }

    private var foreground: Color {
        switch kind {
        case .primary: palette.text
        case .secondary: palette.text
        case .ghost: palette.primary
        case .warning: palette.background
        }
    }

    private var background: Color {
        switch kind {
        case .primary: palette.primary
        case .secondary: palette.surfaceRaised
        case .ghost: Color.clear
        case .warning: palette.warning
        }
    }

    private var stroke: Color {
        switch kind {
        case .primary: palette.primary
        case .secondary: ConsoleTokens.bezel
        case .ghost: palette.primary.opacity(0.55)
        case .warning: palette.warning
        }
    }
}
