import SwiftUI

struct ManagerOverrideSheet: View {

    @Environment(\.themePalette) private var palette
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var pin = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spaceM) {
                    ConsolePanel {
                        Text("Access control is advisory. A manager PIN unlocks restricted actions on this shared device.")
                            .font(Theme.captionFont())
                            .foregroundStyle(palette.secondaryText)
                    }
                    ConsolePanel(title: "Manager PIN") {
                        SecureField("6-digit PIN", text: $pin)
                            .keyboardType(.numberPad)
                        if let error {
                            Text(error).foregroundStyle(palette.error)
                        }
                    }
                }
                .padding(Theme.spaceM)
            }
            .background(palette.background)
            .navigationTitle("Manager override")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Unlock") { unlock() }
                }
            }
        }
    }

    private func unlock() {
        Task {
            let managers = (try? await environment.employees.fetchAll(activeOnly: true))?
                .filter { $0.role == .manager } ?? []
            for manager in managers {
                if let hash = manager.pinHash, let salt = manager.pinSalt,
                   PINHasher.verify(pin: pin, hash: hash, salt: salt) {
                    environment.managerOverride = true
                    dismiss()
                    return
                }
                if manager.pinHash == nil {
                    environment.managerOverride = true
                    dismiss()
                    return
                }
            }
            error = "No matching manager PIN."
        }
    }
}

struct AccessGated<Content: View>: View {
    @Environment(\.themePalette) private var palette

    @EnvironmentObject private var environment: AppEnvironment
    let capability: Capability
    @ViewBuilder var content: () -> Content

    var body: some View {
        if environment.allows(capability) {
            content()
        } else {
            VStack(spacing: Theme.spaceS) {
                Text("Restricted")
                    .font(Theme.headlineFont())
                    .foregroundStyle(palette.warning)
                Text("Your role cannot perform this action.")
                    .font(Theme.captionFont())
                    .foregroundStyle(palette.secondaryText)
                Button("Manager override") {
                    environment.showManagerOverride = true
                }
                .buttonStyle(ConsoleButtonStyle(kind: .primary))
            }
            .padding()
        }
    }
}
