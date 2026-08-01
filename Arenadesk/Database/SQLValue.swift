import Foundation

enum SQLValue: Hashable, Sendable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)
}

struct Row: Sendable {
    private let columns: [String: SQLValue]

    init(_ columns: [String: SQLValue]) {
        self.columns = columns
    }

    subscript(name: String) -> SQLValue {
        columns[name] ?? .null
    }

    func int64(_ name: String) throws -> Int64 {
        guard case .integer(let value) = self[name] else { throw DatabaseError.unexpectedNull }
        return value
    }

    func int(_ name: String) throws -> Int {
        Int(try int64(name))
    }

    func optionalInt64(_ name: String) -> Int64? {
        if case .integer(let value) = self[name] { return value }
        return nil
    }

    func string(_ name: String) throws -> String {
        guard case .text(let value) = self[name] else { throw DatabaseError.unexpectedNull }
        return value
    }

    func optionalString(_ name: String) -> String? {
        if case .text(let value) = self[name] { return value }
        return nil
    }

    func double(_ name: String) throws -> Double {
        switch self[name] {
        case .real(let value): return value
        case .integer(let value): return Double(value)
        default: throw DatabaseError.unexpectedNull
        }
    }

    func bool(_ name: String) throws -> Bool {
        try int64(name) != 0
    }

    func date(_ name: String) throws -> Date {
        Date(timeIntervalSince1970: TimeInterval(try int64(name)))
    }

    func optionalDate(_ name: String) -> Date? {
        guard let seconds = optionalInt64(name) else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    func uuid(_ name: String) throws -> UUID {
        let string = try string(name)
        guard let uuid = UUID(uuidString: string) else {
            throw DatabaseError.stepFailed("Invalid UUID: \(string)")
        }
        return uuid
    }

    func optionalUUID(_ name: String) -> UUID? {
        guard let string = optionalString(name) else { return nil }
        return UUID(uuidString: string)
    }

    func decimalMoney(_ name: String) throws -> Decimal {
        Money.decimal(fromMinorUnits: try int64(name))
    }

    func optionalDecimalMoney(_ name: String) -> Decimal? {
        guard let units = optionalInt64(name) else { return nil }
        return Money.decimal(fromMinorUnits: units)
    }
}
