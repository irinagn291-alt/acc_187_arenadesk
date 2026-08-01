import SwiftUI

@MainActor
final class MaintenanceViewModel: ObservableObject {
    enum Segment: String, CaseIterable {
        case due, planned, active, completed

        var title: String {
            switch self {
            case .due: "Due"
            case .planned: "Planned"
            case .active: "Active"
            case .completed: "Completed"
            }
        }
    }
    @Published var segment: Segment = .due
    @Published var tasks: [MaintenanceTask] = []
    private let environment: AppEnvironment

    init(environment: AppEnvironment) { self.environment = environment }

    func reload() async {
        _ = try? await environment.maintenance.ensureDueTasks()
        switch segment {
        case .due:
            tasks = (try? await environment.maintenance.dueTasks()) ?? []
        case .planned:
            tasks = (try? await environment.maintenance.fetch(status: .planned)) ?? []
        case .active:
            tasks = (try? await environment.maintenance.fetch(status: .active)) ?? []
        case .completed:
            tasks = (try? await environment.maintenance.fetch(status: .completed)) ?? []
        }
    }

    func activate(_ task: MaintenanceTask) async {
        var updated = task
        updated.status = .active
        try? await environment.maintenance.upsert(updated)
        await reload()
    }

    func complete(_ task: MaintenanceTask) async {
        try? await environment.maintenance.complete(id: task.id)
        await reload()
    }
}

struct MaintenanceView: View {

    @Environment(\.themePalette) private var palette
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var holder = VMHolder<MaintenanceViewModel>()

    var body: some View {
        Group {
            if let vm = holder.value {
                AccessGated(capability: .editFloor) {
                    MaintenanceContent(viewModel: vm)
                }
            } else { ProgressView().tint(palette.accent) }
        }
        .onAppear { if holder.value == nil { holder.value = MaintenanceViewModel(environment: environment) } }
    }
}

struct MaintenanceContent: View {
    @Environment(\.themePalette) private var palette

    @ObservedObject var viewModel: MaintenanceViewModel

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            VStack(spacing: Theme.spaceS) {
                Picker("Segment", selection: $viewModel.segment) {
                    ForEach(MaintenanceViewModel.Segment.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.spaceM)
                .onChange(of: viewModel.segment) { _ in Task { await viewModel.reload() } }
                ScrollView {
                    LazyVStack(spacing: Theme.spaceXS) {
                        ForEach(viewModel.tasks) { task in
                            ConsolePanel {
                                Text(task.title).foregroundStyle(palette.text)
                                Text(task.scheduledFor.formatted(date: .abbreviated, time: .omitted))
                                    .font(Theme.captionFont()).foregroundStyle(palette.secondaryText)
                                HStack {
                                    if task.status == .planned {
                                        Button("Activate") { Task { await viewModel.activate(task) } }
                                            .buttonStyle(ConsoleButtonStyle(kind: .secondary))
                                    }
                                    if task.status == .planned || task.status == .active {
                                        Button("Complete") { Task { await viewModel.complete(task) } }
                                            .buttonStyle(ConsoleButtonStyle(kind: .primary))
                                    }
                                }
                            }
                        }
                    }
                    .padding(Theme.spaceM)
                    .padding(.bottom, Theme.consoleBottomClearance)
                }
            }
        }
        .navigationTitle("Maintenance")
        .task { await viewModel.reload() }
    }
}
