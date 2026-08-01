import Foundation
import Testing
@testable import Arenadesk

struct MoneyTests {
    @Test func moneyRoundTripPreservesCents() throws {
        let samples = [
            "0",
            "0.01",
            "1.00",
            "12.34",
            "99.99",
            "1234567.89",
            "0.10",
            "19.95"
        ].compactMap { Decimal(string: $0) }

        #expect(samples.count == 8)
        for sample in samples {
            let units = try Money.minorUnits(from: sample)
            let restored = Money.decimal(fromMinorUnits: units)
            #expect(restored == sample)
        }
    }

    @Test func moneyNeverUsesFloatingBinaryArtifacts() throws {
        let tenth = try #require(Decimal(string: "0.1"))
        let fifth = try #require(Decimal(string: "0.2"))
        let value = tenth + fifth
        let units = try Money.minorUnits(from: value)
        #expect(units == 30)
        #expect(Money.decimal(fromMinorUnits: units) == Decimal(string: "0.30"))
    }

    @Test func minorUnitsRejectsValueBeyondInt64() {
        let tooLarge = Money.maxMajorUnits * 10
        #expect(throws: MoneyError.self) { _ = try Money.minorUnits(from: tooLarge) }
        #expect(throws: MoneyError.self) { _ = try Money.minorUnits(from: -tooLarge) }
    }

    @Test func minorUnitsRejectsNotANumber() {
        #expect(throws: MoneyError.self) { _ = try Money.minorUnits(from: Decimal.nan) }
    }

    @Test func clampedMinorUnitsSaturatesInsteadOfThrowing() {
        #expect(Money.clampedMinorUnits(from: Money.maxMajorUnits * 10) == Int64.max)
        #expect(Money.clampedMinorUnits(from: -Money.maxMajorUnits * 10) == Int64.min)
    }

    @Test func quantityUnitsKeepsMilliPrecisionAndSign() throws {
        #expect(try Money.quantityUnits(from: Decimal(string: "1.234") ?? 0) == 1234)
        #expect(try Money.quantityUnits(from: Decimal(string: "-0.500") ?? 0) == -500)
    }

    @Test func decimalParsingHonoursTheLocaleSeparator() {
        #expect(MoneyFormat.decimal(from: "12,50") == Decimal(string: "12.50"))
        #expect(MoneyFormat.decimal(from: "12.50") == Decimal(string: "12.50"))
        #expect(MoneyFormat.decimal(from: "") == nil)
        #expect(MoneyFormat.decimal(from: "abc") == nil)
    }
}
