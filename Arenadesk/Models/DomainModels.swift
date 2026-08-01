import Foundation

struct Venue: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var address: String
    var phone: String
    var openingTime: DateComponents
    var closingTime: DateComponents
    var currencyCode: String
    var seatHourlyRate: Decimal
}

struct Employee: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var fullName: String
    var role: EmployeeRole
    var phone: String
    var hiredAt: Date
    var hourlyRate: Decimal
    var isActive: Bool
    var note: String
    var pinHash: String?
    var pinSalt: String?
}

struct Shift: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var employeeID: UUID
    var openedAt: Date
    var closedAt: Date?
    var status: ShiftStatus
    var openChecklistRunID: UUID
    var closeChecklistRunID: UUID?
    var openingCash: Decimal
    var closingCash: Decimal?
    var seatSessionCount: Int
    var incidentCount: Int
    var note: String
    var isArchived: Bool
}

struct ChecklistTemplate: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var kind: ChecklistKind
    var version: Int
    var isActive: Bool
    var createdAt: Date
}

struct ChecklistItem: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var templateID: UUID
    var text: String
    var isMandatory: Bool
    var sortIndex: Int
}

struct ChecklistRun: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var templateID: UUID
    var templateVersion: Int
    var startedAt: Date
    var completedAt: Date?
    var employeeID: UUID
}

struct ChecklistResult: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var runID: UUID
    var itemID: UUID
    var itemText: String
    var isChecked: Bool
    var note: String
    var checkedAt: Date?
}

struct Zone: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var kind: ZoneKind
    var capacity: Int
    var sortIndex: Int
    var note: String
}

struct GamingSeat: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var zoneID: UUID
    var label: String
    var state: SeatState
    var cpu: String
    var gpu: String
    var ramGB: Int
    var storage: String
    var monitorModel: String
    var monitorHz: Int
    var commissionedAt: Date
    var lastMaintenanceAt: Date?
    var maintenanceIntervalDays: Int
    var healthScore: Int
    var note: String
}

struct Equipment: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var seatID: UUID?
    var zoneID: UUID?
    var name: String
    var kind: EquipmentKind
    var serialNumber: String
    var state: EquipmentState
    var purchasedAt: Date?
    var warrantyUntil: Date?
    var price: Decimal?
    var stateChangedAt: Date
    var note: String
}

struct EquipmentStateChange: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var equipmentID: UUID
    var fromState: EquipmentState
    var toState: EquipmentState
    var changedAt: Date
    var employeeID: UUID?
    var reason: String
}

struct MaintenanceTask: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var title: String
    var seatID: UUID?
    var equipmentID: UUID?
    var zoneID: UUID?
    var kind: MaintenanceKind
    var status: TaskStatus
    var scheduledFor: Date
    var completedAt: Date?
    var assigneeID: UUID?
    var recurrenceDays: Int?
    var checklistTemplateID: UUID?
    var note: String
}

struct RepairRecord: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var equipmentID: UUID?
    var seatID: UUID?
    var openedAt: Date
    var closedAt: Date?
    var symptom: String
    var actionTaken: String
    var partsCost: Decimal
    var laborCost: Decimal
    var performedBy: String
    var isExternal: Bool
}

struct Incident: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var shiftID: UUID?
    var zoneID: UUID?
    var seatID: UUID?
    var severity: IncidentSeverity
    var kind: IncidentKind
    var occurredAt: Date
    var reportedByID: UUID?
    var summary: String
    var resolution: String
    var isResolved: Bool
    var isArchived: Bool
}

struct SeatSession: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var seatID: UUID
    var shiftID: UUID?
    var startedAt: Date
    var endedAt: Date?
    var purpose: SessionPurpose
    var matchID: UUID?
    var note: String
}

struct Tournament: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var discipline: String
    var format: MatchFormat
    var status: TournamentStatus
    var zoneID: UUID?
    var startsAt: Date
    var endsAt: Date?
    var entryFee: Decimal
    var prizePool: Decimal
    var maxParticipants: Int
    var bestOf: Int
    var swissRoundCount: Int?
    var refereeID: UUID?
    var isArchived: Bool
    var rulesDocumentID: UUID?
}

struct Participant: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var tournamentID: UUID
    var displayName: String
    var teamName: String
    var contact: String
    var seedIndex: Int
    var registeredAt: Date
    var isCheckedIn: Bool
    var isDisqualified: Bool
    var placement: Int?
}

struct Match: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var tournamentID: UUID
    var roundIndex: Int
    var slotIndex: Int
    var participantAID: UUID?
    var participantBID: UUID?
    var scoreA: Int
    var scoreB: Int
    var winnerID: UUID?
    var isBye: Bool
    var scheduledAt: Date?
    var seatAID: UUID?
    var seatBID: UUID?
    var status: MatchStatus
    var note: String
}

struct InventoryItem: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var sku: String
    var unit: String
    var quantity: Decimal
    var minimumQuantity: Decimal
    var unitCost: Decimal
    var categoryName: String
    var isConsumable: Bool
}

struct InventoryMovement: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var itemID: UUID
    var kind: MovementKind
    var quantity: Decimal
    var occurredAt: Date
    var shiftID: UUID?
    var employeeID: UUID?
    var reason: String
}

struct FinanceRecord: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var kind: FinanceKind
    var categoryName: String
    var amount: Decimal
    var occurredAt: Date
    var shiftID: UUID?
    var tournamentID: UUID?
    var repairID: UUID?
    var note: String
}

struct Note: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var title: String
    var body: String
    var isPinned: Bool
    var createdAt: Date
    var updatedAt: Date
}

struct DocumentFile: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var title: String
    var filename: String
    var byteSize: Int64
    var typeIdentifier: String
    var importedAt: Date
    var categoryName: String
}

