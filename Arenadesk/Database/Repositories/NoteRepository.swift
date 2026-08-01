import Foundation

struct NoteRepository: Sendable {
    let database: Database

    func fetchAll() async throws -> [Note] {
        try await database.fetchNotes()
    }

    func upsert(_ note: Note) async throws {
        try await database.upsertNote(note)
    }

    func delete(id: UUID) async throws {
        try await database.deleteNote(id: id)
    }
}

extension Database {
    func fetchNotes() throws -> [Note] {
        try query(
            """
            SELECT id, title, body, is_pinned, created_at, updated_at
            FROM note ORDER BY is_pinned DESC, updated_at DESC;
            """
        ) { statement in
            Note(
                id: try statement.uuid(at: 0),
                title: try statement.string(at: 1),
                body: try statement.string(at: 2),
                isPinned: statement.bool(at: 3),
                createdAt: statement.date(at: 4),
                updatedAt: statement.date(at: 5)
            )
        }
    }

    func upsertNote(_ note: Note) throws {
        try run(
            """
            INSERT INTO note (id, title, body, is_pinned, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title,
                body = excluded.body,
                is_pinned = excluded.is_pinned,
                updated_at = excluded.updated_at;
            """
        ) { statement in
            try statement.bind(note.id, at: 1)
            try statement.bind(note.title, at: 2)
            try statement.bind(note.body, at: 3)
            try statement.bind(note.isPinned, at: 4)
            try statement.bind(note.createdAt, at: 5)
            try statement.bind(note.updatedAt, at: 6)
        }
    }

    func deleteNote(id: UUID) throws {
        try run("DELETE FROM note WHERE id = ?;") { try $0.bind(id, at: 1) }
    }
}
