import Foundation

enum SwissBracket {
    static let maxPairingSteps = 20_000

    static func defaultRoundCount(n: Int) -> Int {
        max(3, Int(ceil(log2(Double(max(n, 2))))))
    }

    static func pairRound(
        tournamentID: UUID,
        roundIndex: Int,
        playerIDs: [UUID],
        scores: [UUID: Int],
        priorPairs: Set<UnorderedPair>,
        priorByeCounts: [UUID: Int]
    ) -> [Match] {
        let sorted = playerIDs.sorted { lhs, rhs in
            let ls = scores[lhs, default: 0]
            let rs = scores[rhs, default: 0]
            if ls != rs { return ls > rs }
            return lhs.uuidString < rhs.uuidString
        }

        var remaining = sorted
        var byeRecipient: UUID?

        if remaining.count % 2 == 1 {
            byeRecipient = remaining.enumerated().min { lhs, rhs in
                let lhsCount = priorByeCounts[lhs.element, default: 0]
                let rhsCount = priorByeCounts[rhs.element, default: 0]
                if lhsCount != rhsCount { return lhsCount < rhsCount }
                return lhs.offset > rhs.offset
            }?.element
            if let byeRecipient {
                remaining.removeAll { $0 == byeRecipient }
            }
        }

        let pairs = pairWithinScoreGroups(remaining, scores: scores, priorPairs: priorPairs)

        var matches: [Match] = []
        for (slot, pair) in pairs.enumerated() {
            matches.append(
                Match(
                    id: UUID(),
                    tournamentID: tournamentID,
                    roundIndex: roundIndex,
                    slotIndex: slot,
                    participantAID: pair.0,
                    participantBID: pair.1,
                    scoreA: 0,
                    scoreB: 0,
                    winnerID: nil,
                    isBye: false,
                    scheduledAt: nil,
                    seatAID: nil,
                    seatBID: nil,
                    status: .pending,
                    note: ""
                )
            )
        }
        if let bye = byeRecipient {
            matches.append(
                Match(
                    id: UUID(),
                    tournamentID: tournamentID,
                    roundIndex: roundIndex,
                    slotIndex: pairs.count,
                    participantAID: bye,
                    participantBID: nil,
                    scoreA: 1,
                    scoreB: 0,
                    winnerID: bye,
                    isBye: true,
                    scheduledAt: nil,
                    seatAID: nil,
                    seatBID: nil,
                    status: .walkover,
                    note: "Bye"
                )
            )
        }
        return matches
    }

    static func pairWithinScoreGroups(
        _ players: [UUID],
        scores: [UUID: Int],
        priorPairs: Set<UnorderedPair>
    ) -> [(UUID, UUID)] {
        if let paired = boundedPair(players, priorPairs: priorPairs) {
            return paired
        }

        var result: [(UUID, UUID)] = []
        var floated: [UUID] = []
        var deferred: [UUID] = []

        let groups = Dictionary(grouping: players) { scores[$0, default: 0] }
        for score in groups.keys.sorted(by: >) {
            guard let group = groups[score] else { continue }
            let members = Set(group)
            var bucket = floated + players.filter { members.contains($0) }
            floated = []
            if bucket.count % 2 == 1, let last = bucket.popLast() {
                floated = [last]
            }
            if let paired = boundedPair(bucket, priorPairs: priorPairs) {
                result += paired
            } else {
                deferred += bucket
            }
        }
        deferred += floated

        if let paired = boundedPair(deferred, priorPairs: priorPairs) {
            result += paired
        } else {
            result += adjacentPair(deferred)
        }
        return result
    }

    static func adjacentPair(_ players: [UUID]) -> [(UUID, UUID)] {
        var result: [(UUID, UUID)] = []
        var i = 0
        while i + 1 < players.count {
            result.append((players[i], players[i + 1]))
            i += 2
        }
        return result
    }

