import SwiftUI

struct NothingHereView: View {
    @Environment(\.themePalette) private var palette

    let image: AppImage
    let title: String
    let detail: String
    var actionTitle: String?
    var action: (() -> Void)?

    init(
        image: AppImage,
        title: String,
        detail: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.image = image
        self.title = title
        self.detail = detail
        self.actionTitle = actionTitle
        self.action = action
    }

    @ScaledMetric(relativeTo: .body) private var artSide: CGFloat = 180

    var body: some View {
        VStack(spacing: Theme.spaceS) {
            image.image
                .resizable()
                .scaledToFit()
                .frame(width: artSide, height: artSide)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous))
                .accessibilityHidden(true)

            Text(title)
                .font(Theme.headlineFont())
                .foregroundStyle(palette.text)

            Text(detail)
                .font(Theme.bodyFont())
                .foregroundStyle(palette.secondaryText)
                .padding(.horizontal, Theme.spaceM)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(ConsoleButtonStyle(kind: .primary))
                    .padding(.top, Theme.spaceXS)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
