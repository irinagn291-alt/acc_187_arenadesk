import Foundation

enum MoneyFormat {
    static let fallbackCurrencyCode = "USD"

    @MainActor static var currencyCode: String {
        get {
            UserDefaults.standard.string(forKey: UserDefaultsKeys.venueCurrencyCode)
                ?? fallbackCurrencyCode
        }
        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaultsKeys.venueCurrencyCode)
        }
    }

    @MainActor
    static func currency(_ value: Decimal) -> String {
        currency(value, code: currencyCode)
    }

    @MainActor
    static func signedCurrency(_ value: Decimal) -> String {
        let sign = value < 0 ? "-" : "+"
        return sign + currency(abs(value), code: currencyCode)
    }

    static func currency(_ value: Decimal, code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.maximumFractionDigits = Money.currencyScale
        formatter.minimumFractionDigits = Money.currencyScale
        return formatter.string(from: value as NSDecimalNumber)
            ?? plain(value, fractionDigits: Money.currencyScale)
    }

    static func quantity(_ value: Decimal) -> String {
        plain(value, fractionDigits: Money.quantityFractionDigits)
    }

    static func plain(_ value: Decimal, fractionDigits: Int = Money.currencyScale) -> String {
        let formatter = decimalFormatter(fractionDigits: fractionDigits)
        return formatter.string(from: value as NSDecimalNumber) ?? "0"
    }

    static func decimal(from text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard !trimmed.isEmpty else { return nil }

        let lastDot = trimmed.lastIndex(of: ".")
        let lastComma = trimmed.lastIndex(of: ",")
        let decimalSeparator: Character?
        switch (lastDot, lastComma) {
        case (nil, nil):
            decimalSeparator = nil
        case (let dot?, nil):
            _ = dot
            decimalSeparator = "."
        case (nil, let comma?):
            _ = comma
            decimalSeparator = ","
        case (let dot?, let comma?):
            decimalSeparator = dot > comma ? "." : ","
        }

        var normalized = ""
        for character in trimmed {
            if character == decimalSeparator {
                normalized.append(".")
            } else if character == "." || character == "," {
                continue
            } else {
                normalized.append(character)
            }
        }
        guard normalized.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" || $0 == "+" }),
              normalized.contains(where: \.isNumber) else {
            return nil
        }
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func decimalFormatter(fractionDigits: Int) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.generatesDecimalNumbers = true
        formatter.maximumFractionDigits = fractionDigits
        formatter.minimumFractionDigits = 0
        return formatter
    }
}
