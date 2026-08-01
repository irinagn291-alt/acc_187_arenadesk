import Foundation
import Testing
@testable import Arenadesk

struct Fixture {
    let database: Database

    static func migrated() async throws -> Fixture {
        let database = try Database(inMemory: true)
        try await Migrator.migrate(database)
        return Fixture(database: database)
    }

    func zone(name: String = "Main") async throws -> Zone {
        let zone = Zone(id: UUID(), name: name, kind: .standard, capacity: 64, sortIndex: 0, note: "")
        try await database.upsertZone(zone)
        return zone
    }

    func seat(
        zoneID: UUID,
        label: String,
        state: SeatState = .ready,
        health: Int = 100,
        commissionedAt: Date = Date(timeIntervalSince1970: 0)
    ) async throws -> GamingSeat {
        let seat = GamingSeat(
            id: UUID(),
            zoneID: zoneID,
            label: label,
            state: state,
            cpu: "cpu",
            gpu: "gpu",
            ramGB: 16,
            storage: "1TB",
            monitorModel: "mon",
            monitorHz: 144,
            commissionedAt: commissionedAt,
            lastMaintenanceAt: nil,
            maintenanceIntervalDays: 30,
            healthScore: health,
            note: ""
        )
        try await database.upsertSeats([seat])
        return seat
    }

    func equipment(seatID: UUID?, state: EquipmentState = .broken) async throws -> Equipment {
        let item = Equipment(
            id: UUID(),
            seatID: seatID,
            zoneID: nil,
            name: "Monitor",
            kind: .monitor,
            serialNumber: "SN-1",
            state: state,
            purchasedAt: nil,
            warrantyUntil: nil,
            price: nil,
            stateChangedAt: Date(timeIntervalSince1970: 0),
            note: ""
        )
        try await database.upsertEquipment(item)
        return item
    }

    func employee(name: String = "Alex") async throws -> Employee {
        let employee = Employee(
            id: UUID(),
            fullName: name,
            role: .manager,
            phone: "555",
            hiredAt: Date(timeIntervalSince1970: 0),
            hourlyRate: 20,
            isActive: true,
            note: "",
            pinHash: nil,
            pinSalt: nil
        )
        try await database.upsertEmployee(employee)
        return employee
    }

    func tournament(
        format: MatchFormat,
        bestOf: Int = 1,
        zoneID: UUID? = nil
    ) async throws -> Tournament {
        let tournament = Tournament(
            id: UUID(),
            name: "Cup",
            discipline: "CS",
            format: format,
            status: .draft,
            zoneID: zoneID,
            startsAt: Date(timeIntervalSince1970: 1_000_000),
            endsAt: nil,
            entryFee: 0,
            prizePool: 0,
            maxParticipants: 64,
            bestOf: bestOf,
            swissRoundCount: nil,
            refereeID: nil,
            isArchived: false,
            rulesDocumentID: nil
        )
        try await database.upsertTournament(tournament)
        return tournament
    }

    @discardableResult
    func participants(_ count: Int, tournamentID: UUID) async throws -> [Participant] {
        var result: [Participant] = []
        for seed in 1...count {
            let participant = Participant(
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
            try await database.upsertParticipant(participant)
            result.append(participant)
        }
        return result
    }

    func repair(equipmentID: UUID?, seatID: UUID?) async throws -> RepairRecord {
        let repair = RepairRecord(
            id: UUID(),
            equipmentID: equipmentID,
            seatID: seatID,
            openedAt: Date(timeIntervalSince1970: 0),
            closedAt: nil,
            symptom: "No signal",
            actionTaken: "",
            partsCost: 0,
            laborCost: 0,
            performedBy: "",
            isExternal: false
        )
        try await database.upsertRepairRecord(repair)
        return repair
    }
}

struct RepairNestedTransactionTests {
    @Test func closingARepairWithEquipmentAlsoRecordsTheStateChange() async throws {
        let fixture = try await Fixture.migrated()
        let zone = try await fixture.zone()
        let seat = try await fixture.seat(zoneID: zone.id, label: "A-01", state: .maintenance)
        let equipment = try await fixture.equipment(seatID: seat.id, state: .broken)
        let repair = try await fixture.repair(equipmentID: equipment.id, seatID: seat.id)
        let closedAt = Date(timeIntervalSince1970: 10_000)

        let repairs = RepairRepository(database: fixture.database)
        let closed = try await repairs.close(
            id: repair.id,
            actionTaken: "Replaced panel",
            partsCost: Decimal(string: "120.50") ?? 0,
            laborCost: Decimal(string: "40.00") ?? 0,
            performedBy: "Alex",
            retireEquipment: false,
            at: closedAt
        )

        #expect(closed.closedAt == closedAt)
        let stored = try #require(try await fixture.database.fetchRepair(id: repair.id))
        #expect(stored.closedAt == closedAt)
        #expect(stored.actionTaken == "Replaced panel")
        #expect(stored.partsCost == Decimal(string: "120.50"))

        let reloaded = try #require(try await fixture.database.fetchEquipmentItem(id: equipment.id))
        #expect(reloaded.state == .ok)

        let history = try await fixture.database.fetchEquipmentStateChanges(equipmentID: equipment.id)
        #expect(history.count == 1)
        #expect(history.first?.fromState == .broken)
        #expect(history.first?.toState == .ok)
    }

