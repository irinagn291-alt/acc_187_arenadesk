import Foundation

struct MaintenanceRepository: Sendable {
    let database: Database

    func fetch(status: TaskStatus?) async throws -> [MaintenanceTask] {
        try await database.fetchMaintenanceTasks(status: status)
    }

    func upsert(_ task: MaintenanceTask) async throws {
        try await database.upsertMaintenanceTask(task)
    }

    func complete(id: UUID, at date: Date = .now) async throws {
        try await database.completeMaintenanceTask(id: id, at: date)
    }

    func ensureDueTasks(now: Date = .now) async throws -> Int {
        try await database.ensureDueMaintenanceTasks(now: now)
    }

    func dueTasks(now: Date = .now) async throws -> [MaintenanceTask] {
        try await database.dueMaintenanceTasks(now: now)
    }

    func dueCount(now: Date = .now) async throws -> Int {
        try await database.dueMaintenanceCount(now: now)
    }
}

extension Database {
    private static let maintenanceColumns = """
        SELECT id, title, seat_id, equipment_id, zone_id, kind, status, scheduled_for,
               completed_at, assignee_id, recurrence_days, checklist_template_id, note
        FROM maintenance_task
        """

    func fetchMaintenanceTasks(status: TaskStatus?) throws -> [MaintenanceTask] {
        if let status {
            return try query(
                "\(Self.maintenanceColumns) WHERE status = ? ORDER BY scheduled_for;",
                bind: { try $0.bind(status.rawValue, at: 1) },
                map: Self.mapMaintenance
            )
        }
        return try query("\(Self.maintenanceColumns) ORDER BY scheduled_for;", map: Self.mapMaintenance)
    }

    func upsertMaintenanceTask(_ task: MaintenanceTask) throws {
        try run(
            """
            INSERT INTO maintenance_task (
                id, title, seat_id, equipment_id, zone_id, kind, status, scheduled_for,
                completed_at, assignee_id, recurrence_days, checklist_template_id, note
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title,
                seat_id = excluded.seat_id,
                equipment_id = excluded.equipment_id,
                zone_id = excluded.zone_id,
                kind = excluded.kind,
                status = excluded.status,
                scheduled_for = excluded.scheduled_for,
                completed_at = excluded.completed_at,
                assignee_id = excluded.assignee_id,
                recurrence_days = excluded.recurrence_days,
                checklist_template_id = excluded.checklist_template_id,
                note = excluded.note;
            """
        ) { statement in
            try statement.bind(task.id, at: 1)
            try statement.bind(task.title, at: 2)
            try statement.bindOptional(task.seatID, at: 3)
            try statement.bindOptional(task.equipmentID, at: 4)
            try statement.bindOptional(task.zoneID, at: 5)
            try statement.bind(task.kind.rawValue, at: 6)
            try statement.bind(task.status.rawValue, at: 7)
            try statement.bind(task.scheduledFor, at: 8)
            try statement.bindOptional(task.completedAt, at: 9)
            try statement.bindOptional(task.assigneeID, at: 10)
            try statement.bindOptional(task.recurrenceDays, at: 11)
            try statement.bindOptional(task.checklistTemplateID, at: 12)
            try statement.bind(task.note, at: 13)
        }
    }

    func completeMaintenanceTask(id: UUID, at date: Date) throws {
        guard let task = try fetchMaintenanceTask(id: id) else { return }
        try withTransaction {
            var updated = task
            updated.status = .completed
            updated.completedAt = date
            try upsertMaintenanceTask(updated)

            if let seatID = task.seatID {
                try run("UPDATE gaming_seat SET last_maintenance_at = ? WHERE id = ?;") { statement in
                    try statement.bind(date, at: 1)
                    try statement.bind(seatID, at: 2)
                }
                _ = try recomputeSeatHealth(id: seatID, now: date)
            }

            if let days = task.recurrenceDays, days > 0 {
                try upsertMaintenanceTask(
                    MaintenanceTask(
                        id: UUID(),
                        title: task.title,
                        seatID: task.seatID,
                        equipmentID: task.equipmentID,
                        zoneID: task.zoneID,
                        kind: task.kind,
                        status: .planned,
                        scheduledFor: date.addingTimeInterval(TimeInterval(days) * TimeConstants.day),
                        completedAt: nil,
                        assigneeID: task.assigneeID,
                        recurrenceDays: days,
                        checklistTemplateID: task.checklistTemplateID,
                        note: task.note
                    )
                )
            }
        }
    }

