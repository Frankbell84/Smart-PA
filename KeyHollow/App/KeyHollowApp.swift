import SwiftUI

@main
struct KeyHollowApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session = VaultSession()

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environmentObject(session)
                    .privacySensitive()

                // A dedicated opaque cover is rendered whenever the scene is not
                // active so iOS app-switcher snapshots never intentionally contain
                // an open vault/photo. Session state is also destroyed below.
                if scenePhase != .active {
                    PrivacyShieldView()
                        .transition(.identity)
                        .zIndex(10_000)
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                session.lock()
            }
        }
    }
}

private struct PrivacyShieldView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 14) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 44))
                Text("KEYHOLLOW")
                    .font(.headline.weight(.semibold))
                    .tracking(3)
            }
            .foregroundStyle(.white)
        }
        .accessibilityHidden(true)
    }
}