    @Test func closingARepairCanRetireTheEquipment() async throws {
        let fixture = try await Fixture.migrated()
        let zone = try await fixture.zone()
        let seat = try await fixture.seat(zoneID: zone.id, label: "A-02")
        let equipment = try await fixture.equipment(seatID: seat.id)
        let repair = try await fixture.repair(equipmentID: equipment.id, seatID: seat.id)

        _ = try await RepairRepository(database: fixture.database).close(
            id: repair.id,
            actionTaken: "Beyond repair",
            partsCost: 0,
            laborCost: 0,
            performedBy: "Alex",
            retireEquipment: true,
            at: Date(timeIntervalSince1970: 10_000)
        )

        let reloaded = try #require(try await fixture.database.fetchEquipmentItem(id: equipment.id))
        #expect(reloaded.state == .retired)
    }

    @Test func closingAMissingRepairThrowsAndChangesNothing() async throws {
        let fixture = try await Fixture.migrated()
        await #expect(throws: DatabaseError.self) {
            _ = try await RepairRepository(database: fixture.database).close(
                id: UUID(),
                actionTaken: "",
                partsCost: 0,
                laborCost: 0,
                performedBy: "",
                retireEquipment: false
            )
        }
    }
}

struct SeatAssignmentTests {
    @Test func autoAssignSeatsFillsEveryPlayableMatchEndToEnd() async throws {
        let fixture = try await Fixture.migrated()
        let zone = try await fixture.zone()
        for index in 1...4 {
            _ = try await fixture.seat(zoneID: zone.id, label: "A-0\(index)")
        }
        let tournament = try await fixture.tournament(format: .singleElimination, zoneID: zone.id)
        try await fixture.participants(4, tournamentID: tournament.id)

        let tournaments = TournamentRepository(database: fixture.database)
        _ = try await tournaments.generateBracket(tournamentID: tournament.id)

        let failures = try await tournaments.autoAssignSeats(tournamentID: tournament.id)

        #expect(failures.isEmpty)
        let matches = try await tournaments.matches(tournamentID: tournament.id)
        let firstRound = matches.filter { $0.roundIndex == 0 && !$0.isBye }
        #expect(firstRound.count == 2)
        for match in firstRound {
            let seatA = try #require(match.seatAID)
            let seatB = try #require(match.seatBID)
            #expect(seatA != seatB)
        }
        let assigned = firstRound.flatMap { [$0.seatAID, $0.seatBID] }.compactMap { $0 }
        #expect(Set(assigned).count == 4)

        let sessions = try await fixture.database.fetchOpenSeatSessions()
        #expect(sessions.count == 4)
        #expect(sessions.allSatisfy { $0.matchID != nil })
        #expect(Set(sessions.compactMap(\.matchID)) == Set(firstRound.map(\.id)))
    }

    @Test func autoAssignSeatsReportsAFailureWithoutInventingAMatchID() async throws {
        let fixture = try await Fixture.migrated()
        let zone = try await fixture.zone()
        _ = try await fixture.seat(zoneID: zone.id, label: "A-01", state: .outOfService, health: 5)
        let tournament = try await fixture.tournament(format: .singleElimination, zoneID: zone.id)
        try await fixture.participants(4, tournamentID: tournament.id)

        let tournaments = TournamentRepository(database: fixture.database)
        _ = try await tournaments.generateBracket(tournamentID: tournament.id)

        let failures = try await tournaments.autoAssignSeats(tournamentID: tournament.id)

        #expect(!failures.isEmpty)
        let matchIDs = Set(
            try await tournaments.matches(tournamentID: tournament.id).map(\.id)
        )
        for failure in failures {
            if let id = failure.matchID {
                #expect(matchIDs.contains(id))
            }
        }
    }

