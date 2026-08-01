import Foundation

struct EquipmentRepository: Sendable {
    let database: Database

    func fetchAll() async throws -> [Equipment] {
        try await database.fetchEquipment(seatID: nil)
    }

    func fetch(seatID: UUID) async throws -> [Equipment] {
        try await database.fetchEquipment(seatID: seatID)
    }

    func fetch(id: UUID) async throws -> Equipment? {
        try await database.fetchEquipmentItem(id: id)
    }

    func upsert(_ item: Equipment) async throws {
        try await database.upsertEquipment(item)
    }

    func changeState(
        id: UUID,
        to newState: EquipmentState,
        employeeID: UUID?,
        reason: String,
        at date: Date = .now
    ) async throws -> RepairRecord? {
        try await database.changeEquipmentState(
            id: id,
            to: newState,
            employeeID: employeeID,
            reason: reason,
            at: date
        )
    }

    func stateHistory(equipmentID: UUID) async throws -> [EquipmentStateChange] {
        try await database.fetchEquipmentStateChanges(equipmentID: equipmentID)
    }

    func openRepairs(equipmentID: UUID) async throws -> [RepairRecord] {
        try await database.fetchOpenRepairs(equipmentID: equipmentID)
    }
}

extension Database {
    private static let equipmentColumns = """
        SELECT id, seat_id, zone_id, name, kind, serial_number, state, purchased_at,
               warranty_until, price_cents, state_changed_at, note
        FROM equipment
        """

    func fetchEquipment(seatID: UUID?) throws -> [Equipment] {
        if let seatID {
            return try query(
                "\(Self.equipmentColumns) WHERE seat_id = ? ORDER BY name;",
                bind: { try $0.bind(seatID, at: 1) },
                map: Self.mapEquipment
            )
        }
        return try query("\(Self.equipmentColumns) ORDER BY name;", map: Self.mapEquipment)
    }

    func fetchEquipmentItem(id: UUID) throws -> Equipment? {
        try queryOne(
            "\(Self.equipmentColumns) WHERE id = ?;",
            bind: { try $0.bind(id, at: 1) },
            map: Self.mapEquipment
        )
    }

    func upsertEquipment(_ item: Equipment) throws {
        try insertEquipmentRow(item)
        if let seatID = item.seatID {
            _ = try recomputeSeatHealth(id: seatID, now: .now)
        }
    }

    func insertEquipmentRow(_ item: Equipment) throws {
        try run(
            """
            INSERT INTO equipment (
                id, seat_id, zone_id, name, kind, serial_number, state, purchased_at,
                warranty_until, price_cents, state_changed_at, note
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                seat_id = excluded.seat_id,
                zone_id = excluded.zone_id,
                name = excluded.name,
                kind = excluded.kind,
                serial_number = excluded.serial_number,
                state = excluded.state,
                purchased_at = excluded.purchased_at,
                warranty_until = excluded.warranty_until,
                price_cents = excluded.price_cents,
                state_changed_at = excluded.state_changed_at,
                note = excluded.note;
            """
        ) { statement in
            try statement.bind(item.id, at: 1)
            try statement.bindOptional(item.seatID, at: 2)
            try statement.bindOptional(item.zoneID, at: 3)
            try statement.bind(item.name, at: 4)
            try statement.bind(item.kind.rawValue, at: 5)
            try statement.bind(item.serialNumber, at: 6)
            try statement.bind(item.state.rawValue, at: 7)
            try statement.bindOptional(item.purchasedAt, at: 8)
            try statement.bindOptional(item.warrantyUntil, at: 9)
            try statement.bindOptionalMoney(item.price, at: 10)
            try statement.bind(item.stateChangedAt, at: 11)
            try statement.bind(item.note, at: 12)
        }
    }

    @discardableResult
    func changeEquipmentState(
        id: UUID,
        to newState: EquipmentState,
        employeeID: UUID?,
        reason: String,
        at date: Date
    ) throws -> RepairRecord? {
        guard let current = try fetchEquipmentItem(id: id) else { return nil }
        if current.state == newState { return nil }

        let openedRepair: RepairRecord? = try withTransaction {
            try run("UPDATE equipment SET state = ?, state_changed_at = ? WHERE id = ?;") { statement in
                try statement.bind(newState.rawValue, at: 1)
                try statement.bind(date, at: 2)
                try statement.bind(id, at: 3)
            }

            try insertEquipmentStateChange(
                EquipmentStateChange(
                    id: UUID(),
                    equipmentID: id,
                    fromState: current.state,
                    toState: newState,
                    changedAt: date,
                    employeeID: employeeID,
                    reason: reason
                )
            )

            guard newState == .inRepair else { return nil }
            let repair = RepairRecord(
                id: UUID(),
                equipmentID: id,
                seatID: current.seatID,
                openedAt: date,
                closedAt: nil,
                symptom: reason.isEmpty ? "Moved to repair" : reason,
                actionTaken: "",
                partsCost: 0,
                laborCost: 0,
                performedBy: "",
                isExternal: false
            )
            try insertRepairRecord(repair)
            return repair
        }
        if let seatID = current.seatID {
            _ = try recomputeSeatHealth(id: seatID, now: date)
        }
        return openedRepair
    }

