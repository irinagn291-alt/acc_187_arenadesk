import Foundation
import Combine

@MainActor
final class AppEnvironment: ObservableObject {
    let database: Database
    let venues: VenueRepository
    let employees: EmployeeRepository
    let zones: ZoneRepository
    let seats: SeatRepository
    let equipment: EquipmentRepository
    let shifts: ShiftRepository
    let checklists: ChecklistRepository
    let sessions: SeatSessionRepository
    let maintenance: MaintenanceRepository
    let repairs: RepairRepository
    let inventory: InventoryRepository
    let finance: FinanceRepository
    let schedule: ScheduleRepository
    let tournaments: TournamentRepository
    let analytics: AnalyticsRepository
    let notes: NoteRepository
    let incidents: IncidentRepository
    let documents: DocumentRepository
    let backup: BackupService
    let notifications: NotificationService

    @Published private(set) var isReady = false
    @Published private(set) var bootstrapError: String?
    @Published var venue: Venue? {
        didSet {
            if let code = venue?.currencyCode, !code.isEmpty {
                MoneyFormat.currencyCode = code
            }
        }
    }
    @Published var activeShift: Shift?
    @Published var activeEmployee: Employee?
    @Published var managerOverride = false
    @Published var showManagerOverride = false
    @Published var activeEmployeeID: UUID? {
        didSet {
            if let activeEmployeeID {
                UserDefaults.standard.set(activeEmployeeID.uuidString, forKey: UserDefaultsKeys.activeEmployeeID)
            } else {
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.activeEmployeeID)
            }
        }
    }

    init(database db: Database, bootstrapError: String? = nil) {
        self.database = db
        self.bootstrapError = bootstrapError
        self.venues = VenueRepository(database: db)
        self.employees = EmployeeRepository(database: db)
        self.zones = ZoneRepository(database: db)
        self.seats = SeatRepository(database: db)
        self.equipment = EquipmentRepository(database: db)
        self.shifts = ShiftRepository(database: db)
        self.checklists = ChecklistRepository(database: db)
        self.sessions = SeatSessionRepository(database: db)
        self.maintenance = MaintenanceRepository(database: db)
        self.repairs = RepairRepository(database: db)
        self.inventory = InventoryRepository(database: db)
        self.finance = FinanceRepository(database: db)
        self.schedule = ScheduleRepository(database: db)
        self.tournaments = TournamentRepository(database: db)
        self.analytics = AnalyticsRepository(database: db)
        self.notes = NoteRepository(database: db)
        self.incidents = IncidentRepository(database: db)
        self.documents = DocumentRepository(database: db)
        self.backup = BackupService(database: db)
        self.notifications = NotificationService()

        if let stored = UserDefaults.standard.string(forKey: UserDefaultsKeys.activeEmployeeID) {
            activeEmployeeID = UUID(uuidString: stored)
        }
    }

    static func live() -> AppEnvironment {
        do {
            return AppEnvironment(database: try Database(path: try Database.applicationSupportPath()))
        } catch let openError {
            do {
                return AppEnvironment(
                    database: try Database(inMemory: true),
                    bootstrapError: openError.localizedDescription
                )
            } catch {
                preconditionFailure("Unable to open any SQLite database: \(openError)")
            }
        }
    }

    func allows(_ capability: Capability) -> Bool {
        AccessControl.allows(capability, role: activeEmployee?.role, managerOverride: managerOverride)
    }

    func markOnboardingCompleted() {
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.onboardingCompleted)
    }

    func bootstrap() async {
        do {
            try AppPaths.ensureDirectories()
            try await Migrator.migrate(database)
            try await checklists.seedDefaultsIfNeeded()
            #if DEBUG
            try await MockDataSeeder.seedIfNeeded(environment: self)
            #endif
            _ = try await maintenance.ensureDueTasks()
            notifications.scheduleMaintenance(try await maintenance.dueTasks())
            venue = try await venues.fetch()
            activeShift = try await shifts.activeShift()
            if let id = activeEmployeeID {
                activeEmployee = try await employees.fetch(id: id)
            }
            await notifyCriticalSeatsIfNeeded()
            isReady = true
        } catch {
            bootstrapError = error.localizedDescription
        }
    }

    func reloadDashboardContext() async {
        venue = try? await venues.fetch()
        activeShift = try? await shifts.activeShift()
        if let id = activeEmployeeID {
            activeEmployee = try? await employees.fetch(id: id)
        }
        await notifyCriticalSeatsIfNeeded()
    }

    func databaseFileSize() -> Int64 {
        database.fileSize()
    }

    private func notifyCriticalSeatsIfNeeded() async {
        let seats = (try? await seats.lowestHealth(limit: 20)) ?? []
        for seat in seats where HealthBand.band(for: seat.healthScore) == .critical {
            notifications.notifyCriticalSeat(label: seat.label, score: seat.healthScore)
        }
    }
}
