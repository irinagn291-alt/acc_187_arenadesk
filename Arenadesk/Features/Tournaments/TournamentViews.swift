import SwiftUI

@MainActor
final class TournamentsViewModel: ObservableObject {
    @Published var tournaments: [Tournament] = []
    @Published var name = ""
    @Published var format: MatchFormat = .singleElimination
    @Published var zones: [Zone] = []
    @Published var zoneID: UUID?
    @Published var showCreate = false
    private let environment: AppEnvironment
    init(environment: AppEnvironment) { self.environment = environment }

    func reload() async {
        tournaments = (try? await environment.tournaments.fetchAll()) ?? []
        zones = (try? await environment.zones.fetchAll()) ?? []
        if zoneID == nil { zoneID = zones.first?.id }
    }

    func create() async {
        guard !name.isEmpty else { return }
        let tournament = Tournament(
            id: UUID(),
            name: name,
            discipline: "FPS",
            format: format,
            status: .registration,
            zoneID: zoneID,
            startsAt: .now,
            endsAt: nil,
            entryFee: 0,
            prizePool: 0,
            maxParticipants: 32,
            bestOf: 3,
            swissRoundCount: nil,
            refereeID: nil,
            isArchived: false,
            rulesDocumentID: nil
        )
        try? await environment.tournaments.upsert(tournament)
        name = ""
        showCreate = false
        await reload()
    }
}

struct TournamentsView: View {

    @Environment(\.themePalette) private var palette
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var holder = VMHolder<TournamentsViewModel>()

    var body: some View {
        Group {
            if let vm = holder.value {
                AccessGated(capability: .runTournaments) {
                    TournamentsContent(viewModel: vm)
                }
            } else { ProgressView().tint(palette.accent) }
        }
        .onAppear { if holder.value == nil { holder.value = TournamentsViewModel(environment: environment) } }
    }
}

struct TournamentsContent: View {
    @Environment(\.themePalette) private var palette

    @ObservedObject var viewModel: TournamentsViewModel

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            if viewModel.tournaments.isEmpty {
                NothingHereView(
                    image: .emptyTournaments,
                    title: "No tournaments",
                    detail: "Create a tournament to run brackets offline on the floor.",
                    actionTitle: "New tournament",
                    action: { viewModel.showCreate = true }
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.spaceS) {
                        FloorBanner(
                            image: .tournamentsBanner,
                            caption: "Brackets running on the floor",
                            height: 150
                        )
                        ForEach(viewModel.tournaments) { tournament in
                            NavigationLink {
                                TournamentDetailView(tournamentID: tournament.id)
                            } label: {
                                ConsolePanel {
                                    HStack(alignment: .top) {
                                        AppImage.zoneTournament.image
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 40, height: 40)
                                            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
                                            .accessibilityHidden(true)
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text(tournament.name)
                                                .font(Theme.headlineFont())
                                                .foregroundStyle(palette.text)
                                            Text(tournament.format.displayName)
                                                .font(Theme.captionFont())
                                                .foregroundStyle(palette.secondaryText)
                                        }
                                        Spacer()
                                        statusPill(tournament.status)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(Theme.spaceM)
                    .padding(.bottom, Theme.consoleBottomClearance)
                }
            }
        }
        .consoleRootChrome(title: "Tournaments", subtitle: "Brackets, stands, and matches")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.showCreate = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New tournament")
            }
        }
        .sheet(isPresented: $viewModel.showCreate) {
            NavigationStack {
                ScrollView {
                    ConsolePanel(title: "Tournament") {
                        TextField("Name", text: $viewModel.name)
                        Picker("Format", selection: $viewModel.format) {
                            ForEach(MatchFormat.allCases, id: \.self) {
                                Text($0.displayName).tag($0)
                            }
                        }
                        Picker("Zone", selection: $viewModel.zoneID) {
                            ForEach(viewModel.zones) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                    .padding(Theme.spaceM)
                }
                .background(palette.background)
                .navigationTitle("New tournament")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { viewModel.showCreate = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") { Task { await viewModel.create() } }
                            .disabled(viewModel.name.isEmpty)
                    }
                }
            }
        }
        .task { await viewModel.reload() }
    }

    private func statusPill(_ status: TournamentStatus) -> some View {
        Text(status.displayName)
            .font(Theme.captionFont())
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(statusColor(status).opacity(0.2))
            .foregroundStyle(statusColor(status))
            .overlay(
                Capsule().stroke(statusColor(status).opacity(0.7), lineWidth: 1)
            )
            .clipShape(Capsule())
    }

    private func statusColor(_ status: TournamentStatus) -> Color {
        switch status {
        case .draft: ConsoleTokens.lampIdle
        case .registration: ConsoleTokens.lampInfo
        case .running: ConsoleTokens.lampReady
        case .completed: palette.primary
        case .cancelled: ConsoleTokens.lampCritical
        }
    }
}

