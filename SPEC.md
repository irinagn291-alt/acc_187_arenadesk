# Arenadesk — Technical Specification

Revision 2. Supersedes the "Cybrium" draft, which listed eighteen structures by name with no fields
and five bracket formats with no algorithms. Every entity is now fully specified, the format list is
narrowed to three fully described algorithms, and the raw SQLite layer is defined.

## 1. Store metadata

- **Name:** Arenadesk
- **Short description:** Run the floor, offline
- **Long description:** Arenadesk is the operations desk for a gaming club or esports venue, built to
  keep working when the internet does not. Open and close shifts against versioned checklists, track
  every seat's health score, schedule maintenance before hardware fails, run tournaments with proper
  seeding and tiebreaks, watch stock levels, and export everything to JSON or CSV. All data lives on
  the device.
- **Keywords:** gaming club,esports,arena,shift,tournament,maintenance,inventory,seats,operations,offline
- **Primary category:** Business
- **Secondary category:** Productivity
- **Age rating:** 4+

## 2. Product goal

A single-device operations tool for one venue. Covers shifts, zones and seats, equipment and its
condition history, maintenance and repairs, staff and rosters, tournaments, stock, cash records,
incidents, documents, analytics, and versioned local backup. No internet, no cloud, no external API.

## 3. Platform and architecture

- iOS 16.0+ (iPad-first layout, iPhone supported), Swift 6.2, SwiftUI.
- Architecture: MVVM, one `ObservableObject` per screen.
- Persistence: **SQLite via the system `libsqlite3` C API, hand-wrapped.** No SPM dependencies.
- Navigation: `NavigationSplitView` on regular width, `NavigationStack` on compact.
- Frameworks: SwiftUI, Foundation, SQLite3, Charts, UserNotifications, UniformTypeIdentifiers,
  QuickLook, and the SwiftUI `fileImporter` / `fileExporter` modifiers.
- `Observation` is **not** used (iOS 17 only).

### 3.1 The database layer

```
Database                — actor owning one sqlite3 handle; every call is serialised through it
Statement               — RAII wrapper: sqlite3_prepare_v2 / _step / _finalize, throws on error
SQLValue                — enum { null, integer(Int64), real(Double), text(String), blob(Data) }
Row                     — column-name to SQLValue map with typed accessors
Migrator                — ordered [Migration], each with version + SQL, applied in one transaction
<Entity>Table           — one type per table: insert, update, delete, and named queries
<Entity>Repository      — maps rows to value structs; the only type view models talk to
```

Rules that are not negotiable:

- `sqlite3_open_v2` with `SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX`.
- `PRAGMA journal_mode = WAL`, `PRAGMA foreign_keys = ON`, `PRAGMA busy_timeout = 5000`
  executed on every connection open.
- All values bound through `sqlite3_bind_*`. String interpolation into SQL is forbidden.
- Every statement finalised in a `defer`; the actor guarantees no statement outlives its handle.
- Money is stored as `INTEGER` minor units (cents), never `REAL`. Dates are stored as
  `INTEGER` Unix seconds. Booleans are `INTEGER` 0/1. UUIDs are `TEXT` lowercase.
- Schema version tracked in `PRAGMA user_version`. `Migrator` refuses to open a file whose version
  exceeds the bundled maximum and surfaces a readable error instead of crashing.
- Multi-row writes (shift close, bracket generation, backup restore) run inside
  `BEGIN IMMEDIATE` / `COMMIT` with rollback on any throw.

## 4. Domain model

All identifiers are `UUID`. `Decimal` fields map to integer minor units at the table boundary.

