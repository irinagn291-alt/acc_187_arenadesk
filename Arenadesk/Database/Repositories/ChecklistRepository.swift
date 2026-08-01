import Foundation

struct ChecklistSeedTemplate: Decodable, Sendable {
    var name: String
    var kind: String
    var items: [ChecklistSeedItem]
}

struct ChecklistSeedItem: Decodable, Sendable {
    var text: String
    var isMandatory: Bool
}

struct ChecklistRepository: Sendable {
    let database: Database

    func seedDefaultsIfNeeded() async throws {
        try await database.seedDefaultChecklistsIfNeeded()
    }

    func activeTemplate(kind: ChecklistKind) async throws -> ChecklistTemplate? {
        try await database.fetchActiveTemplate(kind: kind)
    }

    func items(templateID: UUID) async throws -> [ChecklistItem] {
        try await database.fetchChecklistItems(templateID: templateID)
    }

    func startRun(template: ChecklistTemplate, employeeID: UUID, at date: Date = .now) async throws -> (ChecklistRun, [ChecklistResult]) {
        try await database.startChecklistRun(template: template, employeeID: employeeID, at: date)
    }

    func updateResult(_ result: ChecklistResult) async throws {
        try await database.updateChecklistResult(result)
    }

    func completeRun(id: UUID, at date: Date = .now) async throws {
        try await database.completeChecklistRun(id: id, at: date)
    }

    func results(runID: UUID) async throws -> [ChecklistResult] {
        try await database.fetchChecklistResults(runID: runID)
    }

    func fetchRun(id: UUID) async throws -> ChecklistRun? {
        try await database.fetchChecklistRun(id: id)
    }

    func allTemplates() async throws -> [ChecklistTemplate] {
        try await database.fetchTemplatesNewestFirst()
    }

    func activate(_ template: ChecklistTemplate) async throws {
        try await database.activateChecklistTemplate(template)
    }

    func duplicateAsNextVersion(_ template: ChecklistTemplate) async throws {
        try await database.duplicateChecklistTemplate(template)
    }
}

extension Database {
    func seedDefaultChecklistsIfNeeded() throws {
        guard try scalarInt("SELECT COUNT(*) FROM checklist_template;") == 0 else { return }

        let seeds = try Self.loadBundledChecklists()
        try withTransaction {
            for seed in seeds {
                guard let kind = ChecklistKind(rawValue: seed.kind) else { continue }
                let template = ChecklistTemplate(
                    id: UUID(),
                    name: seed.name,
                    kind: kind,
                    version: 1,
                    isActive: true,
                    createdAt: .now
                )
                try insertChecklistTemplate(template)
                for (index, item) in seed.items.enumerated() {
                    try insertChecklistItem(
                        ChecklistItem(
                            id: UUID(),
                            templateID: template.id,
                            text: item.text,
                            isMandatory: item.isMandatory,
                            sortIndex: index
                        )
                    )
                }
            }
        }
    }

