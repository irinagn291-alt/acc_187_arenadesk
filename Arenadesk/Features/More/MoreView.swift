import SwiftUI

struct MoreView: View {

    @Environment(\.themePalette) private var palette
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spaceM) {
                    ConsolePanel(title: "Operations") {
                        link("Equipment") { EquipmentListView() }
                        link("Maintenance") { MaintenanceView() }
                        link("Repairs") { RepairListView() }
                        if environment.allows(.inventoryMovements) {
                            link("Inventory") { InventoryView() }
                        }
                        if environment.allows(.financeAndAnalytics) {
                            link("Finance") { FinanceView() }
                            link("Analytics") { AnalyticsView() }
                        } else {
                            Button("Finance / Analytics (restricted)") {
                                environment.showManagerOverride = true
                            }
                            .buttonStyle(ConsoleButtonStyle(kind: .ghost))
                        }
                    }
                    ConsolePanel(title: "Records") {
                        link("Documents") { DocumentsView() }
                        link("Notes") { NotesView() }
                        link("Incidents") { IncidentsView() }
                        link("Checklists") { ChecklistTemplatesView() }
                        link("Archive") { ArchiveView() }
                        link("Backup") { BackupView() }
                    }
                    ConsolePanel(title: "Access") {
                        if environment.managerOverride {
                            StatusLamp(tone: .ready, label: "Manager override active")
                            Button("Clear override") { environment.managerOverride = false }
                                .buttonStyle(ConsoleButtonStyle(kind: .secondary))
                        } else {
                            Button("Manager override") { environment.showManagerOverride = true }
                                .buttonStyle(ConsoleButtonStyle(kind: .primary))
                        }
                        if let employee = environment.activeEmployee {
                            KeyValueRow(key: "Active role", value: employee.role.displayName)
                        }
                    }
                    ConsolePanel(title: "App") {
                        link("Settings") { SettingsView() }
                        link("About") { AboutView() }
                        if let venue = environment.venue {
                            KeyValueRow(key: "Venue", value: venue.name, mono: false)
                        }
                        KeyValueRow(key: "Schema", value: "\(Migrator.currentVersion)")
                        KeyValueRow(
                            key: "Database",
                            value: ByteCountFormatter.string(
                                fromByteCount: environment.databaseFileSize(),
                                countStyle: .file
                            )
                        )
                    }
                }
                .padding(Theme.spaceM)
                .padding(.bottom, Theme.consoleBottomClearance)
            }
        }
        .consoleRootChrome(title: "More", subtitle: "Operations, records, and access")
        .sheet(isPresented: $environment.showManagerOverride) {
            ManagerOverrideSheet()
        }
    }

    private func link<Destination: View>(_ title: String, @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink(destination: destination) {
            HStack {
                Text(title).foregroundStyle(palette.text)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(Theme.captionFont())
                    .foregroundStyle(palette.secondaryText)
            }
            .padding(.vertical, 4)
        }
    }
}