@MainActor
final class TournamentDetailViewModel: ObservableObject {
    @Published var tournament: Tournament?
    @Published var participants: [Participant] = []
    @Published var matches: [Match] = []
    @Published var standings: [StandingRow] = []
    @Published var newName = ""
    @Published var failures: [SeatAssignmentFailure] = []
    @Published var error: String?
    private let tournamentID: UUID
    private let environment: AppEnvironment
    init(tournamentID: UUID, environment: AppEnvironment) {
        self.tournamentID = tournamentID
        self.environment = environment
    }

    func reload() async {
        tournament = try? await environment.tournaments.fetch(id: tournamentID)
        participants = (try? await environment.tournaments.participants(tournamentID: tournamentID)) ?? []
        matches = (try? await environment.tournaments.matches(tournamentID: tournamentID)) ?? []
        standings = (try? await environment.tournaments.standings(tournamentID: tournamentID)) ?? []
    }

    func addParticipant() async {
        guard !newName.isEmpty else { return }
        let p = Participant(
            id: UUID(),
            tournamentID: tournamentID,
            displayName: newName,
            teamName: "",
            contact: "",
            seedIndex: participants.count + 1,
            registeredAt: .now,
            isCheckedIn: true,
            isDisqualified: false,
            placement: nil
        )
        try? await environment.tournaments.upsertParticipant(p)
        newName = ""
        await reload()
    }

    func toggleCheckIn(_ participant: Participant) async {
        var updated = participant
        updated.isCheckedIn.toggle()
        try? await environment.tournaments.upsertParticipant(updated)
        await reload()
    }

    func moveSeed(from: IndexSet, to: Int) async {
        var ordered = participants.sorted { $0.seedIndex < $1.seedIndex }
        ordered.move(fromOffsets: from, toOffset: to)
        try? await environment.tournaments.applySeeding(tournamentID: tournamentID, orderedIDs: ordered.map(\.id))
        await reload()
    }

    func generate() async {
        do {
            _ = try await environment.tournaments.generateBracket(tournamentID: tournamentID)
            error = nil
            await reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func autoAssign() async {
        failures = (try? await environment.tournaments.autoAssignSeats(tournamentID: tournamentID)) ?? []
        await reload()
    }
}

struct TournamentDetailView: View {
    @Environment(\.themePalette) private var palette

    @EnvironmentObject private var environment: AppEnvironment
    let tournamentID: UUID
    @StateObject private var holder = VMHolder<TournamentDetailViewModel>()

    var body: some View {
        Group {
            if let vm = holder.value { TournamentDetailContent(viewModel: vm) }
            else { ProgressView().tint(palette.accent) }
        }
        .onAppear {
            if holder.value == nil {
                holder.value = TournamentDetailViewModel(tournamentID: tournamentID, environment: environment)
            }
        }
    }
}

struct TournamentDetailContent: View {
    @Environment(\.themePalette) private var palette

    @ObservedObject var viewModel: TournamentDetailViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spaceM) {
                if let tournament = viewModel.tournament {
                    ConsolePanel(title: "Summary") {
                        Text(tournament.name)
                            .font(Theme.headlineFont())
                            .foregroundStyle(palette.text)
                        KeyValueRow(key: "Format", value: tournament.format.displayName)
                        KeyValueRow(key: "Best of", value: "\(tournament.bestOf)")
                        KeyValueRow(key: "Prize", value: MoneyFormat.currency(tournament.prizePool))
                        Text(tournament.status.displayName)
                            .font(Theme.captionFont())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(palette.primary.opacity(0.2))
                            .foregroundStyle(palette.primary)
                            .clipShape(Capsule())
                        HStack(spacing: Theme.spaceXS) {
                            Button("Generate bracket") { Task { await viewModel.generate() } }
                                .buttonStyle(ConsoleButtonStyle(kind: .primary))
                            Button("Auto-assign seats") { Task { await viewModel.autoAssign() } }
                                .buttonStyle(ConsoleButtonStyle(kind: .secondary))
                        }
                        if let error = viewModel.error {
                            Text(error).foregroundStyle(palette.error).font(Theme.captionFont())
                        }
                    }
                }
                ConsolePanel(title: "Participants") {
                    TextField("Display name", text: $viewModel.newName)
                    Button("Add & check in") { Task { await viewModel.addParticipant() } }
                        .buttonStyle(ConsoleButtonStyle(kind: .primary))
                    ForEach(viewModel.participants.sorted(by: { $0.seedIndex < $1.seedIndex })) { p in
                        HStack {
                            Text("\(p.seedIndex). \(p.displayName)")
                                .font(Theme.bodyFont())
                                .foregroundStyle(palette.text)
                            Spacer()
                            Button(p.isCheckedIn ? "Checked in" : "Check in") {
                                Task { await viewModel.toggleCheckIn(p) }
                            }
                            .buttonStyle(ConsoleButtonStyle(kind: p.isCheckedIn ? .ghost : .secondary))
                        }
                    }
                }
                ConsolePanel(title: "Bracket / Matches") {
                    NavigationLink("Bracket") {
                        BracketView(matches: viewModel.matches, participants: viewModel.participants)
                    }
                    NavigationLink("Matches") {
                        MatchesView(matches: viewModel.matches, tournamentID: viewModel.tournament?.id)
                    }
                    NavigationLink("Standings") {
                        StandingsView(rows: viewModel.standings)
                    }
                }
                if !viewModel.failures.isEmpty {
                    ConsolePanel(title: "Assignment issues") {
                        ForEach(viewModel.failures) { f in
                            Text(f.reason).foregroundStyle(palette.warning).font(Theme.captionFont())
                        }
                    }
                }
            }
            .padding(Theme.spaceM)
            .padding(.bottom, Theme.consoleBottomClearance)
        }
        .background(palette.background)
        .navigationTitle(viewModel.tournament?.name ?? "Tournament")
        .toolbar { EditButton() }
        .task { await viewModel.reload() }
    }
}

