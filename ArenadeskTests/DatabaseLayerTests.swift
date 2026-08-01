import Foundation
import Testing
@testable import Arenadesk

struct DatabaseLayerTests {
    @Test func migrationEmptyToCurrent() async throws {
        let db = try Database(inMemory: true)
        #expect(try await db.userVersion() == 0)
        try await Migrator.migrate(db)
        #expect(try await db.userVersion() == Migrator.currentVersion)
        let count = try await db.withStatement("SELECT COUNT(*) FROM schema_migrations;") { statement in
            _ = try statement.step()
            return statement.int(at: 0)
        }
        #expect(count == Migrator.currentVersion)
    }

    @Test func refusesFutureUserVersion() async throws {
        let db = try Database(inMemory: true)
        try await db.setUserVersion(Migrator.currentVersion + 5)
        await #expect(throws: DatabaseError.self) {
            try await Migrator.migrate(db)
        }
    }

    @Test func foreignKeyEnforcement() async throws {
        let db = try Database(inMemory: true)
        try await Migrator.migrate(db)
        await #expect(throws: DatabaseError.self) {
            try await db.insertOrphanSeatForTests()
        }
    }

    @Test func rollbackOnFailedMultiRowTransaction() async throws {
        let db = try Database(inMemory: true)
        try await Migrator.migrate(db)

        let zoneID = UUID()
        try await db.upsertZone(
            Zone(id: zoneID, name: "Z", kind: .standard, capacity: 2, sortIndex: 0, note: "")
        )

        do {
            try await db.insertSeatThenFailForTests(zoneID: zoneID)
        } catch {
        }

        let count = try await db.withStatement("SELECT COUNT(*) FROM gaming_seat;") { statement in
            _ = try statement.step()
            return statement.int(at: 0)
        }
        #expect(count == 0)
    }

    @Test func moneyRoundTripThroughVenueTable() async throws {
        let db = try Database(inMemory: true)
        try await Migrator.migrate(db)
        let rate = try #require(Decimal(string: "12.34"))
        let venue = Venue(
            id: UUID(),
            name: "Arena",
            address: "1 Main",
            phone: "555",
            openingTime: DateComponents(hour: 10, minute: 0),
            closingTime: DateComponents(hour: 22, minute: 0),
            currencyCode: "USD",
            seatHourlyRate: rate
        )
        try await db.upsertVenue(venue)
        let loaded = try #require(try await db.fetchVenue())
        #expect(loaded.seatHourlyRate == rate)
        #expect(try Money.minorUnits(from: loaded.seatHourlyRate) == 1234)
    }

    @Test func nestedTransactionCommitsBothLevels() async throws {
        let db = try Database(inMemory: true)
        try await Migrator.migrate(db)
        let zoneID = UUID()

        try await db.nestedZoneInsertForTests(outer: zoneID, inner: UUID())

        #expect(try await db.fetchZones().count == 2)
    }

    @Test func nestedTransactionInnerFailureRollsBackOnlyToTheSavepoint() async throws {
        let db = try Database(inMemory: true)
        try await Migrator.migrate(db)

        try await db.nestedZoneInsertRecoveringFromInnerFailureForTests()

        let zones = try await db.fetchZones()
        #expect(zones.count == 1)
        #expect(zones.first?.name == "outer")
    }

    @Test func nestedTransactionOuterFailureRollsBackEverything() async throws {
        let db = try Database(inMemory: true)
        try await Migrator.migrate(db)

        await #expect(throws: DatabaseError.self) {
            try await db.nestedZoneInsertFailingOuterForTests()
        }

        #expect(try await db.fetchZones().isEmpty)
    }

    @Test func setUserVersionRejectsAnOutOfRangeValue() async throws {
        let db = try Database(inMemory: true)
        await #expect(throws: DatabaseError.self) {
            try await db.setUserVersion(-1)
        }
    }
}

extension Database {
    func insertOrphanSeatForTests() throws {
        try withStatement(
            """
            INSERT INTO gaming_seat (
                id, zone_id, label, state, cpu, gpu, ram_gb, storage, monitor_model,
                monitor_hz, commissioned_at, last_maintenance_at, maintenance_interval_days,
                health_score, note
            ) VALUES (?, ?, 'A-01', 'ready', 'cpu', 'gpu', 16, '1TB', 'mon', 144, 0, NULL, 30, 100, '');
            """
        ) { statement in
            try statement.bind(UUID(), at: 1)
            try statement.bind(UUID(), at: 2)
            _ = try statement.step()
        }
    }

    func insertSeatThenFailForTests(zoneID: UUID) throws {
        try withTransaction {
            try withStatement(
                """
                INSERT INTO gaming_seat (
                    id, zone_id, label, state, cpu, gpu, ram_gb, storage, monitor_model,
                    monitor_hz, commissioned_at, last_maintenance_at, maintenance_interval_days,
                    health_score, note
                ) VALUES (?, ?, 'A-01', 'ready', 'c', 'g', 16, '1TB', 'm', 144, 0, NULL, 30, 100, '');
                """
            ) { statement in
                try statement.bind(UUID(), at: 1)
                try statement.bind(zoneID, at: 2)
                _ = try statement.step()
            }
            throw DatabaseError.stepFailed("forced failure")
        }
    }

    private func zone(_ name: String, id: UUID) -> Zone {
        Zone(id: id, name: name, kind: .standard, capacity: 1, sortIndex: 0, note: "")
    }

    func nestedZoneInsertForTests(outer: UUID, inner: UUID) throws {
        try withTransaction {
            try upsertZone(zone("outer", id: outer))
            try withTransaction {
                try upsertZone(zone("inner", id: inner))
            }
        }
    }

    func nestedZoneInsertRecoveringFromInnerFailureForTests() throws {
        try withTransaction {
            try upsertZone(zone("outer", id: UUID()))
            do {
                try withTransaction {
                    try upsertZone(zone("inner", id: UUID()))
                    throw DatabaseError.stepFailed("inner failure")
                }
            } catch {
            }
        }
    }

    func nestedZoneInsertFailingOuterForTests() throws {
        try withTransaction {
            try upsertZone(zone("outer", id: UUID()))
            try withTransaction {
                try upsertZone(zone("inner", id: UUID()))
            }
            throw DatabaseError.stepFailed("outer failure")
        }
    }
}
