import Foundation

struct VenueRepository: Sendable {
    let database: Database

    func fetch() async throws -> Venue? {
        try await database.fetchVenue()
    }

    func upsert(_ venue: Venue) async throws {
        try await database.upsertVenue(venue)
    }

    func count() async throws -> Int {
        try await database.venueCount()
    }
}

extension Database {
    func venueCount() throws -> Int {
        try scalarInt("SELECT COUNT(*) FROM venue;")
    }

    func fetchVenue() throws -> Venue? {
        try queryOne(
            """
            SELECT id, name, address, phone, opening_hour, opening_minute,
                   closing_hour, closing_minute, currency_code, seat_hourly_rate_cents
            FROM venue LIMIT 1;
            """,
            map: Self.mapVenue
        )
    }

    func upsertVenue(_ venue: Venue) throws {
        try run(
            """
            INSERT INTO venue (
                id, name, address, phone, opening_hour, opening_minute,
                closing_hour, closing_minute, currency_code, seat_hourly_rate_cents
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                address = excluded.address,
                phone = excluded.phone,
                opening_hour = excluded.opening_hour,
                opening_minute = excluded.opening_minute,
                closing_hour = excluded.closing_hour,
                closing_minute = excluded.closing_minute,
                currency_code = excluded.currency_code,
                seat_hourly_rate_cents = excluded.seat_hourly_rate_cents;
            """
        ) { statement in
            try statement.bind(venue.id, at: 1)
            try statement.bind(venue.name, at: 2)
            try statement.bind(venue.address, at: 3)
            try statement.bind(venue.phone, at: 4)
            try statement.bind(venue.openingTime.hour ?? 10, at: 5)
            try statement.bind(venue.openingTime.minute ?? 0, at: 6)
            try statement.bind(venue.closingTime.hour ?? 22, at: 7)
            try statement.bind(venue.closingTime.minute ?? 0, at: 8)
            try statement.bind(venue.currencyCode, at: 9)
            try statement.bindMoney(venue.seatHourlyRate, at: 10)
        }
    }

    static func mapVenue(_ statement: Statement) throws -> Venue {
        Venue(
            id: try statement.uuid(at: 0),
            name: try statement.string(at: 1),
            address: try statement.string(at: 2),
            phone: try statement.string(at: 3),
            openingTime: DateComponents(hour: statement.int(at: 4), minute: statement.int(at: 5)),
            closingTime: DateComponents(hour: statement.int(at: 6), minute: statement.int(at: 7)),
            currencyCode: try statement.string(at: 8),
            seatHourlyRate: statement.money(at: 9)
        )
    }
}
