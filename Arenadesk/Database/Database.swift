import Foundation
import SQLite3

actor Database {
    nonisolated(unsafe) private var handle: OpaquePointer?
    nonisolated(unsafe) private var openedPath: String?
    private var transactionDepth = 0
    private var savepointCounter = 0

    static let busyRetryLimit = 5
    static let busyRetryBaseDelay: useconds_t = 10_000

    static func applicationSupportPath(fileName: String = "arenadesk.sqlite") throws -> String {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = root.appendingPathComponent("Arenadesk", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName).path
    }

    init(path: String) throws {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let code = sqlite3_open_v2(path, &db, flags, nil)
        guard code == SQLITE_OK, let db else {
            throw DatabaseError.openFailed(DatabaseError.message(from: db))
        }
        handle = db
        openedPath = path
        try Self.applyPragmas(db)
    }

    init(inMemory: Bool) throws {
        precondition(inMemory)
        try self.init(path: ":memory:")
    }

    deinit {
        if let handle {
            sqlite3_close_v2(handle)
        }
    }

    private static func applyPragmas(_ db: OpaquePointer) throws {
        try exec(db, "PRAGMA journal_mode = WAL;")
        try exec(db, "PRAGMA foreign_keys = ON;")
        try exec(db, "PRAGMA busy_timeout = 5000;")
    }

    private static func exec(_ db: OpaquePointer, _ sql: String) throws {
        var attempt = 0
        while true {
            var errorMessage: UnsafeMutablePointer<CChar>?
            let code = sqlite3_exec(db, sql, nil, nil, &errorMessage)
            if code == SQLITE_OK {
                sqlite3_free(errorMessage)
                return
            }
            let message = errorMessage.map { String(cString: $0) } ?? DatabaseError.message(from: db)
            sqlite3_free(errorMessage)
            guard (code == SQLITE_BUSY || code == SQLITE_LOCKED), attempt < busyRetryLimit else {
                if code == SQLITE_CONSTRAINT { throw DatabaseError.constraint(message) }
                throw DatabaseError.stepFailed(message)
            }
            usleep(busyRetryBaseDelay << attempt)
            attempt += 1
        }
    }

    private func db() throws -> OpaquePointer {
        guard let handle else { throw DatabaseError.notOpen }
        return handle
    }

    func execute(_ sql: String) throws {
        try Self.exec(try db(), sql)
    }

    private func prepare(_ sql: String) throws -> Statement {
        try Statement(database: try db(), sql: sql)
    }

    func withStatement<T>(_ sql: String, _ body: (Statement) throws -> T) throws -> T {
        let statement = try prepare(sql)
        defer { statement.finalize() }
        return try body(statement)
    }

    func run(_ sql: String, _ bind: (Statement) throws -> Void = { _ in }) throws {
        try withStatement(sql) { statement in
            try bind(statement)
            _ = try statement.step()
        }
    }

    func query<T>(
        _ sql: String,
        bind: (Statement) throws -> Void = { _ in },
        map: (Statement) throws -> T
    ) throws -> [T] {
        try withStatement(sql) { statement in
            try bind(statement)
            var rows: [T] = []
            while try statement.step() {
                rows.append(try map(statement))
            }
            return rows
        }
    }

    func queryOne<T>(
        _ sql: String,
        bind: (Statement) throws -> Void = { _ in },
        map: (Statement) throws -> T
    ) throws -> T? {
        try withStatement(sql) { statement in
            try bind(statement)
            guard try statement.step() else { return nil }
            return try map(statement)
        }
    }

    func scalarInt(_ sql: String, _ bind: (Statement) throws -> Void = { _ in }) throws -> Int {
        try queryOne(sql, bind: bind) { $0.int(at: 0) } ?? 0
    }

    func scalarInt64(_ sql: String, _ bind: (Statement) throws -> Void = { _ in }) throws -> Int64 {
        try queryOne(sql, bind: bind) { $0.int64(at: 0) } ?? 0
    }

    func scalarDouble(_ sql: String, _ bind: (Statement) throws -> Void = { _ in }) throws -> Double {
        try queryOne(sql, bind: bind) { $0.double(at: 0) } ?? 0
    }

    func userVersion() throws -> Int {
        try scalarInt("PRAGMA user_version;")
    }

    func setUserVersion(_ version: Int) throws {
        guard version >= 0, version <= Int(Int32.max) else {
            throw DatabaseError.stepFailed("Invalid schema version \(version)")
        }
        try execute("PRAGMA user_version = \(version);")
    }

    func withTransaction<T>(_ body: () throws -> T) throws -> T {
        if transactionDepth == 0 {
            try execute("BEGIN IMMEDIATE;")
            transactionDepth = 1
            do {
                let result = try body()
                try execute("COMMIT;")
                transactionDepth = 0
                return result
            } catch {
                transactionDepth = 0
                try? execute("ROLLBACK;")
                throw error
            }
        }

        savepointCounter += 1
        let name = "sp_\(savepointCounter)"
        try execute("SAVEPOINT \(name);")
        transactionDepth += 1
        do {
            let result = try body()
            try execute("RELEASE SAVEPOINT \(name);")
            transactionDepth -= 1
            return result
        } catch {
            transactionDepth -= 1
            try? execute("ROLLBACK TO SAVEPOINT \(name);")
            try? execute("RELEASE SAVEPOINT \(name);")
            throw error
        }
    }

    nonisolated func fileSize() -> Int64 {
        guard let path = openedPath, path != ":memory:" else { return 0 }
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }
}
