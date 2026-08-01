import Foundation

struct EmployeeRepository: Sendable {
    let database: Database

    func fetchAll(activeOnly: Bool = false) async throws -> [Employee] {
        try await database.fetchEmployees(activeOnly: activeOnly)
    }

    func fetch(id: UUID) async throws -> Employee? {
        try await database.fetchEmployee(id: id)
    }

    func upsert(_ employee: Employee) async throws {
        try await database.upsertEmployee(employee)
    }

    func count() async throws -> Int {
        try await database.employeeCount()
    }
}

extension Database {
    func employeeCount() throws -> Int {
        try scalarInt("SELECT COUNT(*) FROM employee;")
    }

    func fetchEmployees(activeOnly: Bool) throws -> [Employee] {
        let sql = activeOnly
            ? """
              SELECT id, full_name, role, phone, hired_at, hourly_rate_cents,
                     is_active, note, pin_hash, pin_salt
              FROM employee WHERE is_active = 1 ORDER BY full_name;
              """
            : """
              SELECT id, full_name, role, phone, hired_at, hourly_rate_cents,
                     is_active, note, pin_hash, pin_salt
              FROM employee ORDER BY full_name;
              """
        return try query(sql, map: Self.mapEmployee)
    }

    func fetchEmployee(id: UUID) throws -> Employee? {
        try queryOne(
            """
            SELECT id, full_name, role, phone, hired_at, hourly_rate_cents,
                   is_active, note, pin_hash, pin_salt
            FROM employee WHERE id = ?;
            """,
            bind: { try $0.bind(id, at: 1) },
            map: Self.mapEmployee
        )
    }

    func upsertEmployee(_ employee: Employee) throws {
        try run(
            """
            INSERT INTO employee (
                id, full_name, role, phone, hired_at, hourly_rate_cents,
                is_active, note, pin_hash, pin_salt
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                full_name = excluded.full_name,
                role = excluded.role,
                phone = excluded.phone,
                hired_at = excluded.hired_at,
                hourly_rate_cents = excluded.hourly_rate_cents,
                is_active = excluded.is_active,
                note = excluded.note,
                pin_hash = excluded.pin_hash,
                pin_salt = excluded.pin_salt;
            """
        ) { statement in
            try statement.bind(employee.id, at: 1)
            try statement.bind(employee.fullName, at: 2)
            try statement.bind(employee.role.rawValue, at: 3)
            try statement.bind(employee.phone, at: 4)
            try statement.bind(employee.hiredAt, at: 5)
            try statement.bindMoney(employee.hourlyRate, at: 6)
            try statement.bind(employee.isActive, at: 7)
            try statement.bind(employee.note, at: 8)
            try statement.bindOptional(employee.pinHash, at: 9)
            try statement.bindOptional(employee.pinSalt, at: 10)
        }
    }

    static func mapEmployee(_ statement: Statement) throws -> Employee {
        guard let role = EmployeeRole(rawValue: try statement.string(at: 2)) else {
            throw DatabaseError.stepFailed("Invalid employee role")
        }
        return Employee(
            id: try statement.uuid(at: 0),
            fullName: try statement.string(at: 1),
            role: role,
            phone: try statement.string(at: 3),
            hiredAt: statement.date(at: 4),
            hourlyRate: statement.money(at: 5),
            isActive: statement.bool(at: 6),
            note: try statement.string(at: 7),
            pinHash: statement.optionalString(at: 8),
            pinSalt: statement.optionalString(at: 9)
        )
    }
}
