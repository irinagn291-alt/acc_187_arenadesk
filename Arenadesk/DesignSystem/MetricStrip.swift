import SwiftUI

struct MetricStrip: View {
    let fraction: Double
    var color: Color = ConsoleTokens.lampReady

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(ConsoleTokens.dialTrack)
                Capsule()
                    .fill(color)
                    .frame(width: max(0, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: ConsoleTokens.stripHeight)
        .accessibilityHidden(true)
    }
}