struct BracketView: View {
    @Environment(\.themePalette) private var palette

    let matches: [Match]
    let participants: [Participant]

    var body: some View {
        let rounds = Dictionary(grouping: matches, by: \.roundIndex).keys.sorted()
        GeometryReader { geo in
            let columnWidth = min(max(geo.size.width * 0.42, 120), 220)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: Theme.spaceS) {
                    ForEach(rounds, id: \.self) { round in
                        VStack(alignment: .leading, spacing: Theme.spaceXS) {
                            Text("Round \(round + 1)")
                                .font(Theme.captionFont())
                                .foregroundStyle(palette.secondaryText)
                            ForEach(matches.filter { $0.roundIndex == round }.sorted(by: { $0.slotIndex < $1.slotIndex })) { match in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(name(match.participantAID))
                                    Text(name(match.participantBID))
                                    Text(match.isBye ? "BYE" : "\(match.scoreA)-\(match.scoreB)")
                                        .font(Theme.numeral(weight: .semibold))
                                        .foregroundStyle(palette.primary)
                                    Text(match.status.displayName)
                                        .font(Theme.captionFont())
                                        .foregroundStyle(palette.secondaryText)
                                }
                                .padding(10)
                                .frame(width: columnWidth, alignment: .leading)
                                .background(ConsoleTokens.panelFill)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                                        .stroke(ConsoleTokens.bezel, lineWidth: ConsoleTokens.bezelWidth)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
                            }
                        }
                    }
                }
                .padding()
                .padding(.bottom, Theme.consoleBottomClearance)
            }
        }
        .background(palette.background)
        .navigationTitle("Bracket")
    }

    private func name(_ id: UUID?) -> String {
        guard let id else { return "—" }
        return participants.first(where: { $0.id == id })?.displayName ?? "TBD"
    }
}

struct StandingsView: View {
    @Environment(\.themePalette) private var palette

    let rows: [StandingRow]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Theme.spaceXS) {
                ForEach(rows) { row in
                    ConsolePanel {
                        HStack {
                            Text("\(row.seedIndex)")
                                .font(Theme.numeral(weight: .semibold))
                                .foregroundStyle(palette.secondaryText)
                            Text(row.displayName)
                                .foregroundStyle(palette.text)
                            Spacer()
                            Text("\(row.points) pts")
                                .font(Theme.numeral())
                            Text("BH \(row.buchholz)/\(row.medianBuchholz)")
                                .font(Theme.captionFont())
                                .foregroundStyle(palette.secondaryText)
                        }
                    }
                }
            }
            .padding(Theme.spaceM)
        }
        .background(palette.background)
        .navigationTitle("Standings")
    }
}

struct MatchesView: View {
    @Environment(\.themePalette) private var palette

