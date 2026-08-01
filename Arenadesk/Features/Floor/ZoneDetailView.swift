import SwiftUI

@MainActor
final class ZoneDetailViewModel: ObservableObject {
    @Published var zone: Zone?
    @Published var seats: [GamingSeat] = []
    @Published var filterRaw: String? = "all"

    let zoneID: UUID
    private let environment: AppEnvironment

    init(zoneID: UUID, environment: AppEnvironment) {
        self.zoneID = zoneID
        self.environment = environment
    }

    var filter: SeatState? {
        guard let filterRaw, filterRaw != "all" else { return nil }
        return SeatState(rawValue: filterRaw)
    }

    var filtered: [GamingSeat] {
        guard let filter else { return seats }
        return seats.filter { $0.state == filter }
    }

    var filterItems: [PillFilterItem] {
        [PillFilterItem(id: "all", title: "All")]
            + SeatState.allCases.map { PillFilterItem(id: $0.rawValue, title: $0.displayName) }
    }

    func reload() async {
        zone = try? await environment.zones.fetch(id: zoneID)
        seats = (try? await environment.seats.fetch(zoneID: zoneID)) ?? []
    }
}

struct ZoneDetailView: View {

    @Environment(\.themePalette) private var palette
    @EnvironmentObject private var environment: AppEnvironment
    let zoneID: UUID
    @StateObject private var holder = VMHolder<ZoneDetailViewModel>()

    var body: some View {
        Group {
            if let viewModel = holder.value {
                ZoneDetailContent(viewModel: viewModel)
            } else {
                ProgressView().tint(palette.accent)
            }
        }
        .onAppear {
            if holder.value == nil {
                holder.value = ZoneDetailViewModel(zoneID: zoneID, environment: environment)
            }
        }
    }
}

struct ZoneDetailContent: View {
    @Environment(\.themePalette) private var palette

    @ObservedObject var viewModel: ZoneDetailViewModel
    @ScaledMetric(relativeTo: .body) private var tileMin = ConsoleTokens.seatTileMinimum

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: tileMin), spacing: Theme.spaceXS)]
    }

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            VStack(spacing: Theme.spaceS) {
                PillFilterBar(items: viewModel.filterItems, selection: $viewModel.filterRaw)
                ScrollView {
                    LazyVGrid(columns: columns, spacing: Theme.spaceXS) {
                        ForEach(viewModel.filtered) { seat in
                            NavigationLink {
                                SeatDetailView(seatID: seat.id)
                            } label: {
                                SeatTile(
                                    label: seat.label,
                                    state: seat.state,
                                    healthScore: seat.healthScore
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Theme.spaceS)
                    .padding(.bottom, Theme.consoleBottomClearance)
                }
            }
        }
        .navigationTitle(viewModel.zone?.name ?? "Zone")
        .task { await viewModel.reload() }
    }
}