    @Test func autoAssignSeatsMatchesSessionsToTheirOwnMatch() async throws {
        let fixture = try await Fixture.migrated()
        let zone = try await fixture.zone()
        for index in 1...8 {
            _ = try await fixture.seat(zoneID: zone.id, label: "A-0\(index)")
        }
        let tournament = try await fixture.tournament(format: .singleElimination, zoneID: zone.id)
        try await fixture.participants(8, tournamentID: tournament.id)
        let tournaments = TournamentRepository(database: fixture.database)
        _ = try await tournaments.generateBracket(tournamentID: tournament.id)

        _ = try await tournaments.autoAssignSeats(tournamentID: tournament.id)

        let sessions = try await fixture.database.fetchOpenSeatSessions()
        let grouped = Dictionary(grouping: sessions.compactMap(\.matchID)) { $0 }
        #expect(grouped.count == 4)
        #expect(grouped.values.allSatisfy { $0.count == 2 })
    }

    @Test func regeneratingABracketClearsDanglingSessionMatchIDs() async throws {
        let fixture = try await Fixture.migrated()
        let zone = try await fixture.zone()
        for index in 1...4 {
            _ = try await fixture.seat(zoneID: zone.id, label: "A-0\(index)")
        }
        let tournament = try await fixture.tournament(format: .singleElimination, zoneID: zone.id)
        try await fixture.participants(4, tournamentID: tournament.id)
        let tournaments = TournamentRepository(database: fixture.database)
        _ = try await tournaments.generateBracket(tournamentID: tournament.id)
        _ = try await tournaments.autoAssignSeats(tournamentID: tournament.id)

        _ = try await tournaments.generateBracket(tournamentID: tournament.id)

        let liveMatchIDs = Set(try await tournaments.matches(tournamentID: tournament.id).map(\.id))
        let sessions = try await fixture.database.fetchOpenSeatSessions()
        for session in sessions {
            if let matchID = session.matchID {
                #expect(liveMatchIDs.contains(matchID))
            }
        }
    }
}

struct BracketEditingTests {
    @Test func editingOneResultPreservesTheOtherBranch() async throws {
        let fixture = try await Fixture.migrated()
        let zone = try await fixture.zone()
        let tournament = try await fixture.tournament(
            format: .singleElimination,
            bestOf: 1,
            zoneID: zone.id
        )
        try await fixture.participants(4, tournamentID: tournament.id)
        let tournaments = TournamentRepository(database: fixture.database)
        _ = try await tournaments.generateBracket(tournamentID: tournament.id)

        var matches = try await tournaments.matches(tournamentID: tournament.id)
        let semis = matches.filter { $0.roundIndex == 0 }.sorted { $0.slotIndex < $1.slotIndex }
        #expect(semis.count == 2)

        for semi in semis {
            try await tournaments.enterResult(
                matchID: semi.id,
                scoreA: 1,
                scoreB: 0,
                confirmInvalidateDownstream: false
            )
        }

        matches = try await tournaments.matches(tournamentID: tournament.id)
        let finalBefore = try #require(matches.first { $0.roundIndex == 1 })
        let untouchedSemiWinner = try #require(semis[1].participantAID)
        #expect(finalBefore.participantBID == untouchedSemiWinner)

        let edited = try #require(semis.first)
        await #expect(throws: DatabaseError.self) {
            try await tournaments.enterResult(
                matchID: edited.id,
                scoreA: 0,
                scoreB: 1,
                confirmInvalidateDownstream: false
            )
        }
        try await tournaments.enterResult(
            matchID: edited.id,
            scoreA: 0,
            scoreB: 1,
            confirmInvalidateDownstream: true
        )

