import Foundation

enum CSVExporter {
    static func encode(rows: [[String]]) -> Data {
        var lines: [String] = []
        for row in rows {
            lines.append(row.map(escape).joined(separator: ","))
        }
        let body = lines.joined(separator: "\r\n") + "\r\n"
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(body.utf8))
        return data
    }

    private static func escape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    static func write(filename: String, rows: [[String]]) throws -> URL {
        try AppPaths.ensureDirectories()
        let url = AppPaths.exportsDirectory.appendingPathComponent(filename)
        try encode(rows: rows).write(to: url, options: .atomic)
        return url
    }
}
