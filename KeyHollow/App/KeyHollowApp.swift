import Foundation
import SwiftUI

@main
struct KeyHollowApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session = VaultSession()

    private var isHostedUnitTest: Bool {
        NSClassFromString("XCTestCase") != nil
    }

    var body: some Scene {
        WindowGroup {
            if isHostedUnitTest {
                // Security unit tests are hosted by the app executable so they can
                // import internal crypto types. Avoid bootstrapping the production
                // navigation hierarchy in that test host; the prior CI failure was
                // a SwiftUI navigation-bar assertion before XCTest could start.
                Color.clear
            } else {
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
