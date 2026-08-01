import SwiftUI

struct RootView: View {
    private static let gateHoldSeconds: Double = 0.6

    @EnvironmentObject private var environment: AppEnvironment
    @AppStorage(UserDefaultsKeys.onboardingCompleted) private var onboardingCompleted = false
    @State private var stage: Stage = .gate

    private enum Stage {
        case gate
        case venueSetup
        case floor
    }

    var body: some View {
        Group {
            switch stage {
            case .gate:
                LaunchGateView()
            case .venueSetup:
                OnboardingView(onFinished: completeVenueSetup)
            case .floor:
                MainTabView()
            }
        }
        .environment(\.themePalette, ThemePalette.dark)
        .preferredColorScheme(.dark)
        .task {
            await environment.bootstrap()
            try? await Task.sleep(for: .seconds(Self.gateHoldSeconds))
            guard environment.bootstrapError == nil else { return }
            stage = onboardingCompleted ? .floor : .venueSetup
        }
    }

    private func completeVenueSetup() {
        onboardingCompleted = true
        environment.markOnboardingCompleted()
        Task { await environment.notifications.requestAuthorizationIfNeeded() }
        stage = .floor
    }
}
