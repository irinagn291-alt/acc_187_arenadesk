import Foundation

struct SeatAssignmentFailure: Hashable, Sendable, Identifiable {
    var matchID: UUID?
    var reason: String
    var id: String { matchID?.uuidString ?? reason }
}

enum TournamentDefaults {
    static let matchDuration = TimeConstants.hour
}

struct TournamentRepository: Sendable {
    let database: Database

    func fetchAll(includeArchived: Bool = false) async throws -> [Tournament] {
        try await database.fetchTournaments(includeArchived: includeArchived)
    }

    func fetch(id: UUID) async throws -> Tournament? {
        try await database.fetchTournament(id: id)
    }

    func fetchMatch(id: UUID) async throws -> Match? {
        try await database.fetchMatch(id: id)
    }

    func upsert(_ tournament: Tournament) async throws {
        try await database.upsertTournament(tournament)
    }

    func participants(tournamentID: UUID) async throws -> [Participant] {
        try await database.fetchParticipants(tournamentID: tournamentID)
    }

    func upsertParticipant(_ participant: Participant) async throws {
        try await database.upsertParticipant(participant)
    }

    func applySeeding(tournamentID: UUID, orderedIDs: [UUID]) async throws {
        try await database.applySeeding(tournamentID: tournamentID, orderedIDs: orderedIDs)
    }

    func matches(tournamentID: UUID) async throws -> [Match] {
        try await database.fetchMatches(tournamentID: tournamentID)
    }

    func generateBracket(tournamentID: UUID) async throws -> BracketGenerationResult {
        try await database.generateBracket(tournamentID: tournamentID)
    }

    func enterResult(
        matchID: UUID,
        scoreA: Int,
        scoreB: Int,
        confirmInvalidateDownstream: Bool
    ) async throws {
        try await database.enterMatchResult(
            matchID: matchID,
            scoreA: scoreA,
            scoreB: scoreB,
            confirmInvalidateDownstream: confirmInvalidateDownstream
        )
    }

    func autoAssignSeats(
        tournamentID: UUID,
        matchDuration: TimeInterval = TournamentDefaults.matchDuration
    ) async throws -> [SeatAssignmentFailure] {
        try await database.autoAssignSeats(tournamentID: tournamentID, matchDuration: matchDuration)
    }

    func standings(tournamentID: UUID) async throws -> [StandingRow] {
        try await database.tournamentStandings(tournamentID: tournamentID)
    }
}

extension Database {
    private static let tournamentColumns = """
        SELECT id, name, discipline, format, status, zone_id, starts_at, ends_at,
               entry_fee_cents, prize_pool_cents, max_participants, best_of,
               swiss_round_count, referee_id, is_archived, rules_document_id
        FROM tournament
        """

    func fetchTournaments(includeArchived: Bool) throws -> [Tournament] {
        let sql = includeArchived
            ? "\(Self.tournamentColumns) ORDER BY starts_at DESC;"
            : "\(Self.tournamentColumns) WHERE is_archived = 0 ORDER BY starts_at DESC;"
        return try query(sql, map: Self.mapTournament)
    }

    func fetchTournament(id: UUID) throws -> Tournament? {
        try queryOne(
            "\(Self.tournamentColumns) WHERE id = ?;",
            bind: { try $0.bind(id, at: 1) },
            map: Self.mapTournament
        )
    }

    func upsertTournament(_ tournament: Tournament) throws {
        try run(
            """
            INSERT INTO tournament (
                id, name, discipline, format, status, zone_id, starts_at, ends_at,
                entry_fee_cents, prize_pool_cents, max_participants, best_of,
                swiss_round_count, referee_id, is_archived, rules_document_id
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                discipline = excluded.discipline,
                format = excluded.format,
                status = excluded.status,
                zone_id = excluded.zone_id,
                starts_at = excluded.starts_at,
                ends_at = excluded.ends_at,
                entry_fee_cents = excluded.entry_fee_cents,
                prize_pool_cents = excluded.prize_pool_cents,
                max_participants = excluded.max_participants,
                best_of = excluded.best_of,
                swiss_round_count = excluded.swiss_round_count,
                referee_id = excluded.referee_id,
                is_archived = excluded.is_archived,
                rules_document_id = excluded.rules_document_id;
            """
        ) { statement in
            try statement.bind(tournament.id, at: 1)
            try statement.bind(tournament.name, at: 2)
            try statement.bind(tournament.discipline, at: 3)
            try statement.bind(tournament.format.rawValue, at: 4)
            try statement.bind(tournament.status.rawValue, at: 5)
            try statement.bindOptional(tournament.zoneID, at: 6)
            try statement.bind(tournament.startsAt, at: 7)
            try statement.bindOptional(tournament.endsAt, at: 8)
            try statement.bindMoney(tournament.entryFee, at: 9)
            try statement.bindMoney(tournament.prizePool, at: 10)
            try statement.bind(tournament.maxParticipants, at: 11)
            try statement.bind(tournament.bestOf, at: 12)
            try statement.bindOptional(tournament.swissRoundCount, at: 13)
            try statement.bindOptional(tournament.refereeID, at: 14)
            try statement.bind(tournament.isArchived, at: 15)
            try statement.bindOptional(tournament.rulesDocumentID, at: 16)
        }
    }

