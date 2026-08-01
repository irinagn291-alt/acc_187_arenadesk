import Foundation

struct SeatHealthFactors: Hashable, Sendable {
    var hardwareIncidents30d: Int
    var closedRepairs90d: Int
    var seatState: SeatState
    var worstEquipmentState: EquipmentState?
    var commissionedAt: Date
    var lastMaintenanceAt: Date?
    var maintenanceIntervalDays: Int
    var now: Date
}

enum TimeConstants {
    static let hour: TimeInterval = 60 * 60
    static let day: TimeInterval = 24 * hour
    static let thirtyDays: TimeInterval = 30 * day
    static let ninetyDays: TimeInterval = 90 * day
}

enum SeatHealthCalculator {
    static let healthyThreshold = 50
    static let maxAgePenalty = 15

    static func score(for factors: SeatHealthFactors) -> Int {
        var score = 100
        score -= 12 * factors.hardwareIncidents30d
        score -= 8 * factors.closedRepairs90d
        score -= statePenalty(factors.seatState)
        score -= worstEquipmentPenalty(factors.worstEquipmentState)
        let months = monthsSince(factors.commissionedAt, now: factors.now)
        score -= Int(min(Double(maxAgePenalty), (0.5 * months).rounded(.down)))
        if let last = factors.lastMaintenanceAt,
           factors.now.timeIntervalSince(last) <= TimeConstants.thirtyDays {
            score += 5
        }
        let baseline = factors.lastMaintenanceAt ?? factors.commissionedAt
        let dueDate = baseline.addingTimeInterval(
            TimeInterval(factors.maintenanceIntervalDays) * TimeConstants.day
        )
        if factors.now > dueDate {
            score -= 10
        }
        return clamp(score, 0, 100)
    }

    static func clamp(_ value: Int, _ lower: Int, _ upper: Int) -> Int {
        min(upper, max(lower, value))
    }

    static func statePenalty(_ state: SeatState) -> Int {
        switch state {
        case .outOfService: return 30
        case .maintenance: return 15
        case .cleaning: return 5
        default: return 0
        }
    }

    static func worstEquipmentPenalty(_ state: EquipmentState?) -> Int {
        guard let state else { return 0 }
        switch state {
        case .broken: return 25
        case .damaged: return 15
        case .overheating: return 12
        case .inRepair: return 20
        case .cleaning: return 3
        case .ok, .retired: return 0
        }
    }

    private static func monthsSince(_ date: Date, now: Date) -> Double {
        let seconds = max(0, now.timeIntervalSince(date))
        guard seconds.isFinite else { return 0 }
        return seconds / TimeConstants.thirtyDays
    }
}

enum ZoneMetrics {
    static func readiness(readySeats: Int, totalSeats: Int) -> Double? {
        guard totalSeats > 0 else { return nil }
        return Double(readySeats) / Double(totalSeats) * 100
    }

    static func occupancy(occupiedSeats: Int, totalSeats: Int) -> Double? {
        guard totalSeats > 0 else { return nil }
        return Double(occupiedSeats) / Double(totalSeats) * 100
    }
}