    func fetchMaintenanceTask(id: UUID) throws -> MaintenanceTask? {
        try queryOne(
            "\(Self.maintenanceColumns) WHERE id = ?;",
            bind: { try $0.bind(id, at: 1) },
            map: Self.mapMaintenance
        )
    }

    @discardableResult
    func ensureDueMaintenanceTasks(now: Date) throws -> Int {
        let seats = try fetchSeats(zoneID: nil)
        var created: [MaintenanceTask] = []

        let busySeatIDs = Set(
            try query(
                """
                SELECT DISTINCT seat_id FROM maintenance_task
                WHERE seat_id IS NOT NULL AND status IN (?, ?);
                """,
                bind: { statement in
                    try statement.bind(TaskStatus.planned.rawValue, at: 1)
                    try statement.bind(TaskStatus.active.rawValue, at: 2)
                },
                map: { try $0.optionalUUID(at: 0) }
            ).compactMap { $0 }
        )

        for seat in seats where !busySeatIDs.contains(seat.id) {
            let baseline = seat.lastMaintenanceAt ?? seat.commissionedAt
            let due = baseline.addingTimeInterval(
                TimeInterval(seat.maintenanceIntervalDays) * TimeConstants.day
            )
            guard now >= due else { continue }
            created.append(
                MaintenanceTask(
                    id: UUID(),
                    title: "Scheduled maintenance \(seat.label)",
                    seatID: seat.id,
                    equipmentID: nil,
                    zoneID: seat.zoneID,
                    kind: .inspection,
                    status: .planned,
                    scheduledFor: due,
                    completedAt: nil,
                    assigneeID: nil,
                    recurrenceDays: seat.maintenanceIntervalDays,
                    checklistTemplateID: nil,
                    note: ""
                )
            )
        }

        guard !created.isEmpty else { return 0 }
        try withTransaction {
            for task in created {
                try upsertMaintenanceTask(task)
            }
        }
        return created.count
    }

    func dueMaintenanceTasks(now: Date = .now) throws -> [MaintenanceTask] {
        try query(
            """
            \(Self.maintenanceColumns)
            WHERE status IN (?, ?) AND scheduled_for <= ?
            ORDER BY scheduled_for;
            """,
            bind: { statement in
                try statement.bind(TaskStatus.planned.rawValue, at: 1)
                try statement.bind(TaskStatus.active.rawValue, at: 2)
                try statement.bind(now, at: 3)
            },
            map: Self.mapMaintenance
        )
    }

    func fetchAllMaintenanceTasks() throws -> [MaintenanceTask] {
        try query("\(Self.maintenanceColumns) ORDER BY scheduled_for;", map: Self.mapMaintenance)
    }

    static func mapMaintenance(_ statement: Statement) throws -> MaintenanceTask {
        guard let kind = MaintenanceKind(rawValue: try statement.string(at: 5)),
              let status = TaskStatus(rawValue: try statement.string(at: 6)) else {
            throw DatabaseError.stepFailed("Invalid maintenance task")
        }
        return MaintenanceTask(
            id: try statement.uuid(at: 0),
            title: try statement.string(at: 1),
            seatID: try statement.optionalUUID(at: 2),
            equipmentID: try statement.optionalUUID(at: 3),
            zoneID: try statement.optionalUUID(at: 4),
            kind: kind,
            status: status,
            scheduledFor: statement.date(at: 7),
            completedAt: statement.optionalDate(at: 8),
            assigneeID: try statement.optionalUUID(at: 9),
            recurrenceDays: statement.optionalInt(at: 10),
            checklistTemplateID: try statement.optionalUUID(at: 11),
            note: try statement.string(at: 12)
        )
    }
}
