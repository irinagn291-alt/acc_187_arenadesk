import Foundation

struct AnalyticsSnapshot: Sendable {
    var shiftsPerWeek: [(weekStart: Date, count: Int)]
    var averageShiftLengthHours: Double
    var sessionsPerZone: [(zoneName: String, count: Int)]
    var healthDistribution: [(band: String, count: Int)]
    var problematicSeats: [(label: String, incidents: Int, repairs: Int)]
    var repairCostByMonth: [(month: String, cents: Int64)]
    var maintenanceCompleted: Int
    var maintenancePlanned: Int
    var tournamentsByMonth: [(month: String, tournaments: Int, participants: Int)]
    var topInventoryConsumption: [(name: String, quantity: Decimal)]
    var incomeExpenseByMonth: [(month: String, income: Decimal, expense: Decimal)]
}

struct AnalyticsRepository: Sendable {
    let database: Database

    func snapshot(from: Date, to: Date) async throws -> AnalyticsSnapshot {
        try await database.analyticsSnapshot(from: from, to: to)
    }
}

extension Database {
    static let analyticsCalendar = Calendar.current

    private static let monthKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = analyticsCalendar
        formatter.timeZone = analyticsCalendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()

    static func monthKey(for date: Date) -> String {
        monthKeyFormatter.string(from: date)
    }

    func analyticsSnapshot(from: Date, to: Date) throws -> AnalyticsSnapshot {
        AnalyticsSnapshot(
            shiftsPerWeek: try shiftsPerWeek(from: from, to: to),
            averageShiftLengthHours: try averageShiftLength(from: from, to: to),
            sessionsPerZone: try sessionsPerZone(from: from, to: to),
            healthDistribution: try healthDistribution(from: from, to: to),
            problematicSeats: try problematicSeats(from: from, to: to),
            repairCostByMonth: try repairCostByMonth(from: from, to: to),
            maintenanceCompleted: try maintenanceCount(status: .completed, from: from, to: to),
            maintenancePlanned: try maintenanceCount(status: .planned, from: from, to: to),
            tournamentsByMonth: try tournamentsByMonth(from: from, to: to),
            topInventoryConsumption: try topInventoryConsumption(from: from, to: to),
            incomeExpenseByMonth: try incomeExpenseByMonth(from: from, to: to)
        )
    }

    private func shiftsPerWeek(from: Date, to: Date) throws -> [(Date, Int)] {
        let opened = try query(
            "SELECT opened_at FROM shift WHERE opened_at >= ? AND opened_at <= ?;",
            bind: { statement in
                try statement.bind(from, at: 1)
                try statement.bind(to, at: 2)
            },
            map: { $0.date(at: 0) }
        )
        var buckets: [Date: Int] = [:]
        for date in opened {
            let week = Self.analyticsCalendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
            buckets[week, default: 0] += 1
        }
        return buckets.keys.sorted().map { ($0, buckets[$0] ?? 0) }
    }

    private func averageShiftLength(from: Date, to: Date) throws -> Double {
        let spans = try query(
            """
            SELECT opened_at, closed_at FROM shift
            WHERE closed_at IS NOT NULL AND opened_at >= ? AND opened_at <= ?;
            """,
            bind: { statement in
                try statement.bind(from, at: 1)
                try statement.bind(to, at: 2)
            },
            map: { statement -> TimeInterval? in
                guard let closed = statement.optionalDate(at: 1) else { return nil }
                return closed.timeIntervalSince(statement.date(at: 0))
            }
        ).compactMap { $0 }

        guard !spans.isEmpty else { return 0 }
        return spans.reduce(0, +) / Double(spans.count) / TimeConstants.hour
    }

    private func sessionsPerZone(from: Date, to: Date) throws -> [(String, Int)] {
        try query(
            """
            SELECT z.name, COUNT(*)
            FROM seat_session s
            JOIN gaming_seat gs ON gs.id = s.seat_id
            JOIN zone z ON z.id = gs.zone_id
            WHERE s.started_at >= ? AND s.started_at <= ?
            GROUP BY z.name ORDER BY COUNT(*) DESC;
            """,
            bind: { statement in
                try statement.bind(from, at: 1)
                try statement.bind(to, at: 2)
            }
        ) { (try $0.string(at: 0), $0.int(at: 1)) }
    }

    private func healthDistribution(from: Date, to: Date) throws -> [(String, Int)] {
        let seats = try fetchSeats(zoneID: nil).filter { $0.commissionedAt <= to }
        var counts: [String: Int] = [:]
        for seat in seats {
            counts[HealthBand.band(for: seat.healthScore).rawValue, default: 0] += 1
        }
        return ["healthy", "watch", "degraded", "critical"].map { ($0, counts[$0] ?? 0) }
    }

