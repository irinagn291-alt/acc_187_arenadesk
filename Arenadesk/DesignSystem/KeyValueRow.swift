import SwiftUI

struct KeyValueRow: View {
    @Environment(\.themePalette) private var palette

    let key: String
    let value: String
    var valueColor: Color? = nil
    var mono: Bool = true

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key)
                .font(Theme.captionFont())
                .foregroundStyle(palette.secondaryText)
            Spacer(minLength: Theme.spaceXS)
            Text(value)
                .font(mono ? Theme.numeral() : Theme.bodyFont())
                .foregroundStyle(valueColor ?? palette.text)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(key), \(value)")
    }
}
