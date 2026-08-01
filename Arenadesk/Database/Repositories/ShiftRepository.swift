import Foundation

struct ShiftOpenWork: Hashable, Sendable {
    var activeMaintenanceCount: Int
    var unresolvedIncidents: Int
    var openSeatSessions: Int
    var lowStockItems: Int

    var isEmpty: Bool {
        activeMaintenanceCount == 0
            && unresolvedIncidents == 0
            && openSeatSessions == 0
            && lowStockItems == 0
    }

    var summaryNote: String {
        var parts: [String] = []
        if activeMaintenanceCount > 0 { parts.append("\(activeMaintenanceCount) active maintenance") }
        if unresolvedIncidents > 0 { parts.append("\(unresolvedIncidents) unresolved incidents") }
        if openSeatSessions > 0 { parts.append("\(openSeatSessions) open seat sessions") }
        if lowStockItems > 0 { parts.append("\(lowStockItems) low-stock items") }
        return parts.joined(separator: "; ")
    }
}

struct ShiftRepository: Sendable {
    let database: Database

    func activeShift() async throws -> Shift? {
        try await database.fetchActiveShift()
    }

    func fetchRecent(limit: Int = 20) async throws -> [Shift] {
        try await database.fetchRecentShifts(limit: limit)
    }

    func open(
        employeeID: UUID,
        openRunID: UUID,
        openingCash: Decimal,
        at date: Date = .now
    ) async throws -> Shift {
        try await database.openShift(
            employeeID: employeeID,
            openRunID: openRunID,
            openingCash: openingCash,
            at: date
        )
    }

    func close(
        shiftID: UUID,
        closeRunID: UUID,
        closingCash: Decimal,
        note: String,
        at date: Date = .now
    ) async throws {
        try await database.closeShift(
            shiftID: shiftID,
            closeRunID: closeRunID,
            closingCash: closingCash,
            note: note,
            at: date
        )
    }

    func openWork(for shiftID: UUID) async throws -> ShiftOpenWork {
        try await database.fetchShiftOpenWork(shiftID: shiftID)
    }

    func completeCloseChecklistAndClose(
        shiftID: UUID,
        closeRunID: UUID,
        closingCash: Decimal,
        note: String,
        at date: Date = .now
    ) async throws {
        try await database.completeCloseRunAndCloseShift(
            shiftID: shiftID,
            closeRunID: closeRunID,
            closingCash: closingCash,
            note: note,
            at: date
        )
    }

    func todayCounters() async throws -> (sessions: Int, incidents: Int) {
        try await database.fetchTodayCounters()
    }

    func dashboardSnapshot(seatLimit: Int) async throws -> DashboardSnapshot {
        try await database.dashboardSnapshot(seatLimit: seatLimit)
    }
}

struct DashboardSnapshot: Sendable {
    var activeShift: Shift?
    var employeeName: String?
    var zones: [ZoneSummary]
    var lowestHealth: [GamingSeat]
    var counters: (sessions: Int, incidents: Int)
    var dueMaintenance: Int
    var lowStock: Int
}

extension Database {
    static let shiftColumns = """
        SELECT id, employee_id, opened_at, closed_at, status, open_checklist_run_id,
               close_checklist_run_id, opening_cash_cents, closing_cash_cents,
               seat_session_count, incident_count, note, is_archived
        FROM shift
        """

    func dashboardSnapshot(seatLimit: Int) throws -> DashboardSnapshot {
        let shift = try fetchActiveShift()
        return DashboardSnapshot(
            activeShift: shift,
            employeeName: try shift.flatMap { try fetchEmployee(id: $0.employeeID) }?.fullName,
            zones: try fetchZoneSummaries(),
            lowestHealth: try fetchLowestHealthSeats(limit: seatLimit),
            counters: try fetchTodayCounters(),
            dueMaintenance: try dueMaintenanceCount(),
            lowStock: try lowStockCount()
        )
    }

    func fetchActiveShift() throws -> Shift? {
        try queryOne(
            "\(Self.shiftColumns) WHERE status = ? LIMIT 1;",
            bind: { try $0.bind(ShiftStatus.opened.rawValue, at: 1) },
            map: Self.mapShift
        )
    }

    func fetchRecentShifts(limit: Int) throws -> [Shift] {
        try query(
            "\(Self.shiftColumns) ORDER BY opened_at DESC LIMIT ?;",
            bind: { try $0.bind(limit, at: 1) },
            map: Self.mapShift
        )
    }

    func openShift(
        employeeID: UUID,
        openRunID: UUID,
        openingCash: Decimal,
        at date: Date
    ) throws -> Shift {
        if try fetchActiveShift() != nil {
            throw DatabaseError.constraint("A shift is already open")
        }
        let shift = Shift(
            id: UUID(),
            employeeID: employeeID,
            openedAt: date,
            closedAt: nil,
            status: .opened,
            openChecklistRunID: openRunID,
            closeChecklistRunID: nil,
            openingCash: openingCash,
            closingCash: nil,
            seatSessionCount: 0,
            incidentCount: 0,
            note: "",
            isArchived: false
        )
        try insertShift(shift)
        return shift
    }

