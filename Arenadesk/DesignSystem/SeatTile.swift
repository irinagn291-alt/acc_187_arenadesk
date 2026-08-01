import SwiftUI

struct SeatTile: View {
    @Environment(\.themePalette) private var palette

    let label: String
    let state: SeatState
    let healthScore: Int

    @ScaledMetric(relativeTo: .body) private var minSide = ConsoleTokens.seatTileMinimum

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                StatusLamp(tone: lampTone)
                Spacer(minLength: 0)
                Text("\(healthScore)")
                    .font(Theme.numeral(size: .caption, weight: .semibold))
                    .foregroundStyle(Theme.healthColor(healthScore))
            }
            Text(label)
                .font(Theme.numeral(size: .subheadline, weight: .semibold))
                .foregroundStyle(palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(state.displayName)
                .font(Theme.captionFont())
                .foregroundStyle(Theme.seatStateColor(state))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            MetricStrip(fraction: Double(healthScore) / 100, color: Theme.healthColor(healthScore))
        }
        .padding(10)
        .frame(minWidth: minSide, minHeight: minSide, alignment: .topLeading)
        .background(Theme.seatStateColor(state).opacity(0.14))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                .stroke(Theme.seatStateColor(state), lineWidth: ConsoleTokens.bezelWidth)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(state.displayName), health \(healthScore)")
    }

    private var lampTone: StatusLamp.Tone {
        switch state {
        case .ready: .ready
        case .occupied: .active
        case .reserved: .info
        case .cleaning: .watch
        case .maintenance: .critical
        case .outOfService: .idle
        }
    }
}
