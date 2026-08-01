import Foundation

struct SeatSessionRepository: Sendable {
    let database: Database

    func fetch(seatID: UUID, limit: Int = 50) async throws -> [SeatSession] {
        try await database.fetchSeatSessions(seatID: seatID, limit: limit)
    }

    func openSessions(seatID: UUID) async throws -> [SeatSession] {
        try await database.fetchOpenSeatSessions(seatID: seatID)
    }

    func start(
        seatID: UUID,
        shiftID: UUID?,
        purpose: SessionPurpose,
        note: String = "",
        at date: Date = .now
    ) async throws -> SeatSession {
        try await database.startSeatSession(
            seatID: seatID,
            shiftID: shiftID,
            purpose: purpose,
            note: note,
            at: date
        )
    }

    func end(id: UUID, at date: Date = .now) async throws {
        try await database.endSeatSession(id: id, at: date)
    }
}

extension Database {
    private static let seatSessionColumns = """
        SELECT id, seat_id, shift_id, started_at, ended_at, purpose, match_id, note
        FROM seat_session
        """

    func fetchSeatSessions(seatID: UUID, limit: Int) throws -> [SeatSession] {
        try query(
            "\(Self.seatSessionColumns) WHERE seat_id = ? ORDER BY started_at DESC LIMIT ?;",
            bind: { statement in
                try statement.bind(seatID, at: 1)
                try statement.bind(limit, at: 2)
            },
            map: Self.mapSeatSession
        )
    }

    func fetchOpenSeatSessions(seatID: UUID) throws -> [SeatSession] {
        try query(
            "\(Self.seatSessionColumns) WHERE seat_id = ? AND ended_at IS NULL ORDER BY started_at DESC;",
            bind: { try $0.bind(seatID, at: 1) },
            map: Self.mapSeatSession
        )
    }

    func fetchAllSeatSessions() throws -> [SeatSession] {
        try query("\(Self.seatSessionColumns) ORDER BY started_at;", map: Self.mapSeatSession)
    }

    func fetchOpenSeatSessions() throws -> [SeatSession] {
        try query(
            "\(Self.seatSessionColumns) WHERE ended_at IS NULL ORDER BY started_at;",
            map: Self.mapSeatSession
        )
    }

    @discardableResult
    func startSeatSession(
        seatID: UUID,
        shiftID: UUID?,
        purpose: SessionPurpose,
        note: String,
        at date: Date,
        matchID: UUID? = nil
    ) throws -> SeatSession {
        let session = SeatSession(
            id: UUID(),
            seatID: seatID,
            shiftID: shiftID,
            startedAt: date,
            endedAt: nil,
            purpose: purpose,
            matchID: matchID,
            note: note
        )
        try withTransaction {
            try insertSeatSession(session)
            if purpose != .maintenance {
                try run("UPDATE gaming_seat SET state = ? WHERE id = ?;") { statement in
                    try statement.bind(SeatState.occupied.rawValue, at: 1)
                    try statement.bind(seatID, at: 2)
                }
            }
        }
        _ = try recomputeSeatHealth(id: seatID, now: date)
        return session
    }

    func insertSeatSession(_ session: SeatSession) throws {
        try run(
            """
            INSERT OR REPLACE INTO seat_session (
                id, seat_id, shift_id, started_at, ended_at, purpose, match_id, note
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """
        ) { statement in
            try statement.bind(session.id, at: 1)
            try statement.bind(session.seatID, at: 2)
            try statement.bindOptional(session.shiftID, at: 3)
            try statement.bind(session.startedAt, at: 4)
            try statement.bindOptional(session.endedAt, at: 5)
            try statement.bind(session.purpose.rawValue, at: 6)
            try statement.bindOptional(session.matchID, at: 7)
            try statement.bind(session.note, at: 8)
        }
    }

    func endSeatSession(id: UUID, at date: Date) throws {
        guard let existing = try fetchSeatSession(id: id) else { return }
        try withTransaction {
            try run("UPDATE seat_session SET ended_at = ? WHERE id = ?;") { statement in
                try statement.bind(date, at: 1)
                try statement.bind(id, at: 2)
            }

            if try fetchOpenSeatSessions(seatID: existing.seatID).isEmpty {
                try run("UPDATE gaming_seat SET state = ? WHERE id = ? AND state = ?;") { statement in
                    try statement.bind(SeatState.ready.rawValue, at: 1)
                    try statement.bind(existing.seatID, at: 2)
                    try statement.bind(SeatState.occupied.rawValue, at: 3)
                }
            }
        }
        _ = try recomputeSeatHealth(id: existing.seatID, now: date)
    }

    func fetchSeatSession(id: UUID) throws -> SeatSession? {
        try queryOne(
            "\(Self.seatSessionColumns) WHERE id = ?;",
            bind: { try $0.bind(id, at: 1) },
            map: Self.mapSeatSession
        )
    }

    static func mapSeatSession(_ statement: Statement) throws -> SeatSession {
        guard let purpose = SessionPurpose(rawValue: try statement.string(at: 5)) else {
            throw DatabaseError.stepFailed("Invalid session purpose")
        }
        return SeatSession(
            id: try statement.uuid(at: 0),
            seatID: try statement.uuid(at: 1),
            shiftID: try statement.optionalUUID(at: 2),
            startedAt: statement.date(at: 3),
            endedAt: statement.optionalDate(at: 4),
            purpose: purpose,
            matchID: try statement.optionalUUID(at: 6),
            note: try statement.string(at: 7)
        )
    }
}