```swift
struct Venue {
    let id: UUID
    var name: String
    var address: String
    var phone: String
    var openingTime: DateComponents      // hour, minute
    var closingTime: DateComponents
    var currencyCode: String
    var seatHourlyRate: Decimal
}

struct Employee {
    let id: UUID
    var fullName: String
    var role: EmployeeRole
    var phone: String
    var hiredAt: Date
    var hourlyRate: Decimal
    var isActive: Bool
    var note: String
    var pinHash: String?                 // 6-digit PIN, SHA-256 with per-record salt
    var pinSalt: String?
}

struct Shift {
    let id: UUID
    var employeeID: UUID
    var openedAt: Date
    var closedAt: Date?
    var status: ShiftStatus
    var openChecklistRunID: UUID
    var closeChecklistRunID: UUID?
    var openingCash: Decimal
    var closingCash: Decimal?
    var seatSessionCount: Int            // denormalised at close
    var incidentCount: Int               // denormalised at close
    var note: String
    var isArchived: Bool
}

struct ChecklistTemplate {
    let id: UUID
    var name: String
    var kind: ChecklistKind
    var version: Int                     // editing a used template creates version + 1
    var isActive: Bool
    var createdAt: Date
}

struct ChecklistItem {
    let id: UUID
    var templateID: UUID
    var text: String
    var isMandatory: Bool
    var sortIndex: Int
}

struct ChecklistRun {
    let id: UUID
    var templateID: UUID
    var templateVersion: Int             // frozen, so history survives template edits
    var startedAt: Date
    var completedAt: Date?
    var employeeID: UUID
}

struct ChecklistResult {
    let id: UUID
    var runID: UUID
    var itemID: UUID
    var itemText: String                 // frozen copy
    var isChecked: Bool
    var note: String
    var checkedAt: Date?
}

struct Zone {
    let id: UUID
    var name: String
    var kind: ZoneKind
    var capacity: Int
    var sortIndex: Int
    var note: String
}

struct GamingSeat {
    let id: UUID
    var zoneID: UUID
    var label: String                    // "A-07"
    var state: SeatState
    var cpu: String
    var gpu: String
    var ramGB: Int
    var storage: String
    var monitorModel: String
    var monitorHz: Int
    var commissionedAt: Date
    var lastMaintenanceAt: Date?
    var maintenanceIntervalDays: Int
    var healthScore: Int                 // cached result of 5.3, recomputed on any related write
    var note: String
}

struct Equipment {
    let id: UUID
    var seatID: UUID?                    // nil for shared or spare equipment
    var zoneID: UUID?
    var name: String
    var kind: EquipmentKind
    var serialNumber: String
    var state: EquipmentState
    var purchasedAt: Date?
    var warrantyUntil: Date?
    var price: Decimal?
    var stateChangedAt: Date
    var note: String
}

struct EquipmentStateChange {
    let id: UUID
    var equipmentID: UUID
    var fromState: EquipmentState
    var toState: EquipmentState
    var changedAt: Date
    var employeeID: UUID?
    var reason: String
}

struct MaintenanceTask {
    let id: UUID
    var title: String
    var seatID: UUID?
    var equipmentID: UUID?
    var zoneID: UUID?
    var kind: MaintenanceKind
    var status: TaskStatus
    var scheduledFor: Date
    var completedAt: Date?
    var assigneeID: UUID?
    var recurrenceDays: Int?             // completing a recurring task schedules the next one
    var checklistTemplateID: UUID?
    var note: String
}

struct RepairRecord {
    let id: UUID
    var equipmentID: UUID?
    var seatID: UUID?
    var openedAt: Date
    var closedAt: Date?
    var symptom: String
    var actionTaken: String
    var partsCost: Decimal
    var laborCost: Decimal
    var performedBy: String              // free text: may be an external service
    var isExternal: Bool
}

struct Incident {
    let id: UUID
    var shiftID: UUID?
    var zoneID: UUID?
    var seatID: UUID?
    var severity: IncidentSeverity
    var kind: IncidentKind
    var occurredAt: Date
    var reportedByID: UUID?
    var summary: String
    var resolution: String
    var isResolved: Bool
    var isArchived: Bool
}

struct SeatSession {
    let id: UUID
    var seatID: UUID
    var shiftID: UUID?
    var startedAt: Date
    var endedAt: Date?
    var purpose: SessionPurpose          // walkIn, booking, tournament, maintenance
    var matchID: UUID?
    var note: String
}

struct Tournament {
    let id: UUID
    var name: String
    var discipline: String
    var format: MatchFormat
    var status: TournamentStatus
    var zoneID: UUID?
    var startsAt: Date
    var endsAt: Date?
    var entryFee: Decimal
    var prizePool: Decimal
    var maxParticipants: Int
    var bestOf: Int                      // 1, 3 or 5
    var swissRoundCount: Int?            // nil = derived, see 5.5
    var refereeID: UUID?
    var isArchived: Bool
    var rulesDocumentID: UUID?
}

struct Participant {
    let id: UUID
    var tournamentID: UUID
    var displayName: String
    var teamName: String
    var contact: String
    var seedIndex: Int                   // 1-based, assigned at bracket generation
    var registeredAt: Date
    var isCheckedIn: Bool
    var isDisqualified: Bool
    var placement: Int?                  // filled when the tournament completes
}

struct Match {
    let id: UUID
    var tournamentID: UUID
    var roundIndex: Int                  // 0-based
    var slotIndex: Int                   // 0-based position inside the round
    var participantAID: UUID?
    var participantBID: UUID?
    var scoreA: Int
    var scoreB: Int
    var winnerID: UUID?
    var isBye: Bool
    var scheduledAt: Date?
    var seatAID: UUID?
    var seatBID: UUID?
    var status: MatchStatus
    var note: String
}

struct InventoryItem {
    let id: UUID
    var name: String
    var sku: String
    var unit: String                     // "pcs", "l", "kg"
    var quantity: Decimal                // derived from movements, cached
    var minimumQuantity: Decimal
    var unitCost: Decimal
    var categoryName: String
    var isConsumable: Bool
}

struct InventoryMovement {
    let id: UUID
    var itemID: UUID
    var kind: MovementKind               // receipt, issue, writeOff, correction
    var quantity: Decimal                // positive for receipt, issue and writeOff, where `kind`
                                         // carries the sign; signed for correction, which may
                                         // adjust stock in either direction
    var occurredAt: Date
    var shiftID: UUID?
    var employeeID: UUID?
    var reason: String
}

struct FinanceRecord {
    let id: UUID
    var kind: FinanceKind                // income or expense
    var categoryName: String
    var amount: Decimal
    var occurredAt: Date
    var shiftID: UUID?
    var tournamentID: UUID?
    var repairID: UUID?
    var note: String
}

struct Note {
    let id: UUID
    var title: String
    var body: String
    var isPinned: Bool
    var createdAt: Date
    var updatedAt: Date
}

struct DocumentFile {
    let id: UUID
    var title: String
    var filename: String                 // relative to Documents/Files — the file is COPIED in
    var byteSize: Int64
    var typeIdentifier: String           // UTType identifier
    var importedAt: Date
    var categoryName: String
}

struct BackupManifest {
    var schemaVersion: Int
    var appVersion: String
    var createdAt: Date
    var rowCounts: [String: Int]
    var includesFiles: Bool
}

enum ShiftStatus: String { case opened, closed }
enum ChecklistKind: String { case shiftOpen, shiftClose, maintenance, cleaning }
enum ZoneKind: String { case standard, vip, console, streaming, tournament, lounge }
enum SeatState: String { case ready, occupied, reserved, cleaning, maintenance, outOfService }
enum EquipmentState: String { case ok, cleaning, overheating, damaged, broken, inRepair, retired }
enum EquipmentKind: String { case pc, monitor, keyboard, mouse, headset, chair, console, network, other }
enum MaintenanceKind: String { case cleaning, thermalPaste, driverUpdate, diskCheck, cableCheck, inspection, other }
enum TaskStatus: String { case planned, active, completed, skipped }
enum IncidentSeverity: String { case low, medium, high }
enum IncidentKind: String { case hardware, network, customer, safety, theft, cleanliness, other }
enum SessionPurpose: String { case walkIn, booking, tournament, maintenance }
enum MatchFormat: String { case singleElimination, roundRobin, swiss }
enum TournamentStatus: String { case draft, registration, running, completed, cancelled }
enum MatchStatus: String { case pending, ready, running, finished, walkover }
enum MovementKind: String { case receipt, issue, writeOff, correction }
enum FinanceKind: String { case income, expense }
enum EmployeeRole: String { case manager, admin, technician, referee, security }
```

