import SwiftUI

@MainActor
final class ChecklistTemplatesViewModel: ObservableObject {
    @Published var templates: [ChecklistTemplate] = []
    @Published var errorMessage: String?

    private let checklists: ChecklistRepository

    init(environment: AppEnvironment) {
        checklists = environment.checklists
    }

    func reload() async {
        do {
            templates = try await checklists.allTemplates()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func activate(_ template: ChecklistTemplate) async {
        do {
            try await checklists.activate(template)
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func duplicate(_ template: ChecklistTemplate) async {
        do {
            try await checklists.duplicateAsNextVersion(template)
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ChecklistTemplatesView: View {

    @Environment(\.themePalette) private var palette
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var holder = VMHolder<ChecklistTemplatesViewModel>()

    var body: some View {
        Group {
            if let vm = holder.value { ChecklistTemplatesContent(viewModel: vm) }
            else { ProgressView().tint(palette.accent) }
        }
        .onAppear {
            if holder.value == nil {
                holder.value = ChecklistTemplatesViewModel(environment: environment)
            }
        }
    }
}

struct ChecklistTemplatesContent: View {
    @Environment(\.themePalette) private var palette

    @ObservedObject var viewModel: ChecklistTemplatesViewModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Theme.spaceS) {
                ForEach(viewModel.templates) { template in
                    ConsolePanel {
                        HStack {
                            Text(template.name).font(Theme.headlineFont()).foregroundStyle(palette.text)
                            Spacer()
                            Text("v\(template.version)")
                                .font(Theme.numeral())
                                .foregroundStyle(palette.secondaryText)
                        }
                        Text(template.kind.displayName)
                            .font(Theme.captionFont())
                            .foregroundStyle(palette.primary)
                        HStack {
                            if !template.isActive {
                                Button("Activate") { Task { await viewModel.activate(template) } }
                                    .buttonStyle(ConsoleButtonStyle(kind: .primary))
                            } else {
                                StatusLamp(tone: .ready, label: "Active")
                            }
                            Button("Duplicate as new version") {
                                Task { await viewModel.duplicate(template) }
                            }
                            .buttonStyle(ConsoleButtonStyle(kind: .ghost))
                        }
                    }
                }
            }
            .padding(Theme.spaceM)
            .padding(.bottom, Theme.consoleBottomClearance)
        }
        .background(palette.background)
        .navigationTitle("Checklists")
        .task { await viewModel.reload() }
        .alert(
            "Checklists",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}