    private static let participantColumns = """
        SELECT id, tournament_id, display_name, team_name, contact, seed_index,
               registered_at, is_checked_in, is_disqualified, placement
        FROM participant
        """

    func fetchParticipants(tournamentID: UUID) throws -> [Participant] {
        try query(
            "\(Self.participantColumns) WHERE tournament_id = ? ORDER BY seed_index, registered_at;",
            bind: { try $0.bind(tournamentID, at: 1) },
            map: Self.mapParticipant
        )
    }

    func fetchAllParticipants() throws -> [Participant] {
        try query("\(Self.participantColumns) ORDER BY tournament_id, seed_index;", map: Self.mapParticipant)
    }

    func upsertParticipant(_ participant: Participant) throws {
        try run(
            """
            INSERT INTO participant (
                id, tournament_id, display_name, team_name, contact, seed_index,
                registered_at, is_checked_in, is_disqualified, placement
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                display_name = excluded.display_name,
                team_name = excluded.team_name,
                contact = excluded.contact,
                seed_index = excluded.seed_index,
                registered_at = excluded.registered_at,
                is_checked_in = excluded.is_checked_in,
                is_disqualified = excluded.is_disqualified,
                placement = excluded.placement;
            """
        ) { statement in
            try statement.bind(participant.id, at: 1)
            try statement.bind(participant.tournamentID, at: 2)
            try statement.bind(participant.displayName, at: 3)
            try statement.bind(participant.teamName, at: 4)
            try statement.bind(participant.contact, at: 5)
            try statement.bind(participant.seedIndex, at: 6)
            try statement.bind(participant.registeredAt, at: 7)
            try statement.bind(participant.isCheckedIn, at: 8)
            try statement.bind(participant.isDisqualified, at: 9)
            try statement.bindOptional(participant.placement, at: 10)
        }
    }

    func applySeeding(tournamentID: UUID, orderedIDs: [UUID]) throws {
        try withTransaction {
            try withStatement(
                "UPDATE participant SET seed_index = ? WHERE id = ? AND tournament_id = ?;"
            ) { statement in
                for (index, id) in orderedIDs.enumerated() {
                    try statement.reset()
                    try statement.bind(index + 1, at: 1)
                    try statement.bind(id, at: 2)
                    try statement.bind(tournamentID, at: 3)
                    _ = try statement.step()
                }
            }
        }
    }

    private static let matchColumns = """
        SELECT id, tournament_id, round_index, slot_index, participant_a_id, participant_b_id,
               score_a, score_b, winner_id, is_bye, scheduled_at, seat_a_id, seat_b_id, status, note
        FROM match
        """

    func fetchMatches(tournamentID: UUID) throws -> [Match] {
        try query(
            "\(Self.matchColumns) WHERE tournament_id = ? ORDER BY round_index, slot_index;",
            bind: { try $0.bind(tournamentID, at: 1) },
            map: Self.mapMatch
        )
    }

    func fetchAllMatches() throws -> [Match] {
        try query(
            "\(Self.matchColumns) ORDER BY tournament_id, round_index, slot_index;",
            map: Self.mapMatch
        )
    }

