import Foundation

struct DataExportService: Sendable {
    let database: Database

    func exportFinanceCSV() async throws -> URL {
        let records = try await database.fetchFinanceRecords(
            from: Date(timeIntervalSince1970: 0),
            to: Date()
        )
        var rows = [["id", "kind", "category", "amount", "occurred_at", "note"]]
        for r in records {
            rows.append([
                r.id.uuidString.lowercased(),
                r.kind.rawValue,
                r.categoryName,
                "\(r.amount)",
                ISO8601DateFormatter().string(from: r.occurredAt),
                r.note
            ])
        }
        return try CSVExporter.write(filename: "finance.csv", rows: rows)
    }

    func exportInventoryMovementsCSV() async throws -> URL {
        let items = try await database.fetchInventoryItems()
        var rows = [["id", "item", "kind", "quantity", "occurred_at", "reason"]]
        for item in items {
            let movements = try await database.fetchInventoryMovements(itemID: item.id)
            for m in movements {
                rows.append([
                    m.id.uuidString.lowercased(),
                    item.name,
                    m.kind.rawValue,
                    "\(m.quantity)",
                    ISO8601DateFormatter().string(from: m.occurredAt),
                    m.reason
                ])
            }
        }
        return try CSVExporter.write(filename: "inventory-movements.csv", rows: rows)
    }

    func exportShiftsCSV() async throws -> URL {
        let shifts = try await database.fetchRecentShifts(limit: 10_000)
        var rows = [["id", "employee_id", "opened_at", "closed_at", "status", "opening_cash", "closing_cash", "sessions", "incidents"]]
        for s in shifts {
            rows.append([
                s.id.uuidString.lowercased(),
                s.employeeID.uuidString.lowercased(),
                ISO8601DateFormatter().string(from: s.openedAt),
                s.closedAt.map { ISO8601DateFormatter().string(from: $0) } ?? "",
                s.status.rawValue,
                "\(s.openingCash)",
                s.closingCash.map { "\($0)" } ?? "",
                "\(s.seatSessionCount)",
                "\(s.incidentCount)"
            ])
        }
        return try CSVExporter.write(filename: "shifts.csv", rows: rows)
    }

    func exportRepairsCSV() async throws -> URL {
        let repairs = try await database.fetchRepairs(openOnly: false)
        var rows = [["id", "symptom", "opened_at", "closed_at", "parts", "labor", "performed_by"]]
        for r in repairs {
            rows.append([
                r.id.uuidString.lowercased(),
                r.symptom,
                ISO8601DateFormatter().string(from: r.openedAt),
                r.closedAt.map { ISO8601DateFormatter().string(from: $0) } ?? "",
                "\(r.partsCost)",
                "\(r.laborCost)",
                r.performedBy
            ])
        }
        return try CSVExporter.write(filename: "repairs.csv", rows: rows)
    }

    func exportTournamentStandingsCSV(tournamentID: UUID) async throws -> URL {
        let standings = try await database.tournamentStandings(tournamentID: tournamentID)
        var rows = [["seed", "name", "points", "wins", "map_diff", "buchholz", "median_buchholz"]]
        for s in standings {
            rows.append([
                "\(s.seedIndex)",
                s.displayName,
                "\(s.points)",
                "\(s.wins)",
                "\(s.mapDifference)",
                "\(s.buchholz)",
                "\(s.medianBuchholz)"
            ])
        }
        return try CSVExporter.write(filename: "standings-\(tournamentID.uuidString.prefix(8)).csv", rows: rows)
    }
}
