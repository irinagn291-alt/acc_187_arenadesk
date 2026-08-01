import SwiftUI

struct HealthBreakdown: Hashable, Sendable {
    var base: Int = 100
    var incidentPenalty: Int
    var repairPenalty: Int
    var statePenalty: Int
    var equipmentPenalty: Int
    var agePenalty: Int
    var recentMaintenanceBonus: Int
    var overduePenalty: Int
    var score: Int
}

@MainActor
final class SeatDetailViewModel: ObservableObject {
    @Published var seat: GamingSeat?
    @Published var equipment: [Equipment] = []
    @Published var sessions: [SeatSession] = []
    @Published var openSessions: [SeatSession] = []
    @Published var breakdown: HealthBreakdown?
    @Published var errorMessage: String?

    let seatID: UUID
    private let environment: AppEnvironment

    init(seatID: UUID, environment: AppEnvironment) {
        self.seatID = seatID
        self.environment = environment
    }

    func reload() async {
        seat = try? await environment.seats.fetch(id: seatID)
        equipment = (try? await environment.equipment.fetch(seatID: seatID)) ?? []
        sessions = (try? await environment.sessions.fetch(seatID: seatID, limit: 20)) ?? []
        openSessions = (try? await environment.sessions.openSessions(seatID: seatID)) ?? []
        await refreshBreakdown()
    }

    func refreshBreakdown() async {
        guard let seat else { return }
        let score = (try? await environment.seats.recomputeHealth(id: seatID)) ?? seat.healthScore
        self.seat = try? await environment.seats.fetch(id: seatID)
        let factors = SeatHealthFactors(
            hardwareIncidents30d: 0,
            closedRepairs90d: 0,
            seatState: seat.state,
            worstEquipmentState: equipment.map(\.state).max(by: {
                SeatHealthCalculator.worstEquipmentPenalty($0) < SeatHealthCalculator.worstEquipmentPenalty($1)
            }),
            commissionedAt: seat.commissionedAt,
            lastMaintenanceAt: seat.lastMaintenanceAt,
            maintenanceIntervalDays: seat.maintenanceIntervalDays,
            now: .now
        )
        let statePenalty = SeatHealthCalculator.statePenalty(factors.seatState)
        let equipmentPenalty = SeatHealthCalculator.worstEquipmentPenalty(factors.worstEquipmentState)
        let months = max(0, Date().timeIntervalSince(seat.commissionedAt)) / (30 * 24 * 3600)
        let agePenalty = min(15, Int((0.5 * months).rounded(.down)))
        let recentBonus: Int = {
            guard let last = seat.lastMaintenanceAt else { return 0 }
            return Date().timeIntervalSince(last) <= 30 * 24 * 3600 ? 5 : 0
        }()
        let baseline = seat.lastMaintenanceAt ?? seat.commissionedAt
        let due = baseline.addingTimeInterval(TimeInterval(seat.maintenanceIntervalDays) * 24 * 3600)
        let overdue = Date() > due ? 10 : 0
        let incidentRepairGap = 100 - statePenalty - equipmentPenalty - agePenalty + recentBonus - overdue - score
        breakdown = HealthBreakdown(
            incidentPenalty: max(0, incidentRepairGap),
            repairPenalty: 0,
            statePenalty: statePenalty,
            equipmentPenalty: equipmentPenalty,
            agePenalty: agePenalty,
            recentMaintenanceBonus: recentBonus,
            overduePenalty: overdue,
            score: score
        )
    }

    func setState(_ state: SeatState) async {
        try? await environment.seats.updateState(id: seatID, state: state)
        await reload()
    }

