import Foundation

struct SeatRepository: Sendable {
    let database: Database

    func fetchAll() async throws -> [GamingSeat] {
        try await database.fetchSeats(zoneID: nil)
    }

    func fetch(zoneID: UUID) async throws -> [GamingSeat] {
        try await database.fetchSeats(zoneID: zoneID)
    }

    func fetch(id: UUID) async throws -> GamingSeat? {
        try await database.fetchSeat(id: id)
    }

    func lowestHealth(limit: Int = 5) async throws -> [GamingSeat] {
        try await database.fetchLowestHealthSeats(limit: limit)
    }

    func upsert(_ seat: GamingSeat) async throws {
        try await database.upsertSeat(seat)
    }

    func upsertMany(_ seats: [GamingSeat]) async throws {
        try await database.upsertSeats(seats)
    }

    func updateState(id: UUID, state: SeatState) async throws {
        try await database.updateSeatState(id: id, state: state)
    }

    func recomputeHealth(id: UUID, now: Date = .now) async throws -> Int {
        try await database.recomputeSeatHealth(id: id, now: now)
    }
}

extension Database {
    private static let seatColumns = """
        SELECT id, zone_id, label, state, cpu, gpu, ram_gb, storage, monitor_model,
               monitor_hz, commissioned_at, last_maintenance_at, maintenance_interval_days,
               health_score, note
        FROM gaming_seat
        """

    func fetchSeats(zoneID: UUID?) throws -> [GamingSeat] {
        if let zoneID {
            return try query(
                "\(Self.seatColumns) WHERE zone_id = ? ORDER BY label;",
                bind: { try $0.bind(zoneID, at: 1) },
                map: Self.mapSeat
            )
        }
        return try query("\(Self.seatColumns) ORDER BY label;", map: Self.mapSeat)
    }

    func fetchSeat(id: UUID) throws -> GamingSeat? {
        try queryOne(
            "\(Self.seatColumns) WHERE id = ?;",
            bind: { try $0.bind(id, at: 1) },
            map: Self.mapSeat
        )
    }

    func fetchLowestHealthSeats(limit: Int) throws -> [GamingSeat] {
        try query(
            "\(Self.seatColumns) ORDER BY health_score ASC, label ASC LIMIT ?;",
            bind: { try $0.bind(limit, at: 1) },
            map: Self.mapSeat
        )
    }

    func upsertSeat(_ seat: GamingSeat) throws {
        try upsertSeats([seat])
    }

    func upsertSeats(_ seats: [GamingSeat]) throws {
        guard !seats.isEmpty else { return }
        try withTransaction {
            try withStatement(
                """
                INSERT INTO gaming_seat (
                    id, zone_id, label, state, cpu, gpu, ram_gb, storage, monitor_model,
                    monitor_hz, commissioned_at, last_maintenance_at, maintenance_interval_days,
                    health_score, note
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    zone_id = excluded.zone_id,
                    label = excluded.label,
                    state = excluded.state,
                    cpu = excluded.cpu,
                    gpu = excluded.gpu,
                    ram_gb = excluded.ram_gb,
                    storage = excluded.storage,
                    monitor_model = excluded.monitor_model,
                    monitor_hz = excluded.monitor_hz,
                    commissioned_at = excluded.commissioned_at,
                    last_maintenance_at = excluded.last_maintenance_at,
                    maintenance_interval_days = excluded.maintenance_interval_days,
                    health_score = excluded.health_score,
                    note = excluded.note;
                """
            ) { statement in
                for seat in seats {
                    try statement.reset()
                    try statement.bind(seat.id, at: 1)
                    try statement.bind(seat.zoneID, at: 2)
                    try statement.bind(seat.label, at: 3)
                    try statement.bind(seat.state.rawValue, at: 4)
                    try statement.bind(seat.cpu, at: 5)
                    try statement.bind(seat.gpu, at: 6)
                    try statement.bind(seat.ramGB, at: 7)
                    try statement.bind(seat.storage, at: 8)
                    try statement.bind(seat.monitorModel, at: 9)
                    try statement.bind(seat.monitorHz, at: 10)
                    try statement.bind(seat.commissionedAt, at: 11)
                    try statement.bindOptional(seat.lastMaintenanceAt, at: 12)
                    try statement.bind(seat.maintenanceIntervalDays, at: 13)
                    try statement.bind(seat.healthScore, at: 14)
                    try statement.bind(seat.note, at: 15)
                    _ = try statement.step()
                }
            }
        }
    }

