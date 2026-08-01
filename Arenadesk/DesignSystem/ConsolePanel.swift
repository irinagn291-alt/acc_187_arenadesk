import SwiftUI

struct ConsolePanel<Content: View>: View {
    @Environment(\.themePalette) private var palette

    var title: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spaceXS) {
            if let title {
                Text(title.uppercased())
                    .font(Theme.captionFont())
                    .foregroundStyle(palette.secondaryText)
                    .tracking(0.8)
            }
            content()
        }
        .padding(ConsoleTokens.panelInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ConsoleTokens.panelFill)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous)
                .stroke(ConsoleTokens.bezel, lineWidth: ConsoleTokens.bezelWidth)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous))
    }
}
