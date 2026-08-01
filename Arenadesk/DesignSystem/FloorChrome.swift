import SwiftUI
import UIKit

@MainActor
enum FloorChrome {
    static func configure() {
        let ink = UIColor(hex: 0xE6EAF2)
        let quiet = UIColor(hex: 0xC2C8D4)
        let page = UIColor(hex: 0x0B0E14)
        let brand = UIColor(hex: 0x9B87FF)

        let navigation = UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor = page
        navigation.shadowColor = .clear
        navigation.titleTextAttributes = [.foregroundColor: ink]
        navigation.largeTitleTextAttributes = [.foregroundColor: ink]

        let nav = UINavigationBar.appearance()
        nav.standardAppearance = navigation
        nav.scrollEdgeAppearance = navigation
        nav.compactAppearance = navigation
        nav.tintColor = brand
        nav.barStyle = .black

        let item = UITabBarItemAppearance()
        let titleFont = UIFont.systemFont(ofSize: 10, weight: .semibold)
        item.normal.iconColor = quiet
        item.normal.titleTextAttributes = [.foregroundColor: quiet, .font: titleFont]
        item.selected.iconColor = brand
        item.selected.titleTextAttributes = [.foregroundColor: brand, .font: titleFont]

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = page
        tab.shadowColor = .clear
        tab.stackedLayoutAppearance = item
        tab.inlineLayoutAppearance = item
        tab.compactInlineLayoutAppearance = item

        let bar = UITabBar.appearance()
        bar.standardAppearance = tab
        bar.scrollEdgeAppearance = tab
        bar.tintColor = brand
        bar.unselectedItemTintColor = quiet
        bar.barStyle = .black
    }
}

struct ConsoleMasthead: View {
    @Environment(\.themePalette) private var palette
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.titleFont())
                .foregroundStyle(palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(Theme.captionFont())
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .padding(.horizontal, Theme.spaceS)
        .padding(.top, Theme.spaceXS)
        .padding(.bottom, Theme.spaceXS)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.background)
    }
}

private struct ConsoleRootChromeModifier: ViewModifier {
    let title: String
    var subtitle: String?

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                ConsoleMasthead(title: title, subtitle: subtitle)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Color.clear.frame(width: 1, height: 1)
                }
            }
    }
}

extension View {
    func consoleRootChrome(title: String, subtitle: String? = nil) -> some View {
        modifier(ConsoleRootChromeModifier(title: title, subtitle: subtitle))
    }
}

private extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
