import Foundation

enum Migrator {
    static let currentVersion = 2

    static func migrate(_ database: Database) async throws {
        let version = try await database.userVersion()
        if version > currentVersion {
            throw DatabaseError.futureVersion(version)
        }
        if version < 1 {
            try await database.applySchemaV1()
        }
        if version < 2 {
            try await database.applySchemaV2()
        }
    }
}

extension Database {
    func applySchemaV1() throws {
        try applySchema(SchemaV1.sql, version: 1)
    }

    func applySchemaV2() throws {
        try applySchema(SchemaV2.sql, version: 2)
    }

    private func applySchema(_ sql: String, version: Int, at date: Date = .now) throws {
        try withTransaction {
            try execute(sql)
            try run("INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?);") {
                try $0.bind(version, at: 1)
                try $0.bind(date, at: 2)
            }
            try setUserVersion(version)
        }
    }
}

enum SchemaV2 {
    static let sql = """
    CREATE TABLE IF NOT EXISTS planned_shift (
        id TEXT PRIMARY KEY NOT NULL,
        employee_id TEXT NOT NULL REFERENCES employee(id) ON DELETE CASCADE,
        starts_at INTEGER NOT NULL,
        ends_at INTEGER NOT NULL,
        note TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_planned_shift_employee ON planned_shift(employee_id);
    CREATE INDEX IF NOT EXISTS idx_planned_shift_starts ON planned_shift(starts_at);
    """
}

