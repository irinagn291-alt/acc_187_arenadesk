import Foundation

struct BackupPayload: Codable, Sendable {
    var manifest: BackupManifest
    var venues: [Venue] = []
    var employees: [Employee] = []
    var zones: [Zone] = []
    var seats: [GamingSeat] = []
    var equipment: [Equipment] = []
    var equipmentStateChanges: [EquipmentStateChange] = []
    var checklistTemplates: [ChecklistTemplate] = []
    var checklistItems: [ChecklistItem] = []
    var checklistRuns: [ChecklistRun] = []
    var checklistResults: [ChecklistResult] = []
    var shifts: [Shift] = []
    var plannedShifts: [PlannedShift] = []
    var seatSessions: [SeatSession] = []
    var notes: [Note] = []
    var incidents: [Incident] = []
    var documents: [DocumentFile] = []
    var inventoryItems: [InventoryItem] = []
    var inventoryMovements: [InventoryMovement] = []
    var financeRecords: [FinanceRecord] = []
    var tournaments: [Tournament] = []
    var participants: [Participant] = []
    var matches: [Match] = []
    var repairs: [RepairRecord] = []
    var maintenanceTasks: [MaintenanceTask] = []

    init(manifest: BackupManifest) {
        self.manifest = manifest
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        manifest = try container.decode(BackupManifest.self, forKey: .manifest)
        venues = try container.decodeIfPresent([Venue].self, forKey: .venues) ?? []
        employees = try container.decodeIfPresent([Employee].self, forKey: .employees) ?? []
        zones = try container.decodeIfPresent([Zone].self, forKey: .zones) ?? []
        seats = try container.decodeIfPresent([GamingSeat].self, forKey: .seats) ?? []
        equipment = try container.decodeIfPresent([Equipment].self, forKey: .equipment) ?? []
        equipmentStateChanges = try container.decodeIfPresent(
            [EquipmentStateChange].self, forKey: .equipmentStateChanges
        ) ?? []
        checklistTemplates = try container.decodeIfPresent(
            [ChecklistTemplate].self, forKey: .checklistTemplates
        ) ?? []
        checklistItems = try container.decodeIfPresent([ChecklistItem].self, forKey: .checklistItems) ?? []
        checklistRuns = try container.decodeIfPresent([ChecklistRun].self, forKey: .checklistRuns) ?? []
        checklistResults = try container.decodeIfPresent(
            [ChecklistResult].self, forKey: .checklistResults
        ) ?? []
        shifts = try container.decodeIfPresent([Shift].self, forKey: .shifts) ?? []
        plannedShifts = try container.decodeIfPresent([PlannedShift].self, forKey: .plannedShifts) ?? []
        seatSessions = try container.decodeIfPresent([SeatSession].self, forKey: .seatSessions) ?? []
        notes = try container.decodeIfPresent([Note].self, forKey: .notes) ?? []
        incidents = try container.decodeIfPresent([Incident].self, forKey: .incidents) ?? []
        documents = try container.decodeIfPresent([DocumentFile].self, forKey: .documents) ?? []
        inventoryItems = try container.decodeIfPresent([InventoryItem].self, forKey: .inventoryItems) ?? []
        inventoryMovements = try container.decodeIfPresent(
            [InventoryMovement].self, forKey: .inventoryMovements
        ) ?? []
        financeRecords = try container.decodeIfPresent([FinanceRecord].self, forKey: .financeRecords) ?? []
        tournaments = try container.decodeIfPresent([Tournament].self, forKey: .tournaments) ?? []
        participants = try container.decodeIfPresent([Participant].self, forKey: .participants) ?? []
        matches = try container.decodeIfPresent([Match].self, forKey: .matches) ?? []
        repairs = try container.decodeIfPresent([RepairRecord].self, forKey: .repairs) ?? []
        maintenanceTasks = try container.decodeIfPresent(
            [MaintenanceTask].self, forKey: .maintenanceTasks
        ) ?? []
    }
}

enum BackupMigrator {
    static func migrate(_ payload: BackupPayload) throws -> BackupPayload {
        var result = payload
        var version = payload.manifest.schemaVersion

        if version < 1 {
            version = 1
        }
        if version < 2 {
            result = migrateV1ToV2(result)
            version = 2
        }
        guard version == Migrator.currentVersion else {
            throw BackupError.unsupportedVersion(payload.manifest.schemaVersion)
        }
        result.manifest.schemaVersion = version
        return result
    }

