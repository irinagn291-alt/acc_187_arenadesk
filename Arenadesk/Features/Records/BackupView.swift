import SwiftUI

@MainActor
final class BackupViewModel: ObservableObject {
    @Published var backups: [BackupListItem] = []
    @Published var includeFiles = true
    @Published var confirmName = ""
    @Published var restoreURL: URL?
    @Published var message: String?
    @Published var exportMessage: String?
    private let environment: AppEnvironment
    private var backupService: BackupService { BackupService(database: environment.database) }
    private var exportService: DataExportService { DataExportService(database: environment.database) }

    init(environment: AppEnvironment) { self.environment = environment }

    func reload() {
        backups = (try? backupService.listBackups()) ?? []
    }

    func create() async {
        do {
            let url = try await backupService.createBackup(includeFiles: includeFiles)
            message = "Saved \(url.lastPathComponent)"
            reload()
        } catch {
            message = error.localizedDescription
        }
    }

    func restore() async {
        guard let restoreURL else { return }
        do {
            let name = environment.venue?.name ?? ""
            try await backupService.restore(from: restoreURL, typedVenueName: confirmName, currentVenueName: name)
            await environment.reloadDashboardContext()
            try? await environment.checklists.seedDefaultsIfNeeded()
            message = "Restore complete"
            confirmName = ""
            self.restoreURL = nil
        } catch {
            message = error.localizedDescription
        }
    }

    func exportAllCSV() async {
        do {
            _ = try await exportService.exportFinanceCSV()
            _ = try await exportService.exportInventoryMovementsCSV()
            _ = try await exportService.exportShiftsCSV()
            _ = try await exportService.exportRepairsCSV()
            if let first = try await environment.tournaments.fetchAll().first {
                _ = try await exportService.exportTournamentStandingsCSV(tournamentID: first.id)
            }
            exportMessage = "CSV files written to Documents/Exports"
        } catch {
            exportMessage = error.localizedDescription
        }
    }
}

struct BackupView: View {

    @Environment(\.themePalette) private var palette
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var holder = VMHolder<BackupViewModel>()

    var body: some View {
        Group {
            if let vm = holder.value {
                AccessGated(capability: .backupRestoreWipe) {
                    BackupContent(viewModel: vm)
                }
            } else { ProgressView().tint(palette.accent) }
        }
        .onAppear { if holder.value == nil { holder.value = BackupViewModel(environment: environment) } }
    }
}

struct BackupContent: View {
    @Environment(\.themePalette) private var palette

    @ObservedObject var viewModel: BackupViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spaceM) {
                ConsolePanel(title: "Create") {
                    Toggle("Include document files", isOn: $viewModel.includeFiles)
                    Button("Create backup") { Task { await viewModel.create() } }
                        .buttonStyle(ConsoleButtonStyle(kind: .primary))
                }
                ConsolePanel(title: "CSV export") {
                    Button("Export CSV set") { Task { await viewModel.exportAllCSV() } }
                        .buttonStyle(ConsoleButtonStyle(kind: .secondary))
                    if let exportMessage = viewModel.exportMessage {
                        Text(exportMessage).font(Theme.captionFont()).foregroundStyle(palette.secondaryText)
                    }
                }
                ConsolePanel(title: "Backups") {
                    if viewModel.backups.isEmpty {
                        NothingHereView(
                            image: .emptyBackups,
                            title: "No backups yet",
                            detail: "Create a local JSON backup before making large changes."
                        )
                        .frame(minHeight: 220)
                    }
                    ForEach(viewModel.backups) { item in
                        Button {
                            viewModel.restoreURL = item.url
                        } label: {
                            KeyValueRow(
                                key: item.name,
                                value: ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                if viewModel.restoreURL != nil {
                    ConsolePanel(title: "Confirm restore") {
                        Text("Type the venue name to restore. This replaces all local data.")
                            .font(Theme.captionFont())
                            .foregroundStyle(palette.warning)
                        TextField("Venue name", text: $viewModel.confirmName)
                        Button("Restore", role: .destructive) {
                            Task { await viewModel.restore() }
                        }
                        .buttonStyle(ConsoleButtonStyle(kind: .warning))
                    }
                }
                if let message = viewModel.message {
                    AlertBanner(level: .info, title: message)
                }
            }
            .padding(Theme.spaceM)
            .padding(.bottom, Theme.consoleBottomClearance)
        }
        .background(palette.background)
        .navigationTitle("Backup")
        .onAppear { viewModel.reload() }
    }
}
