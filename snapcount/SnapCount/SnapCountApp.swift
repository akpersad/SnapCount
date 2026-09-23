import SwiftUI

@main
struct SnapCountApp: App {
    init() {
        // Before anything else, and in particular before the Meta SDK is configured. If the
        // opt-outs are missing, the SDK would start reporting on first use.
        PrivacyChecks.verifyOrHalt()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
