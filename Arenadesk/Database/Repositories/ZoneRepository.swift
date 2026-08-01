import Foundation

struct ZoneSummary: Identifiable, Hashable, Sendable {
    var zone: Zone
    var totalSeats: Int
    var readySeats: Int
    var occupiedSeats: Int

    var id: UUID { zone.id }

    var readiness: Double? {
        ZoneMetrics.readiness(readySeats: readySeats, totalSeats: totalSeats)
    }

    var occupancy: Double? {
        ZoneMetrics.occupancy(occupiedSeats: occupiedSeats, totalSeats: totalSeats)
    }
}

struct ZoneRepository: Sendable {
    let database: Database

    func fetchAll() async throws -> [Zone] {
        try await database.fetchZones()
    }

    func fetchSummaries() async throws -> [ZoneSummary] {
        try await database.fetchZoneSummaries()
    }

    func fetch(id: UUID) async throws -> Zone? {
        try await database.fetchZone(id: id)
    }

    func upsert(_ zone: Zone) async throws {
        try await database.upsertZone(zone)
    }

    func delete(id: UUID) async throws {
        try await database.deleteZone(id: id)
    }
}

extension Database {
    func fetchZones() throws -> [Zone] {
        try query(
            "SELECT id, name, kind, capacity, sort_index, note FROM zone ORDER BY sort_index, name;",
            map: Self.mapZone
        )
    }

    func fetchZone(id: UUID) throws -> Zone? {
        try queryOne(
            "SELECT id, name, kind, capacity, sort_index, note FROM zone WHERE id = ?;",
            bind: { try $0.bind(id, at: 1) },
            map: Self.mapZone
        )
    }

    func fetchZoneSummaries() throws -> [ZoneSummary] {
        let zones = try fetchZones()
        let seatsByZone = Dictionary(grouping: try fetchSeats(zoneID: nil), by: \.zoneID)
        return zones.map { zone in
            let seats = seatsByZone[zone.id] ?? []
            return ZoneSummary(
                zone: zone,
                totalSeats: seats.count,
                readySeats: seats.filter { $0.state == .ready }.count,
                occupiedSeats: seats.filter { $0.state == .occupied }.count
            )
        }
    }

    func upsertZone(_ zone: Zone) throws {
        try run(
            """
            INSERT INTO zone (id, name, kind, capacity, sort_index, note)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                kind = excluded.kind,
                capacity = excluded.capacity,
                sort_index = excluded.sort_index,
                note = excluded.note;
            """
        ) { statement in
            try statement.bind(zone.id, at: 1)
            try statement.bind(zone.name, at: 2)
            try statement.bind(zone.kind.rawValue, at: 3)
            try statement.bind(zone.capacity, at: 4)
            try statement.bind(zone.sortIndex, at: 5)
            try statement.bind(zone.note, at: 6)
        }
    }

    func deleteZone(id: UUID) throws {
        try run("DELETE FROM zone WHERE id = ?;") { try $0.bind(id, at: 1) }
    }

    static func mapZone(_ statement: Statement) throws -> Zone {
        guard let kind = ZoneKind(rawValue: try statement.string(at: 2)) else {
            throw DatabaseError.stepFailed("Invalid zone kind")
        }
        return Zone(
            id: try statement.uuid(at: 0),
            name: try statement.string(at: 1),
            kind: kind,
            capacity: statement.int(at: 3),
            sortIndex: statement.int(at: 4),
            note: try statement.string(at: 5)
        )
    }
}
