import Foundation

struct FinanceRepository: Sendable {
    let database: Database

    func fetch(from: Date, to: Date) async throws -> [FinanceRecord] {
        try await database.fetchFinanceRecords(from: from, to: to)
    }

    func upsert(_ record: FinanceRecord) async throws {
        try await database.upsertFinanceRecord(record)
    }

    func balance(from: Date, to: Date) async throws -> Decimal {
        try await database.financeBalance(from: from, to: to)
    }

    func categoryBreakdown(from: Date, to: Date) async throws -> [(category: String, income: Decimal, expense: Decimal)] {
        try await database.financeCategoryBreakdown(from: from, to: to)
    }
}

extension Database {
    func fetchFinanceRecords(from: Date, to: Date) throws -> [FinanceRecord] {
        try query(
            """
            SELECT id, kind, category_name, amount_cents, occurred_at,
                   shift_id, tournament_id, repair_id, note
            FROM finance_record
            WHERE occurred_at >= ? AND occurred_at <= ?
            ORDER BY occurred_at DESC;
            """,
            bind: { statement in
                try statement.bind(from, at: 1)
                try statement.bind(to, at: 2)
            },
            map: Self.mapFinance
        )
    }

    func upsertFinanceRecord(_ record: FinanceRecord) throws {
        try run(
            """
            INSERT INTO finance_record (
                id, kind, category_name, amount_cents, occurred_at,
                shift_id, tournament_id, repair_id, note
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                kind = excluded.kind,
                category_name = excluded.category_name,
                amount_cents = excluded.amount_cents,
                occurred_at = excluded.occurred_at,
                shift_id = excluded.shift_id,
                tournament_id = excluded.tournament_id,
                repair_id = excluded.repair_id,
                note = excluded.note;
            """
        ) { statement in
            try statement.bind(record.id, at: 1)
            try statement.bind(record.kind.rawValue, at: 2)
            try statement.bind(record.categoryName, at: 3)
            try statement.bindMoney(record.amount, at: 4)
            try statement.bind(record.occurredAt, at: 5)
            try statement.bindOptional(record.shiftID, at: 6)
            try statement.bindOptional(record.tournamentID, at: 7)
            try statement.bindOptional(record.repairID, at: 8)
            try statement.bind(record.note, at: 9)
        }
    }

    func financeBalance(from: Date, to: Date) throws -> Decimal {
        let cents = try scalarInt64(
            """
            SELECT
                COALESCE(SUM(CASE WHEN kind = ? THEN amount_cents ELSE 0 END), 0) -
                COALESCE(SUM(CASE WHEN kind = ? THEN amount_cents ELSE 0 END), 0)
            FROM finance_record
            WHERE occurred_at >= ? AND occurred_at <= ?;
            """
        ) { statement in
            try statement.bind(FinanceKind.income.rawValue, at: 1)
            try statement.bind(FinanceKind.expense.rawValue, at: 2)
            try statement.bind(from, at: 3)
            try statement.bind(to, at: 4)
        }
        return Money.decimal(fromMinorUnits: cents)
    }

    func financeCategoryBreakdown(from: Date, to: Date) throws -> [(category: String, income: Decimal, expense: Decimal)] {
        try query(
            """
            SELECT category_name,
                COALESCE(SUM(CASE WHEN kind = ? THEN amount_cents ELSE 0 END), 0),
                COALESCE(SUM(CASE WHEN kind = ? THEN amount_cents ELSE 0 END), 0)
            FROM finance_record
            WHERE occurred_at >= ? AND occurred_at <= ?
            GROUP BY category_name
            ORDER BY category_name;
            """,
            bind: { statement in
                try statement.bind(FinanceKind.income.rawValue, at: 1)
                try statement.bind(FinanceKind.expense.rawValue, at: 2)
                try statement.bind(from, at: 3)
                try statement.bind(to, at: 4)
            }
        ) { statement in
            (
                category: try statement.string(at: 0),
                income: Money.decimal(fromMinorUnits: statement.int64(at: 1)),
                expense: Money.decimal(fromMinorUnits: statement.int64(at: 2))
            )
        }
    }

    static func mapFinance(_ statement: Statement) throws -> FinanceRecord {
        guard let kind = FinanceKind(rawValue: try statement.string(at: 1)) else {
            throw DatabaseError.stepFailed("Invalid finance kind")
        }
        return FinanceRecord(
            id: try statement.uuid(at: 0),
            kind: kind,
            categoryName: try statement.string(at: 2),
            amount: statement.money(at: 3),
            occurredAt: statement.date(at: 4),
            shiftID: try statement.optionalUUID(at: 5),
            tournamentID: try statement.optionalUUID(at: 6),
            repairID: try statement.optionalUUID(at: 7),
            note: try statement.string(at: 8)
        )
    }
}
