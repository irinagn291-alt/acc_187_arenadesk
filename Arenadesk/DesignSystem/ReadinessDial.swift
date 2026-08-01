import SwiftUI

struct ReadinessDial: View {
    @Environment(\.themePalette) private var palette

    let title: String
    let value: Double?
    var size: CGFloat? = nil

    @ScaledMetric(relativeTo: .body) private var defaultSide = ConsoleTokens.dialSide

    private var side: CGFloat { size ?? defaultSide }

    private var fraction: Double {
        guard let value else { return 0 }
        return min(max(value / 100, 0), 1)
    }

    private var tone: Color {
        guard let value else { return ConsoleTokens.lampIdle }
        if value >= 85 { return ConsoleTokens.lampReady }
        if value >= 60 { return ConsoleTokens.lampWatch }
        return ConsoleTokens.lampCritical
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(ConsoleTokens.dialTrack, lineWidth: 7)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(tone, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(label)
                    .font(Theme.numeral(size: .caption, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            .frame(width: side, height: side)
            Text(title)
                .font(Theme.captionFont())
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
        }
        .frame(minWidth: side + 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(label)")
    }

    private var label: String {
        guard let value else { return "—" }
        return String(format: "%.0f%%", value)
    }
}
