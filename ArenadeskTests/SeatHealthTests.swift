import Foundation
import Testing
@testable import Arenadesk

struct SeatHealthTests {
    @Test func clampsAtBothEnds() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let high = SeatHealthCalculator.score(
            for: SeatHealthFactors(
                hardwareIncidents30d: 0,
                closedRepairs90d: 0,
                seatState: .ready,
                worstEquipmentState: .ok,
                commissionedAt: now,
                lastMaintenanceAt: now,
                maintenanceIntervalDays: 30,
                now: now
            )
        )
        #expect(high == 100)

        let low = SeatHealthCalculator.score(
            for: SeatHealthFactors(
                hardwareIncidents30d: 20,
                closedRepairs90d: 20,
                seatState: .outOfService,
                worstEquipmentState: .broken,
                commissionedAt: now.addingTimeInterval(-365 * 24 * 3600),
                lastMaintenanceAt: nil,
                maintenanceIntervalDays: 1,
                now: now
            )
        )
        #expect(low == 0)
    }

    @Test func appliesStateAndEquipmentPenalties() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let score = SeatHealthCalculator.score(
            for: SeatHealthFactors(
                hardwareIncidents30d: 1,
                closedRepairs90d: 1,
                seatState: .maintenance,
                worstEquipmentState: .inRepair,
                commissionedAt: now,
                lastMaintenanceAt: now,
                maintenanceIntervalDays: 30,
                now: now
            )
        )
        #expect(score == 50)
    }

    @Test func readinessNilWhenZeroSeats() {
        #expect(ZoneMetrics.readiness(readySeats: 0, totalSeats: 0) == nil)
        #expect(ZoneMetrics.occupancy(occupiedSeats: 0, totalSeats: 0) == nil)
        #expect(ZoneMetrics.readiness(readySeats: 2, totalSeats: 4) == 50)
    }
}
