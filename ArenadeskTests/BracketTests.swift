import Foundation
import Testing
@testable import Arenadesk

struct BracketTests {
    private func participants(_ n: Int) -> [Participant] {
        let tournamentID = UUID()
        return (1...n).map { seed in
            Participant(
                id: UUID(),
                tournamentID: tournamentID,
                displayName: "P\(seed)",
                teamName: "",
                contact: "",
                seedIndex: seed,
                registeredAt: Date(timeIntervalSince1970: TimeInterval(seed)),
                isCheckedIn: true,
                isDisqualified: false,
                placement: nil
            )
        }
    }

    @Test(arguments: [2, 3, 5, 8, 9, 16, 17])
    func singleEliminationByeCountAndFinalSeeds(n: Int) throws {
        let players = participants(n)
        let size = try SingleEliminationBracket.bracketSize(forParticipantCount: n)
        let expectedByes = size - n

        let result = try SingleEliminationBracket.generate(
            tournamentID: players[0].tournamentID,
            participants: players
        )

        #expect(result.byeCount == expectedByes)
        #expect(result.bracketSize == size)
        #expect(result.matches.filter(\.isBye).count == expectedByes)
        #expect(try SingleEliminationBracket.seedsMeetOnlyInFinal(bracketSize: size))

        let order = try SingleEliminationBracket.seedOrder(bracketSize: size)
        #expect(order.count == size)
        #expect(Set(order) == Set(1...size))

        let rounds = Dictionary(grouping: result.matches, by: \.roundIndex)
        #expect(rounds.count == result.roundCount)
        for round in 0..<result.roundCount {
            #expect(rounds[round]?.count == size >> (round + 1))
        }
    }

    @Test func foldSeedingOrderEight() throws {
        let order = try SingleEliminationBracket.seedOrder(bracketSize: 8)
        #expect(order == [1, 8, 4, 5, 2, 7, 3, 6])
    }

