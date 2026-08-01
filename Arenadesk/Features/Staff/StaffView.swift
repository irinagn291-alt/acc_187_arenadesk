import SwiftUI

@MainActor
final class StaffViewModel: ObservableObject {
    @Published var employees: [Employee] = []
    private let environment: AppEnvironment
    init(environment: AppEnvironment) { self.environment = environment }
    func reload() async {
        employees = (try? await environment.employees.fetchAll()) ?? []
    }
}

struct StaffView: View {

    @Environment(\.themePalette) private var palette
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var holder = VMHolder<StaffViewModel>()

    var body: some View {
        Group {
            if let vm = holder.value { StaffContent(viewModel: vm) }
            else { ProgressView().tint(palette.accent) }
        }
        .onAppear { if holder.value == nil { holder.value = StaffViewModel(environment: environment) } }
    }
}

struct StaffContent: View {
    @Environment(\.themePalette) private var palette

    @ObservedObject var viewModel: StaffViewModel

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spaceS) {
                    NavigationLink {
                        ScheduleView()
                    } label: {
                        ConsolePanel {
                            Text("Week schedule")
                                .font(Theme.headlineFont())
                                .foregroundStyle(palette.text)
                        }
                    }
                    .buttonStyle(.plain)
                    ForEach(viewModel.employees) { employee in
                        NavigationLink {
                            EmployeeDetailView(employeeID: employee.id)
                        } label: {
                            ConsolePanel {
                                Text(employee.fullName).font(Theme.headlineFont()).foregroundStyle(palette.text)
                                Text(employee.role.displayName)
                                    .font(Theme.captionFont()).foregroundStyle(palette.primary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Theme.spaceM)
                .padding(.bottom, Theme.consoleBottomClearance)
            }
        }
        .consoleRootChrome(title: "Staff", subtitle: "Employees and weekly schedule")
        .task { await viewModel.reload() }
    }
}

@MainActor
final class EmployeeDetailViewModel: ObservableObject {
    @Published var employee: Employee?
    @Published var shifts: [Shift] = []
    @Published var newPIN = ""
    private let employeeID: UUID
    private let environment: AppEnvironment
    init(employeeID: UUID, environment: AppEnvironment) {
        self.employeeID = employeeID
        self.environment = environment
    }

    func reload() async {
        employee = try? await environment.employees.fetch(id: employeeID)
        shifts = (try? await environment.schedule.shiftsForEmployee(employeeID)) ?? []
    }

    func setPIN() async {
        guard var employee, newPIN.count == 6, newPIN.allSatisfy(\.isNumber) else { return }
        let salt = PINHasher.makeSalt()
        employee.pinSalt = salt
        employee.pinHash = PINHasher.hash(pin: newPIN, salt: salt)
        try? await environment.employees.upsert(employee)
        newPIN = ""
        await reload()
    }

    func clearPIN() async {
        guard var employee else { return }
        employee.pinHash = nil
        employee.pinSalt = nil
        try? await environment.employees.upsert(employee)
        await reload()
    }
}

struct EmployeeDetailView: View {
    @Environment(\.themePalette) private var palette

    @EnvironmentObject private var environment: AppEnvironment
    let employeeID: UUID
    @StateObject private var holder = VMHolder<EmployeeDetailViewModel>()

    var body: some View {
        Group {
            if let vm = holder.value { EmployeeDetailContent(viewModel: vm) }
            else { ProgressView().tint(palette.accent) }
        }
        .onAppear {
            if holder.value == nil {
                holder.value = EmployeeDetailViewModel(employeeID: employeeID, environment: environment)
            }
        }
    }
}

struct EmployeeDetailContent: View {
    @Environment(\.themePalette) private var palette