    func insertEquipmentStateChange(_ change: EquipmentStateChange) throws {
        try run(
            """
            INSERT INTO equipment_state_change (
                id, equipment_id, from_state, to_state, changed_at, employee_id, reason
            ) VALUES (?, ?, ?, ?, ?, ?, ?);
            """
        ) { statement in
            try statement.bind(change.id, at: 1)
            try statement.bind(change.equipmentID, at: 2)
            try statement.bind(change.fromState.rawValue, at: 3)
            try statement.bind(change.toState.rawValue, at: 4)
            try statement.bind(change.changedAt, at: 5)
            try statement.bindOptional(change.employeeID, at: 6)
            try statement.bind(change.reason, at: 7)
        }
    }

    func fetchEquipmentStateChanges(equipmentID: UUID) throws -> [EquipmentStateChange] {
        try query(
            """
            SELECT id, equipment_id, from_state, to_state, changed_at, employee_id, reason
            FROM equipment_state_change WHERE equipment_id = ? ORDER BY changed_at DESC;
            """,
            bind: { try $0.bind(equipmentID, at: 1) },
            map: Self.mapEquipmentStateChange
        )
    }

    func fetchAllEquipmentStateChanges() throws -> [EquipmentStateChange] {
        try query(
            """
            SELECT id, equipment_id, from_state, to_state, changed_at, employee_id, reason
            FROM equipment_state_change ORDER BY changed_at;
            """,
            map: Self.mapEquipmentStateChange
        )
    }

    static func mapEquipmentStateChange(_ statement: Statement) throws -> EquipmentStateChange {
        guard let from = EquipmentState(rawValue: try statement.string(at: 2)),
              let to = EquipmentState(rawValue: try statement.string(at: 3)) else {
            throw DatabaseError.stepFailed("Invalid equipment state")
        }
        return EquipmentStateChange(
            id: try statement.uuid(at: 0),
            equipmentID: try statement.uuid(at: 1),
            fromState: from,
            toState: to,
            changedAt: statement.date(at: 4),
            employeeID: try statement.optionalUUID(at: 5),
            reason: try statement.string(at: 6)
        )
    }

    func insertRepairRecord(_ repair: RepairRecord) throws {
        try run(
            """
            INSERT INTO repair_record (
                id, equipment_id, seat_id, opened_at, closed_at, symptom, action_taken,
                parts_cost_cents, labor_cost_cents, performed_by, is_external
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            { try Self.bindRepair(repair, to: $0) }
        )
    }

    func fetchOpenRepairs(equipmentID: UUID) throws -> [RepairRecord] {
        try query(
            """
            SELECT id, equipment_id, seat_id, opened_at, closed_at, symptom, action_taken,
                   parts_cost_cents, labor_cost_cents, performed_by, is_external
            FROM repair_record WHERE equipment_id = ? AND closed_at IS NULL ORDER BY opened_at DESC;
            """,
            bind: { try $0.bind(equipmentID, at: 1) },
            map: Self.mapRepair
        )
    }

    static func bindRepair(_ repair: RepairRecord, to statement: Statement) throws {
        try statement.bind(repair.id, at: 1)
        try statement.bindOptional(repair.equipmentID, at: 2)
        try statement.bindOptional(repair.seatID, at: 3)
        try statement.bind(repair.openedAt, at: 4)
        try statement.bindOptional(repair.closedAt, at: 5)
        try statement.bind(repair.symptom, at: 6)
        try statement.bind(repair.actionTaken, at: 7)
        try statement.bindMoney(repair.partsCost, at: 8)
        try statement.bindMoney(repair.laborCost, at: 9)
        try statement.bind(repair.performedBy, at: 10)
        try statement.bind(repair.isExternal, at: 11)
    }

    static func mapEquipment(_ statement: Statement) throws -> Equipment {
        guard let kind = EquipmentKind(rawValue: try statement.string(at: 4)),
              let state = EquipmentState(rawValue: try statement.string(at: 6)) else {
            throw DatabaseError.stepFailed("Invalid equipment")
        }
        return Equipment(
            id: try statement.uuid(at: 0),
            seatID: try statement.optionalUUID(at: 1),
            zoneID: try statement.optionalUUID(at: 2),
            name: try statement.string(at: 3),
            kind: kind,
            serialNumber: try statement.string(at: 5),
            state: state,
            purchasedAt: statement.optionalDate(at: 7),
            warrantyUntil: statement.optionalDate(at: 8),
            price: statement.optionalMoney(at: 9),
            stateChangedAt: statement.date(at: 10),
            note: try statement.string(at: 11)
        )
    }

    static func mapRepair(_ statement: Statement) throws -> RepairRecord {
        RepairRecord(
            id: try statement.uuid(at: 0),
            equipmentID: try statement.optionalUUID(at: 1),
            seatID: try statement.optionalUUID(at: 2),
            openedAt: statement.date(at: 3),
            closedAt: statement.optionalDate(at: 4),
            symptom: try statement.string(at: 5),
            actionTaken: try statement.string(at: 6),
            partsCost: statement.money(at: 7),
            laborCost: statement.money(at: 8),
            performedBy: try statement.string(at: 9),
            isExternal: statement.bool(at: 10)
        )
    }
}
