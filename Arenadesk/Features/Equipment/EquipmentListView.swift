import SwiftUI

@MainActor
final class EquipmentListViewModel: ObservableObject {
    @Published var items: [Equipment] = []
    @Published var kindFilter: EquipmentKind?
    @Published var stateFilter: EquipmentState?
    @Published var query = ""

    let seatID: UUID?
    private let environment: AppEnvironment

    init(seatID: UUID?, environment: AppEnvironment) {
        self.seatID = seatID
        self.environment = environment
    }

    var filtered: [Equipment] {
        items.filter { item in
            if let kindFilter, item.kind != kindFilter { return false }
            if let stateFilter, item.state != stateFilter { return false }
            if !query.isEmpty {
                let q = query.lowercased()
                if !item.name.lowercased().contains(q) && !item.serialNumber.lowercased().contains(q) {
                    return false
                }
            }
            return true
        }
    }

    func reload() async {
        if let seatID {
            items = (try? await environment.equipment.fetch(seatID: seatID)) ?? []
        } else {
            items = (try? await environment.equipment.fetchAll()) ?? []
        }
    }
}

struct EquipmentListView: View {

    @Environment(\.themePalette) private var palette
    @EnvironmentObject private var environment: AppEnvironment
    var seatID: UUID? = nil
    @StateObject private var holder = VMHolder<EquipmentListViewModel>()

    var body: some View {
        Group {
            if let viewModel = holder.value {
                EquipmentListContent(viewModel: viewModel)
            } else {
                ProgressView().tint(palette.accent)
            }
        }
        .onAppear {
            if holder.value == nil {
                holder.value = EquipmentListViewModel(seatID: seatID, environment: environment)
            }
        }
    }
}

struct EquipmentListContent: View {
    @Environment(\.themePalette) private var palette

    @ObservedObject var viewModel: EquipmentListViewModel

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            ScrollView {
                LazyVStack(spacing: Theme.spaceXS) {
                    ForEach(viewModel.filtered) { item in
                        NavigationLink {
                            EquipmentDetailView(equipmentID: item.id)
                        } label: {
                            ConsolePanel {
                                Text(item.name)
                                    .font(Theme.headlineFont())
                                    .foregroundStyle(palette.text)
                                KeyValueRow(key: "Serial", value: item.serialNumber)
                                HStack {
                                    Text(item.kind.displayName)
                                        .font(Theme.captionFont())
                                        .foregroundStyle(palette.secondaryText)
                                    Spacer()
                                    StatusLamp(tone: equipmentTone(item.state), label: item.state.displayName)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Theme.spaceM)
                .padding(.bottom, Theme.consoleBottomClearance)
            }
        }
        .navigationTitle("Equipment")
        .searchable(text: $viewModel.query)
        .task { await viewModel.reload() }
    }

    private func equipmentTone(_ state: EquipmentState) -> StatusLamp.Tone {
        switch state {
        case .ok: .ready
        case .cleaning: .watch
        case .overheating, .damaged, .broken: .critical
        case .inRepair: .active
        case .retired: .idle
        }
    }
}
