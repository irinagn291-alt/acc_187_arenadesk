import Foundation
import UniformTypeIdentifiers

struct DocumentRepository: Sendable {
    let database: Database

    func fetchAll() async throws -> [DocumentFile] {
        try await database.fetchDocuments()
    }

    func importFile(from sourceURL: URL, title: String, categoryName: String) async throws -> DocumentFile {
        try await database.importDocument(from: sourceURL, title: title, categoryName: categoryName)
    }

    func delete(id: UUID) async throws {
        try await database.deleteDocument(id: id)
    }

    func fileURL(for document: DocumentFile) -> URL {
        AppPaths.filesDirectory.appendingPathComponent(document.filename)
    }
}

extension Database {
    func fetchDocuments() throws -> [DocumentFile] {
        try query(
            """
            SELECT id, title, filename, byte_size, type_identifier, imported_at, category_name
            FROM document_file ORDER BY imported_at DESC;
            """,
            map: Self.mapDocument
        )
    }

    static func mapDocument(_ statement: Statement) throws -> DocumentFile {
        DocumentFile(
            id: try statement.uuid(at: 0),
            title: try statement.string(at: 1),
            filename: try statement.string(at: 2),
            byteSize: statement.int64(at: 3),
            typeIdentifier: try statement.string(at: 4),
            importedAt: statement.date(at: 5),
            categoryName: try statement.string(at: 6)
        )
    }

    func upsertDocument(_ doc: DocumentFile) throws {
        try run(
            """
            INSERT INTO document_file (
                id, title, filename, byte_size, type_identifier, imported_at, category_name
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title,
                filename = excluded.filename,
                byte_size = excluded.byte_size,
                type_identifier = excluded.type_identifier,
                imported_at = excluded.imported_at,
                category_name = excluded.category_name;
            """
        ) { statement in
            try statement.bind(doc.id, at: 1)
            try statement.bind(doc.title, at: 2)
            try statement.bind(doc.filename, at: 3)
            try statement.bind(doc.byteSize, at: 4)
            try statement.bind(doc.typeIdentifier, at: 5)
            try statement.bind(doc.importedAt, at: 6)
            try statement.bind(doc.categoryName, at: 7)
        }
    }

    func importDocument(from sourceURL: URL, title: String, categoryName: String) throws -> DocumentFile {
        try AppPaths.ensureDirectories()
        let id = UUID()
        let ext = sourceURL.pathExtension
        let filename = ext.isEmpty ? id.uuidString.lowercased() : "\(id.uuidString.lowercased()).\(ext)"
        let dest = AppPaths.filesDirectory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: sourceURL, to: dest)
        let attrs = try FileManager.default.attributesOfItem(atPath: dest.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let typeID = UTType(filenameExtension: ext)?.identifier ?? "public.data"
        let doc = DocumentFile(
            id: id,
            title: title.isEmpty ? sourceURL.deletingPathExtension().lastPathComponent : title,
            filename: filename,
            byteSize: size,
            typeIdentifier: typeID,
            importedAt: .now,
            categoryName: categoryName
        )
        try upsertDocument(doc)
        return doc
    }

    func deleteDocument(id: UUID) throws {
        guard let doc = try fetchDocuments().first(where: { $0.id == id }) else { return }
        let url = AppPaths.filesDirectory.appendingPathComponent(doc.filename)
        try? FileManager.default.removeItem(at: url)
        try run("DELETE FROM document_file WHERE id = ?;") { try $0.bind(id, at: 1) }
    }
}
