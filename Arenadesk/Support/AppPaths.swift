import Foundation

enum AppPaths {
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var filesDirectory: URL {
        documents.appendingPathComponent("Files", isDirectory: true)
    }

    static var backupsDirectory: URL {
        documents.appendingPathComponent("Backups", isDirectory: true)
    }

    static var exportsDirectory: URL {
        documents.appendingPathComponent("Exports", isDirectory: true)
    }

    static func ensureDirectories() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: filesDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: exportsDirectory, withIntermediateDirectories: true)
    }
}
