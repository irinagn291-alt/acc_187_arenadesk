import Foundation
import Testing
@testable import Arenadesk

struct InventoryFinanceTests {
    @Test func inventoryQuantityRecomputesAfterOutOfOrderCorrection() async throws {
        let db = try Database(inMemory: true)
        try await Migrator.migrate(db)
        let item = InventoryItem(
            id: UUID(), name: "Cans", sku: "CAN-1", unit: "pcs",
            quantity: 0, minimumQuantity: 2, unitCost: 1, categoryName: "Bar", isConsumable: true
        )
        try await db.upsertInventoryItem(item)

        _ = try await db.addInventoryMovement(
            InventoryMovement(id: UUID(), itemID: item.id, kind: .receipt, quantity: 10,
                              occurredAt: Date(timeIntervalSince1970: 100), shiftID: nil, employeeID: nil, reason: "")
        )
        _ = try await db.addInventoryMovement(
            InventoryMovement(id: UUID(), itemID: item.id, kind: .issue, quantity: 3,
                              occurredAt: Date(timeIntervalSince1970: 200), shiftID: nil, employeeID: nil, reason: "")
        )
        _ = try await db.addInventoryMovement(
            InventoryMovement(id: UUID(), itemID: item.id, kind: .correction, quantity: -2,
                              occurredAt: Date(timeIntervalSince1970: 50), shiftID: nil, employeeID: nil, reason: "late")
        )

        let loaded = try await db.fetchInventoryItem(id: item.id)
        #expect(loaded?.quantity == 5)
    }

    @Test func accessControlMatrix() {
        #expect(AccessControl.allows(.financeAndAnalytics, role: .manager))
        #expect(!AccessControl.allows(.financeAndAnalytics, role: .technician))
        #expect(AccessControl.allows(.runTournaments, role: .referee))
        #expect(!AccessControl.allows(.openCloseShift, role: .security))
        #expect(AccessControl.allows(.backupRestoreWipe, role: .manager, managerOverride: false))
        #expect(AccessControl.allows(.backupRestoreWipe, role: .security, managerOverride: true))
    }
}
