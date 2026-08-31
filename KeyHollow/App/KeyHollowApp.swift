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
        }
        .onChange(of: scenePhase) { _, newPhase in
            if VaultLifecycleLockPolicy.shouldLock(
                for: newPhase,
                systemPhotoOperationActive: session.isSystemPhotoOperationActive
            ) {
                session.lock()
            }
        }
        .onChange(of: session.isSystemPhotoOperationActive) { _, operationActive in
            // The Photos completion callback can arrive while the scene is still
            // inactive, immediately before iOS returns it to active. Locking in
            // that handoff would force an unnecessary passcode re-entry. A real
            // app switch reaches background and still fails closed.
            if !operationActive,
               VaultLifecycleLockPolicy.shouldLockWhenPhotoOperationEnds(
                   scenePhase: scenePhase
               ) {
                session.lock()
            }
        }
    }
}

enum VaultLifecycleLockPolicy {
    static func shouldLock(
        for phase: ScenePhase,
        systemPhotoOperationActive: Bool
    ) -> Bool {
        switch phase {
        case .active:
            return false
        case .background:
            return true
        case .inactive:
            // iOS presents the user-requested Photos deletion confirmation by
            // temporarily making the app inactive. The opaque privacy shield
            // remains visible, but the vault key may survive only this scoped
            // system interaction. A real background transition still locks.
            return !systemPhotoOperationActive
        @unknown default:
            return true
        }
    }

    static func shouldLockWhenPhotoOperationEnds(scenePhase: ScenePhase) -> Bool {
        scenePhase == .background
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