    private static func loadBundledChecklists() throws -> [ChecklistSeedTemplate] {
        guard let url = Bundle.main.url(forResource: "DefaultChecklists", withExtension: "json") else {
            return Self.fallbackChecklists
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([ChecklistSeedTemplate].self, from: data)
    }

    private static var fallbackChecklists: [ChecklistSeedTemplate] {
        [
            ChecklistSeedTemplate(
                name: "Shift Open",
                kind: "shiftOpen",
                items: [
                    ChecklistSeedItem(text: "Count opening cash drawer", isMandatory: true),
                    ChecklistSeedItem(text: "Walk the floor and confirm seat power", isMandatory: true),
                    ChecklistSeedItem(text: "Check network uplink lights", isMandatory: true),
                    ChecklistSeedItem(text: "Review overnight incidents", isMandatory: false)
                ]
            ),
            ChecklistSeedTemplate(
                name: "Shift Close",
                kind: "shiftClose",
                items: [
                    ChecklistSeedItem(text: "End open seat sessions", isMandatory: true),
                    ChecklistSeedItem(text: "Count closing cash", isMandatory: true),
                    ChecklistSeedItem(text: "Log unresolved work for next shift", isMandatory: true),
                    ChecklistSeedItem(text: "Lock storage and admin desk", isMandatory: false)
                ]
            ),
            ChecklistSeedTemplate(
                name: "Cleaning",
                kind: "cleaning",
                items: [
                    ChecklistSeedItem(text: "Wipe desks and keyboards", isMandatory: true),
                    ChecklistSeedItem(text: "Empty trash bins", isMandatory: true)
                ]
            ),
            ChecklistSeedTemplate(
                name: "Maintenance",
                kind: "maintenance",
                items: [
                    ChecklistSeedItem(text: "Dust PC filters", isMandatory: true),
                    ChecklistSeedItem(text: "Verify temperatures under load", isMandatory: true)
                ]
            )
        ]
    }

    func insertChecklistTemplate(_ template: ChecklistTemplate) throws {
        try run(
            """
            INSERT OR REPLACE INTO checklist_template (id, name, kind, version, is_active, created_at)
            VALUES (?, ?, ?, ?, ?, ?);
            """
        ) { statement in
            try statement.bind(template.id, at: 1)
            try statement.bind(template.name, at: 2)
            try statement.bind(template.kind.rawValue, at: 3)
            try statement.bind(template.version, at: 4)
            try statement.bind(template.isActive, at: 5)
            try statement.bind(template.createdAt, at: 6)
        }
    }

    func insertChecklistItem(_ item: ChecklistItem) throws {
        try run(
            """
            INSERT OR REPLACE INTO checklist_item (id, template_id, text, is_mandatory, sort_index)
            VALUES (?, ?, ?, ?, ?);
            """
        ) { statement in
            try statement.bind(item.id, at: 1)
            try statement.bind(item.templateID, at: 2)
            try statement.bind(item.text, at: 3)
            try statement.bind(item.isMandatory, at: 4)
            try statement.bind(item.sortIndex, at: 5)
        }
    }

    private static let templateColumns = """
        SELECT id, name, kind, version, is_active, created_at FROM checklist_template
        """

    func fetchActiveTemplate(kind: ChecklistKind) throws -> ChecklistTemplate? {
        try queryOne(
            "\(Self.templateColumns) WHERE kind = ? AND is_active = 1 ORDER BY version DESC LIMIT 1;",
            bind: { try $0.bind(kind.rawValue, at: 1) },
            map: Self.mapTemplate
        )
    }

    func fetchChecklistTemplates() throws -> [ChecklistTemplate] {
        try query("\(Self.templateColumns) ORDER BY kind, version;", map: Self.mapTemplate)
    }

    func fetchTemplatesNewestFirst() throws -> [ChecklistTemplate] {
        try query("\(Self.templateColumns) ORDER BY kind, version DESC;", map: Self.mapTemplate)
    }

    func activateChecklistTemplate(_ template: ChecklistTemplate) throws {
        try withTransaction {
            try run("UPDATE checklist_template SET is_active = 0 WHERE kind = ?;") {
                try $0.bind(template.kind.rawValue, at: 1)
            }
            try run("UPDATE checklist_template SET is_active = 1 WHERE id = ?;") {
                try $0.bind(template.id, at: 1)
            }
        }
    }

    func duplicateChecklistTemplate(_ template: ChecklistTemplate) throws {
        let items = try fetchChecklistItems(templateID: template.id)
        let next = ChecklistTemplate(
            id: UUID(),
            name: template.name,
            kind: template.kind,
            version: template.version + 1,
            isActive: false,
            createdAt: .now
        )
        try withTransaction {
            try insertChecklistTemplate(next)
            for item in items {
                try insertChecklistItem(
                    ChecklistItem(
                        id: UUID(),
                        templateID: next.id,
                        text: item.text,
                        isMandatory: item.isMandatory,
                        sortIndex: item.sortIndex
                    )
                )
            }
        }
    }

    func fetchChecklistItems(templateID: UUID) throws -> [ChecklistItem] {
        try query(
            """
            SELECT id, template_id, text, is_mandatory, sort_index
            FROM checklist_item WHERE template_id = ? ORDER BY sort_index;
            """,
            bind: { try $0.bind(templateID, at: 1) },
            map: Self.mapChecklistItem
        )
    }

    func fetchAllChecklistItems() throws -> [ChecklistItem] {
        try query(
            """
            SELECT id, template_id, text, is_mandatory, sort_index
            FROM checklist_item ORDER BY template_id, sort_index;
            """,
            map: Self.mapChecklistItem
        )
    }

    static func mapChecklistItem(_ statement: Statement) throws -> ChecklistItem {
        ChecklistItem(
            id: try statement.uuid(at: 0),
            templateID: try statement.uuid(at: 1),
            text: try statement.string(at: 2),
            isMandatory: statement.bool(at: 3),
            sortIndex: statement.int(at: 4)
        )
    }

    func startChecklistRun(
        template: ChecklistTemplate,
        employeeID: UUID,
        at date: Date
    ) throws -> (ChecklistRun, [ChecklistResult]) {
        let items = try fetchChecklistItems(templateID: template.id)
        let run = ChecklistRun(
            id: UUID(),
            templateID: template.id,
            templateVersion: template.version,
            startedAt: date,
            completedAt: nil,
            employeeID: employeeID
        )
        var results: [ChecklistResult] = []
        try withTransaction {
            try insertChecklistRun(run)
            try withStatement(
                """
                INSERT INTO checklist_result (
                    id, run_id, item_id, item_text, is_checked, note, checked_at
                ) VALUES (?, ?, ?, ?, 0, '', NULL);
                """
            ) { statement in
                for item in items {
                    let result = ChecklistResult(
                        id: UUID(),
                        runID: run.id,
                        itemID: item.id,
                        itemText: item.text,
                        isChecked: false,
                        note: "",
                        checkedAt: nil
                    )
                    try statement.reset()
                    try statement.bind(result.id, at: 1)
                    try statement.bind(result.runID, at: 2)
                    try statement.bind(result.itemID, at: 3)
                    try statement.bind(result.itemText, at: 4)
                    _ = try statement.step()
                    results.append(result)
                }
            }
        }
        return (run, results)
    }

    func insertChecklistRun(_ checklistRun: ChecklistRun) throws {
        try run(
            """
            INSERT OR REPLACE INTO checklist_run (
                id, template_id, template_version, started_at, completed_at, employee_id
            ) VALUES (?, ?, ?, ?, ?, ?);
            """
        ) { statement in
            try statement.bind(checklistRun.id, at: 1)
            try statement.bind(checklistRun.templateID, at: 2)
            try statement.bind(checklistRun.templateVersion, at: 3)
            try statement.bind(checklistRun.startedAt, at: 4)
            try statement.bindOptional(checklistRun.completedAt, at: 5)
            try statement.bind(checklistRun.employeeID, at: 6)
        }
    }

    func upsertChecklistResult(_ result: ChecklistResult) throws {
        try run(
            """
            INSERT OR REPLACE INTO checklist_result (
                id, run_id, item_id, item_text, is_checked, note, checked_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?);
            """
        ) { statement in
            try statement.bind(result.id, at: 1)
            try statement.bind(result.runID, at: 2)
            try statement.bind(result.itemID, at: 3)
            try statement.bind(result.itemText, at: 4)
            try statement.bind(result.isChecked, at: 5)
            try statement.bind(result.note, at: 6)
            try statement.bindOptional(result.checkedAt, at: 7)
        }
    }

    func updateChecklistResult(_ result: ChecklistResult) throws {
        try run(
            """
            UPDATE checklist_result
            SET is_checked = ?, note = ?, checked_at = ?
            WHERE id = ?;
            """
        ) { statement in
            try statement.bind(result.isChecked, at: 1)
            try statement.bind(result.note, at: 2)
            try statement.bindOptional(result.checkedAt, at: 3)
            try statement.bind(result.id, at: 4)
        }
    }

    func completeChecklistRun(id: UUID, at date: Date) throws {
        try run("UPDATE checklist_run SET completed_at = ? WHERE id = ?;") { statement in
            try statement.bind(date, at: 1)
            try statement.bind(id, at: 2)
        }
    }

    private static let checklistResultColumns = """
        SELECT id, run_id, item_id, item_text, is_checked, note, checked_at FROM checklist_result
        """

    func fetchChecklistResults(runID: UUID) throws -> [ChecklistResult] {
        try query(
            "\(Self.checklistResultColumns) WHERE run_id = ?;",
            bind: { try $0.bind(runID, at: 1) },
            map: Self.mapChecklistResult
        )
    }

    func fetchAllChecklistResults() throws -> [ChecklistResult] {
        try query("\(Self.checklistResultColumns) ORDER BY run_id;", map: Self.mapChecklistResult)
    }

    static func mapChecklistResult(_ statement: Statement) throws -> ChecklistResult {
        ChecklistResult(
            id: try statement.uuid(at: 0),
            runID: try statement.uuid(at: 1),
            itemID: try statement.uuid(at: 2),
            itemText: try statement.string(at: 3),
            isChecked: statement.bool(at: 4),
            note: try statement.string(at: 5),
            checkedAt: statement.optionalDate(at: 6)
        )
    }

    private static let checklistRunColumns = """
        SELECT id, template_id, template_version, started_at, completed_at, employee_id
        FROM checklist_run
        """

    func fetchChecklistRun(id: UUID) throws -> ChecklistRun? {
        try queryOne(
            "\(Self.checklistRunColumns) WHERE id = ?;",
            bind: { try $0.bind(id, at: 1) },
            map: Self.mapChecklistRun
        )
    }

    func fetchAllChecklistRuns() throws -> [ChecklistRun] {
        try query("\(Self.checklistRunColumns) ORDER BY started_at;", map: Self.mapChecklistRun)
    }

    static func mapChecklistRun(_ statement: Statement) throws -> ChecklistRun {
        ChecklistRun(
            id: try statement.uuid(at: 0),
            templateID: try statement.uuid(at: 1),
            templateVersion: statement.int(at: 2),
            startedAt: statement.date(at: 3),
            completedAt: statement.optionalDate(at: 4),
            employeeID: try statement.uuid(at: 5)
        )
    }

    static func mapTemplate(_ statement: Statement) throws -> ChecklistTemplate {
        guard let kind = ChecklistKind(rawValue: try statement.string(at: 2)) else {
            throw DatabaseError.stepFailed("Invalid checklist kind")
        }
        return ChecklistTemplate(
            id: try statement.uuid(at: 0),
            name: try statement.string(at: 1),
            kind: kind,
            version: statement.int(at: 3),
            isActive: statement.bool(at: 4),
            createdAt: statement.date(at: 5)
        )
    }
}
