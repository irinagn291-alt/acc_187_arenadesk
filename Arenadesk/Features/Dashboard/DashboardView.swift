import SwiftUI

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var activeShift: Shift?
    @Published var employeeName: String?
    @Published var zones: [ZoneSummary] = []
    @Published var lowestHealth: [GamingSeat] = []
    @Published var sessionCount = 0
    @Published var incidentCount = 0
    @Published var dueMaintenance = 0
    @Published var lowStock = 0
    @Published var showOpenShift = false
    @Published var showCloseShift = false

    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func reload() async {
        let snapshot = try? await environment.shifts.dashboardSnapshot(seatLimit: 5)
        activeShift = snapshot?.activeShift
        environment.activeShift = activeShift
        zones = snapshot?.zones ?? []
        lowestHealth = snapshot?.lowestHealth ?? []
        sessionCount = snapshot?.counters.sessions ?? 0
        incidentCount = snapshot?.counters.incidents ?? 0
        dueMaintenance = snapshot?.dueMaintenance ?? 0
        lowStock = snapshot?.lowStock ?? 0
        employeeName = snapshot?.employeeName
    }
}

struct DashboardView: View {

    @Environment(\.themePalette) private var palette
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var holder = VMHolder<DashboardViewModel>()

    var body: some View {
        Group {
            if let viewModel = holder.value {
                DashboardContent(viewModel: viewModel)
            } else {
                ProgressView().tint(palette.accent)
            }
        }
        .onAppear {
            if holder.value == nil {
                holder.value = DashboardViewModel(environment: environment)
            }
        }
    }
}

struct DashboardContent: View {
    @Environment(\.themePalette) private var palette

    @EnvironmentObject private var environment: AppEnvironment
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spaceM) {
                    FloorBanner(
                        image: .dashboardBanner,
                        caption: "Live floor readiness",
                        height: 170
                    )
                    shiftCard
                    zoneStrip
                    healthSection
                    counters
                    alerts
                    quickActions
                }
                .padding(Theme.spaceM)
                .padding(.bottom, Theme.consoleBottomClearance)
            }
        }
        .consoleRootChrome(title: "Dashboard", subtitle: "Shift, zones, and floor health")
        .task { await viewModel.reload() }
        .sheet(isPresented: $viewModel.showOpenShift) {
            NavigationStack {
                ShiftOpenView { await viewModel.reload() }
            }
        }
        .sheet(isPresented: $viewModel.showCloseShift) {
            NavigationStack {
                ShiftCloseView { await viewModel.reload() }
            }
        }
    }

    private var shiftCard: some View {
        ConsolePanel(title: "Active shift") {
            if let shift = viewModel.activeShift {
                Text(viewModel.employeeName ?? "Staff")
                    .font(Theme.headlineFont())
                    .foregroundStyle(palette.text)
                KeyValueRow(
                    key: "Opened",
                    value: shift.openedAt.formatted(date: .omitted, time: .shortened)
                )
                StatusLamp(tone: .ready, label: "Live")
            } else {
                Text("No open shift")
                    .font(Theme.headlineFont())
                    .foregroundStyle(palette.warning)
                StatusLamp(tone: .watch, label: "Idle")
            }
        }
    }

    private var zoneStrip: some View {
        ConsolePanel(title: "Zone readiness") {
            if viewModel.zones.isEmpty {
                Text("No zones yet")
                    .font(Theme.captionFont())
                    .foregroundStyle(palette.secondaryText)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.spaceS) {
                        ForEach(viewModel.zones) { summary in
                            VStack(spacing: Theme.spaceXS) {
                                summary.zone.kind.badgeImage.image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 44, height: 44)
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
                                    .accessibilityHidden(true)
                                ReadinessDial(title: summary.zone.name, value: summary.readiness)
                            }
                        }
                    }
                }
            }
        }
    }

    private var healthSection: some View {
        ConsolePanel(title: "Lowest health seats") {
            if viewModel.lowestHealth.isEmpty {
                Text("No seats tracked")
                    .font(Theme.captionFont())
                    .foregroundStyle(palette.secondaryText)
            } else {
                ForEach(viewModel.lowestHealth) { seat in
                    NavigationLink {
                        SeatDetailView(seatID: seat.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(seat.label)
                                    .font(Theme.numeral(weight: .semibold))
                                    .foregroundStyle(palette.text)
                                Spacer()
                                Text("\(seat.healthScore)")
                                    .font(Theme.numeral(weight: .semibold))
                                    .foregroundStyle(Theme.healthColor(seat.healthScore))
                            }
                            MetricStrip(
                                fraction: Double(seat.healthScore) / 100,
                                color: Theme.healthColor(seat.healthScore)
                            )
                            Text(HealthBand.band(for: seat.healthScore).displayName)
                                .font(Theme.captionFont())
                                .foregroundStyle(Theme.healthColor(seat.healthScore))
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private var counters: some View {
        HStack(spacing: Theme.spaceS) {
            counter("Sessions", value: "\(viewModel.sessionCount)", tone: .info)
            counter("Incidents", value: "\(viewModel.incidentCount)", tone: viewModel.incidentCount > 0 ? .watch : .ready)
        }
    }

    private func counter(_ title: String, value: String, tone: StatusLamp.Tone) -> some View {
        ConsolePanel {
            StatusLamp(tone: tone, label: title)
            Text(value)
                .font(Theme.titleFont())
                .foregroundStyle(palette.text)
                .contentTransition(.numericText())
        }
    }

    @ViewBuilder
    private var alerts: some View {
        if viewModel.dueMaintenance > 0 {
            NavigationLink {
                MaintenanceView()
            } label: {
                AlertBanner(
                    level: .watch,
                    title: "Due maintenance",
                    detail: "\(viewModel.dueMaintenance) task\(viewModel.dueMaintenance == 1 ? "" : "s") waiting"
                )
            }
            .buttonStyle(.plain)
        }
        if viewModel.lowStock > 0 {
            NavigationLink {
                InventoryView()
            } label: {
                AlertBanner(
                    level: .critical,
                    title: "Low stock",
                    detail: "\(viewModel.lowStock) item\(viewModel.lowStock == 1 ? "" : "s") at or below minimum"
                )
            }
            .buttonStyle(.plain)
        }
        if viewModel.dueMaintenance == 0 && viewModel.lowStock == 0 {
            AlertBanner(
                level: .info,
                title: "All clear",
                detail: "No maintenance or stock alerts"
            )
        }
    }

    private var quickActions: some View {
        HStack(spacing: Theme.spaceS) {
            if environment.allows(.openCloseShift) {
                if viewModel.activeShift == nil {
                    Button("Open shift") { viewModel.showOpenShift = true }
                        .buttonStyle(ConsoleButtonStyle(kind: .primary))
                } else {
                    Button("Close shift") { viewModel.showCloseShift = true }
                        .buttonStyle(ConsoleButtonStyle(kind: .warning))
                }
            }
            NavigationLink("Floor") { FloorView() }
                .buttonStyle(ConsoleButtonStyle(kind: .secondary))
            if environment.allows(.financeAndAnalytics) {
                NavigationLink("Analytics") { AnalyticsView() }
                    .buttonStyle(ConsoleButtonStyle(kind: .ghost))
            }
        }
    }
}

@MainActor
final class VMHolder<T: ObservableObject>: ObservableObject {
    @Published var value: T?
}