        matches = try await tournaments.matches(tournamentID: tournament.id)
        let finalAfter = try #require(matches.first { $0.roundIndex == 1 })
        #expect(finalAfter.participantAID == edited.participantBID)
        #expect(finalAfter.participantBID == untouchedSemiWinner)
    }

    @Test func editingAResultOnlyClearsMatchesOnTheTransitivePath() async throws {
        let fixture = try await Fixture.migrated()
        let zone = try await fixture.zone()
        let tournament = try await fixture.tournament(
            format: .singleElimination,
            bestOf: 1,
            zoneID: zone.id
        )
        try await fixture.participants(8, tournamentID: tournament.id)
        let tournaments = TournamentRepository(database: fixture.database)
        _ = try await tournaments.generateBracket(tournamentID: tournament.id)

        for round in 0..<3 {
            let roundMatches = try await tournaments.matches(tournamentID: tournament.id)
                .filter { $0.roundIndex == round && !$0.isBye }
            for match in roundMatches {
                try await tournaments.enterResult(
                    matchID: match.id,
                    scoreA: 1,
                    scoreB: 0,
                    confirmInvalidateDownstream: true
                )
            }
        }

        let before = try await tournaments.matches(tournamentID: tournament.id)
        #expect(before.filter { $0.status == .finished }.count == 7)

        let edited = try #require(
            before.first { $0.roundIndex == 0 && $0.slotIndex == 0 }
        )
        try await tournaments.enterResult(
            matchID: edited.id,
            scoreA: 0,
            scoreB: 1,
            confirmInvalidateDownstream: true
        )

        let after = try await tournaments.matches(tournamentID: tournament.id)
        let otherQuarters = after.filter { $0.roundIndex == 0 && $0.slotIndex != 0 }
        #expect(otherQuarters.allSatisfy { $0.status == .finished })

        let farSemi = try #require(after.first { $0.roundIndex == 1 && $0.slotIndex == 1 })
        #expect(farSemi.status == .finished)
        #expect(farSemi.winnerID != nil)

        let nearSemi = try #require(after.first { $0.roundIndex == 1 && $0.slotIndex == 0 })
        #expect(nearSemi.participantAID == edited.participantBID)
    }

    @Test func scoresOutsideTheBestOfRangeAreRejected() async throws {
        let fixture = try await Fixture.migrated()
        let zone = try await fixture.zone()
        let tournament = try await fixture.tournament(
            format: .singleElimination,
            bestOf: 3,
            zoneID: zone.id
        )
        try await fixture.participants(4, tournamentID: tournament.id)
        let tournaments = TournamentRepository(database: fixture.database)
        _ = try await tournaments.generateBracket(tournamentID: tournament.id)
        let match = try #require(
            try await tournaments.matches(tournamentID: tournament.id).first { $0.roundIndex == 0 }
        )

        await #expect(throws: DatabaseError.self) {
            try await tournaments.enterResult(
                matchID: match.id,
                scoreA: -1,
                scoreB: 0,
                confirmInvalidateDownstream: false
            )
        }
        await #expect(throws: DatabaseError.self) {
            try await tournaments.enterResult(
                matchID: match.id,
                scoreA: 4,
                scoreB: 0,
                confirmInvalidateDownstream: false
            )
        }
    }

    @Test func aDrawIsRejectedInAnEliminationBracket() async throws {
        let fixture = try await Fixture.migrated()
        let zone = try await fixture.zone()
        let tournament = try await fixture.tournament(
            format: .singleElimination,
            bestOf: 2,
            zoneID: zone.id
        )
        try await fixture.participants(4, tournamentID: tournament.id)
        let tournaments = TournamentRepository(database: fixture.database)
        _ = try await tournaments.generateBracket(tournamentID: tournament.id)
        let match = try #require(
            try await tournaments.matches(tournamentID: tournament.id).first { $0.roundIndex == 0 }
        )

        await #expect(throws: DatabaseError.self) {
            try await tournaments.enterResult(
                matchID: match.id,
                scoreA: 1,
                scoreB: 1,
                confirmInvalidateDownstream: false
            )
        }
    }

    @Test func aDrawIsAcceptedInRoundRobin() async throws {
        let fixture = try await Fixture.migrated()
        let tournament = try await fixture.tournament(format: .roundRobin, bestOf: 2)
        try await fixture.participants(4, tournamentID: tournament.id)
        let tournaments = TournamentRepository(database: fixture.database)
        _ = try await tournaments.generateBracket(tournamentID: tournament.id)
        let match = try #require(
            try await tournaments.matches(tournamentID: tournament.id).first { !$0.isBye }
        )

        try await tournaments.enterResult(
            matchID: match.id,
            scoreA: 1,
            scoreB: 1,
            confirmInvalidateDownstream: false
        )

        let stored = try #require(try await tournaments.fetchMatch(id: match.id))
        #expect(stored.status == .finished)
        #expect(stored.winnerID == nil)
    }
}