    @ObservedObject var viewModel: EmployeeDetailViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spaceM) {
                if let employee = viewModel.employee {
                    ConsolePanel(title: "Profile") {
                        KeyValueRow(key: "Name", value: employee.fullName, mono: false)
                        KeyValueRow(key: "Role", value: employee.role.displayName)
                        KeyValueRow(key: "Phone", value: employee.phone)
                    }
                    ConsolePanel(title: "PIN") {
                        SecureField("New 6-digit PIN", text: $viewModel.newPIN).keyboardType(.numberPad)
                        Button("Set PIN") { Task { await viewModel.setPIN() } }
                            .buttonStyle(ConsoleButtonStyle(kind: .primary))
                        if employee.pinHash != nil {
                            Button("Clear PIN", role: .destructive) { Task { await viewModel.clearPIN() } }
                                .buttonStyle(ConsoleButtonStyle(kind: .warning))
                        }
                    }
                    ConsolePanel(title: "Shift history") {
                        ForEach(viewModel.shifts) { shift in
                            VStack(alignment: .leading) {
                                Text(shift.openedAt.formatted()).foregroundStyle(palette.text)
                                Text("Sessions \(shift.seatSessionCount) · Incidents \(shift.incidentCount)")
                                    .font(Theme.captionFont()).foregroundStyle(palette.secondaryText)
                            }
                        }
                    }
                }
            }
            .padding(Theme.spaceM)
            .padding(.bottom, Theme.consoleBottomClearance)
        }
        .background(palette.background)
        .navigationTitle("Employee")
        .task { await viewModel.reload() }
    }
}

@MainActor
final class ScheduleViewModel: ObservableObject {
    @Published var weekStart: Date = Calendar.current.date(from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
    @Published var plans: [PlannedShift] = []
    @Published var employees: [Employee] = []
    @Published var selectedEmployeeID: UUID?
    private let environment: AppEnvironment
    init(environment: AppEnvironment) { self.environment = environment }

    var weekEnd: Date { Calendar.current.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart }

    func reload() async {
        employees = (try? await environment.employees.fetchAll(activeOnly: true)) ?? []
        if selectedEmployeeID == nil { selectedEmployeeID = employees.first?.id }
        plans = (try? await environment.schedule.fetch(from: weekStart, to: weekEnd)) ?? []
    }

    func addPlan(dayOffset: Int) async {
        guard let employeeID = selectedEmployeeID else { return }
        let day = Calendar.current.date(byAdding: .day, value: dayOffset, to: weekStart) ?? weekStart
        let start = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: day) ?? day
        let end = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: day) ?? day
        let plan = PlannedShift(id: UUID(), employeeID: employeeID, startsAt: start, endsAt: end, note: "")
        try? await environment.schedule.upsert(plan)
        await reload()
    }
}

struct ScheduleView: View {
    @Environment(\.themePalette) private var palette

    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var holder = VMHolder<ScheduleViewModel>()

    var body: some View {
        Group {
            if let vm = holder.value { ScheduleContent(viewModel: vm) }
            else { ProgressView().tint(palette.accent) }
        }
        .onAppear { if holder.value == nil { holder.value = ScheduleViewModel(environment: environment) } }
    }
}

struct ScheduleContent: View {
    @Environment(\.themePalette) private var palette

    @ObservedObject var viewModel: ScheduleViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spaceM) {
                ConsolePanel {
                    DatePicker("Week of", selection: $viewModel.weekStart, displayedComponents: .date)
                        .onChange(of: viewModel.weekStart) { _ in Task { await viewModel.reload() } }
                    Picker("Employee", selection: $viewModel.selectedEmployeeID) {
                        ForEach(viewModel.employees) { Text($0.fullName).tag(Optional($0.id)) }
                    }
                }
                ConsolePanel(title: "Days") {
                    ForEach(0..<7, id: \.self) { offset in
                        let day = Calendar.current.date(byAdding: .day, value: offset, to: viewModel.weekStart) ?? viewModel.weekStart
                        let dayPlans = viewModel.plans.filter {
                            Calendar.current.isDate($0.startsAt, inSameDayAs: day)
                        }
                        VStack(alignment: .leading) {
                            HStack {
                                Text(day.formatted(date: .abbreviated, time: .omitted))
                                    .foregroundStyle(palette.text)
                                Spacer()
                                Button("Add") { Task { await viewModel.addPlan(dayOffset: offset) } }
                                    .buttonStyle(ConsoleButtonStyle(kind: .ghost))
                            }
                            ForEach(dayPlans) { plan in
                                Text(employeeName(plan.employeeID) + " \(plan.startsAt.formatted(date: .omitted, time: .shortened))–\(plan.endsAt.formatted(date: .omitted, time: .shortened))")
                                    .font(Theme.captionFont())
                                    .foregroundStyle(palette.secondaryText)
                            }
                        }
                    }
                }
            }
            .padding(Theme.spaceM)
            .padding(.bottom, Theme.consoleBottomClearance)
        }
        .background(palette.background)
        .navigationTitle("Schedule")
        .task { await viewModel.reload() }
    }

    private func employeeName(_ id: UUID) -> String {
        viewModel.employees.first(where: { $0.id == id })?.fullName ?? "Staff"
    }
}
