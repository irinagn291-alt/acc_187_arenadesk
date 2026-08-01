import SwiftUI

@MainActor
final class ShiftCloseViewModel: ObservableObject {
    @Published var results: [ChecklistResult] = []
    @Published var run: ChecklistRun?
    @Published var itemsByID: [UUID: ChecklistItem] = [:]
    @Published var closingCash = "0.00"
    @Published var openWork: ShiftOpenWork?
    @Published var passUnresolved = false
    @Published var errorMessage: String?
    @Published var isWorking = false

    private let environment: AppEnvironment
    private let onFinished: () async -> Void

    init(environment: AppEnvironment, onFinished: @escaping () async -> Void) {
        self.environment = environment
        self.onFinished = onFinished
    }

    func load() async {
        guard run == nil else { return }
        guard let shift = try? await environment.shifts.activeShift(),
              let template = try? await environment.checklists.activeTemplate(kind: .shiftClose) else {
            errorMessage = "No open shift."
            return
        }
        let items = (try? await environment.checklists.items(templateID: template.id)) ?? []
        itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        if let pair = try? await environment.checklists.startRun(
            template: template,
            employeeID: shift.employeeID
        ) {
            run = pair.0
            results = pair.1
        }
        openWork = try? await environment.shifts.openWork(for: shift.id)
        closingCash = MoneyFormat.plain(shift.openingCash)
    }

    var mandatoryComplete: Bool {
        results.allSatisfy { result in
            guard let item = itemsByID[result.itemID] else { return result.isChecked }
            return !item.isMandatory || result.isChecked
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

    func closeShift() async {
        errorMessage = nil
        guard let shift = try? await environment.shifts.activeShift(), let run else {
            errorMessage = "Missing shift or checklist."
            return
        }
        guard mandatoryComplete else {
            errorMessage = "Check every mandatory item."
            return
        }
        if let work = openWork, !work.isEmpty, !passUnresolved {
            errorMessage = "Resolve open work or confirm handoff."
            return
        }
        guard let cash = MoneyFormat.decimal(from: closingCash), cash >= 0 else {
            errorMessage = "Enter the closing cash amount."
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            var note = ""
            if passUnresolved, let work = openWork, !work.isEmpty {
                note = "Passed to next shift: \(work.summaryNote)"
            }
            try await environment.shifts.completeCloseChecklistAndClose(
                shiftID: shift.id,
                closeRunID: run.id,
                closingCash: cash,
                note: note
            )
            await environment.reloadDashboardContext()
            await onFinished()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ShiftCloseView: View {

    @Environment(\.themePalette) private var palette
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    var onFinished: () async -> Void
    @StateObject private var holder = VMHolder<ShiftCloseViewModel>()

    var body: some View {
        Group {
            if let viewModel = holder.value {
                ShiftCloseContent(viewModel: viewModel, dismiss: dismiss)
            } else {
                ProgressView().tint(palette.accent)
            }
        }
        .onAppear {
            if holder.value == nil {
                holder.value = ShiftCloseViewModel(environment: environment) {
                    await onFinished()
                    dismiss()
                }
            }
        }
    }
}

struct ShiftCloseContent: View {
    @Environment(\.themePalette) private var palette

    @ObservedObject var viewModel: ShiftCloseViewModel
    var dismiss: DismissAction

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spaceM) {
                    ConsolePanel(title: "Close checklist") {
                        ForEach(viewModel.results) { result in
                            Toggle(isOn: Binding(
                                get: { result.isChecked },
                                set: { _ in Task { await viewModel.toggle(result) } }
                            )) {
                                Text(result.itemText)
                            }
                        }
                    }
                    ConsolePanel(title: "Cash") {
                        TextField("Closing cash", text: $viewModel.closingCash)
                            .keyboardType(.decimalPad)
                    }
                    if let work = viewModel.openWork, !work.isEmpty {
                        ConsolePanel(title: "Open work") {
                            Text(work.summaryNote).foregroundStyle(palette.text)
                            Toggle("Pass unresolved to next shift", isOn: $viewModel.passUnresolved)
                        }
                    }
                    if let error = viewModel.errorMessage {
                        AlertBanner(level: .critical, title: "Cannot close", detail: error)
                    }
                }
                .padding(Theme.spaceM)
            }
        }
        .navigationTitle("Close shift")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Close") {
                    Task { await viewModel.closeShift() }
                }
                .disabled(viewModel.isWorking)
            }
        }
        .task { await viewModel.load() }
    }
}