## 5. Core logic

### 5.1 Roles and access

| Capability | manager | admin | technician | referee | security |
| --- | --- | --- | --- | --- | --- |
| Open / close shift | yes | yes | no | no | no |
| Edit seats, zones, equipment | yes | no | yes | no | no |
| Change equipment state, close repairs | yes | yes | yes | no | no |
| Run tournaments, enter results | yes | yes | no | yes | no |
| Inventory movements | yes | yes | yes | no | no |
| Finance records and analytics | yes | no | no | no | no |
| File incidents | yes | yes | yes | yes | yes |
| Backup, restore, wipe | yes | no | no | no | no |

The active employee is selected at shift open and confirmed with a 6-digit PIN when one is set.
Access control is advisory-by-design: forbidden actions are hidden and disabled, and a manager
override sheet exists. This is a shared-device tool, not a security boundary — the specification
states so, and the About screen repeats it.

### 5.2 Shifts

Open requires: an active employee selected, the active `shiftOpen` template completed with every
`isMandatory` item checked, and no other shift in `.opened` state. A `ChecklistRun` is created and
its `templateVersion` frozen.

Close runs the `shiftClose` template, then blocks on a summary of open work: maintenance tasks with
`status == .active`, unresolved incidents from this shift, seat sessions still without `endedAt`, and
inventory items below minimum. The user either resolves them or confirms passing them to the next
shift; confirming writes the list into `Shift.note`. Closing sets `closedAt`, denormalises the
counters, and sets `isArchived = true`.

