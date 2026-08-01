import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var venueName = ""
    @Published var address = ""
    @Published var phone = ""
    @Published var currency = "USD"
    @Published var seatRate = "5.00"
    @Published var integrityResult: String?
    @Published var wipeConfirm = ""
    @Published var message: String?
    private let environment: AppEnvironment
    init(environment: AppEnvironment) { self.environment = environment }

    func load() {
        guard let venue = environment.venue else { return }
        venueName = venue.name
        address = venue.address
        phone = venue.phone
        currency = venue.currencyCode
        seatRate = MoneyFormat.plain(venue.seatHourlyRate)
    }

    func saveVenue() async {
        guard var venue = environment.venue else { return }
        venue.name = venueName
        venue.address = address
        venue.phone = phone
        venue.currencyCode = currency.uppercased()
        venue.seatHourlyRate = MoneyFormat.decimal(from: seatRate) ?? venue.seatHourlyRate
        try? await environment.venues.upsert(venue)
        await environment.reloadDashboardContext()
        message = "Venue saved"
    }

    func runIntegrity() async {
        integrityResult = (try? await environment.backup.integrityCheck()) ?? "failed"
    }

    func wipe() async {
        guard wipeConfirm == environment.venue?.name, !(environment.venue?.name.isEmpty ?? true) else {
            message = "Type the venue name to wipe."
            return
        }
        do {
            try await environment.backup.wipeAllUserData()
            UserDefaults.standard.set(false, forKey: UserDefaultsKeys.onboardingCompleted)
            UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.didSeedMockData)
            UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.activeEmployeeID)
            environment.activeEmployeeID = nil
            try await environment.checklists.seedDefaultsIfNeeded()
            await environment.reloadDashboardContext()
            message = "All data wiped. Restart onboarding from the app launch."
            wipeConfirm = ""
        } catch {
            message = error.localizedDescription
        }
    }
}

struct SettingsView: View {

    @Environment(\.themePalette) private var palette
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var holder = VMHolder<SettingsViewModel>()

    var body: some View {
        Group {
            if let vm = holder.value { SettingsContent(viewModel: vm) }
            else { ProgressView().tint(palette.accent) }
        }
        .onAppear {
            if holder.value == nil {
                let vm = SettingsViewModel(environment: environment)
                vm.load()
                holder.value = vm
            }
        }
    }
}

struct SettingsContent: View {
    @Environment(\.themePalette) private var palette

    @EnvironmentObject private var environment: AppEnvironment
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spaceM) {
                ConsolePanel(title: "Venue") {
                    TextField("Name", text: $viewModel.venueName)
                    TextField("Address", text: $viewModel.address)
                    TextField("Phone", text: $viewModel.phone)
                    TextField("Currency", text: $viewModel.currency)
                    TextField("Seat hourly rate", text: $viewModel.seatRate)
                        .keyboardType(.decimalPad)
                    Button("Save venue") { Task { await viewModel.saveVenue() } }
                        .buttonStyle(ConsoleButtonStyle(kind: .primary))
                }
                ConsolePanel(title: "Notifications") {
                    Toggle("Local reminders", isOn: Binding(
                        get: { environment.notifications.isEnabled },
                        set: { environment.notifications.isEnabled = $0 }
                    ))
                    Button("Request permission") {
                        Task { await environment.notifications.requestAuthorizationIfNeeded() }
                    }
                    .buttonStyle(ConsoleButtonStyle(kind: .secondary))
                }
                ConsolePanel(title: "Database") {
                    KeyValueRow(
                        key: "Size",
                        value: ByteCountFormatter.string(fromByteCount: environment.databaseFileSize(), countStyle: .file)
                    )
                    KeyValueRow(key: "Schema", value: "\(Migrator.currentVersion)")
                    Button("Integrity check") { Task { await viewModel.runIntegrity() } }
                        .buttonStyle(ConsoleButtonStyle(kind: .ghost))
                    if let integrityResult = viewModel.integrityResult {
                        Text(integrityResult).font(Theme.numeral()).foregroundStyle(palette.secondaryText)
                    }
                }
                if environment.allows(.backupRestoreWipe) {
                    ConsolePanel(title: "Danger zone") {
                        TextField("Type venue name to wipe", text: $viewModel.wipeConfirm)
                        Button("Wipe all data", role: .destructive) {
                            Task { await viewModel.wipe() }
                        }
                        .buttonStyle(ConsoleButtonStyle(kind: .warning))
                    }
                }
                NavigationLink {
                    AboutView()
                } label: {
                    ConsolePanel {
                        Text("About").font(Theme.headlineFont()).foregroundStyle(palette.text)
                    }
                }
                .buttonStyle(.plain)
                if let message = viewModel.message {
                    AlertBanner(level: .info, title: message)
                }
            }
            .padding(Theme.spaceM)
            .padding(.bottom, Theme.consoleBottomClearance)
        }
        .background(palette.background)
        .navigationTitle("Settings")
    }
}

struct AboutView: View {
    @Environment(\.themePalette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spaceM) {
                ConsolePanel(title: "Arenadesk") {
                    KeyValueRow(
                        key: "Version",
                        value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
                    )
                    KeyValueRow(key: "Schema", value: "\(Migrator.currentVersion)")
                }
                ConsolePanel(title: "Privacy") {
                    Text("All venue data stays on this device. There is no account, cloud sync, analytics or advertising.")
                        .font(Theme.bodyFont())
                        .foregroundStyle(palette.secondaryText)
                }
                ConsolePanel(title: "Access control") {
                    Text("Staff roles and PINs are convenience gates for a shared device. They are not a security boundary and do not encrypt data.")
                        .font(Theme.bodyFont())
                        .foregroundStyle(palette.secondaryText)
                }
            }
            .padding(Theme.spaceM)
        }
        .background(palette.background)
        .navigationTitle("About")
    }
}
