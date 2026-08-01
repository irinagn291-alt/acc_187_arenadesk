import SwiftUI

@MainActor
final class EquipmentDetailViewModel: ObservableObject {
    @Published var item: Equipment?
    @Published var history: [EquipmentStateChange] = []
    @Published var openRepairs: [RepairRecord] = []
    @Published var reason = ""
    @Published var lastOpenedRepair: RepairRecord?
    @Published var errorMessage: String?

    let equipmentID: UUID
    private let environment: AppEnvironment

    init(equipmentID: UUID, environment: AppEnvironment) {
        self.equipmentID = equipmentID
        self.environment = environment
    }

    func reload() async {
        item = try? await environment.equipment.fetch(id: equipmentID)
        history = (try? await environment.equipment.stateHistory(equipmentID: equipmentID)) ?? []
        openRepairs = (try? await environment.equipment.openRepairs(equipmentID: equipmentID)) ?? []
    }

    func changeState(to state: EquipmentState) async {
        do {
            let repair = try await environment.equipment.changeState(
                id: equipmentID,
                to: state,
                employeeID: environment.activeEmployeeID,
                reason: reason.isEmpty ? "State change" : reason
            )
            lastOpenedRepair = repair
            reason = ""
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct EquipmentDetailView: View {

    @Environment(\.themePalette) private var palette
    @EnvironmentObject private var environment: AppEnvironment
    let equipmentID: UUID
    @StateObject private var holder = VMHolder<EquipmentDetailViewModel>()

    var body: some View {
        Group {
            if let viewModel = holder.value {
                EquipmentDetailContent(viewModel: viewModel)
            } else {
                ProgressView().tint(palette.accent)
            }
        }
        .onAppear {
            if holder.value == nil {
                holder.value = EquipmentDetailViewModel(equipmentID: equipmentID, environment: environment)
            }
        }
    }
}

struct EquipmentDetailContent: View {
    @Environment(\.themePalette) private var palette

    @ObservedObject var viewModel: EquipmentDetailViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spaceM) {
                if let item = viewModel.item {
                    ConsolePanel(title: "Details") {
                        KeyValueRow(key: "Name", value: item.name, mono: false)
                        KeyValueRow(key: "Serial", value: item.serialNumber)
                        KeyValueRow(key: "Kind", value: item.kind.displayName)
                        KeyValueRow(key: "State", value: item.state.displayName)
                        if let warranty = item.warrantyUntil {
                            KeyValueRow(
                                key: "Warranty until",
                                value: warranty.formatted(date: .abbreviated, time: .omitted)
                            )
                        }
                    }
                    ConsolePanel(title: "Change state") {
                        TextField("Reason", text: $viewModel.reason)
                        ForEach(EquipmentState.allCases, id: \.self) { state in
                            Button(state.displayName) {
                                Task { await viewModel.changeState(to: state) }
                            }
                            .buttonStyle(ConsoleButtonStyle(kind: .secondary))
                        }
                    }
                    if let repair = viewModel.lastOpenedRepair {
                        ConsolePanel(title: "Repair opened") {
                            Text(repair.symptom).foregroundStyle(palette.text)
                            KeyValueRow(key: "ID", value: repair.id.uuidString.lowercased())
                        }
                    }
                    if !viewModel.openRepairs.isEmpty {
                        ConsolePanel(title: "Open repairs") {
                            ForEach(viewModel.openRepairs) { repair in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(repair.symptom).foregroundStyle(palette.text)
                                    Text(repair.openedAt.formatted())
                                        .font(Theme.captionFont())
                                        .foregroundStyle(palette.secondaryText)
                                }
                            }
                        }
                    }
                    ConsolePanel(title: "History") {
                        ForEach(viewModel.history) { change in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(change.fromState.displayName) → \(change.toState.displayName)")
                                    .font(Theme.numeral())
                                    .foregroundStyle(palette.text)
                                Text(change.reason)
                                    .font(Theme.captionFont())
                                    .foregroundStyle(palette.secondaryText)
                                Text(change.changedAt.formatted())
                                    .font(Theme.captionFont())
                                    .foregroundStyle(palette.secondaryText)
                            }
                        }
                    }
                }
                if let error = viewModel.errorMessage {
                    AlertBanner(level: .critical, title: "Update failed", detail: error)
                }
            }
            .padding(Theme.spaceM)
            .padding(.bottom, Theme.consoleBottomClearance)
        }
        .background(palette.background)
        .navigationTitle(viewModel.item?.name ?? "Equipment")
        .task { await viewModel.reload() }
    }
}
