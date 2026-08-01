import SwiftUI
import Charts

@MainActor
final class AnalyticsViewModel: ObservableObject {
    @Published var snapshot: AnalyticsSnapshot?
    @Published var rangeDays = 30
    private let environment: AppEnvironment
    init(environment: AppEnvironment) { self.environment = environment }

    func reload() async {
        let to = Date()
        let from = Calendar.current.date(byAdding: .day, value: -rangeDays, to: to) ?? to
        snapshot = try? await environment.analytics.snapshot(from: from, to: to)
    }
}

struct AnalyticsView: View {

    @Environment(\.themePalette) private var palette
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var holder = VMHolder<AnalyticsViewModel>()

    var body: some View {
        Group {
            if let vm = holder.value {
                AccessGated(capability: .financeAndAnalytics) {
                    AnalyticsContent(viewModel: vm)
                }
            } else { ProgressView().tint(palette.accent) }
        }
        .onAppear { if holder.value == nil { holder.value = AnalyticsViewModel(environment: environment) } }
    }
}

struct AnalyticsContent: View {
    @Environment(\.themePalette) private var palette

    @ObservedObject var viewModel: AnalyticsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spaceM) {
                Picker("Range", selection: $viewModel.rangeDays) {
                    Text("7d").tag(7)
                    Text("30d").tag(30)
                    Text("90d").tag(90)
                }
                .pickerStyle(.segmented)
                .onChange(of: viewModel.rangeDays) { _ in Task { await viewModel.reload() } }

                if let snapshot = viewModel.snapshot {
                    chartBlock(title: "Shifts / week", empty: snapshot.shiftsPerWeek.isEmpty) {
                        Chart(snapshot.shiftsPerWeek, id: \.weekStart) { item in
                            BarMark(x: .value("Week", item.weekStart), y: .value("Shifts", item.count))
                                .foregroundStyle(palette.primary)
                        }
                        .chartXAxis {
                            AxisMarks(values: .automatic) { _ in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                    .foregroundStyle(palette.divider)
                                AxisValueLabel().foregroundStyle(palette.secondaryText)
                            }
                        }
                        .chartYAxis {
                            AxisMarks { _ in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                    .foregroundStyle(palette.divider)
                                AxisValueLabel().foregroundStyle(palette.secondaryText)
                            }
                        }
                    }
                    ConsolePanel {
                        KeyValueRow(
                            key: "Avg shift length",
                            value: String(format: "%.1f h", snapshot.averageShiftLengthHours)
                        )
                    }
                    chartBlock(title: "Sessions / zone", empty: snapshot.sessionsPerZone.isEmpty) {
                        Chart(snapshot.sessionsPerZone, id: \.zoneName) { item in
                            BarMark(x: .value("Zone", item.zoneName), y: .value("Sessions", item.count))
                                .foregroundStyle(palette.accent)
                        }
                        .chartXAxis {
                            AxisMarks { _ in
                                AxisValueLabel().foregroundStyle(palette.secondaryText)
                            }
                        }
                        .chartYAxis {
                            AxisMarks { _ in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                    .foregroundStyle(palette.divider)
                                AxisValueLabel().foregroundStyle(palette.secondaryText)
                            }
                        }
                    }
                    chartBlock(title: "Health distribution", empty: snapshot.healthDistribution.allSatisfy { $0.count == 0 }) {
                        Chart(snapshot.healthDistribution, id: \.band) { item in
                            BarMark(
                                x: .value("Band", healthBandLabel(item.band)),
                                y: .value("Seats", item.count)
                            )
                            .foregroundStyle(by: .value("Band", healthBandLabel(item.band)))
                        }
                        .chartForegroundStyleScale([
                            HealthBand.healthy.displayName: Theme.healthBandColor(.healthy),
                            HealthBand.watch.displayName: Theme.healthBandColor(.watch),
                            HealthBand.degraded.displayName: Theme.healthBandColor(.degraded),
                            HealthBand.critical.displayName: Theme.healthBandColor(.critical)
                        ])
                        .chartLegend(.hidden)
                        .chartXAxis {
                            AxisMarks { _ in
                                AxisValueLabel().foregroundStyle(palette.secondaryText)
                            }
                        }
                        .chartYAxis {
                            AxisMarks { _ in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                    .foregroundStyle(palette.divider)
                                AxisValueLabel().foregroundStyle(palette.secondaryText)
                            }
                        }
                    }
                    ConsolePanel(title: "Problematic seats") {
                        if snapshot.problematicSeats.isEmpty {
                            Text("No incident/repair data")
                                .font(Theme.captionFont())
                                .foregroundStyle(palette.secondaryText)
                        } else {
                            ForEach(snapshot.problematicSeats, id: \.label) { row in
                                KeyValueRow(
                                    key: row.label,
                                    value: "\(row.incidents) inc / \(row.repairs) repairs"
                                )
                            }
                        }
                    }
                    ConsolePanel {
                        KeyValueRow(
                            key: "Maintenance",
                            value: "\(snapshot.maintenanceCompleted) completed / \(snapshot.maintenancePlanned) planned"
                        )
                    }
                    chartBlock(title: "Income vs expense", empty: snapshot.incomeExpenseByMonth.isEmpty) {
                        Chart {
                            ForEach(snapshot.incomeExpenseByMonth, id: \.month) { row in
                                BarMark(
                                    x: .value("Month", row.month),
                                    y: .value("Income", NSDecimalNumber(decimal: row.income).doubleValue)
                                )
                                .foregroundStyle(palette.accent)
                                BarMark(
                                    x: .value("Month", row.month),
                                    y: .value("Expense", NSDecimalNumber(decimal: row.expense).doubleValue)
                                )
                                .foregroundStyle(palette.error)
                            }
                        }
                        .chartXAxis {
                            AxisMarks { _ in
                                AxisValueLabel().foregroundStyle(palette.secondaryText)
                            }
                        }
                        .chartYAxis {
                            AxisMarks { _ in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                    .foregroundStyle(palette.divider)
                                AxisValueLabel().foregroundStyle(palette.secondaryText)
                            }
                        }
                    }
                } else {
                    Text("No analytics yet").foregroundStyle(palette.secondaryText)
                }
            }
            .padding()
            .padding(.bottom, Theme.consoleBottomClearance)
        }
        .background(palette.background)
        .navigationTitle("Analytics")
        .task { await viewModel.reload() }
    }

    private func healthBandLabel(_ raw: String) -> String {
        HealthBand(rawValue: raw)?.displayName ?? raw.capitalized
    }

    @ViewBuilder
    private func chartBlock<Content: View>(
        title: String,
        empty: Bool,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        ConsolePanel(title: title) {
            if empty {
                Text("Nothing in this range")
                    .font(Theme.captionFont())
                    .foregroundStyle(palette.secondaryText)
            } else {
                content().frame(height: 180)
            }
        }
    }
}
