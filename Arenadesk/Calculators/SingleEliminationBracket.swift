import Foundation

struct BracketGenerationResult: Sendable {
    var matches: [Match]
    var bracketSize: Int
    var byeCount: Int
    var roundCount: Int
}

enum SingleEliminationBracket {
    static func seedOrder(bracketSize: Int) throws -> [Int] {
        guard bracketSize >= 2, bracketSize.nonzeroBitCount == 1 else {
            throw DatabaseError.invalidBracket("Bracket size \(bracketSize) is not a power of two ≥ 2")
        }
        if bracketSize == 2 { return [1, 2] }
        let half = try seedOrder(bracketSize: bracketSize / 2)
        let mirrored = half.map { (bracketSize + 1) - $0 }
        return try interleave(half, mirrored)
    }

    static func interleave(_ a: [Int], _ b: [Int]) throws -> [Int] {
        guard a.count == b.count else {
            throw DatabaseError.invalidBracket("Cannot interleave halves of unequal length")
        }
        var result: [Int] = []
        result.reserveCapacity(a.count * 2)
        for index in a.indices {
            result.append(a[index])
            result.append(b[index])
        }
        return result
    }

    static func bracketSize(forParticipantCount n: Int) throws -> Int {
        guard n >= 2 else {
            throw DatabaseError.invalidBracket("Need at least 2 participants")
        }
        var size = 1
        while size < n { size <<= 1 }
        return size
    }

    static func byeCount(n: Int) throws -> Int {
        try bracketSize(forParticipantCount: n) - n
    }

    static func generate(
        tournamentID: UUID,
        participants: [Participant]
    ) throws -> BracketGenerationResult {
        let seeded = participants
            .filter { $0.isCheckedIn && !$0.isDisqualified }
            .sorted { $0.seedIndex < $1.seedIndex }
        let n = seeded.count
        let size = try bracketSize(forParticipantCount: n)
        let byes = size - n
        let order = try seedOrder(bracketSize: size)
        let roundCount = Int(log2(Double(size)))

        var bySeed: [Int: Participant] = [:]
        for participant in seeded {
            bySeed[participant.seedIndex] = participant
        }

        let slots: [UUID?] = order.map { seed in
            seed <= n ? bySeed[seed]?.id : nil
        }

        var matches: [Match] = []

        for slot in 0..<(size / 2) {
            let a = slots[slot * 2]
            let b = slots[slot * 2 + 1]
            let isBye = a == nil || b == nil
            var winner: UUID?
            var status: MatchStatus = .pending
            if isBye {
                winner = a ?? b
                status = .walkover
            }
            matches.append(
                Match(
                    id: UUID(),
                    tournamentID: tournamentID,
                    roundIndex: 0,
                    slotIndex: slot,
                    participantAID: a,
                    participantBID: b,
                    scoreA: 0,
                    scoreB: 0,
                    winnerID: winner,
                    isBye: isBye,
                    scheduledAt: nil,
                    seatAID: nil,
                    seatBID: nil,
                    status: status,
                    note: ""
                )
            )
        }

        for round in 1..<roundCount {
            let matchCount = size >> (round + 1)
            for slot in 0..<matchCount {
                matches.append(
                    Match(
                        id: UUID(),
                        tournamentID: tournamentID,
                        roundIndex: round,
                        slotIndex: slot,
                        participantAID: nil,
                        participantBID: nil,
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
        }

        advanceByeWinners(matches: &matches, roundCount: roundCount)

        return BracketGenerationResult(
            matches: matches.sorted { lhs, rhs in
                if lhs.roundIndex != rhs.roundIndex { return lhs.roundIndex < rhs.roundIndex }
                return lhs.slotIndex < rhs.slotIndex
            },
            bracketSize: size,
            byeCount: byes,
            roundCount: roundCount
        )
    }

    private static func advanceByeWinners(matches: inout [Match], roundCount: Int) {
        for round in 0..<(roundCount - 1) {
            let current = matches.filter { $0.roundIndex == round }
            for match in current where match.status == .walkover || match.status == .finished {
                guard let winner = match.winnerID else { continue }
                placeWinner(winner, from: match, into: &matches)
            }
        }
    }

    static func placeWinner(_ winnerID: UUID, from match: Match, into matches: inout [Match]) {
        let nextRound = match.roundIndex + 1
        let nextSlot = match.slotIndex / 2
        guard let index = matches.firstIndex(where: { $0.roundIndex == nextRound && $0.slotIndex == nextSlot }) else {
            return
        }
        if match.slotIndex % 2 == 0 {
            matches[index].participantAID = winnerID
        } else {
            matches[index].participantBID = winnerID
        }
        let isDecided = matches[index].status == .finished || matches[index].status == .walkover
        if !isDecided,
           matches[index].participantAID != nil,
           matches[index].participantBID != nil {
            matches[index].status = .ready
        }
    }

    static func seedsMeetOnlyInFinal(bracketSize: Int) throws -> Bool {
        let order = try seedOrder(bracketSize: bracketSize)
        let half = bracketSize / 2
        guard let i1 = order.firstIndex(of: 1), let i2 = order.firstIndex(of: 2) else { return false }
        return (i1 < half) != (i2 < half)
    }
}