    private static func migrateV1ToV2(_ payload: BackupPayload) -> BackupPayload {
        var result = payload
        result.plannedShifts = []
        return result
    }
}

enum BackupError: Error, LocalizedError, Sendable {
    case schemaTooNew(Int)
    case unsupportedVersion(Int)
    case venueNameMismatch
    case decodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .schemaTooNew(let v):
            "Backup schema version \(v) is newer than this app supports (\(Migrator.currentVersion))."
        case .unsupportedVersion(let v):
            "No migration path exists from backup schema version \(v)."
        case .venueNameMismatch:
            "Venue name confirmation did not match."
        case .decodeFailed(let m):
            "Failed to read backup: \(m)"
        }
    }
}

struct BackupListItem: Identifiable, Hashable, Sendable {
    let url: URL
    let size: Int64
    var id: String { url.path }
    var name: String { url.lastPathComponent }
}

struct BackupService: Sendable {
    let database: Database

    func listBackups() throws -> [BackupListItem] {
        try AppPaths.ensureDirectories()
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: AppPaths.backupsDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls
            .filter { $0.pathExtension == "json" }
            .map { url in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                return BackupListItem(url: url, size: Int64(size))
            }
            .sorted { $0.name > $1.name }
    }

    func createBackup(includeFiles: Bool) async throws -> URL {
        try AppPaths.ensureDirectories()
        var payload = try await database.exportBackupPayload(appVersion: appVersion())
        payload.manifest.includesFiles = includeFiles

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)

        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = AppPaths.backupsDirectory.appendingPathComponent("arenadesk-\(stamp).json")
        try data.write(to: url, options: .atomic)

