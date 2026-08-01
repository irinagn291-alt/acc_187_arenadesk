import SwiftUI

@MainActor
final class IncidentsViewModel: ObservableObject {
    @Published var incidents: [Incident] = []
    @Published var severityFilter: IncidentSeverity?
    @Published var unresolvedOnly = false
    private let environment: AppEnvironment
    init(environment: AppEnvironment) { self.environment = environment }

    var filtered: [Incident] {
        incidents.filter { i in
            if let severityFilter, i.severity != severityFilter { return false }
            if unresolvedOnly && i.isResolved { return false }
            return true
        }
    }

    func reload() async {
        incidents = (try? await environment.incidents.fetchAll()) ?? []
    }
}

struct IncidentsView: View {

    @Environment(\.themePalette) private var palette
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var holder = VMHolder<IncidentsViewModel>()

    var body: some View {
        Group {
            if let vm = holder.value {
                AccessGated(capability: .fileIncidents) {
                    IncidentsContent(viewModel: vm)
                }
            } else { ProgressView().tint(palette.accent) }
        }
        .onAppear { if holder.value == nil { holder.value = IncidentsViewModel(environment: environment) } }
    }
}

struct IncidentsContent: View {
    @Environment(\.themePalette) private var palette

    @ObservedObject var viewModel: IncidentsViewModel

    var body: some View {
        Group {
            if viewModel.incidents.isEmpty {
                NothingHereView(image: .emptyIncidents, title: "No incidents", detail: "File an incident when something goes wrong on the floor.")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.spaceM) {
                        ConsolePanel(title: "Filters") {
                            Picker("Severity", selection: $viewModel.severityFilter) {
                                Text("All").tag(Optional<IncidentSeverity>.none)
                                ForEach(IncidentSeverity.allCases, id: \.self) {
                                    Text($0.displayName).tag(Optional($0))
                                }
                            }
                            Toggle("Unresolved only", isOn: $viewModel.unresolvedOnly)
                        }
                        ForEach(viewModel.filtered) { incident in
                            NavigationLink {
                                IncidentEditorView(incident: incident) { await viewModel.reload() }
                            } label: {
                                ConsolePanel {
                                    Text(incident.summary)
                                        .font(Theme.headlineFont())
                                        .foregroundStyle(palette.text)
                                    Text("\(incident.severity.displayName) · \(incident.kind.displayName)")
                                        .font(Theme.captionFont())
                                        .foregroundStyle(incident.isResolved ? palette.secondaryText : palette.warning)
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
        .background(palette.background)
        .navigationTitle("Incidents")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink("New") {
                    IncidentEditorView(incident: nil) { await viewModel.reload() }
                }
            }
        }
        .task { await viewModel.reload() }
    }
}

struct IncidentEditorView: View {
    @Environment(\.themePalette) private var palette
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    let incident: Incident?
    var onSave: () async -> Void

    @State private var summary = ""
    @State private var resolution = ""
    @State private var severity: IncidentSeverity = .medium
    @State private var kind: IncidentKind = .hardware
    @State private var isResolved = false
    @State private var zones: [Zone] = []
    @State private var seats: [GamingSeat] = []
    @State private var zoneID: UUID?
    @State private var seatID: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spaceM) {
                ConsolePanel(title: "Details") {
                    TextField("Summary", text: $summary)
                    Picker("Severity", selection: $severity) {
                        ForEach(IncidentSeverity.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    Picker("Kind", selection: $kind) {
                        ForEach(IncidentKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    Picker("Zone", selection: $zoneID) {
                        Text("None").tag(Optional<UUID>.none)
                        ForEach(zones) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Picker("Seat", selection: $seatID) {
                        Text("None").tag(Optional<UUID>.none)
                        ForEach(seats.filter { zoneID == nil || $0.zoneID == zoneID }) { Text($0.label).tag(Optional($0.id)) }
                    }
                }
                ConsolePanel(title: "Resolution") {
                    TextField("Resolution", text: $resolution, axis: .vertical)
                    Toggle("Resolved", isOn: $isResolved)
                }
            }
            .padding(Theme.spaceM)
        }
        .background(palette.background)
        .navigationTitle(incident == nil ? "New incident" : "Incident")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
            }
        }
        .task {
            zones = (try? await environment.zones.fetchAll()) ?? []
            seats = (try? await environment.seats.fetchAll()) ?? []
            if let incident {
                summary = incident.summary
                resolution = incident.resolution
                severity = incident.severity
                kind = incident.kind
                isResolved = incident.isResolved
                zoneID = incident.zoneID
                seatID = incident.seatID
            }
        }
    }

    private func save() async {
        let saved = Incident(
            id: incident?.id ?? UUID(),
            shiftID: environment.activeShift?.id ?? incident?.shiftID,
            zoneID: zoneID,
            seatID: seatID,
            severity: severity,
            kind: kind,
            occurredAt: incident?.occurredAt ?? .now,
            reportedByID: environment.activeEmployeeID,
            summary: summary,
            resolution: resolution,
            isResolved: isResolved,
            isArchived: incident?.isArchived ?? false
        )
        try? await environment.incidents.upsert(saved)
        await onSave()
        dismiss()
    }
}
