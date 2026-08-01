import Foundation

enum RoundRobinBracket {
    static func generate(
        tournamentID: UUID,
        participants: [Participant]
    ) throws -> BracketGenerationResult {
        let players = participants
            .filter { $0.isCheckedIn && !$0.isDisqualified }
            .sorted { $0.seedIndex < $1.seedIndex }
        let n = players.count
        guard n >= 2 else {
            throw DatabaseError.invalidBracket("Need at least 2 participants")
        }

        var entries: [UUID?] = players.map(\.id)
        let odd = n % 2 == 1
        if odd { entries.append(nil) }
        let m = entries.count
        let rounds = m - 1
        var matches: [Match] = []

        var circle = Array(entries.dropFirst())
        for round in 0..<rounds {
            let row: [UUID?] = [entries[0]] + circle
            for i in 0..<(m / 2) {
                let a = row[i]
                let b = row[m - 1 - i]
                let isBye = a == nil || b == nil
                matches.append(
                    Match(
                        id: UUID(),
                        tournamentID: tournamentID,
                        roundIndex: round,
                        slotIndex: i,
                        participantAID: a,
                        participantBID: b,
                        scoreA: 0,
                        scoreB: 0,
                        winnerID: isBye ? (a ?? b) : nil,
                        isBye: isBye,
                        scheduledAt: nil,
                        seatAID: nil,
                        seatBID: nil,
                        status: isBye ? .walkover : .pending,
                        note: ""
                    )
                )
            }
            if let last = circle.popLast() {
                circle.insert(last, at: 0)
            }
        }

        return BracketGenerationResult(
            matches: matches,
            bracketSize: m,
            byeCount: odd ? rounds : 0,
            roundCount: rounds
        )
    }

    static func pairCount(n: Int) -> Int {
        n * (n - 1) / 2
    }
}

struct StandingRow: Hashable, Sendable, Identifiable {
    var participantID: UUID
    var displayName: String
    var seedIndex: Int
    var played: Int
    var wins: Int
    var draws: Int
    var losses: Int
    var points: Int
    var scoreFor: Int
    var scoreAgainst: Int
    var buchholz: Int
    var medianBuchholz: Int

    var id: UUID { participantID }
    var mapDifference: Int { scoreFor - scoreAgainst }
}

enum StandingsCalculator {
    static func roundRobin(
        participants: [Participant],
        matches: [Match],
        bestOf: Int
    ) -> [StandingRow] {
        var rows: [UUID: StandingRow] = [:]
        for p in participants where !p.isDisqualified {
            rows[p.id] = StandingRow(
                participantID: p.id,
                displayName: p.displayName,
                seedIndex: p.seedIndex,
                played: 0, wins: 0, draws: 0, losses: 0, points: 0,
                scoreFor: 0, scoreAgainst: 0, buchholz: 0, medianBuchholz: 0
            )
        }

        let finished = matches.filter { !$0.isBye && ($0.status == .finished || $0.status == .walkover) }
        for match in finished {
            guard let a = match.participantAID, let b = match.participantBID else { continue }
            guard var ra = rows[a], var rb = rows[b] else { continue }
            ra.played += 1
            rb.played += 1
            ra.scoreFor += match.scoreA
            ra.scoreAgainst += match.scoreB
            rb.scoreFor += match.scoreB
            rb.scoreAgainst += match.scoreA

            if let winner = match.winnerID {
                if winner == a {
                    ra.wins += 1; ra.points += 3
                    rb.losses += 1
                } else {
                    rb.wins += 1; rb.points += 3
                    ra.losses += 1
                }
            } else if bestOf == 1 && match.scoreA == match.scoreB {
                ra.draws += 1; rb.draws += 1
                ra.points += 1; rb.points += 1
            }
            rows[a] = ra
            rows[b] = rb
        }

        let headToHead = headToHeadScores(matches: finished)

        var list = Array(rows.values)
        list.sort { lhs, rhs in
            let lhsKey = sortKey(lhs, headToHead: headToHead)
            let rhsKey = sortKey(rhs, headToHead: headToHead)
            return lhsKey < rhsKey
        }
        return list
    }

    private static func sortKey(
        _ row: StandingRow,
        headToHead: [UUID: Int]
    ) -> (Int, Int, Int, Int, Int) {
        (
            -row.points,
            -(headToHead[row.participantID] ?? 0),
            -row.mapDifference,
            -row.scoreFor,
            row.seedIndex
        )
    }

    static func headToHeadScores(matches: [Match]) -> [UUID: Int] {
        var result: [UUID: Int] = [:]
        for match in matches {
            guard let a = match.participantAID,
                  let b = match.participantBID,
                  let winner = match.winnerID else { continue }
            let loser = winner == a ? b : a
            result[winner, default: 0] += 1
            result[loser, default: 0] -= 1
        }
        return result
    }
}
