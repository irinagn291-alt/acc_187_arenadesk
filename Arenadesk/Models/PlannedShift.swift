import Foundation

struct PlannedShift: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var employeeID: UUID
    var startsAt: Date
    var endsAt: Date
    var note: String
}