    func upsertMatch(_ match: Match) throws {
        try run(
            """
            INSERT INTO match (
                id, tournament_id, round_index, slot_index, participant_a_id, participant_b_id,
                score_a, score_b, winner_id, is_bye, scheduled_at, seat_a_id, seat_b_id, status, note
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                participant_a_id = excluded.participant_a_id,
                participant_b_id = excluded.participant_b_id,
                score_a = excluded.score_a,
                score_b = excluded.score_b,
                winner_id = excluded.winner_id,
                is_bye = excluded.is_bye,
                scheduled_at = excluded.scheduled_at,
                seat_a_id = excluded.seat_a_id,
                seat_b_id = excluded.seat_b_id,
                status = excluded.status,
                note = excluded.note;
            """
        ) { statement in
            try statement.bind(match.id, at: 1)
            try statement.bind(match.tournamentID, at: 2)
            try statement.bind(match.roundIndex, at: 3)
            try statement.bind(match.slotIndex, at: 4)
            try statement.bindOptional(match.participantAID, at: 5)
            try statement.bindOptional(match.participantBID, at: 6)
            try statement.bind(match.scoreA, at: 7)
            try statement.bind(match.scoreB, at: 8)
            try statement.bindOptional(match.winnerID, at: 9)
            try statement.bind(match.isBye, at: 10)
            try statement.bindOptional(match.scheduledAt, at: 11)
            try statement.bindOptional(match.seatAID, at: 12)
            try statement.bindOptional(match.seatBID, at: 13)
            try statement.bind(match.status.rawValue, at: 14)
            try statement.bind(match.note, at: 15)
        }
    }

    func generateBracket(tournamentID: UUID) throws -> BracketGenerationResult {
        guard let tournament = try fetchTournament(id: tournamentID) else {
            throw DatabaseError.stepFailed("Tournament missing")
        }
        var participants = try fetchParticipants(tournamentID: tournamentID)
            .filter { $0.isCheckedIn && !$0.isDisqualified }
        if participants.allSatisfy({ $0.seedIndex == 0 }) {
            participants.sort { $0.registeredAt < $1.registeredAt }
            for (index, var p) in participants.enumerated() {
                p.seedIndex = index + 1
                try upsertParticipant(p)
                participants[index] = p
            }
        } else {
            participants.sort { $0.seedIndex < $1.seedIndex }
        }
        guard participants.count >= 2 else {
            throw DatabaseError.stepFailed("Need at least 2 checked-in participants")
        }

        let generated: BracketGenerationResult
        switch tournament.format {
        case .singleElimination:
            generated = try SingleEliminationBracket.generate(
                tournamentID: tournamentID,
                participants: participants
            )
        case .roundRobin:
            generated = try RoundRobinBracket.generate(
                tournamentID: tournamentID,
                participants: participants
            )
        case .swiss:
            let scores = Dictionary(uniqueKeysWithValues: participants.map { ($0.id, 0) })
            let first = SwissBracket.pairRound(
                tournamentID: tournamentID,
                roundIndex: 0,
                playerIDs: participants.map(\.id),
                scores: scores,
                priorPairs: [],
                priorByeCounts: [:]
            )
            generated = BracketGenerationResult(
                matches: first,
                bracketSize: participants.count,
                byeCount: first.filter(\.isBye).count,
                roundCount: tournament.swissRoundCount ?? SwissBracket.defaultRoundCount(n: participants.count)
            )
        }

        try withTransaction {
            try run(
                """
                UPDATE seat_session SET match_id = NULL
                WHERE match_id IN (SELECT id FROM match WHERE tournament_id = ?);
                """
            ) { try $0.bind(tournamentID, at: 1) }
            try run("DELETE FROM match WHERE tournament_id = ?;") { try $0.bind(tournamentID, at: 1) }
            for match in generated.matches {
                try upsertMatch(match)
            }
            var updated = tournament
            updated.status = .running
            try upsertTournament(updated)
        }
        return generated
    }

