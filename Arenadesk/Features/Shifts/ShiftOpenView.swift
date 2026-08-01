import SwiftUI

@MainActor
final class ShiftOpenViewModel: ObservableObject {
    @Published var employees: [Employee] = []
    @Published var selectedEmployeeID: UUID?
    @Published var pin = ""
    @Published var openingCash = "0.00"
    @Published var results: [ChecklistResult] = []
    @Published var run: ChecklistRun?
    @Published var template: ChecklistTemplate?
    @Published var itemsByID: [UUID: ChecklistItem] = [:]
    @Published var errorMessage: String?
    @Published var isWorking = false

    private let environment: AppEnvironment
    private let onFinished: () async -> Void

    init(environment: AppEnvironment, onFinished: @escaping () async -> Void) {
        self.environment = environment
        self.onFinished = onFinished
    }

    func load() async {
        employees = (try? await environment.employees.fetchAll(activeOnly: true)) ?? []
        selectedEmployeeID = environment.activeEmployeeID ?? employees.first?.id
        template = try? await environment.checklists.activeTemplate(kind: .shiftOpen)
        if let template {
            let items = (try? await environment.checklists.items(templateID: template.id)) ?? []
            itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        }
    }

    var mandatoryComplete: Bool {
        results.allSatisfy { result in
            guard let item = itemsByID[result.itemID] else { return result.isChecked }
            return !item.isMandatory || result.isChecked
        }
    }

    func startChecklistIfNeeded() async {
        guard run == nil,
              let template,
              let employeeID = selectedEmployeeID else { return }
        do {
            let pair = try await environment.checklists.startRun(template: template, employeeID: employeeID)
            run = pair.0
            results = pair.1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggle(_ result: ChecklistResult) async {
        var updated = result
        updated.isChecked.toggle()
        updated.checkedAt = updated.isChecked ? .now : nil
        try? await environment.checklists.updateResult(updated)
        if let index = results.firstIndex(where: { $0.id == result.id }) {
            results[index] = updated
        }
    }

    func confirmPIN() -> Bool {
        guard let id = selectedEmployeeID,
              let employee = employees.first(where: { $0.id == id }) else { return false }
        guard let hash = employee.pinHash, let salt = employee.pinSalt else { return true }
        return PINHasher.verify(pin: pin, hash: hash, salt: salt)
    }

    func openShift() async {
        errorMessage = nil
        guard let employeeID = selectedEmployeeID, let run else {
            errorMessage = "Complete the open checklist first."
            return
        }
        guard confirmPIN() else {
            errorMessage = "Incorrect PIN."
            return
        }
        guard mandatoryComplete else {
            errorMessage = "Check every mandatory item."
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            try await environment.checklists.completeRun(id: run.id)
            let cash = MoneyFormat.decimal(from: openingCash) ?? 0
            _ = try await environment.shifts.open(
                employeeID: employeeID,
                openRunID: run.id,
                openingCash: cash
            )
            environment.activeEmployeeID = employeeID
            await environment.reloadDashboardContext()
            await onFinished()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ShiftOpenView: View {

    @Environment(\.themePalette) private var palette
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    var onFinished: () async -> Void
    @StateObject private var holder = VMHolder<ShiftOpenViewModel>()

    var body: some View {
        Group {
            if let viewModel = holder.value {
                ShiftOpenContent(viewModel: viewModel, dismiss: dismiss)
            } else {
                ProgressView().tint(palette.accent)
            }
        }
        .onAppear {
            if holder.value == nil {
                holder.value = ShiftOpenViewModel(environment: environment) {
                    await onFinished()
                    dismiss()
                }
            }
        }
    }
}

struct ShiftOpenContent: View {
    @Environment(\.themePalette) private var palette

    @ObservedObject var viewModel: ShiftOpenViewModel
    var dismiss: DismissAction

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spaceM) {
                    ConsolePanel(title: "Employee") {
                        Picker("Staff", selection: $viewModel.selectedEmployeeID) {
                            ForEach(viewModel.employees) { employee in
                                Text(employee.fullName).tag(Optional(employee.id))
                            }
                        }
                        SecureField("PIN if set", text: $viewModel.pin)
                            .keyboardType(.numberPad)
                        TextField("Opening cash", text: $viewModel.openingCash)
                            .keyboardType(.decimalPad)
                    }
                    ConsolePanel(title: "Open checklist") {
                        if viewModel.results.isEmpty {
                            Button("Load checklist") {
                                Task { await viewModel.startChecklistIfNeeded() }
                            }
                            .buttonStyle(ConsoleButtonStyle(kind: .secondary))
                        } else {
                            ForEach(viewModel.results) { result in
                                Toggle(isOn: Binding(
                                    get: { result.isChecked },
                                    set: { _ in Task { await viewModel.toggle(result) } }
                                )) {
                                    VStack(alignment: .leading) {
                                        Text(result.itemText)
                                        if viewModel.itemsByID[result.itemID]?.isMandatory == true {
                                            Text("Mandatory")
                                                .font(Theme.captionFont())
                                                .foregroundStyle(palette.warning)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    if let error = viewModel.errorMessage {
                        AlertBanner(level: .critical, title: "Cannot open", detail: error)
                    }
                }
                .padding(Theme.spaceM)
            }
        }
        .navigationTitle("Open shift")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Open") {
                    Task { await viewModel.openShift() }
                }
                .disabled(viewModel.isWorking || viewModel.run == nil)
            }
        }
        .task { await viewModel.load() }
    }
}
