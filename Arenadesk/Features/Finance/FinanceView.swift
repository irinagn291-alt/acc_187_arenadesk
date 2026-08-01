import SwiftUI

@MainActor
final class FinanceViewModel: ObservableObject {
    @Published var records: [FinanceRecord] = []
    @Published var balance: Decimal = 0
    @Published var breakdown: [(category: String, income: Decimal, expense: Decimal)] = []
    @Published var rangeDays = 30
    @Published var kind: FinanceKind = .expense
    @Published var category = "General"
    @Published var amount = ""
    @Published var error: String?
    private let environment: AppEnvironment
    init(environment: AppEnvironment) { self.environment = environment }

    private var range: (Date, Date) {
        let to = Date()
        let from = Calendar.current.date(byAdding: .day, value: -rangeDays, to: to) ?? to
        return (from, to)
    }

    func reload() async {
        let (from, to) = range
        records = (try? await environment.finance.fetch(from: from, to: to)) ?? []
        balance = (try? await environment.finance.balance(from: from, to: to)) ?? 0
        breakdown = (try? await environment.finance.categoryBreakdown(from: from, to: to)) ?? []
    }

    func add() async {
        guard let value = MoneyFormat.decimal(from: amount), value > 0 else {
            error = "Enter a positive amount."
            return
        }
        error = nil
        let record = FinanceRecord(
            id: UUID(),
            kind: kind,
            categoryName: category,
            amount: value,
            occurredAt: .now,
            shiftID: environment.activeShift?.id,
            tournamentID: nil,
            repairID: nil,
            note: ""
        )
        try? await environment.finance.upsert(record)
        amount = ""
        await reload()
    }
}

struct FinanceView: View {

    @Environment(\.themePalette) private var palette
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var holder = VMHolder<FinanceViewModel>()

    var body: some View {
        Group {
            if let vm = holder.value {
                AccessGated(capability: .financeAndAnalytics) {
                    FinanceContent(viewModel: vm)
                }
            } else { ProgressView().tint(palette.accent) }
        }
        .onAppear { if holder.value == nil { holder.value = FinanceViewModel(environment: environment) } }
    }
}

struct FinanceContent: View {
    @Environment(\.themePalette) private var palette

    @ObservedObject var viewModel: FinanceViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spaceM) {
                ConsolePanel(title: "Range") {
                    Picker("Days", selection: $viewModel.rangeDays) {
                        Text("7").tag(7)
                        Text("30").tag(30)
                        Text("90").tag(90)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: viewModel.rangeDays) { _ in Task { await viewModel.reload() } }
                    KeyValueRow(
                        key: "Balance",
                        value: MoneyFormat.currency(viewModel.balance),
                        valueColor: viewModel.balance >= 0 ? palette.accent : palette.error
                    )
                }
                ConsolePanel(title: "Add record") {
                    Picker("Kind", selection: $viewModel.kind) {
                        ForEach(FinanceKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    TextField("Category", text: $viewModel.category)
                    TextField("Amount", text: $viewModel.amount).keyboardType(.decimalPad)
                    Button("Save") { Task { await viewModel.add() } }
                        .buttonStyle(ConsoleButtonStyle(kind: .primary))
                    if let error = viewModel.error {
                        Text(error).font(Theme.captionFont()).foregroundStyle(palette.error)
                    }
                }
                ConsolePanel(title: "By category") {
                    if viewModel.breakdown.isEmpty {
                        Text("No records in range").foregroundStyle(palette.secondaryText)
                    } else {
                        ForEach(viewModel.breakdown, id: \.category) { row in
                            KeyValueRow(
                                key: row.category,
                                value: "+\(MoneyFormat.currency(row.income)) / -\(MoneyFormat.currency(row.expense))"
                            )
                        }
                    }
                }
                ConsolePanel(title: "Records") {
                    ForEach(viewModel.records) { record in
                        KeyValueRow(
                            key: "\(record.kind.displayName) · \(record.categoryName)",
                            value: (record.kind == .income ? "+" : "-") + MoneyFormat.currency(record.amount),
                            valueColor: record.kind == .income ? palette.accent : palette.error
                        )
                    }
                }
            }
            .padding(Theme.spaceM)
            .padding(.bottom, Theme.consoleBottomClearance)
        }
        .background(palette.background)
        .navigationTitle("Finance")
        .task { await viewModel.reload() }
    }
}
