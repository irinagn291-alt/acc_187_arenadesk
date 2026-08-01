import SwiftUI

enum AppTab: Int, Hashable, CaseIterable {
    case dashboard, floor, tournaments, staff, more

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .floor: "Floor"
        case .tournaments: "Tournaments"
        case .staff: "Staff"
        case .more: "More"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .floor: "rectangle.split.3x3"
        case .tournaments: "trophy"
        case .staff: "person.3"
        case .more: "ellipsis.circle"
        }
    }
}

struct MainTabView: View {

    @Environment(\.themePalette) private var palette
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage(UserDefaultsKeys.lastSelectedTab) private var selectedTabRaw = 0
    @State private var splitSelection: AppTab? = .dashboard

    private var selectedTab: AppTab {
        AppTab(rawValue: selectedTabRaw) ?? .dashboard
    }

    var body: some View {
        Group {
            if sizeClass == .regular {
                regularLayout
            } else {
                compactLayout
            }
        }
        .tint(palette.primary)
        .onAppear {
            FloorChrome.configure()
            splitSelection = selectedTab
        }
        .sheet(isPresented: $environment.showManagerOverride) {
            ManagerOverrideSheet()
        }
    }

    private var compactLayout: some View {
        TabView(selection: Binding(
            get: { selectedTab },
            set: { selectedTabRaw = $0.rawValue }
        )) {
            NavigationStack {
                DashboardView()
            }
            .tabItem { Label(AppTab.dashboard.title, systemImage: AppTab.dashboard.systemImage) }
            .tag(AppTab.dashboard)

            NavigationStack {
                FloorView()
            }
            .tabItem { Label(AppTab.floor.title, systemImage: AppTab.floor.systemImage) }
            .tag(AppTab.floor)

            NavigationStack {
                TournamentsView()
            }
            .tabItem { Label(AppTab.tournaments.title, systemImage: AppTab.tournaments.systemImage) }
            .tag(AppTab.tournaments)

            NavigationStack {
                StaffView()
            }
            .tabItem { Label(AppTab.staff.title, systemImage: AppTab.staff.systemImage) }
            .tag(AppTab.staff)

            NavigationStack {
                MoreView()
            }
            .tabItem { Label(AppTab.more.title, systemImage: AppTab.more.systemImage) }
            .tag(AppTab.more)
        }
    }

    private var regularLayout: some View {
        NavigationSplitView {
            List(AppTab.allCases, id: \.self, selection: $splitSelection) { tab in
                Label(tab.title, systemImage: tab.systemImage)
                    .tag(Optional(tab))
            }
            .navigationTitle(environment.venue?.name ?? "Arenadesk")
            .listStyle(.sidebar)
        } detail: {
            NavigationStack {
                switch splitSelection ?? .dashboard {
                case .dashboard: DashboardView()
                case .floor: FloorView()
                case .tournaments: TournamentsView()
                case .staff: StaffView()
                case .more: MoreView()
                }
            }
        }
        .onChange(of: splitSelection) { newValue in
            if let newValue {
                selectedTabRaw = newValue.rawValue
            }
        }
    }
}

struct PlaceholderScreen: View {
    @Environment(\.themePalette) private var palette

    let title: String
    let detail: String

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            VStack(spacing: Theme.spaceS) {
                Text(title).font(Theme.titleFont()).foregroundStyle(palette.text)
                Text(detail)
                    .font(Theme.bodyFont())
                    .foregroundStyle(palette.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.spaceM)
            }
        }
        .navigationTitle(title)
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppEnvironment(database: try! Database(inMemory: true)))
        .preferredColorScheme(.dark)
}
