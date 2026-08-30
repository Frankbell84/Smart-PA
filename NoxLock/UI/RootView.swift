import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: VaultSession

    var body: some View {
        Group {
            if session.isUnlocked {
                VaultPlaceholderView()
            } else {
                LockView()
            }
        }
    }
}

private struct LockView: View {
    @State private var digits = ""

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 18), count: 3)

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 52))

            Text("NOXLOCK")
                .font(.title.bold())
                .tracking(4)

            HStack(spacing: 12) {
                ForEach(0..<6, id: \.self) { index in
                    Circle()
                        .fill(index < digits.count ? Color.primary : Color.secondary.opacity(0.25))
                        .frame(width: 12, height: 12)
                }
            }
            .accessibilityLabel("Passcode entry")

            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(1...9, id: \.self) { value in key(String(value)) }
                Color.clear.frame(height: 64)
                key("0")
                Button {
                    if !digits.isEmpty { digits.removeLast() }
                } label: {
                    Image(systemName: "delete.left")
                        .frame(maxWidth: .infinity, minHeight: 64)
                }
            }
            .font(.title2)

            Spacer()
        }
        .padding(.horizontal, 38)
    }

    private func key(_ value: String) -> some View {
        Button {
            guard digits.count < 6 else { return }
            digits.append(value)
            // SECURITY TODO: Route completed passcodes through the production
            // KDF + vault discovery service. Never persist the raw passcode.
        } label: {
            Text(value)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(.thinMaterial, in: Circle())
        }
    }
}

private struct VaultPlaceholderView: View {
    @EnvironmentObject private var session: VaultSession

    var body: some View {
        NavigationStack {
            ContentUnavailableView("Encrypted Vault", systemImage: "photo.on.rectangle.angled", description: Text("Encrypted photo storage is the next implementation milestone."))
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Lock") { session.lock() }
                    }
                }
        }
    }
}
