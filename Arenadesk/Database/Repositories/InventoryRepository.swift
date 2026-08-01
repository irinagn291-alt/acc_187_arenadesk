import Foundation

struct InventoryRepository: Sendable {
    let database: Database

    func fetchAll() async throws -> [InventoryItem] {
        try await database.fetchInventoryItems()
    }

    func fetch(id: UUID) async throws -> InventoryItem? {
        try await database.fetchInventoryItem(id: id)
    }

    func upsert(_ item: InventoryItem) async throws {
        try await database.upsertInventoryItem(item)
    }

    func movements(itemID: UUID) async throws -> [InventoryMovement] {
        try await database.fetchInventoryMovements(itemID: itemID)
    }

    func addMovement(_ movement: InventoryMovement) async throws -> (item: InventoryItem, crossedLowStock: Bool) {
        try await database.addInventoryMovement(movement)
    }

    func lowStockItems() async throws -> [InventoryItem] {
        try await database.fetchLowStockItems()
    }
}

extension Database {
    private static let inventoryItemColumns = """
        SELECT id, name, sku, unit, quantity_milli, minimum_quantity_milli,
               unit_cost_cents, category_name, is_consumable
        FROM inventory_item
        """

    func fetchInventoryItems() throws -> [InventoryItem] {
        try query("\(Self.inventoryItemColumns) ORDER BY name;", map: Self.mapInventoryItem)
    }

    func fetchInventoryItem(id: UUID) throws -> InventoryItem? {
        try queryOne(
            "\(Self.inventoryItemColumns) WHERE id = ?;",
            bind: { try $0.bind(id, at: 1) },
            map: Self.mapInventoryItem
        )
    }

    func upsertInventoryItem(_ item: InventoryItem) throws {
        try run(
            """
            INSERT INTO inventory_item (
                id, name, sku, unit, quantity_milli, minimum_quantity_milli,
                unit_cost_cents, category_name, is_consumable
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                sku = excluded.sku,
                unit = excluded.unit,
                quantity_milli = excluded.quantity_milli,
                minimum_quantity_milli = excluded.minimum_quantity_milli,
                unit_cost_cents = excluded.unit_cost_cents,
                category_name = excluded.category_name,
                is_consumable = excluded.is_consumable;
            """
        ) { statement in
            try statement.bind(item.id, at: 1)
            try statement.bind(item.name, at: 2)
            try statement.bind(item.sku, at: 3)
            try statement.bind(item.unit, at: 4)
            try statement.bindQuantity(item.quantity, at: 5)
            try statement.bindQuantity(item.minimumQuantity, at: 6)
            try statement.bindMoney(item.unitCost, at: 7)
            try statement.bind(item.categoryName, at: 8)
            try statement.bind(item.isConsumable, at: 9)
        }
    }

    private static let movementColumns = """
        SELECT id, item_id, kind, quantity_milli, occurred_at, shift_id, employee_id, reason
        FROM inventory_movement
        """

    func fetchInventoryMovements(itemID: UUID) throws -> [InventoryMovement] {
        try query(
            "\(Self.movementColumns) WHERE item_id = ? ORDER BY occurred_at DESC;",
            bind: { try $0.bind(itemID, at: 1) },
            map: Self.mapInventoryMovement
        )
    }

    func fetchAllInventoryMovements() throws -> [InventoryMovement] {
        try query("\(Self.movementColumns) ORDER BY occurred_at;", map: Self.mapInventoryMovement)
    }

    static func mapInventoryMovement(_ statement: Statement) throws -> InventoryMovement {
        guard let kind = MovementKind(rawValue: try statement.string(at: 2)) else {
            throw DatabaseError.stepFailed("Invalid movement kind")
        }
        return InventoryMovement(
            id: try statement.uuid(at: 0),
            itemID: try statement.uuid(at: 1),
            kind: kind,
            quantity: statement.quantity(at: 3),
            occurredAt: statement.date(at: 4),
            shiftID: try statement.optionalUUID(at: 5),
            employeeID: try statement.optionalUUID(at: 6),
            reason: try statement.string(at: 7)
        )
    }

    @discardableResult
    func recomputeInventoryQuantity(itemID: UUID) throws -> Decimal {
        let total = try scalarInt64(
            """
            SELECT COALESCE(SUM(
                CASE kind
                    WHEN ? THEN quantity_milli
                    WHEN ? THEN -quantity_milli
                    WHEN ? THEN -quantity_milli
                    WHEN ? THEN quantity_milli
                    ELSE 0
                END
            ), 0)
            FROM inventory_movement WHERE item_id = ?;
            """
        ) { statement in
            try statement.bind(MovementKind.receipt.rawValue, at: 1)
            try statement.bind(MovementKind.issue.rawValue, at: 2)
            try statement.bind(MovementKind.writeOff.rawValue, at: 3)
            try statement.bind(MovementKind.correction.rawValue, at: 4)
            try statement.bind(itemID, at: 5)
        }

        try run("UPDATE inventory_item SET quantity_milli = ? WHERE id = ?;") { statement in
            try statement.bind(total, at: 1)
            try statement.bind(itemID, at: 2)
        }
        return Money.decimal(fromQuantityUnits: total)
    }

    func insertInventoryMovement(_ movement: InventoryMovement) throws {
        try run(
            """
            INSERT OR REPLACE INTO inventory_movement (
                id, item_id, kind, quantity_milli, occurred_at, shift_id, employee_id, reason
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """
        ) { statement in
            try statement.bind(movement.id, at: 1)
            try statement.bind(movement.itemID, at: 2)
            try statement.bind(movement.kind.rawValue, at: 3)
            let stored = movement.kind == .correction ? movement.quantity : abs(movement.quantity)
            try statement.bindQuantity(stored, at: 4)
            try statement.bind(movement.occurredAt, at: 5)
            try statement.bindOptional(movement.shiftID, at: 6)
            try statement.bindOptional(movement.employeeID, at: 7)
            try statement.bind(movement.reason, at: 8)
        }
    }

    func addInventoryMovement(_ movement: InventoryMovement) throws -> (item: InventoryItem, crossedLowStock: Bool) {
        guard let before = try fetchInventoryItem(id: movement.itemID) else {
            throw DatabaseError.stepFailed("Inventory item missing")
        }
        let wasLow = before.quantity <= before.minimumQuantity
        try withTransaction {
            try insertInventoryMovement(movement)
            try recomputeInventoryQuantity(itemID: movement.itemID)
        }
        guard let after = try fetchInventoryItem(id: movement.itemID) else {
            throw DatabaseError.stepFailed("Inventory item missing after write")
        }
        let isLow = after.quantity <= after.minimumQuantity
        return (after, !wasLow && isLow)
    }

    func fetchLowStockItems() throws -> [InventoryItem] {
        try query(
            """
            \(Self.inventoryItemColumns)
            WHERE quantity_milli <= minimum_quantity_milli
            ORDER BY name;
            """,
            map: Self.mapInventoryItem
        )
    }

    static func mapInventoryItem(_ statement: Statement) throws -> InventoryItem {
        InventoryItem(
            id: try statement.uuid(at: 0),
            name: try statement.string(at: 1),
            sku: try statement.string(at: 2),
            unit: try statement.string(at: 3),
            quantity: statement.quantity(at: 4),
            minimumQuantity: statement.quantity(at: 5),
            unitCost: statement.money(at: 6),
            categoryName: try statement.string(at: 7),
            isConsumable: statement.bool(at: 8)
        )
    }
}
