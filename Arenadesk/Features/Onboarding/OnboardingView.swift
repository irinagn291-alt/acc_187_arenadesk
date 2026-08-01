import SwiftUI

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var venueName = ""
    @Published var address = ""
    @Published var phone = ""
    @Published var currencyCode = "USD"
    @Published var seatHourlyRate = "5.00"
    @Published var zoneName = "Main Floor"
    @Published var zoneKind: ZoneKind = .standard
    @Published var seatCount = "8"
    @Published var seatPrefix = "A"
    @Published var employeeName = ""
    @Published var employeeRole: EmployeeRole = .manager
    @Published var employeePhone = ""
    @Published var pin = ""
    @Published var step = 0
    @Published var errorMessage: String?

    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    var canAdvance: Bool {
        switch step {
        case 0: !venueName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case 1: (Int(seatCount) ?? 0) > 0 && !zoneName.isEmpty
        case 2: !employeeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default: true
        }
    }

    func finish() async -> Bool {
        errorMessage = nil
        let rate = MoneyFormat.decimal(from: seatHourlyRate) ?? 5
        let count = max(1, Int(seatCount) ?? 8)
        let venue = Venue(
            id: UUID(),
            name: venueName.trimmingCharacters(in: .whitespacesAndNewlines),
            address: address,
            phone: phone,
            openingTime: DateComponents(hour: 10, minute: 0),
            closingTime: DateComponents(hour: 22, minute: 0),
            currencyCode: currencyCode.uppercased(),
            seatHourlyRate: rate
        )
        let zone = Zone(
            id: UUID(),
            name: zoneName,
            kind: zoneKind,
            capacity: count,
            sortIndex: 0,
            note: ""
        )
        var seats: [GamingSeat] = []
        for index in 1...count {
            seats.append(
                GamingSeat(
                    id: UUID(),
                    zoneID: zone.id,
                    label: "\(seatPrefix)-\(String(format: "%02d", index))",
                    state: .ready,
                    cpu: "Ryzen 5",
                    gpu: "RTX 3060",
                    ramGB: 16,
                    storage: "1TB NVMe",
                    monitorModel: "27\" IPS",
                    monitorHz: 144,
                    commissionedAt: .now,
                    lastMaintenanceAt: nil,
                    maintenanceIntervalDays: 30,
                    healthScore: 100,
                    note: ""
                )
            )
        }
        var pinHash: String?
        var pinSalt: String?
        if pin.count == 6, pin.allSatisfy(\.isNumber) {
            let salt = PINHasher.makeSalt()
            pinSalt = salt
            pinHash = PINHasher.hash(pin: pin, salt: salt)
        }
        let employee = Employee(
            id: UUID(),
            fullName: employeeName.trimmingCharacters(in: .whitespacesAndNewlines),
            role: employeeRole,
            phone: employeePhone,
            hiredAt: .now,
            hourlyRate: 0,
            isActive: true,
            note: "",
            pinHash: pinHash,
            pinSalt: pinSalt
        )
        do {
            try await environment.venues.upsert(venue)
            try await environment.zones.upsert(zone)
            try await environment.seats.upsertMany(seats)
            try await environment.employees.upsert(employee)
            try await environment.checklists.seedDefaultsIfNeeded()
            environment.activeEmployeeID = employee.id
            await environment.reloadDashboardContext()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

@MainActor
private final class OnboardingHolder: ObservableObject {
    @Published var viewModel: OnboardingViewModel?
}

struct OnboardingView: View {

    @Environment(\.themePalette) private var palette
    @EnvironmentObject private var environment: AppEnvironment
    var onFinished: () -> Void
    @StateObject private var holder = OnboardingHolder()

    var body: some View {
        Group {
            if let viewModel = holder.viewModel {
                OnboardingContent(viewModel: viewModel, onFinished: onFinished)
            } else {
                ProgressView().tint(palette.accent)
            }
        }
        .onAppear {
            if holder.viewModel == nil {
                holder.viewModel = OnboardingViewModel(environment: environment)
            }
        }
    }
}

struct OnboardingContent: View {
    @Environment(\.themePalette) private var palette

    @ObservedObject var viewModel: OnboardingViewModel
    var onFinished: () -> Void

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            VStack(spacing: Theme.spaceM) {
                Text("Arenadesk")
                    .font(Theme.titleFont())
                    .foregroundStyle(palette.primary)
                stepImage.image
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 160)
                    .padding(.horizontal, Theme.spaceL)
                Text(stepTitle)
                    .font(Theme.headlineFont())
                    .foregroundStyle(palette.text)
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.spaceS) {
                        stepFields
                    }
                    .padding(.horizontal, Theme.spaceM)
                }
                if let error = viewModel.errorMessage {
                    Text(error).font(Theme.captionFont()).foregroundStyle(palette.error)
                }
                HStack {
                    if viewModel.step > 0 {
                        Button("Back") { viewModel.step -= 1 }
                            .foregroundStyle(palette.secondaryText)
                    }
                    Spacer()
                    Button(viewModel.step == 2 ? "Finish" : "Continue") {
                        Task {
                            if viewModel.step < 2 {
                                viewModel.step += 1
                            } else if await viewModel.finish() {
                                onFinished()
                            }
                        }
                    }
                    .disabled(!viewModel.canAdvance)
                    .buttonStyle(.borderedProminent)
                    .tint(palette.primary)
                }
                .padding(.horizontal, Theme.spaceM)
                .padding(.bottom, Theme.spaceM)
            }
            .padding(.top, Theme.spaceL)
        }
    }

    private var stepTitle: String {
        switch viewModel.step {
        case 0: "Venue setup"
        case 1: "First zone and seats"
        default: "First employee"
        }
    }

    private var stepImage: AppImage {
        switch viewModel.step {
        case 0: .onboardingVenue
        case 1: .onboardingFloor
        default: .onboardingChecklists
        }
    }

    @ViewBuilder
    private var stepFields: some View {
        switch viewModel.step {
        case 0:
            field("Venue name", text: $viewModel.venueName)
            field("Address", text: $viewModel.address)
            field("Phone", text: $viewModel.phone)
            field("Currency", text: $viewModel.currencyCode)
            field("Seat hourly rate", text: $viewModel.seatHourlyRate)
                .keyboardType(.decimalPad)
        case 1:
            field("Zone name", text: $viewModel.zoneName)
            Picker("Zone kind", selection: $viewModel.zoneKind) {
                ForEach(ZoneKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.menu)
            .tint(palette.primary)
            field("Seat count", text: $viewModel.seatCount)
                .keyboardType(.numberPad)
            field("Seat label prefix", text: $viewModel.seatPrefix)
        default:
            field("Full name", text: $viewModel.employeeName)
            Picker("Role", selection: $viewModel.employeeRole) {
                ForEach(EmployeeRole.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.menu)
            .tint(palette.primary)
            field("Phone", text: $viewModel.employeePhone)
            field("Optional 6-digit PIN", text: $viewModel.pin)
                .keyboardType(.numberPad)
        }
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.captionFont())
                .foregroundStyle(palette.secondaryText)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }
}
