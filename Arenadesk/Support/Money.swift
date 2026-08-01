import Foundation

enum MoneyError: Error, LocalizedError, Sendable {
    case notANumber
    case outOfRange(Decimal)

    var errorDescription: String? {
        switch self {
        case .notANumber:
            "The amount is not a valid number."
        case .outOfRange(let value):
            "The amount \(value) is outside the supported range."
        }
    }
}

enum Money {
    static let scale: Int64 = 100
    static let quantityScale: Int64 = 1000
    static let currencyScale = 2
    static let quantityFractionDigits = 3

    static let maxMajorUnits = Decimal(Int64.max) / Decimal(scale)
    static let maxQuantity = Decimal(Int64.max) / Decimal(quantityScale)

    static func minorUnits(from decimal: Decimal) throws -> Int64 {
        try scaled(decimal, fractionDigits: 2, scale: scale, limit: maxMajorUnits)
    }

    static func decimal(fromMinorUnits units: Int64) -> Decimal {
        Decimal(units) / Decimal(scale)
    }

    static func quantityUnits(from decimal: Decimal) throws -> Int64 {
        try scaled(decimal, fractionDigits: 3, scale: quantityScale, limit: maxQuantity)
    }

    static func decimal(fromQuantityUnits units: Int64) -> Decimal {
        Decimal(units) / Decimal(quantityScale)
    }

    static func clampedMinorUnits(from decimal: Decimal) -> Int64 {
        (try? minorUnits(from: decimal)) ?? (decimal < 0 ? Int64.min : Int64.max)
    }

    private static func scaled(
        _ decimal: Decimal,
        fractionDigits: Int16,
        scale: Int64,
        limit: Decimal
    ) throws -> Int64 {
        guard !decimal.isNaN else { throw MoneyError.notANumber }
        guard decimal.magnitude <= limit else { throw MoneyError.outOfRange(decimal) }

        var value = decimal
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, Int(fractionDigits), .plain)

        let number = NSDecimalNumber(decimal: rounded * Decimal(scale))
        guard !number.decimalValue.isNaN else { throw MoneyError.notANumber }
        let result = number.int64Value
        guard Decimal(result) / Decimal(scale) == rounded else {
            throw MoneyError.outOfRange(decimal)
        }
        return result
    }
}