    func enterMatchResult(
        matchID: UUID,
        scoreA: Int,
        scoreB: Int,
        confirmInvalidateDownstream: Bool
    ) throws {
        guard var match = try fetchMatch(id: matchID),
              let tournament = try fetchTournament(id: match.tournamentID) else {
            throw DatabaseError.stepFailed("Match missing")
        }
        let needed = tournament.bestOf / 2 + 1
        let wasFinished = match.status == .finished

        guard scoreA >= 0, scoreB >= 0,
              scoreA <= tournament.bestOf, scoreB <= tournament.bestOf else {
            throw DatabaseError.invalidScore(
                "Scores must be between 0 and \(tournament.bestOf)."
            )
        }

        let isDraw = scoreA == scoreB && scoreA < needed
        if isDraw && tournament.format != .roundRobin {
            throw DatabaseError.invalidScore("This format needs a decided winner.")
        }

        if wasFinished && tournament.format == .singleElimination && !confirmInvalidateDownstream {
            throw DatabaseError.needsDownstreamConfirmation
        }

        try withTransaction {
            match.scoreA = scoreA
            match.scoreB = scoreB
            if scoreA >= needed {
                match.winnerID = match.participantAID
                match.status = .finished
            } else if scoreB >= needed {
                match.winnerID = match.participantBID
                match.status = .finished
            } else if isDraw {
                match.winnerID = nil
                match.status = .finished
            } else {
                throw DatabaseError.invalidScore("Scores do not decide a winner yet.")
            }
            try upsertMatch(match)

            guard tournament.format == .singleElimination else { return }

            var all = try fetchMatches(tournamentID: tournament.id)
            if wasFinished {
                Self.clearDownstreamPath(of: match, in: &all)
            }
            Self.replayAdvancement(from: match.roundIndex, in: &all)

            for updated in all where updated.roundIndex > match.roundIndex {
                try upsertMatch(updated)
            }
        }
    }

    static func clearDownstreamPath(of match: Match, in matches: inout [Match]) {
        let maxRound = matches.map(\.roundIndex).max() ?? match.roundIndex
        guard maxRound > match.roundIndex else { return }

        for round in (match.roundIndex + 1)...maxRound {
            let slot = match.slotIndex >> (round - match.roundIndex)
            guard let index = matches.firstIndex(
                where: { $0.roundIndex == round && $0.slotIndex == slot }
            ) else { continue }
            matches[index].participantAID = nil
            matches[index].participantBID = nil
            matches[index].winnerID = nil
            matches[index].scoreA = 0
            matches[index].scoreB = 0
            matches[index].status = .pending
            matches[index].seatAID = nil
            matches[index].seatBID = nil
        }
    }

    static func replayAdvancement(from startRound: Int, in matches: inout [Match]) {
        let maxRound = matches.map(\.roundIndex).max() ?? startRound
        guard maxRound > startRound else { return }

        for round in startRound...(maxRound - 1) {
            let decided = matches.filter {
                $0.roundIndex == round
                    && ($0.status == .finished || $0.status == .walkover)
                    && $0.winnerID != nil
            }
            for source in decided {
                guard let winner = source.winnerID else { continue }
                SingleEliminationBracket.placeWinner(winner, from: source, into: &matches)
            }
        }
    }

    func fetchMatch(id: UUID) throws -> Match? {
        try queryOne(
            "\(Self.matchColumns) WHERE id = ?;",
            bind: { try $0.bind(id, at: 1) },
            map: Self.mapMatch
        )
    }

    func autoAssignSeats(tournamentID: UUID, matchDuration: TimeInterval) throws -> [SeatAssignmentFailure] {
        guard let tournament = try fetchTournament(id: tournamentID) else {
            return [SeatAssignmentFailure(matchID: nil, reason: "Tournament not found")]
        }
        guard let zoneID = tournament.zoneID else {
            return [SeatAssignmentFailure(matchID: nil, reason: "Tournament has no zone")]
        }
        var matches = try fetchMatches(tournamentID: tournamentID)
            .filter {
                !$0.isBye
                    && $0.status != .finished
                    && $0.status != .walkover
                    && $0.participantAID != nil
                    && $0.participantBID != nil
            }
        matches.sort {
            let ls = $0.scheduledAt ?? .distantFuture
            let rs = $1.scheduledAt ?? .distantFuture
            if ls != rs { return ls < rs }
            if $0.roundIndex != $1.roundIndex { return $0.roundIndex < $1.roundIndex }
            return $0.slotIndex < $1.slotIndex
        }

        var failures: [SeatAssignmentFailure] = []
        var reserved: [UUID: [(Date, Date)]] = [:]

        try withTransaction {
            let candidates = try fetchSeats(zoneID: zoneID)
                .filter { $0.state == .ready && $0.healthScore >= SeatHealthCalculator.healthyThreshold }
                .sorted { $0.healthScore > $1.healthScore }

            for var match in matches {
                let start = match.scheduledAt ?? tournament.startsAt
                let end = start.addingTimeInterval(matchDuration)

                var chosen: [GamingSeat] = []
                for seat in candidates {
                    if chosen.count == 2 { break }
                    let busy = try hasOverlappingSession(seatID: seat.id, start: start, end: end)
                        || (reserved[seat.id] ?? []).contains(where: { $0.0 < end && start < $0.1 })
                    if busy { continue }
                    chosen.append(seat)
                }
                guard chosen.count == 2 else {
                    failures.append(
                        SeatAssignmentFailure(matchID: match.id, reason: "Not enough assignable seats")
                    )
                    continue
                }
                match.seatAID = chosen[0].id
                match.seatBID = chosen[1].id
                try upsertMatch(match)
                for seat in chosen {
                    reserved[seat.id, default: []].append((start, end))
                    try startSeatSession(
                        seatID: seat.id,
                        shiftID: nil,
                        purpose: .tournament,
                        note: "match:\(match.id.uuidString.lowercased())",
                        at: start,
                        matchID: match.id
                    )
                }
            }
        }
        return failures
    }

