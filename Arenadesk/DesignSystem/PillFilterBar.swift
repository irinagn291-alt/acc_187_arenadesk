import SwiftUI

struct PillFilterItem: Identifiable, Hashable {
    let id: String
    let title: String
}

struct PillFilterBar: View {
    @Environment(\.themePalette) private var palette

    let items: [PillFilterItem]
    @Binding var selection: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    let selected = selection == item.id
                    Button {
                        selection = item.id
                    } label: {
                        Text(item.title)
                            .font(Theme.captionFont())
                            .padding(.horizontal, 12)
                            .frame(height: ConsoleTokens.filterPillHeight)
                            .background(selected ? palette.primary : palette.surfaceRaised)
                            .foregroundStyle(palette.text)
                            .overlay(
                                Capsule()
                                    .stroke(selected ? palette.primary : ConsoleTokens.bezel, lineWidth: 1)
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.spaceS)
        }
    }
}
