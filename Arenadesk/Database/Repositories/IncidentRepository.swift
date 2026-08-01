import Foundation

struct IncidentRepository: Sendable {
    let database: Database

    func fetchAll(includeArchived: Bool = false) async throws -> [Incident] {
        try await database.fetchIncidents(includeArchived: includeArchived)
    }

    func fetch(id: UUID) async throws -> Incident? {
        try await database.fetchIncident(id: id)
    }

    func upsert(_ incident: Incident) async throws {
        try await database.upsertIncident(incident)
        if let seatID = incident.seatID {
            _ = try await database.recomputeSeatHealth(id: seatID, now: .now)
        }
    }

    func archive(id: UUID) async throws {
        try await database.archiveIncident(id: id)
    }
}

extension Database {
    private static let incidentColumns = """
        SELECT id, shift_id, zone_id, seat_id, severity, kind, occurred_at,
               reported_by_id, summary, resolution, is_resolved, is_archived
        FROM incident
        """

    func fetchIncidents(includeArchived: Bool) throws -> [Incident] {
        let sql = includeArchived
            ? "\(Self.incidentColumns) ORDER BY occurred_at DESC;"
            : "\(Self.incidentColumns) WHERE is_archived = 0 ORDER BY occurred_at DESC;"
        return try query(sql, map: Self.mapIncident)
    }

    func fetchIncident(id: UUID) throws -> Incident? {
        try queryOne(
            "\(Self.incidentColumns) WHERE id = ?;",
            bind: { try $0.bind(id, at: 1) },
            map: Self.mapIncident
        )
    }

    func upsertIncident(_ incident: Incident) throws {
        try run(
            """
            INSERT INTO incident (
                id, shift_id, zone_id, seat_id, severity, kind, occurred_at,
                reported_by_id, summary, resolution, is_resolved, is_archived
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                shift_id = excluded.shift_id,
                zone_id = excluded.zone_id,
                seat_id = excluded.seat_id,
                severity = excluded.severity,
                kind = excluded.kind,
                occurred_at = excluded.occurred_at,
                reported_by_id = excluded.reported_by_id,
                summary = excluded.summary,
                resolution = excluded.resolution,
                is_resolved = excluded.is_resolved,
                is_archived = excluded.is_archived;
            """
        ) { statement in
            try statement.bind(incident.id, at: 1)
            try statement.bindOptional(incident.shiftID, at: 2)
            try statement.bindOptional(incident.zoneID, at: 3)
            try statement.bindOptional(incident.seatID, at: 4)
            try statement.bind(incident.severity.rawValue, at: 5)
            try statement.bind(incident.kind.rawValue, at: 6)
            try statement.bind(incident.occurredAt, at: 7)
            try statement.bindOptional(incident.reportedByID, at: 8)
            try statement.bind(incident.summary, at: 9)
            try statement.bind(incident.resolution, at: 10)
            try statement.bind(incident.isResolved, at: 11)
            try statement.bind(incident.isArchived, at: 12)
        }
    }

    func archiveIncident(id: UUID) throws {
        try run("UPDATE incident SET is_archived = 1 WHERE id = ?;") { try $0.bind(id, at: 1) }
    }

    static func mapIncident(_ statement: Statement) throws -> Incident {
        guard let severity = IncidentSeverity(rawValue: try statement.string(at: 4)),
              let kind = IncidentKind(rawValue: try statement.string(at: 5)) else {
            throw DatabaseError.stepFailed("Invalid incident")
        }
        return Incident(
            id: try statement.uuid(at: 0),
            shiftID: try statement.optionalUUID(at: 1),
            zoneID: try statement.optionalUUID(at: 2),
            seatID: try statement.optionalUUID(at: 3),
            severity: severity,
            kind: kind,
            occurredAt: statement.date(at: 6),
            reportedByID: try statement.optionalUUID(at: 7),
            summary: try statement.string(at: 8),
            resolution: try statement.string(at: 9),
            isResolved: statement.bool(at: 10),
            isArchived: statement.bool(at: 11)
        )
    }
}