    private func problematicSeats(from: Date, to: Date) throws -> [(String, Int, Int)] {
        try query(
            """
            SELECT gs.label,
                (SELECT COUNT(*) FROM incident i
                 WHERE i.seat_id = gs.id AND i.occurred_at >= ?1 AND i.occurred_at <= ?2),
                (SELECT COUNT(*) FROM repair_record r
                 WHERE r.seat_id = gs.id AND r.opened_at >= ?1 AND r.opened_at <= ?2)
            FROM gaming_seat gs
            ORDER BY
                (SELECT COUNT(*) FROM incident i
                 WHERE i.seat_id = gs.id AND i.occurred_at >= ?1 AND i.occurred_at <= ?2) +
                (SELECT COUNT(*) FROM repair_record r
                 WHERE r.seat_id = gs.id AND r.opened_at >= ?1 AND r.opened_at <= ?2) DESC,
                gs.label ASC
            LIMIT 10;
            """,
            bind: { statement in
                try statement.bind(from, at: 1)
                try statement.bind(to, at: 2)
            }
        ) { (try $0.string(at: 0), $0.int(at: 1), $0.int(at: 2)) }
    }

    private func repairCostByMonth(from: Date, to: Date) throws -> [(String, Int64)] {
        let rows = try query(
            """
            SELECT closed_at, parts_cost_cents + labor_cost_cents
            FROM repair_record
            WHERE closed_at IS NOT NULL AND closed_at >= ? AND closed_at <= ?;
            """,
            bind: { statement in
                try statement.bind(from, at: 1)
                try statement.bind(to, at: 2)
            },
            map: { (Self.monthKey(for: $0.date(at: 0)), $0.int64(at: 1)) }
        )
        var buckets: [String: Int64] = [:]
        for (month, cents) in rows {
            buckets[month, default: 0] += cents
        }
        return buckets.keys.sorted().map { ($0, buckets[$0] ?? 0) }
    }

    private func maintenanceCount(status: TaskStatus, from: Date, to: Date) throws -> Int {
        try scalarInt(
            """
            SELECT COUNT(*) FROM maintenance_task
            WHERE status = ? AND scheduled_for >= ? AND scheduled_for <= ?;
            """
        ) { statement in
            try statement.bind(status.rawValue, at: 1)
            try statement.bind(from, at: 2)
            try statement.bind(to, at: 3)
        }
    }

    private func tournamentsByMonth(from: Date, to: Date) throws -> [(String, Int, Int)] {
        let rows = try query(
            """
            SELECT t.starts_at, t.id, COUNT(p.id)
            FROM tournament t
            LEFT JOIN participant p ON p.tournament_id = t.id
            WHERE t.starts_at >= ? AND t.starts_at <= ?
            GROUP BY t.id ORDER BY t.starts_at;
            """,
            bind: { statement in
                try statement.bind(from, at: 1)
                try statement.bind(to, at: 2)
            },
            map: { (Self.monthKey(for: $0.date(at: 0)), $0.int(at: 2)) }
        )
        var tournaments: [String: Int] = [:]
        var participants: [String: Int] = [:]
        for (month, count) in rows {
            tournaments[month, default: 0] += 1
            participants[month, default: 0] += count
        }
        return tournaments.keys.sorted().map {
            ($0, tournaments[$0] ?? 0, participants[$0] ?? 0)
        }
    }

    private func topInventoryConsumption(from: Date, to: Date) throws -> [(String, Decimal)] {
        try query(
            """
            SELECT i.name, SUM(m.quantity_milli)
            FROM inventory_movement m
            JOIN inventory_item i ON i.id = m.item_id
            WHERE m.kind IN (?, ?) AND m.occurred_at >= ? AND m.occurred_at <= ?
            GROUP BY i.name
            ORDER BY SUM(m.quantity_milli) DESC
            LIMIT 10;
            """,
            bind: { statement in
                try statement.bind(MovementKind.issue.rawValue, at: 1)
                try statement.bind(MovementKind.writeOff.rawValue, at: 2)
                try statement.bind(from, at: 3)
                try statement.bind(to, at: 4)
            }
        ) { (try $0.string(at: 0), Money.decimal(fromQuantityUnits: $0.int64(at: 1))) }
    }

    private func incomeExpenseByMonth(from: Date, to: Date) throws -> [(String, Decimal, Decimal)] {
        let rows = try query(
            """
            SELECT occurred_at, kind, amount_cents
            FROM finance_record
            WHERE occurred_at >= ? AND occurred_at <= ?;
            """,
            bind: { statement in
                try statement.bind(from, at: 1)
                try statement.bind(to, at: 2)
            },
            map: { (Self.monthKey(for: $0.date(at: 0)), try $0.string(at: 1), $0.int64(at: 2)) }
        )
        var income: [String: Int64] = [:]
        var expense: [String: Int64] = [:]
        for (month, kind, cents) in rows {
            switch FinanceKind(rawValue: kind) {
            case .income: income[month, default: 0] += cents
            case .expense: expense[month, default: 0] += cents
            case .none: continue
            }
        }
        return Set(income.keys).union(expense.keys).sorted().map {
            (
                $0,
                Money.decimal(fromMinorUnits: income[$0] ?? 0),
                Money.decimal(fromMinorUnits: expense[$0] ?? 0)
            )
        }
    }
}