    static func boundedPair(
        _ players: [UUID],
        priorPairs: Set<UnorderedPair>,
        stepLimit: Int = maxPairingSteps
    ) -> [(UUID, UUID)]? {
        guard players.count >= 2 else { return players.isEmpty ? [] : nil }
        var steps = 0

        func search(_ remaining: [UUID], _ acc: [(UUID, UUID)]) -> [(UUID, UUID)]? {
            if remaining.isEmpty { return acc }
            steps += 1
            if steps > stepLimit { return nil }
            guard let first = remaining.first else { return acc }
            let rest = Array(remaining.dropFirst())
            for (index, candidate) in rest.enumerated() {
                guard !priorPairs.contains(UnorderedPair(first, candidate)) else { continue }
                var next = rest
                next.remove(at: index)
                if let result = search(next, acc + [(first, candidate)]) {
                    return result
                }
                if steps > stepLimit { return nil }
            }
            return nil
        }
        return search(players, [])
    }

    static func buchholz(participantID: UUID, matches: [Match], scores: [UUID: Int]) -> Int {
        opponentIDs(participantID, matches: matches)
            .map { scores[$0, default: 0] }
            .reduce(0, +)
    }

    static func medianBuchholz(participantID: UUID, matches: [Match], scores: [UUID: Int]) -> Int {
        var opp = opponentIDs(participantID, matches: matches).map { scores[$0, default: 0] }
        guard opp.count >= 3 else { return 0 }
        opp.sort()
        opp.removeFirst()
        opp.removeLast()
        return opp.reduce(0, +)
    }

    static func opponentIDs(_ participantID: UUID, matches: [Match]) -> [UUID] {
        var result: [UUID] = []
        for match in matches where !match.isBye {
            if match.participantAID == participantID, let other = match.participantBID {
                result.append(other)
            } else if match.participantBID == participantID, let other = match.participantAID {
                result.append(other)
            }
        }
        return result
    }

    static func swissStandings(
        participants: [Participant],
        matches: [Match]
    ) -> [StandingRow] {
        var scores: [UUID: Int] = [:]
        for p in participants { scores[p.id] = 0 }
        for match in matches where match.status == .finished || match.status == .walkover {
            if let winner = match.winnerID {
                scores[winner, default: 0] += 1
            }
        }

        var rows: [StandingRow] = participants.map { p in
            StandingRow(
                participantID: p.id,
                displayName: p.displayName,
                seedIndex: p.seedIndex,
                played: 0,
                wins: scores[p.id, default: 0],
                draws: 0,
                losses: 0,
                points: scores[p.id, default: 0],
                scoreFor: 0,
                scoreAgainst: 0,
                buchholz: buchholz(participantID: p.id, matches: matches, scores: scores),
                medianBuchholz: medianBuchholz(participantID: p.id, matches: matches, scores: scores)
            )
        }
        let headToHead = StandingsCalculator.headToHeadScores(
            matches: matches.filter { !$0.isBye && ($0.status == .finished || $0.status == .walkover) }
        )
        rows.sort { lhs, rhs in
            let lhsKey = (
                -lhs.points, -lhs.buchholz, -lhs.medianBuchholz,
                -(headToHead[lhs.participantID] ?? 0), lhs.seedIndex
            )
            let rhsKey = (
                -rhs.points, -rhs.buchholz, -rhs.medianBuchholz,
                -(headToHead[rhs.participantID] ?? 0), rhs.seedIndex
            )
            return lhsKey < rhsKey
        }
        return rows
    }

    static func priorPairs(from matches: [Match]) -> Set<UnorderedPair> {
        var set: Set<UnorderedPair> = []
        for match in matches where !match.isBye {
            if let a = match.participantAID, let b = match.participantBID {
                set.insert(UnorderedPair(a, b))
            }
        }
        return set
    }

    static func byeCounts(from matches: [Match]) -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for id in matches.filter(\.isBye).compactMap(\.participantAID) {
            counts[id, default: 0] += 1
        }
        return counts
    }
}

struct UnorderedPair: Hashable, Sendable {
    let a: UUID
    let b: UUID

    init(_ lhs: UUID, _ rhs: UUID) {
        if lhs.uuidString < rhs.uuidString {
            a = lhs; b = rhs
        } else {
            a = rhs; b = lhs
        }
    }
}