    func startSession(purpose: SessionPurpose) async {
        do {
            _ = try await environment.sessions.start(
                seatID: seatID,
                shiftID: environment.activeShift?.id,
                purpose: purpose
            )
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func endSession(_ session: SeatSession) async {
        try? await environment.sessions.end(id: session.id)
        await reload()
    }
}

struct SeatDetailView: View {

    @Environment(\.themePalette) private var palette
    @EnvironmentObject private var environment: AppEnvironment
    let seatID: UUID
    @StateObject private var holder = VMHolder<SeatDetailViewModel>()

    var body: some View {
        Group {
            if let viewModel = holder.value {
                SeatDetailContent(viewModel: viewModel)
            } else {
                ProgressView().tint(palette.accent)
            }
        }
        .onAppear {
            if holder.value == nil {
                holder.value = SeatDetailViewModel(seatID: seatID, environment: environment)
            }
        }
    }
}

struct SeatDetailContent: View {
    @Environment(\.themePalette) private var palette

    @ObservedObject var viewModel: SeatDetailViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spaceM) {
                if let seat = viewModel.seat {
                    ConsolePanel(title: "Specs") {
                        KeyValueRow(key: "CPU", value: seat.cpu)
                        KeyValueRow(key: "GPU", value: seat.gpu)
                        KeyValueRow(key: "RAM", value: "\(seat.ramGB) GB")
                        KeyValueRow(key: "Storage", value: seat.storage)
                        KeyValueRow(key: "Monitor", value: "\(seat.monitorModel) @ \(seat.monitorHz) Hz")
                        KeyValueRow(key: "State", value: seat.state.displayName)
                    }
                    ConsolePanel(title: "Health") {
                        Text("\(seat.healthScore)")
                            .font(Theme.titleFont())
                            .foregroundStyle(Theme.healthColor(seat.healthScore))
                        MetricStrip(
                            fraction: Double(seat.healthScore) / 100,
                            color: Theme.healthColor(seat.healthScore)
                        )
                        Text(HealthBand.band(for: seat.healthScore).displayName)
                            .font(Theme.captionFont())
                            .foregroundStyle(Theme.healthColor(seat.healthScore))
                        if let breakdown = viewModel.breakdown {
                            KeyValueRow(key: "State penalty", value: "-\(breakdown.statePenalty)")
                            KeyValueRow(key: "Equipment penalty", value: "-\(breakdown.equipmentPenalty)")
                            KeyValueRow(key: "Age penalty", value: "-\(breakdown.agePenalty)")
                            KeyValueRow(key: "Maintenance bonus", value: "+\(breakdown.recentMaintenanceBonus)")
                            KeyValueRow(key: "Overdue penalty", value: "-\(breakdown.overduePenalty)")
                        }
                    }
                    ConsolePanel(title: "State actions") {
                        ForEach(SeatState.allCases, id: \.self) { state in
                            Button(state.displayName) {
                                Task { await viewModel.setState(state) }
                            }
                            .buttonStyle(ConsoleButtonStyle(kind: .secondary))
                            .tint(Theme.seatStateColor(state))
                        }
                    }
                }
                ConsolePanel(title: "Equipment") {
                    ForEach(viewModel.equipment) { item in
                        NavigationLink {
                            EquipmentDetailView(equipmentID: item.id)
                        } label: {
                            HStack {
                                Text(item.name).foregroundStyle(palette.text)
                                Spacer()
                                Text(item.state.displayName)
                                    .font(Theme.captionFont())
                                    .foregroundStyle(palette.secondaryText)
                            }
                        }
                    }
                    NavigationLink("All equipment") {
                        EquipmentListView(seatID: viewModel.seatID)
                    }
                }
                ConsolePanel(title: "Sessions") {
                    if viewModel.openSessions.isEmpty {
                        Button("Start walk-in session") {
                            Task { await viewModel.startSession(purpose: .walkIn) }
                        }
                        .buttonStyle(ConsoleButtonStyle(kind: .primary))
                    } else {
                        ForEach(viewModel.openSessions) { session in
                            Button("End \(session.purpose.displayName)") {
                                Task { await viewModel.endSession(session) }
                            }
                            .buttonStyle(ConsoleButtonStyle(kind: .warning))
                        }
                    }
                    ForEach(viewModel.sessions) { session in
                        VStack(alignment: .leading) {
                            Text(session.purpose.displayName).foregroundStyle(palette.text)
                            Text(session.startedAt.formatted())
                                .font(Theme.captionFont())
                                .foregroundStyle(palette.secondaryText)
                        }
                    }
                }
                if let error = viewModel.errorMessage {
                    AlertBanner(level: .critical, title: "Session error", detail: error)
                }
            }
            .padding(Theme.spaceM)
            .padding(.bottom, Theme.consoleBottomClearance)
        }
        .background(palette.background)
        .navigationTitle(viewModel.seat?.label ?? "Seat")
        .task { await viewModel.reload() }
    }
}