enum SchemaV1 {
    static let sql = """
    CREATE TABLE IF NOT EXISTS schema_migrations (
        version INTEGER PRIMARY KEY NOT NULL,
        applied_at INTEGER NOT NULL
    );

    CREATE TABLE IF NOT EXISTS venue (
        id TEXT PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        address TEXT NOT NULL,
        phone TEXT NOT NULL,
        opening_hour INTEGER NOT NULL,
        opening_minute INTEGER NOT NULL,
        closing_hour INTEGER NOT NULL,
        closing_minute INTEGER NOT NULL,
        currency_code TEXT NOT NULL,
        seat_hourly_rate_cents INTEGER NOT NULL
    );

    CREATE TABLE IF NOT EXISTS employee (
        id TEXT PRIMARY KEY NOT NULL,
        full_name TEXT NOT NULL,
        role TEXT NOT NULL,
        phone TEXT NOT NULL,
        hired_at INTEGER NOT NULL,
        hourly_rate_cents INTEGER NOT NULL,
        is_active INTEGER NOT NULL,
        note TEXT NOT NULL,
        pin_hash TEXT,
        pin_salt TEXT
    );

    CREATE TABLE IF NOT EXISTS checklist_template (
        id TEXT PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        kind TEXT NOT NULL,
        version INTEGER NOT NULL,
        is_active INTEGER NOT NULL,
        created_at INTEGER NOT NULL
    );

    CREATE TABLE IF NOT EXISTS checklist_item (
        id TEXT PRIMARY KEY NOT NULL,
        template_id TEXT NOT NULL REFERENCES checklist_template(id) ON DELETE CASCADE,
        text TEXT NOT NULL,
        is_mandatory INTEGER NOT NULL,
        sort_index INTEGER NOT NULL
    );

    CREATE TABLE IF NOT EXISTS checklist_run (
        id TEXT PRIMARY KEY NOT NULL,
        template_id TEXT NOT NULL REFERENCES checklist_template(id),
        template_version INTEGER NOT NULL,
        started_at INTEGER NOT NULL,
        completed_at INTEGER,
        employee_id TEXT NOT NULL REFERENCES employee(id)
    );

    CREATE TABLE IF NOT EXISTS checklist_result (
        id TEXT PRIMARY KEY NOT NULL,
        run_id TEXT NOT NULL REFERENCES checklist_run(id) ON DELETE CASCADE,
        item_id TEXT NOT NULL,
        item_text TEXT NOT NULL,
        is_checked INTEGER NOT NULL,
        note TEXT NOT NULL,
        checked_at INTEGER
    );

    CREATE TABLE IF NOT EXISTS shift (
        id TEXT PRIMARY KEY NOT NULL,
        employee_id TEXT NOT NULL REFERENCES employee(id),
        opened_at INTEGER NOT NULL,
        closed_at INTEGER,
        status TEXT NOT NULL,
        open_checklist_run_id TEXT NOT NULL REFERENCES checklist_run(id),
        close_checklist_run_id TEXT REFERENCES checklist_run(id),
        opening_cash_cents INTEGER NOT NULL,
        closing_cash_cents INTEGER,
        seat_session_count INTEGER NOT NULL DEFAULT 0,
        incident_count INTEGER NOT NULL DEFAULT 0,
        note TEXT NOT NULL,
        is_archived INTEGER NOT NULL DEFAULT 0
    );

    CREATE TABLE IF NOT EXISTS zone (
        id TEXT PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        kind TEXT NOT NULL,
        capacity INTEGER NOT NULL,
        sort_index INTEGER NOT NULL,
        note TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS gaming_seat (
        id TEXT PRIMARY KEY NOT NULL,
        zone_id TEXT NOT NULL REFERENCES zone(id) ON DELETE CASCADE,
        label TEXT NOT NULL,
        state TEXT NOT NULL,
        cpu TEXT NOT NULL,
        gpu TEXT NOT NULL,
        ram_gb INTEGER NOT NULL,
        storage TEXT NOT NULL,
        monitor_model TEXT NOT NULL,
        monitor_hz INTEGER NOT NULL,
        commissioned_at INTEGER NOT NULL,
        last_maintenance_at INTEGER,
        maintenance_interval_days INTEGER NOT NULL,
        health_score INTEGER NOT NULL,
        note TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS equipment (
        id TEXT PRIMARY KEY NOT NULL,
        seat_id TEXT REFERENCES gaming_seat(id) ON DELETE SET NULL,
        zone_id TEXT REFERENCES zone(id) ON DELETE SET NULL,
        name TEXT NOT NULL,
        kind TEXT NOT NULL,
        serial_number TEXT NOT NULL,
        state TEXT NOT NULL,
        purchased_at INTEGER,
        warranty_until INTEGER,
        price_cents INTEGER,
        state_changed_at INTEGER NOT NULL,
        note TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS equipment_state_change (
        id TEXT PRIMARY KEY NOT NULL,
        equipment_id TEXT NOT NULL REFERENCES equipment(id) ON DELETE CASCADE,
        from_state TEXT NOT NULL,
        to_state TEXT NOT NULL,
        changed_at INTEGER NOT NULL,
        employee_id TEXT REFERENCES employee(id),
        reason TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS maintenance_task (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL,
        seat_id TEXT REFERENCES gaming_seat(id) ON DELETE SET NULL,
        equipment_id TEXT REFERENCES equipment(id) ON DELETE SET NULL,
        zone_id TEXT REFERENCES zone(id) ON DELETE SET NULL,
        kind TEXT NOT NULL,
        status TEXT NOT NULL,
        scheduled_for INTEGER NOT NULL,
        completed_at INTEGER,
        assignee_id TEXT REFERENCES employee(id),
        recurrence_days INTEGER,
        checklist_template_id TEXT REFERENCES checklist_template(id),
        note TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS repair_record (
        id TEXT PRIMARY KEY NOT NULL,
        equipment_id TEXT REFERENCES equipment(id) ON DELETE SET NULL,
        seat_id TEXT REFERENCES gaming_seat(id) ON DELETE SET NULL,
        opened_at INTEGER NOT NULL,
        closed_at INTEGER,
        symptom TEXT NOT NULL,
        action_taken TEXT NOT NULL,
        parts_cost_cents INTEGER NOT NULL,
        labor_cost_cents INTEGER NOT NULL,
        performed_by TEXT NOT NULL,
        is_external INTEGER NOT NULL
    );

    CREATE TABLE IF NOT EXISTS incident (
        id TEXT PRIMARY KEY NOT NULL,
        shift_id TEXT REFERENCES shift(id) ON DELETE SET NULL,
        zone_id TEXT REFERENCES zone(id) ON DELETE SET NULL,
        seat_id TEXT REFERENCES gaming_seat(id) ON DELETE SET NULL,
        severity TEXT NOT NULL,
        kind TEXT NOT NULL,
        occurred_at INTEGER NOT NULL,
        reported_by_id TEXT REFERENCES employee(id),
        summary TEXT NOT NULL,
        resolution TEXT NOT NULL,
        is_resolved INTEGER NOT NULL,
        is_archived INTEGER NOT NULL DEFAULT 0
    );

    CREATE TABLE IF NOT EXISTS seat_session (
        id TEXT PRIMARY KEY NOT NULL,
        seat_id TEXT NOT NULL REFERENCES gaming_seat(id) ON DELETE CASCADE,
        shift_id TEXT REFERENCES shift(id) ON DELETE SET NULL,
        started_at INTEGER NOT NULL,
        ended_at INTEGER,
        purpose TEXT NOT NULL,
        match_id TEXT,
        note TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS tournament (
        id TEXT PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        discipline TEXT NOT NULL,
        format TEXT NOT NULL,
        status TEXT NOT NULL,
        zone_id TEXT REFERENCES zone(id) ON DELETE SET NULL,
        starts_at INTEGER NOT NULL,
        ends_at INTEGER,
        entry_fee_cents INTEGER NOT NULL,
        prize_pool_cents INTEGER NOT NULL,
        max_participants INTEGER NOT NULL,
        best_of INTEGER NOT NULL,
        swiss_round_count INTEGER,
        referee_id TEXT REFERENCES employee(id),
        is_archived INTEGER NOT NULL DEFAULT 0,
        rules_document_id TEXT
    );

    CREATE TABLE IF NOT EXISTS participant (
        id TEXT PRIMARY KEY NOT NULL,
        tournament_id TEXT NOT NULL REFERENCES tournament(id) ON DELETE CASCADE,
        display_name TEXT NOT NULL,
        team_name TEXT NOT NULL,
        contact TEXT NOT NULL,
        seed_index INTEGER NOT NULL,
        registered_at INTEGER NOT NULL,
        is_checked_in INTEGER NOT NULL,
        is_disqualified INTEGER NOT NULL,
        placement INTEGER
    );

    CREATE TABLE IF NOT EXISTS match (
        id TEXT PRIMARY KEY NOT NULL,
        tournament_id TEXT NOT NULL REFERENCES tournament(id) ON DELETE CASCADE,
        round_index INTEGER NOT NULL,
        slot_index INTEGER NOT NULL,
        participant_a_id TEXT REFERENCES participant(id),
        participant_b_id TEXT REFERENCES participant(id),
        score_a INTEGER NOT NULL DEFAULT 0,
        score_b INTEGER NOT NULL DEFAULT 0,
        winner_id TEXT REFERENCES participant(id),
        is_bye INTEGER NOT NULL DEFAULT 0,
        scheduled_at INTEGER,
        seat_a_id TEXT REFERENCES gaming_seat(id),
        seat_b_id TEXT REFERENCES gaming_seat(id),
        status TEXT NOT NULL,
        note TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS inventory_item (
        id TEXT PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        sku TEXT NOT NULL,
        unit TEXT NOT NULL,
        quantity_milli INTEGER NOT NULL,
        minimum_quantity_milli INTEGER NOT NULL,
        unit_cost_cents INTEGER NOT NULL,
        category_name TEXT NOT NULL,
        is_consumable INTEGER NOT NULL
    );

    CREATE TABLE IF NOT EXISTS inventory_movement (
        id TEXT PRIMARY KEY NOT NULL,
        item_id TEXT NOT NULL REFERENCES inventory_item(id) ON DELETE CASCADE,
        kind TEXT NOT NULL,
        quantity_milli INTEGER NOT NULL,
        occurred_at INTEGER NOT NULL,
        shift_id TEXT REFERENCES shift(id),
        employee_id TEXT REFERENCES employee(id),
        reason TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS finance_record (
        id TEXT PRIMARY KEY NOT NULL,
        kind TEXT NOT NULL,
        category_name TEXT NOT NULL,
        amount_cents INTEGER NOT NULL,
        occurred_at INTEGER NOT NULL,
        shift_id TEXT REFERENCES shift(id),
        tournament_id TEXT REFERENCES tournament(id),
        repair_id TEXT REFERENCES repair_record(id),
        note TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS note (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        is_pinned INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
    );

    CREATE TABLE IF NOT EXISTS document_file (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL,
        filename TEXT NOT NULL,
        byte_size INTEGER NOT NULL,
        type_identifier TEXT NOT NULL,
        imported_at INTEGER NOT NULL,
        category_name TEXT NOT NULL
    );

    CREATE INDEX IF NOT EXISTS idx_checklist_item_template ON checklist_item(template_id);
    CREATE INDEX IF NOT EXISTS idx_checklist_run_template ON checklist_run(template_id);
    CREATE INDEX IF NOT EXISTS idx_checklist_run_employee ON checklist_run(employee_id);
    CREATE INDEX IF NOT EXISTS idx_checklist_result_run ON checklist_result(run_id);
    CREATE INDEX IF NOT EXISTS idx_shift_employee ON shift(employee_id);
    CREATE INDEX IF NOT EXISTS idx_shift_status ON shift(status);
    CREATE INDEX IF NOT EXISTS idx_shift_open_run ON shift(open_checklist_run_id);
    CREATE INDEX IF NOT EXISTS idx_shift_close_run ON shift(close_checklist_run_id);
    CREATE INDEX IF NOT EXISTS idx_seat_zone ON gaming_seat(zone_id);
    CREATE INDEX IF NOT EXISTS idx_equipment_seat ON equipment(seat_id);
    CREATE INDEX IF NOT EXISTS idx_equipment_zone ON equipment(zone_id);
    CREATE INDEX IF NOT EXISTS idx_equipment_state_change_equipment ON equipment_state_change(equipment_id);
    CREATE INDEX IF NOT EXISTS idx_equipment_state_change_employee ON equipment_state_change(employee_id);
    CREATE INDEX IF NOT EXISTS idx_maintenance_seat ON maintenance_task(seat_id);
    CREATE INDEX IF NOT EXISTS idx_maintenance_equipment ON maintenance_task(equipment_id);
    CREATE INDEX IF NOT EXISTS idx_maintenance_zone ON maintenance_task(zone_id);
    CREATE INDEX IF NOT EXISTS idx_maintenance_assignee ON maintenance_task(assignee_id);
    CREATE INDEX IF NOT EXISTS idx_repair_equipment ON repair_record(equipment_id);
    CREATE INDEX IF NOT EXISTS idx_repair_seat ON repair_record(seat_id);
    CREATE INDEX IF NOT EXISTS idx_incident_shift ON incident(shift_id);
    CREATE INDEX IF NOT EXISTS idx_incident_zone ON incident(zone_id);
    CREATE INDEX IF NOT EXISTS idx_incident_seat ON incident(seat_id);
    CREATE INDEX IF NOT EXISTS idx_incident_reported_by ON incident(reported_by_id);
    CREATE INDEX IF NOT EXISTS idx_seat_session_seat_started ON seat_session(seat_id, started_at);
    CREATE INDEX IF NOT EXISTS idx_seat_session_shift ON seat_session(shift_id);
    CREATE INDEX IF NOT EXISTS idx_tournament_zone ON tournament(zone_id);
    CREATE INDEX IF NOT EXISTS idx_tournament_referee ON tournament(referee_id);
    CREATE INDEX IF NOT EXISTS idx_participant_tournament ON participant(tournament_id);
    CREATE INDEX IF NOT EXISTS idx_match_tournament ON match(tournament_id);
    CREATE INDEX IF NOT EXISTS idx_match_participant_a ON match(participant_a_id);
    CREATE INDEX IF NOT EXISTS idx_match_participant_b ON match(participant_b_id);
    CREATE INDEX IF NOT EXISTS idx_match_seat_a ON match(seat_a_id);
    CREATE INDEX IF NOT EXISTS idx_match_seat_b ON match(seat_b_id);
    CREATE INDEX IF NOT EXISTS idx_inventory_movement_item_occurred ON inventory_movement(item_id, occurred_at);
    CREATE INDEX IF NOT EXISTS idx_inventory_movement_shift ON inventory_movement(shift_id);
    CREATE INDEX IF NOT EXISTS idx_inventory_movement_employee ON inventory_movement(employee_id);
    CREATE INDEX IF NOT EXISTS idx_finance_occurred ON finance_record(occurred_at);
    CREATE INDEX IF NOT EXISTS idx_finance_shift ON finance_record(shift_id);
    CREATE INDEX IF NOT EXISTS idx_finance_tournament ON finance_record(tournament_id);
    CREATE INDEX IF NOT EXISTS idx_finance_repair ON finance_record(repair_id);
    """
}
