import SwiftUI

@main
struct NoxLockApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session = VaultSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .privacySensitive()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                session.lock()
            }
        }
    }
}