### 5.3 Seat health score

The venue's central operational signal, recomputed whenever a related row changes.

```
score = 100
      - 12 * (incidents of kind .hardware for this seat in the last 30 days)
      -  8 * (repair records touching this seat closed in the last 90 days)
      - penalty(state):  outOfService 30, maintenance 15, cleaning 5, others 0
      - worstEquipmentPenalty: broken 25, damaged 15, overheating 12, inRepair 20, cleaning 3, ok 0
      - min(15, 0.5 * months since commissionedAt)
      + (lastMaintenanceAt within the last 30 days ? 5 : 0)
      - (maintenance overdue by more than maintenanceIntervalDays ? 10 : 0)
score = clamp(score, 0, 100)
```

Bands: `85...100` healthy, `70...84` watch, `50...69` degraded, `0...49` critical. The dashboard lists
the five lowest-scoring seats; a seat entering `critical` raises a local notification once per day.

### 5.4 Zones, occupancy and equipment history

```
readySeats  = seats in zone with state == .ready
totalSeats  = seats in zone
readiness   = totalSeats == 0 ? nil : readySeats / totalSeats * 100     // nil renders "no seats"
occupancy   = totalSeats == 0 ? nil : occupiedSeats / totalSeats * 100
utilisation(seat, range) = sum of session durations in range / opening hours in range * 100
```

Every equipment state change writes an `EquipmentStateChange` row and updates `stateChangedAt`;
moving to `.inRepair` opens a `RepairRecord` automatically, and closing that record returns the
equipment to `.ok` unless the user chooses `.retired`.

### 5.5 Tournaments

**Seeding.** Checked-in, non-disqualified participants are ordered by check-in time unless the
organiser reorders them manually; `seedIndex` is then written 1..n and frozen.

**Single elimination.** Bracket size is `size = 2^ceil(log2(n))`. `byes = size - n`. Seeds are placed
by the standard fold pattern so that seed 1 and seed 2 can only meet in the final: for bracket size
`size`, slot order is generated recursively as `order(2) = [1, 2]`,
`order(2k) = interleave(order(k), (2k + 1) - order(k))`. The top `byes` seeds receive byes; a bye
match is created with `isBye = true`, `participantBID = nil`, `status = .walkover` and its winner
advances immediately. Rounds are pre-created empty and filled as winners resolve. Round count is
`log2(size)`; the final round has one match.

**Round robin.** `n` participants play `n - 1` rounds using the circle method; with odd `n` a
virtual bye entry is added. Round `r` pairs are generated by fixing entry 0 and rotating the rest.
Standings: 3 points for a win, 1 for a draw when `bestOf == 1`, 0 for a loss. Tiebreaks in order:
head-to-head result, map difference (`scoreFor - scoreAgainst`), maps won, then seed index.

