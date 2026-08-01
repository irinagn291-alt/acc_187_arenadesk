import Foundation
import SQLite3

enum DatabaseError: Error, LocalizedError, Sendable {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case bindFailed(String)
    case futureVersion(Int)
    case unexpectedNull
    case notOpen
    case constraint(String)
    case invalidScore(String)
    case needsDownstreamConfirmation
    case invalidBracket(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let m): "Failed to open database: \(m)"
        case .prepareFailed(let m): "Failed to prepare statement: \(m)"
        case .stepFailed(let m): "Failed to step statement: \(m)"
        case .bindFailed(let m): "Failed to bind value: \(m)"
        case .futureVersion(let v): "Database version \(v) is newer than this app supports."
        case .unexpectedNull: "Unexpected NULL column."
        case .notOpen: "Database is not open."
        case .constraint(let m): "Constraint failed: \(m)"
        case .invalidScore(let m): m
        case .needsDownstreamConfirmation:
            "Re-entering this result clears the matches this winner advanced to."
        case .invalidBracket(let m): "Cannot build bracket: \(m)"
        }
    }

    static func message(from db: OpaquePointer?) -> String {
        if let db, let cString = sqlite3_errmsg(db) {
            return String(cString: cString)
        }
        return "unknown error"
    }
}
