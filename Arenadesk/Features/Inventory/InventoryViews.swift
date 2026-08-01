import SwiftUI

@MainActor
final class InventoryViewModel: ObservableObject {
    @Published var items: [InventoryItem] = []
    @Published var name = ""
    @Published var sku = ""
    @Published var minimum = "1"
    private let environment: AppEnvironment
    init(environment: AppEnvironment) { self.environment = environment }

    func reload() async {
        items = (try? await environment.inventory.fetchAll()) ?? []
    }

    func addItem() async {
        let item = InventoryItem(
            id: UUID(),
            name: name,
            sku: sku,
            unit: "pcs",
            quantity: 0,
            minimumQuantity: MoneyFormat.decimal(from: minimum) ?? 1,
            unitCost: 0,
            categoryName: "General",
            isConsumable: true
        )
        try? await environment.inventory.upsert(item)
        name = ""; sku = ""
        await reload()
    }
}

struct InventoryView: View {

    @Environment(\.themePalette) private var palette
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var holder = VMHolder<InventoryViewModel>()

    var body: some View {
        Group {
            if let vm = holder.value {
                AccessGated(capability: .inventoryMovements) {
                    InventoryContent(viewModel: vm)
                }
            } else { ProgressView().tint(palette.accent) }
        }
        .onAppear { if holder.value == nil { holder.value = InventoryViewModel(environment: environment) } }
    }
}

struct InventoryContent: View {
    @Environment(\.themePalette) private var palette

    @ObservedObject var viewModel: InventoryViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spaceM) {
                ConsolePanel(title: "Add item") {
                    TextField("Name", text: $viewModel.name)
                    TextField("SKU", text: $viewModel.sku)
                    TextField("Minimum", text: $viewModel.minimum)
                    Button("Add") { Task { await viewModel.addItem() } }
                        .buttonStyle(ConsoleButtonStyle(kind: .primary))
                }
                ConsolePanel(title: "Stock") {
                    ForEach(viewModel.items) { item in
                        NavigationLink {
                            InventoryItemDetailView(itemID: item.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(item.name).foregroundStyle(palette.text)
                                    Text(item.sku).font(Theme.numeral()).foregroundStyle(palette.secondaryText)
                                }
                                Spacer()
                                Text(MoneyFormat.quantity(item.quantity))
                                    .font(Theme.numeral(weight: .semibold))
                                    .foregroundStyle(item.quantity <= item.minimumQuantity ? palette.warning : palette.text)
                            }
                        }
                    }
                }
            }
            .padding(Theme.spaceM)
            .padding(.bottom, Theme.consoleBottomClearance)
        }
        .background(palette.background)
        .navigationTitle("Inventory")
        .task { await viewModel.reload() }
    }
}

@MainActor
final class InventoryItemDetailViewModel: ObservableObject {
    @Published var item: InventoryItem?
    @Published var movements: [InventoryMovement] = []
    @Published var kind: MovementKind = .receipt
    @Published var quantity = "1"
    @Published var reason = ""
    @Published var flaggedOverIssue = false
    private let itemID: UUID
    private let environment: AppEnvironment
    init(itemID: UUID, environment: AppEnvironment) {
        self.itemID = itemID
        self.environment = environment
    }

    func reload() async {
        item = try? await environment.inventory.fetch(id: itemID)
        movements = (try? await environment.inventory.movements(itemID: itemID)) ?? []
    }

    func addMovement() async {
        guard let item else { return }
        let qty = MoneyFormat.decimal(from: quantity) ?? 0
        if kind == .issue && qty > item.quantity { flaggedOverIssue = true }
        let movement = InventoryMovement(
            id: UUID(),
            itemID: itemID,
            kind: kind,
            quantity: qty,
            occurredAt: .now,
            shiftID: environment.activeShift?.id,
            employeeID: environment.activeEmployeeID,
            reason: reason
        )
        if let result = try? await environment.inventory.addMovement(movement) {
            NotificationHooks.lowStockIfNeeded(item: result.item, crossed: result.crossedLowStock)
        }
        reason = ""
        await reload()
    }
}

struct InventoryItemDetailView: View {
    @Environment(\.themePalette) private var palette

    @EnvironmentObject private var environment: AppEnvironment
    let itemID: UUID
    @StateObject private var holder = VMHolder<InventoryItemDetailViewModel>()

    var body: some View {
        Group {
            if let vm = holder.value { InventoryItemDetailContent(viewModel: vm) }
            else { ProgressView().tint(palette.accent) }
        }
        .onAppear {
            if holder.value == nil {
                holder.value = InventoryItemDetailViewModel(itemID: itemID, environment: environment)
            }
        }
    }
}

struct InventoryItemDetailContent: View {
    @Environment(\.themePalette) private var palette

    @ObservedObject var viewModel: InventoryItemDetailViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spaceM) {
                if let item = viewModel.item {
                    ConsolePanel(title: "Item") {
                        Text(item.name).font(Theme.headlineFont()).foregroundStyle(palette.text)
                        KeyValueRow(
                            key: "Quantity",
                            value: "\(MoneyFormat.quantity(item.quantity)) \(item.unit)"
                        )
                        KeyValueRow(key: "Minimum", value: MoneyFormat.quantity(item.minimumQuantity))
                    }
                }
                ConsolePanel(title: "Add movement") {
                    Picker("Kind", selection: $viewModel.kind) {
                        ForEach(MovementKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    TextField("Quantity", text: $viewModel.quantity).keyboardType(.decimalPad)
                    TextField("Reason", text: $viewModel.reason)
                    Button("Save") { Task { await viewModel.addMovement() } }
                        .buttonStyle(ConsoleButtonStyle(kind: .primary))
                    if viewModel.flaggedOverIssue {
                        AlertBanner(
                            level: .watch,
                            title: "Over-issue",
                            detail: "Issued more than on hand — flagged."
                        )
                    }
                }
                ConsolePanel(title: "Ledger") {
                    ForEach(viewModel.movements) { movement in
                        VStack(alignment: .leading) {
                            Text("\(movement.kind.displayName) \(MoneyFormat.quantity(movement.quantity))")
                                .font(Theme.numeral())
                                .foregroundStyle(palette.text)
                            Text(movement.reason).font(Theme.captionFont()).foregroundStyle(palette.secondaryText)
                        }
                    }
                }
            }
            .padding(Theme.spaceM)
            .padding(.bottom, Theme.consoleBottomClearance)
        }
        .background(palette.background)
        .navigationTitle("Item")
        .task { await viewModel.reload() }
    }
}