    let matches: [Match]
    let tournamentID: UUID?
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Theme.spaceXS) {
                ForEach(matches.sorted(by: {
                    let ls = $0.scheduledAt ?? .distantFuture
                    let rs = $1.scheduledAt ?? .distantFuture
                    if ls != rs { return ls < rs }
                    if $0.roundIndex != $1.roundIndex { return $0.roundIndex < $1.roundIndex }
                    return $0.slotIndex < $1.slotIndex
                })) { match in
                    NavigationLink {
                        MatchDetailView(matchID: match.id)
                    } label: {
                        ConsolePanel {
                            Text("R\(match.roundIndex + 1) · Slot \(match.slotIndex + 1)")
                                .font(Theme.headlineFont())
                                .foregroundStyle(palette.text)
                            KeyValueRow(
                                key: "Score",
                                value: "\(match.scoreA)-\(match.scoreB)"
                            )
                            Text(match.status.displayName)
                                .font(Theme.captionFont())
                                .foregroundStyle(palette.secondaryText)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Theme.spaceM)
        }
        .background(palette.background)
        .navigationTitle("Matches")
    }
}

@MainActor
final class MatchDetailViewModel: ObservableObject {
    @Published var match: Match?
    @Published var scoreA = "0"
    @Published var scoreB = "0"
    @Published var confirmInvalidate = false
    @Published var needsConfirm = false
    @Published var error: String?
    private let matchID: UUID
    private let environment: AppEnvironment
    init(matchID: UUID, environment: AppEnvironment) {
        self.matchID = matchID
        self.environment = environment
    }

    func reload() async {
        match = try? await environment.tournaments.fetchMatch(id: matchID)
        if let match {
            scoreA = "\(match.scoreA)"
            scoreB = "\(match.scoreB)"
        }
    }

    func save(confirm: Bool) async {
        do {
            try await environment.tournaments.enterResult(
                matchID: matchID,
                scoreA: Int(scoreA) ?? 0,
                scoreB: Int(scoreB) ?? 0,
                confirmInvalidateDownstream: confirm
            )
            needsConfirm = false
            error = nil
            await reload()
        } catch DatabaseError.needsDownstreamConfirmation {
            needsConfirm = true
            error = nil
        } catch {
            needsConfirm = false
            self.error = error.localizedDescription
        }
    }

    func walkover(winnerIsA: Bool) async {
        guard let match else { return }
        let need: Int
        if let tournament = try? await environment.tournaments.fetch(id: match.tournamentID) {
            need = tournament.bestOf / 2 + 1
        } else {
            need = 1
        }
        scoreA = winnerIsA ? "\(need)" : "0"
        scoreB = winnerIsA ? "0" : "\(need)"
        await save(confirm: false)
    }
}

struct MatchDetailView: View {
    @Environment(\.themePalette) private var palette

    @EnvironmentObject private var environment: AppEnvironment
    let matchID: UUID
    @StateObject private var holder = VMHolder<MatchDetailViewModel>()

    var body: some View {
        Group {
            if let vm = holder.value { MatchDetailContent(viewModel: vm) }
            else { ProgressView().tint(palette.accent) }
        }
        .onAppear {
            if holder.value == nil {
                holder.value = MatchDetailViewModel(matchID: matchID, environment: environment)
            }
        }
    }
}

struct MatchDetailContent: View {
    @Environment(\.themePalette) private var palette

    @ObservedObject var viewModel: MatchDetailViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spaceM) {
                if let match = viewModel.match {
                    ConsolePanel(title: "Match") {
                        KeyValueRow(key: "Round", value: "\(match.roundIndex + 1)")
                        KeyValueRow(key: "Slot", value: "\(match.slotIndex + 1)")
                        KeyValueRow(key: "Status", value: match.status.displayName)
                        if match.isBye {
                            StatusLamp(tone: .watch, label: "Bye")
                        }
                    }
                    ConsolePanel(title: "Scores") {
                        TextField("Score A", text: $viewModel.scoreA).keyboardType(.numberPad)
                        TextField("Score B", text: $viewModel.scoreB).keyboardType(.numberPad)
                        Button("Save result") { Task { await viewModel.save(confirm: false) } }
                            .buttonStyle(ConsoleButtonStyle(kind: .primary))
                        HStack {
                            Button("Walkover A") { Task { await viewModel.walkover(winnerIsA: true) } }
                                .buttonStyle(ConsoleButtonStyle(kind: .secondary))
                            Button("Walkover B") { Task { await viewModel.walkover(winnerIsA: false) } }
                                .buttonStyle(ConsoleButtonStyle(kind: .secondary))
                        }
                    }
                    if let error = viewModel.error {
                        AlertBanner(level: .critical, title: "Could not save", detail: error)
                    }
                }
            }
            .padding(Theme.spaceM)
        }
        .background(palette.background)
        .navigationTitle("Match")
        .task { await viewModel.reload() }
        .confirmationDialog(
            "Editing this result clears downstream matches.",
            isPresented: $viewModel.needsConfirm,
            titleVisibility: .visible
        ) {
            Button("Confirm invalidate", role: .destructive) {
                Task { await viewModel.save(confirm: true) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
