import SwiftUI

struct AlertBanner: View {
    @Environment(\.themePalette) private var palette

    enum Level {
        case info, watch, critical

        var tone: StatusLamp.Tone {
            switch self {
            case .info: .info
            case .watch: .watch
            case .critical: .critical
            }
        }

        var fill: Color {
            switch self {
            case .info: ConsoleTokens.lampInfo.opacity(0.12)
            case .watch: ConsoleTokens.lampWatch.opacity(0.14)
            case .critical: ConsoleTokens.lampCritical.opacity(0.16)
            }
        }

        var stroke: Color {
            switch self {
            case .info: ConsoleTokens.lampInfo.opacity(0.55)
            case .watch: ConsoleTokens.lampWatch.opacity(0.65)
            case .critical: ConsoleTokens.lampCritical.opacity(0.7)
            }
        }
    }

    let level: Level
    let title: String
    var detail: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: Theme.spaceXS) {
            StatusLamp(tone: level.tone)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.headlineFont())
                    .foregroundStyle(palette.text)
                if let detail {
                    Text(detail)
                        .font(Theme.captionFont())
                        .foregroundStyle(palette.secondaryText)
                }
            }
            Spacer(minLength: 0)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(Theme.captionFont())
                    .buttonStyle(ConsoleButtonStyle(kind: .ghost))
            }
        }
        .padding(ConsoleTokens.panelInset)
        .background(level.fill)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                .stroke(level.stroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
    }
}
