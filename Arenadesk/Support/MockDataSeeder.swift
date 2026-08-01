import Foundation

#if DEBUG
enum MockDataSeeder {
    @MainActor
    static func seedIfNeeded(environment: AppEnvironment) async throws {
        if (try? await environment.venues.fetch()) != nil { return }

        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.didSeedMockData)

        let calendar = Calendar.current
        let now = Date()
        func daysAgo(_ days: Int, hours: Int = 0) -> Date {
            calendar.date(byAdding: .day, value: -days, to: now)?
                .addingTimeInterval(TimeInterval(-hours * 3600)) ?? now
        }

        let venue = Venue(
            id: UUID(),
            name: "Northside Arena",
            address: "482 Market Street",
            phone: "+1 555 0142",
            openingTime: DateComponents(hour: 10, minute: 0),
            closingTime: DateComponents(hour: 23, minute: 0),
            currencyCode: "USD",
            seatHourlyRate: 6
        )
        try await environment.venues.upsert(venue)

        let mainZone = Zone(id: UUID(), name: "Main Floor", kind: .standard, capacity: 8, sortIndex: 0, note: "Primary PCs")
        let vipZone = Zone(id: UUID(), name: "VIP Booths", kind: .vip, capacity: 4, sortIndex: 1, note: "High refresh")
        let tourneyZone = Zone(id: UUID(), name: "Tournament Pit", kind: .tournament, capacity: 4, sortIndex: 2, note: "Bracket seats")
        for zone in [mainZone, vipZone, tourneyZone] {
            try await environment.zones.upsert(zone)
        }

        let seatSpecs: [(Zone, String, SeatState, Int, String, String, Int)] = [
            (mainZone, "A-01", .occupied, 92, "Ryzen 5 5600", "RTX 3060", 16),
            (mainZone, "A-02", .ready, 88, "Ryzen 5 5600", "RTX 3060", 16),
            (mainZone, "A-03", .ready, 95, "Ryzen 5 5600", "RTX 3060", 16),
            (mainZone, "A-04", .cleaning, 80, "Ryzen 5 5600", "RTX 3060", 16),
            (mainZone, "A-05", .reserved, 90, "Ryzen 7 5700X", "RTX 3070", 32),
            (mainZone, "A-06", .ready, 86, "Ryzen 5 5600", "RTX 3060", 16),
            (mainZone, "A-07", .maintenance, 54, "Ryzen 5 3600", "RTX 2060", 16),
            (mainZone, "A-08", .outOfService, 28, "i5-9400F", "GTX 1660", 16),
            (vipZone, "V-01", .occupied, 97, "Ryzen 7 5800X", "RTX 4070", 32),
            (vipZone, "V-02", .ready, 93, "Ryzen 7 5800X", "RTX 4070", 32),
            (vipZone, "V-03", .ready, 91, "Ryzen 7 5800X", "RTX 4070", 32),
            (vipZone, "V-04", .reserved, 89, "Ryzen 7 5800X", "RTX 4070", 32),
            (tourneyZone, "T-01", .ready, 94, "Ryzen 7 5700X", "RTX 3070", 32),
            (tourneyZone, "T-02", .ready, 90, "Ryzen 7 5700X", "RTX 3070", 32),
            (tourneyZone, "T-03", .occupied, 85, "Ryzen 7 5700X", "RTX 3070", 32),
            (tourneyZone, "T-04", .cleaning, 78, "Ryzen 7 5700X", "RTX 3070", 32)
        ]

        var seats: [GamingSeat] = []
        for (zone, label, state, health, cpu, gpu, ram) in seatSpecs {
            seats.append(
                GamingSeat(
                    id: UUID(),
                    zoneID: zone.id,
                    label: label,
                    state: state,
                    cpu: cpu,
                    gpu: gpu,
                    ramGB: ram,
                    storage: ram >= 32 ? "2TB NVMe" : "1TB NVMe",
                    monitorModel: zone.kind == .vip ? "27\" OLED" : "27\" IPS",
                    monitorHz: zone.kind == .vip ? 240 : 144,
                    commissionedAt: daysAgo(Int.random(in: 120...400)),
                    lastMaintenanceAt: daysAgo(Int.random(in: 5...40)),
                    maintenanceIntervalDays: 30,
                    healthScore: health,
                    note: health < 50 ? "Awaiting parts" : ""
                )
            )
        }
        try await environment.seats.upsertMany(seats)