    func hasOverlappingSession(seatID: UUID, start: Date, end: Date) throws -> Bool {
        try scalarInt(
            """
            SELECT COUNT(*) FROM seat_session
            WHERE seat_id = ?
              AND started_at < ?
              AND (ended_at IS NULL OR ended_at > ?);
            """
        ) { statement in
            try statement.bind(seatID, at: 1)
            try statement.bind(end, at: 2)
            try statement.bind(start, at: 3)
        } > 0
    }

    func tournamentStandings(tournamentID: UUID) throws -> [StandingRow] {
        guard let tournament = try fetchTournament(id: tournamentID) else { return [] }
        let participants = try fetchParticipants(tournamentID: tournamentID)
        let matches = try fetchMatches(tournamentID: tournamentID)
        switch tournament.format {
        case .roundRobin, .singleElimination:
            return StandingsCalculator.roundRobin(
                participants: participants,
                matches: matches,
                bestOf: tournament.bestOf
            )
        case .swiss:
            return SwissBracket.swissStandings(participants: participants, matches: matches)
        }
    }

    static func mapTournament(_ statement: Statement) throws -> Tournament {
        guard let format = MatchFormat(rawValue: try statement.string(at: 3)),
              let status = TournamentStatus(rawValue: try statement.string(at: 4)) else {
            throw DatabaseError.stepFailed("Invalid tournament")
        }
        return Tournament(
            id: try statement.uuid(at: 0),
            name: try statement.string(at: 1),
            discipline: try statement.string(at: 2),
            format: format,
            status: status,
            zoneID: try statement.optionalUUID(at: 5),
            startsAt: statement.date(at: 6),
            endsAt: statement.optionalDate(at: 7),
            entryFee: statement.money(at: 8),
            prizePool: statement.money(at: 9),
            maxParticipants: statement.int(at: 10),
            bestOf: statement.int(at: 11),
            swissRoundCount: statement.optionalInt(at: 12),
            refereeID: try statement.optionalUUID(at: 13),
            isArchived: statement.bool(at: 14),
            rulesDocumentID: try statement.optionalUUID(at: 15)
        )
    }

    static func mapParticipant(_ statement: Statement) throws -> Participant {
        Participant(
            id: try statement.uuid(at: 0),
            tournamentID: try statement.uuid(at: 1),
            displayName: try statement.string(at: 2),
            teamName: try statement.string(at: 3),
            contact: try statement.string(at: 4),
            seedIndex: statement.int(at: 5),
            registeredAt: statement.date(at: 6),
            isCheckedIn: statement.bool(at: 7),
            isDisqualified: statement.bool(at: 8),
            placement: statement.optionalInt(at: 9)
        )
    }

    static func mapMatch(_ statement: Statement) throws -> Match {
        guard let status = MatchStatus(rawValue: try statement.string(at: 13)) else {
            throw DatabaseError.stepFailed("Invalid match status")
        }
        return Match(
            id: try statement.uuid(at: 0),
            tournamentID: try statement.uuid(at: 1),
            roundIndex: statement.int(at: 2),
            slotIndex: statement.int(at: 3),
            participantAID: try statement.optionalUUID(at: 4),
            participantBID: try statement.optionalUUID(at: 5),
            scoreA: statement.int(at: 6),
            scoreB: statement.int(at: 7),
            winnerID: try statement.optionalUUID(at: 8),
            isBye: statement.bool(at: 9),
            scheduledAt: statement.optionalDate(at: 10),
            seatAID: try statement.optionalUUID(at: 11),
            seatBID: try statement.optionalUUID(at: 12),
            status: status,
            note: try statement.string(at: 14)
        )
    }
}