    func updateSeatState(id: UUID, state: SeatState) throws {
        try run("UPDATE gaming_seat SET state = ? WHERE id = ?;") { statement in
            try statement.bind(state.rawValue, at: 1)
            try statement.bind(id, at: 2)
        }
        _ = try recomputeSeatHealth(id: id, now: .now)
    }

    @discardableResult
    func recomputeSeatHealth(id: UUID, now: Date) throws -> Int {
        guard let seat = try fetchSeat(id: id) else { return 0 }
        let cutoff30 = now.addingTimeInterval(-TimeConstants.thirtyDays)
        let cutoff90 = now.addingTimeInterval(-TimeConstants.ninetyDays)

        let incidents = try scalarInt(
            """
            SELECT COUNT(*) FROM incident
            WHERE seat_id = ? AND kind = ? AND occurred_at >= ?;
            """
        ) { statement in
            try statement.bind(id, at: 1)
            try statement.bind(IncidentKind.hardware.rawValue, at: 2)
            try statement.bind(cutoff30, at: 3)
        }

        let repairs = try scalarInt(
            """
            SELECT COUNT(*) FROM repair_record
            WHERE seat_id = ? AND closed_at IS NOT NULL AND closed_at >= ?;
            """
        ) { statement in
            try statement.bind(id, at: 1)
            try statement.bind(cutoff90, at: 2)
        }

        let equipment = try fetchEquipment(seatID: id)
        let worst = equipment
            .map(\.state)
            .max(by: { Self.equipmentSeverity($0) < Self.equipmentSeverity($1) })

        let score = SeatHealthCalculator.score(
            for: SeatHealthFactors(
                hardwareIncidents30d: incidents,
                closedRepairs90d: repairs,
                seatState: seat.state,
                worstEquipmentState: worst,
                commissionedAt: seat.commissionedAt,
                lastMaintenanceAt: seat.lastMaintenanceAt,
                maintenanceIntervalDays: seat.maintenanceIntervalDays,
                now: now
            )
        )

        try run("UPDATE gaming_seat SET health_score = ? WHERE id = ?;") { statement in
            try statement.bind(score, at: 1)
            try statement.bind(id, at: 2)
        }
        return score
    }

    private static func equipmentSeverity(_ state: EquipmentState) -> Int {
        SeatHealthCalculator.worstEquipmentPenalty(state)
    }

    static func mapSeat(_ statement: Statement) throws -> GamingSeat {
        guard let state = SeatState(rawValue: try statement.string(at: 3)) else {
            throw DatabaseError.stepFailed("Invalid seat state")
        }
        return GamingSeat(
            id: try statement.uuid(at: 0),
            zoneID: try statement.uuid(at: 1),
            label: try statement.string(at: 2),
            state: state,
            cpu: try statement.string(at: 4),
            gpu: try statement.string(at: 5),
            ramGB: statement.int(at: 6),
            storage: try statement.string(at: 7),
            monitorModel: try statement.string(at: 8),
            monitorHz: statement.int(at: 9),
            commissionedAt: statement.date(at: 10),
            lastMaintenanceAt: statement.optionalDate(at: 11),
            maintenanceIntervalDays: statement.int(at: 12),
            healthScore: statement.int(at: 13),
            note: try statement.string(at: 14)
        )
    }
}