    @Test func singleEliminationThrowsInsteadOfTrappingOnEmptyField() {
        #expect(throws: DatabaseError.self) {
            _ = try SingleEliminationBracket.generate(
                tournamentID: UUID(),
                participants: []
            )
        }
        #expect(throws: DatabaseError.self) {
            _ = try SingleEliminationBracket.bracketSize(forParticipantCount: 1)
        }
    }

    @Test(arguments: [4, 5])
    func roundRobinEachPairOnce(n: Int) throws {
        let players = participants(n)

        let result = try RoundRobinBracket.generate(
            tournamentID: players[0].tournamentID,
            participants: players
        )

        var pairs: [UnorderedPair: Int] = [:]
        for match in result.matches where !match.isBye {
            guard let a = match.participantAID, let b = match.participantBID else { continue }
            pairs[UnorderedPair(a, b), default: 0] += 1
        }
        #expect(pairs.values.allSatisfy { $0 == 1 })
        #expect(pairs.count == RoundRobinBracket.pairCount(n: n))

        let rounds = Set(result.matches.map(\.roundIndex))
        #expect(rounds.count == (n % 2 == 0 ? n - 1 : n))
        for player in players {
            let appearances = result.matches.filter {
                $0.participantAID == player.id || $0.participantBID == player.id
            }
            #expect(appearances.count == rounds.count)
        }
    }

    @Test func roundRobinThrowsBelowTwoParticipants() {
        #expect(throws: DatabaseError.self) {
            _ = try RoundRobinBracket.generate(tournamentID: UUID(), participants: [])
        }
    }

    @Test func roundRobinTiebreaksPreferMapDifferenceThenSeed() {
        let players = participants(3)
        let a = players[0].id
        let b = players[1].id
        let c = players[2].id
        let tid = players[0].tournamentID
        let matches = [
            finished(tid, 0, 0, a, b, a, 2, 0),
            finished(tid, 0, 1, a, c, a, 2, 1),
            finished(tid, 1, 0, b, c, b, 2, 0)
        ]

        let standings = StandingsCalculator.roundRobin(
            participants: players,
            matches: matches,
            bestOf: 3
        )

        #expect(standings[0].participantID == a)
        #expect(standings[1].participantID == b)
        #expect(standings[2].participantID == c)
    }

    @Test func roundRobinBeatCycleProducesStableTransitiveOrder() {
        let players = participants(3)
        let a = players[0].id
        let b = players[1].id
        let c = players[2].id
        let tid = players[0].tournamentID
        let matches = [
            finished(tid, 0, 0, a, b, a, 1, 0),
            finished(tid, 1, 0, b, c, b, 1, 0),
            finished(tid, 2, 0, c, a, c, 1, 0)
        ]

        var orders: Set<[UUID]> = []
        for _ in 0..<32 {
            let standings = StandingsCalculator.roundRobin(
                participants: players.shuffled(),
                matches: matches.shuffled(),
                bestOf: 1
            )
            orders.insert(standings.map(\.participantID))
        }

        #expect(orders.count == 1)
        #expect(orders.first == [a, b, c])
    }

    @Test func headToHeadScoresAreSymmetricAndNet() {
        let players = participants(3)
        let (a, b, c) = (players[0].id, players[1].id, players[2].id)
        let tid = players[0].tournamentID
        let scores = StandingsCalculator.headToHeadScores(matches: [
            finished(tid, 0, 0, a, b, a, 1, 0),
            finished(tid, 1, 0, b, c, b, 1, 0),
            finished(tid, 2, 0, c, a, c, 1, 0)
        ])
        #expect(scores[a] == 0)
        #expect(scores[b] == 0)
        #expect(scores[c] == 0)
    }

    private func playSwiss(
        playerCount: Int,
        rounds: Int
    ) -> (matches: [Match], priorPairs: Set<UnorderedPair>, byeCounts: [UUID: Int], ids: [UUID]) {
        let players = participants(playerCount)
        let ids = players.map(\.id)
        var scores = Dictionary(uniqueKeysWithValues: ids.map { ($0, 0) })
        var allMatches: [Match] = []
        var priorPairs: Set<UnorderedPair> = []
        var byeCounts: [UUID: Int] = [:]

        for round in 0..<rounds {
            let roundMatches = SwissBracket.pairRound(
                tournamentID: players[0].tournamentID,
                roundIndex: round,
                playerIDs: ids,
                scores: scores,
                priorPairs: priorPairs,
                priorByeCounts: byeCounts
            )
            for var match in roundMatches {
                if match.isBye {
                    if let winner = match.winnerID { scores[winner, default: 0] += 1 }
                } else if let a = match.participantAID {
                    match.winnerID = a
                    match.status = .finished
                    match.scoreA = 1
                    scores[a, default: 0] += 1
                }
                allMatches.append(match)
            }
            priorPairs = SwissBracket.priorPairs(from: allMatches)
            byeCounts = SwissBracket.byeCounts(from: allMatches)
        }
        return (allMatches, priorPairs, byeCounts, ids)
    }

    @Test func swissNeverRepeatsAPairing() {
        let played = playSwiss(playerCount: 5, rounds: 3)
        #expect(played.priorPairs.count == played.matches.filter { !$0.isBye }.count)
    }

    @Test func swissSpreadsByesEvenlyAcrossAnOddField() {
        let played = playSwiss(playerCount: 5, rounds: 5)

        let counts = played.ids.map { played.byeCounts[$0, default: 0] }
        #expect(counts.allSatisfy { $0 == 1 })
    }

    @Test func swissGivesNoByeToAnEvenField() {
        let played = playSwiss(playerCount: 6, rounds: 3)
        #expect(played.matches.allSatisfy { !$0.isBye })
        #expect(played.byeCounts.isEmpty)
    }

    @Test func swissPairingStaysBoundedForALargeLateRound() {
        let ids = (0..<32).map { _ in UUID() }
        var priorPairs: Set<UnorderedPair> = []
        for (index, lhs) in ids.enumerated() {
            for rhs in ids.dropFirst(index + 1) {
                priorPairs.insert(UnorderedPair(lhs, rhs))
            }
        }

        let start = Date()
        let pairs = SwissBracket.pairWithinScoreGroups(
            ids,
            scores: Dictionary(uniqueKeysWithValues: ids.map { ($0, 1) }),
            priorPairs: priorPairs
        )
        let elapsed = Date().timeIntervalSince(start)

        #expect(pairs.count == ids.count / 2)
        #expect(elapsed < 2)
        #expect(Set(pairs.flatMap { [$0.0, $0.1] }).count == ids.count)
    }

    @Test func boundedPairAbandonsSearchAtTheStepLimit() {
        let ids = (0..<10).map { _ in UUID() }
        var priorPairs: Set<UnorderedPair> = []
        for (index, lhs) in ids.enumerated() {
            for rhs in ids.dropFirst(index + 1) {
                priorPairs.insert(UnorderedPair(lhs, rhs))
            }
        }
        #expect(SwissBracket.boundedPair(ids, priorPairs: priorPairs, stepLimit: 50) == nil)
    }

    @Test func swissBuchholzHandComputedFivePlayers() throws {
        let players = participants(5)
        let a = players[0].id
        let b = players[1].id
        let c = players[2].id
        let d = players[3].id
        let e = players[4].id
        let tid = players[0].tournamentID

        let matches: [Match] = [
            finished(tid, 0, 0, a, b, a, 1, 0),
            finished(tid, 0, 1, c, d, c, 1, 0),
            bye(tid, 0, 2, e),
            finished(tid, 1, 0, a, c, a, 1, 0),
            finished(tid, 1, 1, b, e, b, 1, 0),
            bye(tid, 1, 2, d),
            finished(tid, 2, 0, a, e, a, 1, 0),
            finished(tid, 2, 1, c, b, c, 1, 0)
        ]

        let standings = SwissBracket.swissStandings(participants: players, matches: matches)
        let byID = Dictionary(uniqueKeysWithValues: standings.map { ($0.participantID, $0) })

        #expect(byID[a]?.points == 3)
        #expect(byID[c]?.points == 2)
        #expect(byID[b]?.points == 1)
        #expect(byID[d]?.points == 1)
        #expect(byID[e]?.points == 1)

        #expect(byID[a]?.buchholz == 4)
        #expect(byID[a]?.medianBuchholz == 1)

        #expect(byID[c]?.buchholz == 5)
        #expect(byID[c]?.medianBuchholz == 1)

        #expect(byID[d]?.buchholz == 2)
        #expect(byID[d]?.medianBuchholz == 0)
    }

    @Test func medianBuchholzIsZeroWithFewerThanThreeOpponents() {
        let players = participants(3)
        let (a, b, c) = (players[0].id, players[1].id, players[2].id)
        let tid = players[0].tournamentID
        let matches = [
            finished(tid, 0, 0, a, b, a, 1, 0),
            finished(tid, 1, 0, a, c, a, 1, 0)
        ]
        let scores = [a: 2, b: 0, c: 0]

        #expect(SwissBracket.buchholz(participantID: a, matches: matches, scores: scores) == 0)
        #expect(SwissBracket.medianBuchholz(participantID: a, matches: matches, scores: scores) == 0)
        #expect(SwissBracket.medianBuchholz(participantID: b, matches: matches, scores: scores) == 0)
    }

    private func finished(
        _ tid: UUID, _ round: Int, _ slot: Int,
        _ a: UUID, _ b: UUID, _ winner: UUID,
        _ scoreA: Int, _ scoreB: Int
    ) -> Match {
        Match(
            id: UUID(), tournamentID: tid, roundIndex: round, slotIndex: slot,
            participantAID: a, participantBID: b, scoreA: scoreA, scoreB: scoreB,
            winnerID: winner, isBye: false, scheduledAt: nil, seatAID: nil, seatBID: nil,
            status: .finished, note: ""
        )
    }

    private func bye(_ tid: UUID, _ round: Int, _ slot: Int, _ player: UUID) -> Match {
        Match(
            id: UUID(), tournamentID: tid, roundIndex: round, slotIndex: slot,
            participantAID: player, participantBID: nil, scoreA: 1, scoreB: 0,
            winnerID: player, isBye: true, scheduledAt: nil, seatAID: nil, seatBID: nil,
            status: .walkover, note: "Bye"
        )
    }
}