        let salt = PINHasher.makeSalt()
        let manager = Employee(
            id: UUID(),
            fullName: "Alex Morgan",
            role: .manager,
            phone: "+1 555 0101",
            hiredAt: daysAgo(400),
            hourlyRate: 22,
            isActive: true,
            note: "Floor lead",
            pinHash: PINHasher.hash(pin: "123456", salt: salt),
            pinSalt: salt
        )
        let tech = Employee(
            id: UUID(),
            fullName: "Jordan Lee",
            role: .technician,
            phone: "+1 555 0102",
            hiredAt: daysAgo(200),
            hourlyRate: 18,
            isActive: true,
            note: "",
            pinHash: nil,
            pinSalt: nil
        )
        let admin = Employee(
            id: UUID(),
            fullName: "Sam Rivera",
            role: .admin,
            phone: "+1 555 0103",
            hiredAt: daysAgo(300),
            hourlyRate: 20,
            isActive: true,
            note: "",
            pinHash: nil,
            pinSalt: nil
        )
        let referee = Employee(
            id: UUID(),
            fullName: "Casey Brooks",
            role: .referee,
            phone: "+1 555 0104",
            hiredAt: daysAgo(90),
            hourlyRate: 16,
            isActive: true,
            note: "Tournament nights",
            pinHash: nil,
            pinSalt: nil
        )
        for employee in [manager, tech, admin, referee] {
            try await environment.employees.upsert(employee)
        }