    func insertShift(_ shift: Shift) throws {
        try run(
            """
            INSERT OR REPLACE INTO shift (
                id, employee_id, opened_at, closed_at, status, open_checklist_run_id,
                close_checklist_run_id, opening_cash_cents, closing_cash_cents,
                seat_session_count, incident_count, note, is_archived
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
        ) { statement in
            try statement.bind(shift.id, at: 1)
            try statement.bind(shift.employeeID, at: 2)
            try statement.bind(shift.openedAt, at: 3)
            try statement.bindOptional(shift.closedAt, at: 4)
            try statement.bind(shift.status.rawValue, at: 5)
            try statement.bind(shift.openChecklistRunID, at: 6)
            try statement.bindOptional(shift.closeChecklistRunID, at: 7)
            try statement.bindMoney(shift.openingCash, at: 8)
            try statement.bindOptionalMoney(shift.closingCash, at: 9)
            try statement.bind(shift.seatSessionCount, at: 10)
            try statement.bind(shift.incidentCount, at: 11)
            try statement.bind(shift.note, at: 12)
            try statement.bind(shift.isArchived, at: 13)
        }
    }

    func closeShift(
        shiftID: UUID,
        closeRunID: UUID,
        closingCash: Decimal,
        note: String,
        at date: Date
    ) throws {
        try withTransaction {
            let sessionCount = try countSeatSessions(shiftID: shiftID)
            let incidentCount = try countIncidents(shiftID: shiftID)
            try run(
                """
                UPDATE shift SET
                    closed_at = ?,
                    status = ?,
                    close_checklist_run_id = ?,
                    closing_cash_cents = ?,
                    seat_session_count = ?,
                    incident_count = ?,
                    note = ?,
                    is_archived = 1
                WHERE id = ?;
                """
            ) { statement in
                try statement.bind(date, at: 1)
                try statement.bind(ShiftStatus.closed.rawValue, at: 2)
                try statement.bind(closeRunID, at: 3)
                try statement.bindMoney(closingCash, at: 4)
                try statement.bind(sessionCount, at: 5)
                try statement.bind(incidentCount, at: 6)
                try statement.bind(note, at: 7)
                try statement.bind(shiftID, at: 8)
            }
        }
    }

    func completeCloseRunAndCloseShift(
        shiftID: UUID,
        closeRunID: UUID,
        closingCash: Decimal,
        note: String,
        at date: Date
    ) throws {
        try withTransaction {
            try completeChecklistRun(id: closeRunID, at: date)
            try closeShift(
                shiftID: shiftID,
                closeRunID: closeRunID,
                closingCash: closingCash,
                note: note,
                at: date
            )
        }
    }

    func fetchShiftOpenWork(shiftID: UUID) throws -> ShiftOpenWork {
        ShiftOpenWork(
            activeMaintenanceCount: try scalarInt(
                "SELECT COUNT(*) FROM maintenance_task WHERE status = ?;"
            ) { try $0.bind(TaskStatus.active.rawValue, at: 1) },
            unresolvedIncidents: try scalarInt(
                "SELECT COUNT(*) FROM incident WHERE shift_id = ? AND is_resolved = 0;"
            ) { try $0.bind(shiftID, at: 1) },
            openSeatSessions: try scalarInt(
                "SELECT COUNT(*) FROM seat_session WHERE shift_id = ? AND ended_at IS NULL;"
            ) { try $0.bind(shiftID, at: 1) },
            lowStockItems: try lowStockCount()
        )
    }

    func fetchTodayCounters() throws -> (sessions: Int, incidents: Int) {
        let start = Calendar.current.startOfDay(for: Date())
        return (
            sessions: try scalarInt("SELECT COUNT(*) FROM seat_session WHERE started_at >= ?;") {
                try $0.bind(start, at: 1)
            },
            incidents: try scalarInt("SELECT COUNT(*) FROM incident WHERE occurred_at >= ?;") {
                try $0.bind(start, at: 1)
            }
        )
    }

    func countSeatSessions(shiftID: UUID) throws -> Int {
        try scalarInt("SELECT COUNT(*) FROM seat_session WHERE shift_id = ?;") {
            try $0.bind(shiftID, at: 1)
        }
    }

    func countIncidents(shiftID: UUID) throws -> Int {
        try scalarInt("SELECT COUNT(*) FROM incident WHERE shift_id = ?;") {
            try $0.bind(shiftID, at: 1)
        }
    }

    func dueMaintenanceCount(now: Date = .now) throws -> Int {
        try scalarInt(
            "SELECT COUNT(*) FROM maintenance_task WHERE status IN (?, ?) AND scheduled_for <= ?;"
        ) { statement in
            try statement.bind(TaskStatus.planned.rawValue, at: 1)
            try statement.bind(TaskStatus.active.rawValue, at: 2)
            try statement.bind(now, at: 3)
        }
    }

    func lowStockCount() throws -> Int {
        try scalarInt(
            "SELECT COUNT(*) FROM inventory_item WHERE quantity_milli <= minimum_quantity_milli;"
        )
    }

    static func mapShift(_ statement: Statement) throws -> Shift {
        guard let status = ShiftStatus(rawValue: try statement.string(at: 4)) else {
            throw DatabaseError.stepFailed("Invalid shift status")
        }
        return Shift(
            id: try statement.uuid(at: 0),
            employeeID: try statement.uuid(at: 1),
            openedAt: statement.date(at: 2),
            closedAt: statement.optionalDate(at: 3),
            status: status,
            openChecklistRunID: try statement.uuid(at: 5),
            closeChecklistRunID: try statement.optionalUUID(at: 6),
            openingCash: statement.money(at: 7),
            closingCash: statement.optionalMoney(at: 8),
            seatSessionCount: statement.int(at: 9),
            incidentCount: statement.int(at: 10),
            note: try statement.string(at: 11),
            isArchived: statement.bool(at: 12)
        )
    }
}