struct BackupRoundTripTests {
    @Test func backupWipeRestorePreservesEveryTable() async throws {
        let fixture = try await Fixture.migrated()
        let before = try await fixture.seedEveryTable()
        let service = BackupService(database: fixture.database)
        let payload = try await fixture.database.exportBackupPayload(appVersion: "1.0")

        try await fixture.database.wipeUserData()
        #expect(try await fixture.database.rowCountsByTable().values.allSatisfy { $0 == 0 })
        try await fixture.database.restoreBackupPayload(payload)

        let after = try await fixture.database.rowCountsByTable()
        #expect(after == before)
        for (table, count) in before {
            #expect(after[table] == count, "table \(table) lost rows")
        }
        _ = service
    }

    @Test func restoredRowsKeepTheirValues() async throws {
        let fixture = try await Fixture.migrated()
        _ = try await fixture.seedEveryTable()
        let seatsBefore = try await fixture.database.fetchSeats(zoneID: nil)
        let matchesBefore = try await fixture.database.fetchAllMatches()
        let movementsBefore = try await fixture.database.fetchAllInventoryMovements()
        let payload = try await fixture.database.exportBackupPayload(appVersion: "1.0")

        try await fixture.database.wipeUserData()
        try await fixture.database.restoreBackupPayload(payload)

        #expect(try await fixture.database.fetchSeats(zoneID: nil) == seatsBefore)
        #expect(Set(try await fixture.database.fetchAllMatches()) == Set(matchesBefore))
        #expect(
            Set(try await fixture.database.fetchAllInventoryMovements()) == Set(movementsBefore)
        )
    }

    @Test func restoreKeepsInventoryQuantityConsistentWithTheLedger() async throws {
        let fixture = try await Fixture.migrated()
        _ = try await fixture.seedEveryTable()
        let payload = try await fixture.database.exportBackupPayload(appVersion: "1.0")
        let itemsBefore = try await fixture.database.fetchInventoryItems()

        try await fixture.database.wipeUserData()
        try await fixture.database.restoreBackupPayload(payload)

        let itemsAfter = try await fixture.database.fetchInventoryItems()
        #expect(itemsAfter == itemsBefore)
        #expect(!itemsAfter.isEmpty)
    }

    @Test func aV1PayloadMigratesForwardInsteadOfBeingRejected() async throws {
        var payload = BackupPayload(
            manifest: BackupManifest(
                schemaVersion: 1,
                appVersion: "1.0",
                createdAt: .now,
                rowCounts: [:],
                includesFiles: false
            )
        )
        payload.venues = [
            Venue(
                id: UUID(),
                name: "Arena",
                address: "1 Main",
                phone: "555",
                openingTime: DateComponents(hour: 10, minute: 0),
                closingTime: DateComponents(hour: 22, minute: 0),
                currencyCode: "USD",
                seatHourlyRate: 5
            )
        ]

        let migrated = try BackupMigrator.migrate(payload)

        #expect(migrated.manifest.schemaVersion == Migrator.currentVersion)
        #expect(migrated.venues.count == 1)
        #expect(migrated.plannedShifts.isEmpty)
    }

    @Test func aBackupFileMissingNewerTablesStillDecodes() async throws {
        let json = """
        {
          "manifest": {
            "schemaVersion": 1,
            "appVersion": "1.0",
            "createdAt": 0,
            "rowCounts": {},
            "includesFiles": false
          },
          "venues": [],
          "employees": []
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let data = try #require(json.data(using: .utf8))
        let payload = try decoder.decode(BackupPayload.self, from: data)

        #expect(payload.matches.isEmpty)
        #expect(payload.checklistRuns.isEmpty)
        #expect(payload.maintenanceTasks.isEmpty)
        #expect(payload.seatSessions.isEmpty)
    }

    @Test func restoreRefusesAPayloadFromANewerSchema() async throws {
        let fixture = try await Fixture.migrated()
        let payload = BackupPayload(
            manifest: BackupManifest(
                schemaVersion: Migrator.currentVersion + 1,
                appVersion: "9.0",
                createdAt: .now,
                rowCounts: [:],
                includesFiles: false
            )
        )
        #expect(throws: BackupError.self) { _ = try BackupMigrator.migrate(payload) }
        _ = fixture
    }
}

extension Fixture {
    @discardableResult
    func seedEveryTable() async throws -> [String: Int] {
        let venue = Venue(
            id: UUID(),
            name: "Arena",
            address: "1 Main",
            phone: "555",
            openingTime: DateComponents(hour: 10, minute: 0),
            closingTime: DateComponents(hour: 22, minute: 0),
            currencyCode: "USD",
            seatHourlyRate: Decimal(string: "5.50") ?? 5
        )
        try await database.upsertVenue(venue)

        let employee = try await employee()
        let zone = try await zone()
        let seat = try await seat(zoneID: zone.id, label: "A-01")
        let equipment = try await equipment(seatID: seat.id, state: .ok)

        _ = try await database.changeEquipmentState(
            id: equipment.id,
            to: .broken,
            employeeID: employee.id,
            reason: "Test",
            at: Date(timeIntervalSince1970: 100)
        )

        try await database.seedDefaultChecklistsIfNeeded()
        let template = try #require(try await database.fetchActiveTemplate(kind: .shiftOpen))
        let (run, _) = try await database.startChecklistRun(
            template: template,
            employeeID: employee.id,
            at: Date(timeIntervalSince1970: 200)
        )

        let shift = try await database.openShift(
            employeeID: employee.id,
            openRunID: run.id,
            openingCash: 100,
            at: Date(timeIntervalSince1970: 300)
        )

        try await database.upsertPlannedShift(
            PlannedShift(
                id: UUID(),
                employeeID: employee.id,
                startsAt: Date(timeIntervalSince1970: 400),
                endsAt: Date(timeIntervalSince1970: 500),
                note: "Planned"
            )
        )

        _ = try await database.startSeatSession(
            seatID: seat.id,
            shiftID: shift.id,
            purpose: .walkIn,
            note: "",
            at: Date(timeIntervalSince1970: 600)
        )

        try await database.upsertNote(
            Note(
                id: UUID(),
                title: "N",
                body: "B",
                isPinned: false,
                createdAt: Date(timeIntervalSince1970: 700),
                updatedAt: Date(timeIntervalSince1970: 700)
            )
        )

        try await database.upsertIncident(
            Incident(
                id: UUID(),
                shiftID: shift.id,
                zoneID: zone.id,
                seatID: seat.id,
                severity: .low,
                kind: .hardware,
                occurredAt: Date(timeIntervalSince1970: 800),
                reportedByID: employee.id,
                summary: "S",
                resolution: "",
                isResolved: false,
                isArchived: false
            )
        )

        try await database.upsertDocument(
            DocumentFile(
                id: UUID(),
                title: "Doc",
                filename: "doc.pdf",
                byteSize: 10,
                typeIdentifier: "com.adobe.pdf",
                importedAt: Date(timeIntervalSince1970: 900),
                categoryName: "Rules"
            )
        )

        let item = InventoryItem(
            id: UUID(),
            name: "Cable",
            sku: "SKU-1",
            unit: "pcs",
            quantity: 0,
            minimumQuantity: 2,
            unitCost: Decimal(string: "3.25") ?? 3,
            categoryName: "Parts",
            isConsumable: true
        )
        try await database.upsertInventoryItem(item)
        _ = try await database.addInventoryMovement(
            InventoryMovement(
                id: UUID(),
                itemID: item.id,
                kind: .receipt,
                quantity: 10,
                occurredAt: Date(timeIntervalSince1970: 1000),
                shiftID: shift.id,
                employeeID: employee.id,
                reason: "Delivery"
            )
        )

        let repair = try await repair(equipmentID: equipment.id, seatID: seat.id)

        try await database.upsertFinanceRecord(
            FinanceRecord(
                id: UUID(),
                kind: .expense,
                categoryName: "Repairs",
                amount: Decimal(string: "12.50") ?? 12,
                occurredAt: Date(timeIntervalSince1970: 1100),
                shiftID: shift.id,
                tournamentID: nil,
                repairID: repair.id,
                note: ""
            )
        )

        let tournament = try await tournament(format: .singleElimination, zoneID: zone.id)
        try await participants(4, tournamentID: tournament.id)
        _ = try await database.generateBracket(tournamentID: tournament.id)

        try await database.upsertMaintenanceTask(
            MaintenanceTask(
                id: UUID(),
                title: "Dust",
                seatID: seat.id,
                equipmentID: nil,
                zoneID: zone.id,
                kind: .cleaning,
                status: .planned,
                scheduledFor: Date(timeIntervalSince1970: 1200),
                completedAt: nil,
                assigneeID: employee.id,
                recurrenceDays: 30,
                checklistTemplateID: nil,
                note: ""
            )
        )

        let counts = try await database.rowCountsByTable()
        #expect(counts.values.allSatisfy { $0 > 0 }, "a table was left empty: \(counts)")
        return counts
    }
}
