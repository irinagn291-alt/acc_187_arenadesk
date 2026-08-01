import Foundation
import Testing
@testable import Arenadesk

struct BackupCSVTests {
    @Test func csvHasUtf8BomAndRfc4180Quotes() {
        let data = CSVExporter.encode(rows: [
            ["a", "b,c", "say \"hi\""]
        ])
        #expect(data.starts(with: [0xEF, 0xBB, 0xBF]))
        let text = String(data: data.dropFirst(3), encoding: .utf8) ?? ""
        #expect(text.contains("\"b,c\""))
        #expect(text.contains("\"say \"\"hi\"\"\""))
    }

    @Test func backupRefusesNewerSchema() async throws {
        let db = try Database(inMemory: true)
        try await Migrator.migrate(db)
        let service = BackupService(database: db)
        let payload = BackupPayload(
            manifest: BackupManifest(
                schemaVersion: Migrator.currentVersion + 3,
                appVersion: "9.0",
                createdAt: .now,
                rowCounts: [:],
                includesFiles: false
            )
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("future.json")
        try encoder.encode(payload).write(to: url)
        await #expect(throws: BackupError.self) {
            try await service.restore(from: url, typedVenueName: "X", currentVenueName: "X")
        }
    }

    @Test func integrityCheckReturnsOk() async throws {
        let db = try Database(inMemory: true)
        try await Migrator.migrate(db)
        let result = try await db.integrityCheck()
        #expect(result == "ok")
    }
}
