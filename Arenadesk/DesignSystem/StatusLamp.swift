import SwiftUI

struct StatusLamp: View {
    enum Tone {
        case ready, watch, critical, idle, active, info

        var color: Color {
            switch self {
            case .ready: ConsoleTokens.lampReady
            case .watch: ConsoleTokens.lampWatch
            case .critical: ConsoleTokens.lampCritical
            case .idle: ConsoleTokens.lampIdle
            case .active: ConsoleTokens.lampActive
            case .info: ConsoleTokens.lampInfo
            }
        }
    }

    let tone: Tone
    var label: String?

    @ScaledMetric(relativeTo: .caption) private var diameter = ConsoleTokens.lampDiameter

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tone.color)
                .frame(width: diameter, height: diameter)
                .shadow(color: tone.color.opacity(0.55), radius: 3, x: 0, y: 0)
            if let label {
                Text(label)
                    .font(Theme.captionFont())
                    .foregroundStyle(tone.color)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label ?? "Status")
    }
}
