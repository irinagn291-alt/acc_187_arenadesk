import SwiftUI

@MainActor
final class ArchiveViewModel: ObservableObject {
    @Published var shifts: [Shift] = []
    @Published var tournaments: [Tournament] = []
    @Published var incidents: [Incident] = []
    private let environment: AppEnvironment
    init(environment: AppEnvironment) { self.environment = environment }

    func reload() async {
        shifts = ((try? await environment.shifts.fetchRecent(limit: 200)) ?? []).filter(\.isArchived)
        tournaments = ((try? await environment.tournaments.fetchAll(includeArchived: true)) ?? []).filter(\.isArchived)
        incidents = ((try? await environment.incidents.fetchAll(includeArchived: true)) ?? []).filter(\.isArchived)
    }
}

struct ArchiveView: View {

    @Environment(\.themePalette) private var palette
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var holder = VMHolder<ArchiveViewModel>()

    var body: some View {
        Group {
            if let vm = holder.value { ArchiveContent(viewModel: vm) }
            else { ProgressView().tint(palette.accent) }
        }
        .onAppear { if holder.value == nil { holder.value = ArchiveViewModel(environment: environment) } }
    }
}

struct ArchiveContent: View {
    @Environment(\.themePalette) private var palette

    @ObservedObject var viewModel: ArchiveViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spaceM) {
                ConsolePanel(title: "Shifts") {
                    if viewModel.shifts.isEmpty {
                        Text("None").foregroundStyle(palette.secondaryText)
                    }
                    ForEach(viewModel.shifts) { shift in
                        VStack(alignment: .leading) {
                            Text(shift.openedAt.formatted()).foregroundStyle(palette.text)
                            Text("Sessions \(shift.seatSessionCount) · \(shift.note)")
                                .font(Theme.captionFont()).foregroundStyle(palette.secondaryText)
                        }
                    }
                }
                ConsolePanel(title: "Tournaments") {
                    if viewModel.tournaments.isEmpty {
                        Text("None").foregroundStyle(palette.secondaryText)
                    }
                    ForEach(viewModel.tournaments) { t in
                        KeyValueRow(key: t.name, value: t.status.displayName)
                    }
                }
                ConsolePanel(title: "Incidents") {
                    if viewModel.incidents.isEmpty {
                        Text("None").foregroundStyle(palette.secondaryText)
                    }
                    ForEach(viewModel.incidents) { i in
                        KeyValueRow(key: i.summary, value: i.severity.displayName, mono: false)
                    }
                }
            }
            .padding(Theme.spaceM)
            .padding(.bottom, Theme.consoleBottomClearance)
        }
        .background(palette.background)
        .navigationTitle("Archive")
        .task { await viewModel.reload() }
    }
}
