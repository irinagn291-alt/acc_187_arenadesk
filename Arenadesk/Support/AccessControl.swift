import Foundation

enum Capability: String, CaseIterable, Sendable {
    case openCloseShift
    case editFloor
    case changeEquipmentCloseRepairs
    case runTournaments
    case inventoryMovements
    case financeAndAnalytics
    case fileIncidents
    case backupRestoreWipe
}

enum AccessControl {
    static func allows(_ capability: Capability, role: EmployeeRole) -> Bool {
        switch capability {
        case .openCloseShift:
            return role == .manager || role == .admin
        case .editFloor:
            return role == .manager || role == .technician
        case .changeEquipmentCloseRepairs:
            return role == .manager || role == .admin || role == .technician
        case .runTournaments:
            return role == .manager || role == .admin || role == .referee
        case .inventoryMovements:
            return role == .manager || role == .admin || role == .technician
        case .financeAndAnalytics:
            return role == .manager
        case .fileIncidents:
            return true
        case .backupRestoreWipe:
            return role == .manager
        }
    }

    static func allows(_ capability: Capability, role: EmployeeRole?, managerOverride: Bool) -> Bool {
        if managerOverride { return true }
        guard let role else { return false }
        return allows(capability, role: role)
    }
}