**Swiss.** Round count defaults to `ceil(log2(n))`, minimum 3, and is overridable via
`swissRoundCount`. Each round sorts players by score, then pairs greedily inside score groups while
avoiding rematches, backtracking one player at a time when a group cannot be paired. Odd player out
receives a bye worth one win, and no player may receive two byes. Tiebreaks in order: Buchholz (sum
of opponents' scores), median Buchholz (Buchholz minus best and worst opponent), head-to-head, seed.

**Results.** A match needs `ceil(bestOf / 2)` map wins. Entering a result sets `winnerID`, sets
`status = .finished`, advances the winner in elimination formats, and recomputes standings. Editing a
finished result in an elimination bracket invalidates and clears every downstream match, behind an
explicit confirmation. Disqualifying a participant converts their pending matches to walkovers.

**Scheduling and seat assignment.** Matches are ordered by `scheduledAt`, then `roundIndex`, then
`slotIndex`. A seat is assignable when it belongs to the tournament zone, its state is `.ready`, its
health score is at least 50, and it has no `SeatSession` overlapping the match window. Assignment
walks the ordered match list and takes the two highest-health free seats per match, opening a
`SeatSession` with `purpose == .tournament` and the `matchID`. Unassignable matches are listed with
the reason rather than silently skipped.

### 5.6 Inventory and finance

```
quantity = sum(receipt) + sum(correction) - sum(issue) - sum(writeOff)
```

A `correction` movement is signed: a stocktake that finds less on the shelf than the records claim
records a negative quantity, and one that finds more records a positive one. The other three kinds
always store a positive quantity and take their sign from `kind`.

The cached `quantity` is recomputed from movements on every write, never incremented blindly.
Crossing `quantity <= minimumQuantity` downward raises one notification per item per day. Issuing
more than is on hand is allowed but flagged, because physical stock and records drift in practice.

```
balance(range) = sum(income in range) - sum(expense in range)
```

Closing a repair with non-zero cost offers to create the matching expense record, pre-filled and
linked by `repairID`. Tournament entry fees and prize pool likewise link by `tournamentID`.

### 5.7 Maintenance scheduling

A seat is due when `now >= (lastMaintenanceAt ?? commissionedAt) + maintenanceIntervalDays`.
Due seats without an open task get one created with `status = .planned` on launch. Completing a task
with `recurrenceDays` set creates the next occurrence at `completedAt + recurrenceDays`. Notification
identifiers are `maintenance-<task.id>`, scheduled at 10:00 local on `scheduledFor`.

### 5.8 Analytics

Everything is computed from local SQL aggregates: shifts per week, average shift length, seat
sessions and utilisation per zone, health score distribution, the ten most problematic seats by
incident and repair count, repair cost by month, maintenance completed versus planned, tournaments
and participants by month, inventory consumption of the top ten items, and income versus expense by
month. Every chart accepts a date range and each has a stated empty state.

### 5.9 Backup, export, import

Backup writes `Documents/Backups/arenadesk-<ISO8601>.json` containing a `BackupManifest` plus one
array per table. Restore validates `schemaVersion` against the bundled schema: equal restores
directly, lower runs forward migrations on the decoded payload, higher is refused with a readable
message. Restore is destructive, runs in one transaction, and requires typing the venue name to
confirm. Optionally documents are included as a sibling folder copy. CSV export covers finance,
inventory movements, shifts, repairs and tournament standings, comma-separated with a UTF-8 BOM and
RFC 4180 quoting. Imported documents are **copied** into `Documents/Files` — no security-scoped
bookmarks are retained, so a moved or deleted source file cannot break the app.

## 6. Screens

| Screen | Contents | Navigates to |
| --- | --- | --- |
| SplashView | Wordmark, open database, run migrations | MainTabView or OnboardingView |
| OnboardingView | Venue setup, first zone and seats, first employee, checklist templates | MainTabView |
| MainTabView | Tabs: Dashboard, Floor, Tournaments, Staff, More | — |
| DashboardView | Active shift card, zone readiness strip, five lowest-health seats, today's counters, due maintenance, low stock, quick actions | ShiftOpen, ShiftClose, Analytics, SeatDetail |
| ShiftOpenView | Employee picker, PIN, checklist run, opening cash | Dashboard |
| ShiftCloseView | Closing checklist, open-work summary, closing cash, report preview | Dashboard |
| ShiftHistoryView | Past shifts with duration, sessions, incidents | ShiftDetail |
| ShiftDetailView | Both checklist runs, cash, incidents, note | Dashboard |
| AnalyticsView | Range picker and every chart from 5.8 | — |
| FloorView | Zone list with readiness and occupancy | ZoneDetail, ZoneEditor |
| ZoneDetailView | Seat grid coloured by state, health badges, filters | SeatDetail |
| SeatDetailView | Specs, health score with factor breakdown, attached equipment, session history, maintenance history, state actions | Equipment, Maintenance, SessionLog |
| EquipmentListView | Search, filters by kind and state, warranty flags | EquipmentDetail, EquipmentEditor |
| EquipmentDetailView | State with change action, state-change history, repairs, warranty | RepairDetail |
| MaintenanceView | Segments: due, planned, active, completed | MaintenanceEditor, ChecklistRun |
| RepairListView | Open and closed repairs, cost totals | RepairDetail |
| InventoryView | Stock list with low-stock highlighting, movement entry | InventoryItemDetail |
| InventoryItemDetailView | Movement ledger, recompute, minimum level | InventoryView |
| FinanceView | Balance, records by range, category breakdown | FinanceRecordEditor |
| TournamentsView | Active and archived tournaments | TournamentDetail, TournamentEditor |
| TournamentDetailView | Status, format, participants count, prize pool, generate bracket | Participants, Bracket, Matches, Standings |
| ParticipantsView | Registration, check-in, seeding reorder, disqualify | TournamentDetail |
| BracketView | Horizontally scrolling rounds for elimination, round list for Swiss and round robin | MatchDetail |
| StandingsView | Table with points and every tiebreak column | MatchDetail |
| MatchesView | Schedule ordered by time, seat assignment, auto-assign action | MatchDetail |
| MatchDetailView | Participants, map scores, seats, walkover, note | BracketView |
| StaffView | Employees with role badges | EmployeeDetail, EmployeeEditor |
| EmployeeDetailView | Contact, role, shift history, hours in range, PIN management | StaffView |
| ScheduleView | Week grid of planned shifts per employee | ShiftPlanEditor |
| MoreView | Entry list | Documents, Notes, Incidents, Checklists, Archive, Backup, Settings |
| DocumentsView | Imported files with QuickLook preview, categories | — |
| NotesView | Pinned and recent notes | NoteEditor |
| IncidentsView | Filters by severity, kind, resolution | IncidentDetail, IncidentEditor |
| ChecklistTemplatesView | Templates by kind with version numbers, activate, duplicate | ChecklistTemplateEditor |
| ArchiveView | Archived shifts, tournaments and incidents, read-only | detail screens |
| BackupView | Create backup, restore with typed confirmation, CSV exports, backup list with sizes | — |
| SettingsView | Venue, notifications, seat rate, database size, integrity check, wipe | AboutView |
| AboutView | Version, schema version, privacy statement, access-control disclaimer | — |

## 7. Design

Dark only. The theme setting from the previous draft is removed — `UserDefaults` stores no theme key.

```
primary        #7C5CFF
primaryMuted   #241F3D
background     #0B0E14
surface        #151A23
surfaceRaised  #1D2430
text           #E6EAF2
secondaryText  #8A93A6
accent         #00D2A0
warning        #F5A524
error          #E5484D
divider        #232A36
corners        10 / 16 / 24
spacing        8 / 16 / 24 / 40
title          24 bold
headline       18 semibold
body           16 regular
caption        12 medium
mono           15 monospaced   // seat labels, serial numbers, scores
```

Seat state colours: ready `#00D2A0`, occupied `#7C5CFF`, reserved `#5B7FFF`, cleaning `#F5A524`,
maintenance `#E5484D`, out of service `#5A6373`. Health bands reuse accent / warning / error.
Layout targets iPad landscape first: three-column split on regular width, collapsing to a stack on
compact. All numeric tables use monospaced digits.

## 8. Storage layout

- SQLite at `Application Support/arenadesk.sqlite` (excluded from iCloud backup only if the user
  asks; default is included). Tables mirror section 4 one-to-one, plus a `schema_migrations` audit
  table. Indices on every foreign key, on `shift.status`, `seat.zone_id`, `match.tournament_id`,
  `seat_session.seat_id, started_at`, `finance_record.occurred_at` and
  `inventory_movement.item_id, occurred_at`.
- `UserDefaults`: notification preferences, first-launch flag, last selected tab, last analytics
  range, active employee id.
- `Documents/Files/` — copied documents. `Documents/Backups/` — JSON backups.
  `Documents/Exports/` — CSV exports.
- Bundled `Resources/DefaultChecklists.json` seeds the shift-open, shift-close, cleaning and
  maintenance templates on first launch.

## 9. Delivery phases

1. **Foundation** — `Database` actor, `Statement`, `Migrator`, schema v1, repositories, value models,
   theme, split navigation, venue onboarding. Database layer tests come first.
2. **Floor** — dashboard, shifts with versioned checklists, zones, seats, seat sessions, equipment
   and state history, health score.
3. **Upkeep** — maintenance scheduling and recurrence, repairs, inventory with movement ledger,
   finance records, staff and roster.
4. **Competition** — tournaments, participants, seeding, all three bracket algorithms, standings and
   tiebreaks, seat auto-assignment, analytics.
5. **Records and resilience** — documents with QuickLook, notes, incidents, archive, backup, restore,
   CSV export, notifications, integrity check, animations, performance pass at 200 seats /
   50 000 sessions / 20 tournaments.

## 10. Testing

Database layer: migration from empty to current, refusal of a future `user_version`, rollback on a
failed multi-row transaction, foreign-key enforcement, and money round-tripping without precision
loss.

Bracket algorithms carry the heaviest test burden, Given/When/Then: single elimination for
n = 2, 3, 5, 8, 9, 16, 17 asserting bye count, that seed 1 and seed 2 meet no earlier than the final,
and that every round is reachable; round robin for odd and even n asserting each pair meets exactly
once and each entry plays every round; Swiss asserting no rematches, no double byes, and correct
Buchholz and median Buchholz on a hand-computed five-player example. Also required: health score
clamping at both ends, readiness with zero seats returning nil, inventory quantity recomputation
after an out-of-order correction, and downstream invalidation when a finished elimination result is
edited.

## 11. Permissions and privacy

- `NSDocumentsFolderUsageDescription` — "Access to files is used to import and export backups,
  documents, CSV and JSON."
- Local notifications requested on first launch after onboarding — "Reminders for maintenance,
  shifts, tournaments, low stock and seats in critical condition."
- `PrivacyInfo.xcprivacy` is required and declares:
  `NSPrivacyAccessedAPICategoryUserDefaults` (reason `CA92.1`),
  `NSPrivacyAccessedAPICategoryFileTimestamp` (reason `C617.1`),
  `NSPrivacyAccessedAPICategoryDiskSpace` (reason `E174.1`),
  with `NSPrivacyTracking = false` and no collected data types.
- Camera, microphone, photos, location and contacts are not used. No networking entitlement, no
  analytics, no advertising, no account.
- Employee records are staff contact data entered by the venue operator; the About screen states that
  it never leaves the device and that PINs are convenience gates, not encryption.

## 12. Visual assets

Mandatory deliverable. The build is not complete while `AppIcon.appiconset` is empty or while any
screen listed below falls back to an SF Symbol placeholder.

### App icon

Three 1024x1024 PNG variants, no transparency, no rounded corners. The app is dark-only, so the dark
variant is designed first and the light variant derived from it.

| File | Appearance | Content |
| --- | --- | --- |
| `icon-dark.png` | luminosity / dark | Seat grid with a readiness indicator, `#7C5CFF` and `#00D2A0` on `#0B0E14` |
| `icon-light.png` | default | Same mark inverted onto a light neutral ground |
| `icon-tinted.png` | luminosity / tinted | Grayscale mark, no background fill |

Alpha must be flattened before submission.

### Illustrations and badges

PNG, single-scale image sets (a `Contents.json` entry with no `scale` key), transparent background,
1024 px on the long edge for illustrations and 512 px for badges, drawn in the dark palette of
section 7. Every illustration is reviewed on an iPad landscape layout, where it renders largest.

| Asset | Used by |
| --- | --- |
| `onboarding-venue` | Onboarding — venue details |
| `onboarding-floor` | Onboarding — first zone and seats |
| `onboarding-checklists` | Onboarding — checklist templates |
| `empty-zones` | FloorView, no zones configured |
| `empty-tournaments` | TournamentsView, none created |
| `empty-incidents` | IncidentsView, nothing filed |
| `empty-documents` | DocumentsView, nothing imported |
| `empty-backups` | BackupView, no backups yet |
| `zone-standard`, `zone-vip`, `zone-console`, `zone-streaming`, `zone-tournament`, `zone-lounge` | Zone rows and pickers, one badge per `ZoneKind` case |

The six zone badges share one visual system: identical framing and stroke weight, differing only in
the interior mark, so a zone list reads as a set rather than as six unrelated drawings. Asset names
are exposed through a `DesignSystem/AppImage.swift` enum, and `ZoneKind` maps to its badge through an
exhaustive `switch` so a new case cannot compile without artwork. `AccentColor.colorset` is filled
with `#7C5CFF`. `actool` warnings about assets are treated as build errors.
