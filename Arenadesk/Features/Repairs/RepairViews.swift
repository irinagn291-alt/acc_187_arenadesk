import SwiftUI

@MainActor
final class RepairListViewModel: ObservableObject {
    @Published var repairs: [RepairRecord] = []
    @Published var openTotal: Decimal = 0
    @Published var closedTotal: Decimal = 0
    @Published var openOnly = true
    private let environment: AppEnvironment
    init(environment: AppEnvironment) { self.environment = environment }

    func reload() async {
        repairs = (try? await environment.repairs.fetchAll(openOnly: openOnly)) ?? []
        if let totals = try? await environment.repairs.costTotals() {
            openTotal = totals.open
            closedTotal = totals.closed
        }
    }
}

struct RepairListView: View {

    @Environment(\.themePalette) private var palette
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var holder = VMHolder<RepairListViewModel>()

    var body: some View {
        Group {
            if let vm = holder.value {
                AccessGated(capability: .changeEquipmentCloseRepairs) {
                    RepairListContent(viewModel: vm)
                }
            } else { ProgressView().tint(palette.accent) }
        }
        .onAppear { if holder.value == nil { holder.value = RepairListViewModel(environment: environment) } }
    }
}

struct RepairListContent: View {
    @Environment(\.themePalette) private var palette

    @ObservedObject var viewModel: RepairListViewModel

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spaceM) {
                    ConsolePanel {
                        Toggle("Open only", isOn: $viewModel.openOnly)
                            .onChange(of: viewModel.openOnly) { _ in Task { await viewModel.reload() } }
                        KeyValueRow(key: "Open cost", value: MoneyFormat.currency(viewModel.openTotal))
                        KeyValueRow(key: "Closed cost", value: MoneyFormat.currency(viewModel.closedTotal))
                    }
                    ConsolePanel(title: "Repairs") {
                        ForEach(viewModel.repairs) { repair in
                            NavigationLink {
                                RepairDetailView(repairID: repair.id)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(repair.symptom).foregroundStyle(palette.text)
                                    Text(repair.openedAt.formatted())
                                        .font(Theme.captionFont()).foregroundStyle(palette.secondaryText)
                                }
                            }
                        }
                    }
                }
                .padding(Theme.spaceM)
                .padding(.bottom, Theme.consoleBottomClearance)
            }
        }
        .navigationTitle("Repairs")
        .task { await viewModel.reload() }
    }
}

@MainActor
final class RepairDetailViewModel: ObservableObject {
    @Published var repair: RepairRecord?
    @Published var actionTaken = ""
    @Published var partsCost = "0"
    @Published var laborCost = "0"
    @Published var performedBy = ""
    @Published var retire = false
    @Published var offerFinance = false
    @Published var pendingExpense: FinanceRecord?
    private let repairID: UUID
    private let environment: AppEnvironment
    init(repairID: UUID, environment: AppEnvironment) {
        self.repairID = repairID
        self.environment = environment
    }

    func reload() async {
        repair = try? await environment.repairs.fetch(id: repairID)
        if let repair {
            actionTaken = repair.actionTaken
            partsCost = "\(repair.partsCost)"
            laborCost = "\(repair.laborCost)"
            performedBy = repair.performedBy
        }
    }

    func close() async {
        let parts = MoneyFormat.decimal(from: partsCost) ?? 0
        let labor = MoneyFormat.decimal(from: laborCost) ?? 0
        guard let closed = try? await environment.repairs.close(
            id: repairID,
            actionTaken: actionTaken,
            partsCost: parts,
            laborCost: labor,
            performedBy: performedBy,
            retireEquipment: retire
        ) else { return }
        repair = closed
        let total = parts + labor
        if total > 0 {
            pendingExpense = FinanceRecord(
                id: UUID(),
                kind: .expense,
                categoryName: "Repairs",
                amount: total,
                occurredAt: .now,
                shiftID: environment.activeShift?.id,
                tournamentID: nil,
                repairID: closed.id,
                note: closed.symptom
            )
            offerFinance = true
        }
    }

    func saveExpense() async {
        guard let pendingExpense else { return }
        try? await environment.finance.upsert(pendingExpense)
        offerFinance = false
    }
}

struct RepairDetailView: View {
    @Environment(\.themePalette) private var palette

    @EnvironmentObject private var environment: AppEnvironment
    let repairID: UUID
    @StateObject private var holder = VMHolder<RepairDetailViewModel>()

    var body: some View {
        Group {
            if let vm = holder.value { RepairDetailContent(viewModel: vm) }
            else { ProgressView().tint(palette.accent) }
        }
        .onAppear {
            if holder.value == nil {
                holder.value = RepairDetailViewModel(repairID: repairID, environment: environment)
            }
        }
    }
}

struct RepairDetailContent: View {
    @Environment(\.themePalette) private var palette
    @ObservedObject var viewModel: RepairDetailViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spaceM) {
                if let repair = viewModel.repair {
                    ConsolePanel(title: "Symptom") {
                        Text(repair.symptom).foregroundStyle(palette.text)
                    }
                    if repair.closedAt == nil {
                        ConsolePanel(title: "Close repair") {
                            TextField("Action taken", text: $viewModel.actionTaken)
                            TextField("Parts cost", text: $viewModel.partsCost).keyboardType(.decimalPad)
                            TextField("Labor cost", text: $viewModel.laborCost).keyboardType(.decimalPad)
                            TextField("Performed by", text: $viewModel.performedBy)
                            Toggle("Retire equipment", isOn: $viewModel.retire)
                            Button("Close repair") { Task { await viewModel.close() } }
                                .buttonStyle(ConsoleButtonStyle(kind: .primary))
                        }
                    } else {
                        ConsolePanel(title: "Closed") {
                            Text(repair.actionTaken).foregroundStyle(palette.text)
                            KeyValueRow(
                                key: "Total",
                                value: MoneyFormat.currency(repair.partsCost + repair.laborCost)
                            )
                        }
                    }
                }
            }
            .padding(Theme.spaceM)
            .padding(.bottom, Theme.consoleBottomClearance)
        }
        .background(palette.background)
        .navigationTitle("Repair")
        .task { await viewModel.reload() }
        .alert("Create expense?", isPresented: $viewModel.offerFinance) {
            Button("Create") { Task { await viewModel.saveExpense() } }
            Button("Skip", role: .cancel) { viewModel.offerFinance = false }
        } message: {
            Text("Link a finance expense to this repair.")
        }
    }
}
