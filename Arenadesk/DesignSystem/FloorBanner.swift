import SwiftUI

struct FloorBanner: View {
    let image: AppImage
    var caption: String? = nil
    var height: CGFloat = 170

    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spaceXS) {
            image.image
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerMedium, style: .continuous))
                .accessibilityHidden(true)
            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(Theme.captionFont())
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