struct BackupManifest: Hashable, Codable, Sendable {
    var schemaVersion: Int
    var appVersion: String
    var createdAt: Date
    var rowCounts: [String: Int]
    var includesFiles: Bool
}

enum ShiftStatus: String, Codable, CaseIterable, Sendable {
    case opened, closed
}

enum ChecklistKind: String, Codable, CaseIterable, Sendable {
    case shiftOpen, shiftClose, maintenance, cleaning

    var displayName: String {
        switch self {
        case .shiftOpen: "Shift open"
        case .shiftClose: "Shift close"
        case .maintenance: "Maintenance"
        case .cleaning: "Cleaning"
        }
    }
}

enum ZoneKind: String, Codable, CaseIterable, Sendable {
    case standard, vip, console, streaming, tournament, lounge

    var displayName: String {
        switch self {
        case .standard: "Standard"
        case .vip: "VIP"
        case .console: "Console"
        case .streaming: "Streaming"
        case .tournament: "Tournament"
        case .lounge: "Lounge"
        }
    }
}

enum SeatState: String, Codable, CaseIterable, Sendable {
    case ready, occupied, reserved, cleaning, maintenance, outOfService

    var displayName: String {
        switch self {
        case .ready: "Ready"
        case .occupied: "Occupied"
        case .reserved: "Reserved"
        case .cleaning: "Cleaning"
        case .maintenance: "Maintenance"
        case .outOfService: "Out of service"
        }
    }
}

enum EquipmentState: String, Codable, CaseIterable, Sendable {
    case ok, cleaning, overheating, damaged, broken, inRepair, retired

    var displayName: String {
        switch self {
        case .ok: "OK"
        case .cleaning: "Cleaning"
        case .overheating: "Overheating"
        case .damaged: "Damaged"
        case .broken: "Broken"
        case .inRepair: "In repair"
        case .retired: "Retired"
        }
    }
}

enum EquipmentKind: String, Codable, CaseIterable, Sendable {
    case pc, monitor, keyboard, mouse, headset, chair, console, network, other

    var displayName: String {
        switch self {
        case .pc: "PC"
        case .monitor: "Monitor"
        case .keyboard: "Keyboard"
        case .mouse: "Mouse"
        case .headset: "Headset"
        case .chair: "Chair"
        case .console: "Console"
        case .network: "Network"
        case .other: "Other"
        }
    }
}

enum MaintenanceKind: String, Codable, CaseIterable, Sendable {
    case cleaning, thermalPaste, driverUpdate, diskCheck, cableCheck, inspection, other
}

enum TaskStatus: String, Codable, CaseIterable, Sendable {
    case planned, active, completed, skipped
}

enum IncidentSeverity: String, Codable, CaseIterable, Sendable {
    case low, medium, high

    var displayName: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }
}

enum IncidentKind: String, Codable, CaseIterable, Sendable {
    case hardware, network, customer, safety, theft, cleanliness, other

    var displayName: String {
        switch self {
        case .hardware: "Hardware"
        case .network: "Network"
        case .customer: "Customer"
        case .safety: "Safety"
        case .theft: "Theft"
        case .cleanliness: "Cleanliness"
        case .other: "Other"
        }
    }
}

enum SessionPurpose: String, Codable, CaseIterable, Sendable {
    case walkIn, booking, tournament, maintenance

    var displayName: String {
        switch self {
        case .walkIn: "Walk-in"
        case .booking: "Booking"
        case .tournament: "Tournament"
        case .maintenance: "Maintenance"
        }
    }
}

enum MatchFormat: String, Codable, CaseIterable, Sendable {
    case singleElimination, roundRobin, swiss

    var displayName: String {
        switch self {
        case .singleElimination: "Single elimination"
        case .roundRobin: "Round robin"
        case .swiss: "Swiss"
        }
    }
}

enum TournamentStatus: String, Codable, CaseIterable, Sendable {
    case draft, registration, running, completed, cancelled

    var displayName: String {
        switch self {
        case .draft: "Draft"
        case .registration: "Registration"
        case .running: "Running"
        case .completed: "Completed"
        case .cancelled: "Cancelled"
        }
    }
}

enum MatchStatus: String, Codable, CaseIterable, Sendable {
    case pending, ready, running, finished, walkover

    var displayName: String {
        switch self {
        case .pending: "Pending"
        case .ready: "Ready"
        case .running: "Running"
        case .finished: "Finished"
        case .walkover: "Walkover"
        }
    }
}

enum MovementKind: String, Codable, CaseIterable, Sendable {
    case receipt, issue, writeOff, correction

    var displayName: String {
        switch self {
        case .receipt: "Receipt"
        case .issue: "Issue"
        case .writeOff: "Write-off"
        case .correction: "Correction"
        }
    }
}

enum FinanceKind: String, Codable, CaseIterable, Sendable {
    case income, expense

    var displayName: String {
        switch self {
        case .income: "Income"
        case .expense: "Expense"
        }
    }
}

enum EmployeeRole: String, Codable, CaseIterable, Sendable {
    case manager, admin, technician, referee, security

    var displayName: String {
        switch self {
        case .manager: "Manager"
        case .admin: "Admin"
        case .technician: "Technician"
        case .referee: "Referee"
        case .security: "Security"
        }
    }
}

enum HealthBand: String, Sendable {
    case healthy, watch, degraded, critical

    var displayName: String {
        switch self {
        case .healthy: "Healthy"
        case .watch: "Watch"
        case .degraded: "Degraded"
        case .critical: "Critical"
        }
    }

    static func band(for score: Int) -> HealthBand {
        switch score {
        case 85...100: .healthy
        case 70...84: .watch
        case 50...69: .degraded
        default: .critical
        }
    }
}
