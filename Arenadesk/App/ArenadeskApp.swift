import SwiftUI

@main
struct ArenadeskApp: App {
    @StateObject private var environment = AppEnvironment.live()

    init() {
        MainActor.assumeIsolated {
            FloorChrome.configure()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
                .preferredColorScheme(.dark)
        }
    }
}