        guard let openTemplate = try await environment.checklists.activeTemplate(kind: .shiftOpen) else {
            throw NSError(domain: "MockDataSeeder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing open checklist"])
        }
        let (openRun, openResults) = try await environment.checklists.startRun(
            template: openTemplate,
            employeeID: manager.id,
            at: daysAgo(0, hours: 3)
        )
        for var result in openResults {
            result.isChecked = true
            result.checkedAt = daysAgo(0, hours: 3)
            try await environment.checklists.updateResult(result)
        }
        try await environment.checklists.completeRun(id: openRun.id, at: daysAgo(0, hours: 3))

        let shift = try await environment.shifts.open(
            employeeID: manager.id,
            openRunID: openRun.id,
            openingCash: 250,
            at: daysAgo(0, hours: 3)
        )

        if let maintenanceTemplate = try await environment.checklists.activeTemplate(kind: .maintenance) {
            _ = try await environment.checklists.startRun(
                template: maintenanceTemplate,
                employeeID: tech.id,
                at: daysAgo(0, hours: 1)
            )
        }

        let occupied = seats.filter { $0.state == .occupied }
        for seat in occupied.prefix(3) {
            _ = try await environment.sessions.start(
                seatID: seat.id,
                shiftID: shift.id,
                purpose: seat.label.hasPrefix("T") ? .tournament : .walkIn,
                note: "",
                at: daysAgo(0, hours: Int.random(in: 1...2))
            )
        }
        if let ready = seats.first(where: { $0.label == "A-02" }) {
            let session = try await environment.sessions.start(
                seatID: ready.id,
                shiftID: shift.id,
                purpose: .booking,
                at: daysAgo(0, hours: 4)
            )
            try await environment.sessions.end(id: session.id, at: daysAgo(0, hours: 2))
        }

        let headset = Equipment(
            id: UUID(),
            seatID: seats[0].id,
            zoneID: mainZone.id,
            name: "Headset A-01",
            kind: .headset,
            serialNumber: "HS-1001",
            state: .ok,
            purchasedAt: daysAgo(180),
            warrantyUntil: calendar.date(byAdding: .day, value: 180, to: now),
            price: 80,
            stateChangedAt: daysAgo(10),
            note: ""
        )
        let router = Equipment(
            id: UUID(),
            seatID: nil,
            zoneID: mainZone.id,
            name: "Core switch",
            kind: .network,
            serialNumber: "SW-220",
            state: .ok,
            purchasedAt: daysAgo(500),
            warrantyUntil: nil,
            price: 420,
            stateChangedAt: daysAgo(2),
            note: ""
        )
        let brokenGPU = Equipment(
            id: UUID(),
            seatID: seats.first(where: { $0.label == "A-08" })?.id,
            zoneID: mainZone.id,
            name: "GPU A-08",
            kind: .pc,
            serialNumber: "GPU-880",
            state: .ok,
            purchasedAt: daysAgo(700),
            warrantyUntil: nil,
            price: 250,
            stateChangedAt: daysAgo(1),
            note: "Artifacting under load"
        )
        let chair = Equipment(
            id: UUID(),
            seatID: seats.first(where: { $0.label == "V-01" })?.id,
            zoneID: vipZone.id,
            name: "VIP chair V-01",
            kind: .chair,
            serialNumber: "CH-401",
            state: .cleaning,
            purchasedAt: daysAgo(120),
            warrantyUntil: calendar.date(byAdding: .day, value: 240, to: now),
            price: 350,
            stateChangedAt: now,
            note: ""
        )
        for item in [headset, router, brokenGPU, chair] {
            try await environment.equipment.upsert(item)
        }
        _ = try await environment.equipment.changeState(
            id: brokenGPU.id,
            to: .inRepair,
            employeeID: tech.id,
            reason: "GPU artifacts and thermal shutdown",
            at: daysAgo(1)
        )
        try await environment.repairs.upsert(
            RepairRecord(
                id: UUID(),
                equipmentID: headset.id,
                seatID: seats[0].id,
                openedAt: daysAgo(12),
                closedAt: daysAgo(10),
                symptom: "Left ear muffled",
                actionTaken: "Replaced ear cushion and cable",
                partsCost: 18,
                laborCost: 20,
                performedBy: tech.fullName,
                isExternal: false
            )
        )

        try await environment.maintenance.upsert(
            MaintenanceTask(
                id: UUID(),
                title: "Deep clean A-07 dust filters",
                seatID: seats.first(where: { $0.label == "A-07" })?.id,
                equipmentID: nil,
                zoneID: mainZone.id,
                kind: .cleaning,
                status: .active,
                scheduledFor: daysAgo(1),
                completedAt: nil,
                assigneeID: tech.id,
                recurrenceDays: 30,
                checklistTemplateID: nil,
                note: "Overdue from last week"
            )
        )
        try await environment.maintenance.upsert(
            MaintenanceTask(
                id: UUID(),
                title: "Thermal paste VIP row",
                seatID: seats.first(where: { $0.label == "V-02" })?.id,
                equipmentID: nil,
                zoneID: vipZone.id,
                kind: .thermalPaste,
                status: .planned,
                scheduledFor: calendar.date(byAdding: .day, value: 2, to: now) ?? now,
                completedAt: nil,
                assigneeID: tech.id,
                recurrenceDays: 180,
                checklistTemplateID: nil,
                note: ""
            )
        )

        let inventory: [InventoryItem] = [
            .init(id: UUID(), name: "Microfiber cloths", sku: "CL-01", unit: "pack",
                  quantity: 2, minimumQuantity: 5, unitCost: 8, categoryName: "Cleaning", isConsumable: true),
            .init(id: UUID(), name: "Thermal paste", sku: "TP-02", unit: "tube",
                  quantity: 1, minimumQuantity: 3, unitCost: 12, categoryName: "Parts", isConsumable: true),
            .init(id: UUID(), name: "USB headsets", sku: "HS-10", unit: "each",
                  quantity: 12, minimumQuantity: 4, unitCost: 45, categoryName: "Peripherals", isConsumable: false),
            .init(id: UUID(), name: "Keyboard switches", sku: "KB-22", unit: "set",
                  quantity: 6, minimumQuantity: 2, unitCost: 15, categoryName: "Parts", isConsumable: true)
        ]
        for item in inventory {
            try await environment.inventory.upsert(item)
        }

        try await environment.finance.upsert(
            FinanceRecord(
                id: UUID(),
                kind: .income,
                categoryName: "Walk-in seats",
                amount: 420,
                occurredAt: daysAgo(0, hours: 1),
                shiftID: shift.id,
                tournamentID: nil,
                repairID: nil,
                note: "Afternoon sessions"
            )
        )
        try await environment.finance.upsert(
            FinanceRecord(
                id: UUID(),
                kind: .expense,
                categoryName: "Parts",
                amount: 96,
                occurredAt: daysAgo(1),
                shiftID: nil,
                tournamentID: nil,
                repairID: nil,
                note: "Headset cushions + paste"
            )
        )

        let tournament = Tournament(
            id: UUID(),
            name: "Friday Night Cup",
            discipline: "FPS",
            format: .singleElimination,
            status: .registration,
            zoneID: tourneyZone.id,
            startsAt: now.addingTimeInterval(3600),
            endsAt: nil,
            entryFee: 10,
            prizePool: 80,
            maxParticipants: 4,
            bestOf: 3,
            swissRoundCount: nil,
            refereeID: referee.id,
            isArchived: false,
            rulesDocumentID: nil
        )
        try await environment.tournaments.upsert(tournament)
        let names = ["Nova", "Pixel", "Harbor", "Quill"]
        var participantIDs: [UUID] = []
        for (index, name) in names.enumerated() {
            let participant = Participant(
                id: UUID(),
                tournamentID: tournament.id,
                displayName: name,
                teamName: "",
                contact: "",
                seedIndex: index,
                registeredAt: daysAgo(2),
                isCheckedIn: true,
                isDisqualified: false,
                placement: nil
            )
            participantIDs.append(participant.id)
            try await environment.tournaments.upsertParticipant(participant)
        }
        _ = try await environment.tournaments.generateBracket(tournamentID: tournament.id)
        var running = tournament
        running.status = .running
        try await environment.tournaments.upsert(running)
        if let matches = try? await environment.tournaments.matches(tournamentID: tournament.id),
           let first = matches.first(where: { !$0.isBye }) {
            try? await environment.tournaments.enterResult(
                matchID: first.id,
                scoreA: 2,
                scoreB: 1,
                confirmInvalidateDownstream: false
            )
        }

        try await environment.incidents.upsert(
            Incident(
                id: UUID(),
                shiftID: shift.id,
                zoneID: mainZone.id,
                seatID: seats.first(where: { $0.label == "A-07" })?.id,
                severity: .medium,
                kind: .hardware,
                occurredAt: daysAgo(0, hours: 2),
                reportedByID: tech.id,
                summary: "Seat A-07 overheating under load",
                resolution: "Moved guest to A-03; maintenance opened",
                isResolved: false,
                isArchived: false
            )
        )
        try await environment.incidents.upsert(
            Incident(
                id: UUID(),
                shiftID: shift.id,
                zoneID: vipZone.id,
                seatID: seats.first(where: { $0.label == "V-01" })?.id,
                severity: .low,
                kind: .cleanliness,
                occurredAt: daysAgo(0, hours: 1),
                reportedByID: manager.id,
                summary: "Spill on VIP desk mat",
                resolution: "Mat replaced; chair flagged for cleaning",
                isResolved: true,
                isArchived: false
            )
        )

        try await environment.notes.upsert(
            Note(
                id: UUID(),
                title: "Friday cup briefing",
                body: "Four players checked in. Keep T-row clear after 7pm. Spare headsets in back closet.",
                isPinned: true,
                createdAt: daysAgo(1),
                updatedAt: now
            )
        )

        environment.activeEmployeeID = manager.id
        environment.activeEmployee = manager
        environment.venue = venue
        environment.activeShift = shift
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.didSeedMockData)
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.onboardingCompleted)
    }
}
#endif
