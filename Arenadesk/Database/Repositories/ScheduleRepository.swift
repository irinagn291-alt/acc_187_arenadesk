import Foundation

struct ScheduleRepository: Sendable {
    let database: Database

    func fetch(from: Date, to: Date) async throws -> [PlannedShift] {
        try await database.fetchPlannedShifts(from: from, to: to)
    }

    func upsert(_ plan: PlannedShift) async throws {
        try await database.upsertPlannedShift(plan)
    }

    func delete(id: UUID) async throws {
        try await database.deletePlannedShift(id: id)
    }

    func shiftsForEmployee(_ employeeID: UUID, limit: Int = 50) async throws -> [Shift] {
        try await database.fetchShifts(employeeID: employeeID, limit: limit)
    }
}

extension Database {
    private static let plannedShiftColumns = """
        SELECT id, employee_id, starts_at, ends_at, note FROM planned_shift
        """

    func fetchPlannedShifts(from: Date, to: Date) throws -> [PlannedShift] {
        try query(
            "\(Self.plannedShiftColumns) WHERE starts_at < ? AND ends_at > ? ORDER BY starts_at;",
            bind: { statement in
                try statement.bind(to, at: 1)
                try statement.bind(from, at: 2)
            },
            map: Self.mapPlannedShift
        )
    }

    func fetchAllPlannedShifts() throws -> [PlannedShift] {
        try query("\(Self.plannedShiftColumns) ORDER BY starts_at;", map: Self.mapPlannedShift)
    }

    static func mapPlannedShift(_ statement: Statement) throws -> PlannedShift {
        PlannedShift(
            id: try statement.uuid(at: 0),
            employeeID: try statement.uuid(at: 1),
            startsAt: statement.date(at: 2),
            endsAt: statement.date(at: 3),
            note: try statement.string(at: 4)
        )
    }

    func upsertPlannedShift(_ plan: PlannedShift) throws {
        try run(
            """
            INSERT INTO planned_shift (id, employee_id, starts_at, ends_at, note)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                employee_id = excluded.employee_id,
                starts_at = excluded.starts_at,
                ends_at = excluded.ends_at,
                note = excluded.note;
            """
        ) { statement in
            try statement.bind(plan.id, at: 1)
            try statement.bind(plan.employeeID, at: 2)
            try statement.bind(plan.startsAt, at: 3)
            try statement.bind(plan.endsAt, at: 4)
            try statement.bind(plan.note, at: 5)
        }
    }

    func deletePlannedShift(id: UUID) throws {
        try run("DELETE FROM planned_shift WHERE id = ?;") { try $0.bind(id, at: 1) }
    }

    func fetchShifts(employeeID: UUID, limit: Int) throws -> [Shift] {
        try query(
            """
            SELECT id, employee_id, opened_at, closed_at, status, open_checklist_run_id,
                   close_checklist_run_id, opening_cash_cents, closing_cash_cents,
                   seat_session_count, incident_count, note, is_archived
            FROM shift WHERE employee_id = ? ORDER BY opened_at DESC LIMIT ?;
            """,
            bind: { statement in
                try statement.bind(employeeID, at: 1)
                try statement.bind(limit, at: 2)
            },
            map: Self.mapShift
        )
    }
}