        if includeFiles {
            let sibling = url.deletingPathExtension().appendingPathExtension("files")
            try? FileManager.default.removeItem(at: sibling)
            if FileManager.default.fileExists(atPath: AppPaths.filesDirectory.path) {
                try FileManager.default.copyItem(at: AppPaths.filesDirectory, to: sibling)
            }
        }
        return url
    }

    func restore(from url: URL, typedVenueName: String, currentVenueName: String) async throws {
        guard typedVenueName == currentVenueName, !currentVenueName.isEmpty else {
            throw BackupError.venueNameMismatch
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let payload: BackupPayload
        do {
            payload = try decoder.decode(BackupPayload.self, from: data)
        } catch {
            throw BackupError.decodeFailed(error.localizedDescription)
        }
        if payload.manifest.schemaVersion > Migrator.currentVersion {
            throw BackupError.schemaTooNew(payload.manifest.schemaVersion)
        }
        try await database.restoreBackupPayload(BackupMigrator.migrate(payload))

        let sibling = url.deletingPathExtension().appendingPathExtension("files")
        if FileManager.default.fileExists(atPath: sibling.path) {
            try AppPaths.ensureDirectories()
            try? FileManager.default.removeItem(at: AppPaths.filesDirectory)
            try FileManager.default.copyItem(at: sibling, to: AppPaths.filesDirectory)
        }
    }

    func integrityCheck() async throws -> String {
        try await database.integrityCheck()
    }

    func wipeAllUserData() async throws {
        try await database.wipeUserData()
    }

    private func appVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

extension Database {
    static let userTables = [
        "checklist_result",
        "finance_record",
        "match",
        "participant",
        "seat_session",
        "incident",
        "maintenance_task",
        "repair_record",
        "equipment_state_change",
        "inventory_movement",
        "tournament",
        "equipment",
        "gaming_seat",
        "inventory_item",
        "planned_shift",
        "shift",
        "checklist_run",
        "checklist_item",
        "checklist_template",
        "zone",
        "note",
        "document_file",
        "employee",
        "venue"
    ]

    func exportBackupPayload(appVersion: String) throws -> BackupPayload {
        var payload = BackupPayload(
            manifest: BackupManifest(
                schemaVersion: Migrator.currentVersion,
                appVersion: appVersion,
                createdAt: .now,
                rowCounts: [:],
                includesFiles: false
            )
        )
        payload.venues = try fetchVenue().map { [$0] } ?? []
        payload.employees = try fetchEmployees(activeOnly: false)
        payload.zones = try fetchZones()
        payload.seats = try fetchSeats(zoneID: nil)
        payload.equipment = try fetchEquipment(seatID: nil)
        payload.equipmentStateChanges = try fetchAllEquipmentStateChanges()
        payload.checklistTemplates = try fetchChecklistTemplates()
        payload.checklistItems = try fetchAllChecklistItems()
        payload.checklistRuns = try fetchAllChecklistRuns()
        payload.checklistResults = try fetchAllChecklistResults()
        payload.shifts = try fetchRecentShifts(limit: Int.max)
        payload.plannedShifts = try fetchAllPlannedShifts()
        payload.seatSessions = try fetchAllSeatSessions()
        payload.notes = try fetchNotes()
        payload.incidents = try fetchIncidents(includeArchived: true)
        payload.documents = try fetchDocuments()
        payload.inventoryItems = try fetchInventoryItems()
        payload.inventoryMovements = try fetchAllInventoryMovements()
        payload.financeRecords = try fetchFinanceRecords(from: .distantPast, to: .distantFuture)
        payload.tournaments = try fetchTournaments(includeArchived: true)
        payload.participants = try fetchAllParticipants()
        payload.matches = try fetchAllMatches()
        payload.repairs = try fetchRepairs(openOnly: false)
        payload.maintenanceTasks = try fetchAllMaintenanceTasks()

        payload.manifest.rowCounts = [
            "venue": payload.venues.count,
            "employee": payload.employees.count,
            "zone": payload.zones.count,
            "gaming_seat": payload.seats.count,
            "equipment": payload.equipment.count,
            "equipment_state_change": payload.equipmentStateChanges.count,
            "checklist_template": payload.checklistTemplates.count,
            "checklist_item": payload.checklistItems.count,
            "checklist_run": payload.checklistRuns.count,
            "checklist_result": payload.checklistResults.count,
            "shift": payload.shifts.count,
            "planned_shift": payload.plannedShifts.count,
            "seat_session": payload.seatSessions.count,
            "note": payload.notes.count,
            "incident": payload.incidents.count,
            "document_file": payload.documents.count,
            "inventory_item": payload.inventoryItems.count,
            "inventory_movement": payload.inventoryMovements.count,
            "finance_record": payload.financeRecords.count,
            "tournament": payload.tournaments.count,
            "participant": payload.participants.count,
            "match": payload.matches.count,
            "repair_record": payload.repairs.count,
            "maintenance_task": payload.maintenanceTasks.count
        ]
        return payload
    }

    func restoreBackupPayload(_ payload: BackupPayload) throws {
        try withTransaction {
            try wipeUserData()

            for venue in payload.venues { try upsertVenue(venue) }
            for employee in payload.employees { try upsertEmployee(employee) }
            for document in payload.documents { try upsertDocument(document) }
            for note in payload.notes { try upsertNote(note) }
            for zone in payload.zones { try upsertZone(zone) }
            try upsertSeats(payload.seats)
            for item in payload.equipment { try insertEquipmentRow(item) }
            for change in payload.equipmentStateChanges { try insertEquipmentStateChange(change) }

            for template in payload.checklistTemplates { try insertChecklistTemplate(template) }
            for item in payload.checklistItems { try insertChecklistItem(item) }
            for checklistRun in payload.checklistRuns { try insertChecklistRun(checklistRun) }
            for result in payload.checklistResults { try upsertChecklistResult(result) }

            for shift in payload.shifts { try insertShift(shift) }
            for plan in payload.plannedShifts { try upsertPlannedShift(plan) }

            for tournament in payload.tournaments { try upsertTournament(tournament) }
            for participant in payload.participants { try upsertParticipant(participant) }
            for match in payload.matches { try upsertMatch(match) }

            for session in payload.seatSessions { try insertSeatSession(session) }
            for incident in payload.incidents { try upsertIncident(incident) }
            for repair in payload.repairs { try upsertRepairRecord(repair) }
            for task in payload.maintenanceTasks { try upsertMaintenanceTask(task) }

            for item in payload.inventoryItems { try upsertInventoryItem(item) }
            for movement in payload.inventoryMovements { try insertInventoryMovement(movement) }
            for item in payload.inventoryItems {
                try recomputeInventoryQuantity(itemID: item.id)
            }

            for record in payload.financeRecords { try upsertFinanceRecord(record) }
        }
    }

    func wipeUserData() throws {
        for table in Self.userTables {
            try execute("DELETE FROM \(table);")
        }
    }

    func integrityCheck() throws -> String {
        try queryOne("PRAGMA integrity_check;") { try $0.string(at: 0) } ?? "unknown"
    }

    func rowCountsByTable() throws -> [String: Int] {
        var counts: [String: Int] = [:]
        for table in Self.userTables {
            counts[table] = try scalarInt("SELECT COUNT(*) FROM \(table);")
        }
        return counts
    }
}
