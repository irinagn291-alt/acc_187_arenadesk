import Foundation

struct RepairRepository: Sendable {
    let database: Database

    func fetchAll(openOnly: Bool = false) async throws -> [RepairRecord] {
        try await database.fetchRepairs(openOnly: openOnly)
    }

    func fetch(id: UUID) async throws -> RepairRecord? {
        try await database.fetchRepair(id: id)
    }

    func upsert(_ repair: RepairRecord) async throws {
        try await database.upsertRepairRecord(repair)
    }

    func close(
        id: UUID,
        actionTaken: String,
        partsCost: Decimal,
        laborCost: Decimal,
        performedBy: String,
        retireEquipment: Bool,
        at date: Date = .now
    ) async throws -> RepairRecord {
        try await database.closeRepair(
            id: id,
            actionTaken: actionTaken,
            partsCost: partsCost,
            laborCost: laborCost,
            performedBy: performedBy,
            retireEquipment: retireEquipment,
            at: date
        )
    }

    func costTotals() async throws -> (open: Decimal, closed: Decimal) {
        try await database.repairCostTotals()
    }
}

extension Database {
    private static let repairColumns = """
        SELECT id, equipment_id, seat_id, opened_at, closed_at, symptom, action_taken,
               parts_cost_cents, labor_cost_cents, performed_by, is_external
        FROM repair_record
        """

    func fetchRepairs(openOnly: Bool) throws -> [RepairRecord] {
        let sql = openOnly
            ? "\(Self.repairColumns) WHERE closed_at IS NULL ORDER BY opened_at DESC;"
            : "\(Self.repairColumns) ORDER BY opened_at DESC;"
        return try query(sql, map: Self.mapRepair)
    }

    func fetchRepair(id: UUID) throws -> RepairRecord? {
        try queryOne(
            "\(Self.repairColumns) WHERE id = ?;",
            bind: { try $0.bind(id, at: 1) },
            map: Self.mapRepair
        )
    }

    func upsertRepairRecord(_ repair: RepairRecord) throws {
        try run(
            """
            INSERT INTO repair_record (
                id, equipment_id, seat_id, opened_at, closed_at, symptom, action_taken,
                parts_cost_cents, labor_cost_cents, performed_by, is_external
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                equipment_id = excluded.equipment_id,
                seat_id = excluded.seat_id,
                opened_at = excluded.opened_at,
                closed_at = excluded.closed_at,
                symptom = excluded.symptom,
                action_taken = excluded.action_taken,
                parts_cost_cents = excluded.parts_cost_cents,
                labor_cost_cents = excluded.labor_cost_cents,
                performed_by = excluded.performed_by,
                is_external = excluded.is_external;
            """,
            { try Self.bindRepair(repair, to: $0) }
        )
    }

    func closeRepair(
        id: UUID,
        actionTaken: String,
        partsCost: Decimal,
        laborCost: Decimal,
        performedBy: String,
        retireEquipment: Bool,
        at date: Date
    ) throws -> RepairRecord {
        guard var repair = try fetchRepair(id: id) else {
            throw DatabaseError.stepFailed("Repair not found")
        }
        repair.closedAt = date
        repair.actionTaken = actionTaken
        repair.partsCost = partsCost
        repair.laborCost = laborCost
        repair.performedBy = performedBy

        let closed = repair
        try withTransaction {
            try upsertRepairRecord(closed)

            if let equipmentID = closed.equipmentID {
                _ = try changeEquipmentState(
                    id: equipmentID,
                    to: retireEquipment ? .retired : .ok,
                    employeeID: nil,
                    reason: retireEquipment ? "Retired after repair" : "Repair closed",
                    at: date
                )
            }
            if let seatID = closed.seatID {
                _ = try recomputeSeatHealth(id: seatID, now: date)
            }
        }
        return repair
    }

    func repairCostTotals() throws -> (open: Decimal, closed: Decimal) {
        let open = try scalarInt64(
            """
            SELECT COALESCE(SUM(parts_cost_cents + labor_cost_cents), 0)
            FROM repair_record WHERE closed_at IS NULL;
            """
        )
        let closed = try scalarInt64(
            """
            SELECT COALESCE(SUM(parts_cost_cents + labor_cost_cents), 0)
            FROM repair_record WHERE closed_at IS NOT NULL;
            """
        )
        return (Money.decimal(fromMinorUnits: open), Money.decimal(fromMinorUnits: closed))
    }
}
