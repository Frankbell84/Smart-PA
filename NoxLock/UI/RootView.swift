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
    @State private var message: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 18), count: 3)

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 52))

            Text("NOXLOCK")
                .font(.title.bold())
                .tracking(4)

            HStack(spacing: 7) {
                ForEach(0..<min(digits.count, PasscodePolicy.maximumLength), id: \.self) { _ in
                    Circle()
                        .fill(Color.primary)
                        .frame(width: 9, height: 9)
                }

                if digits.isEmpty {
                    Text("Enter passcode")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            }
            .frame(minHeight: 20)
            .accessibilityLabel(digits.isEmpty ? "Passcode entry empty" : "Passcode entry contains \(digits.count) digits")

            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(1...9, id: \.self) { value in key(String(value)) }

                Button {
                    submit()
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity, minHeight: 64)
                }
                .disabled(digits.count < PasscodePolicy.minimumLength)
                .accessibilityLabel("Unlock")

                key("0")

                Button {
                    if !digits.isEmpty {
                        digits.removeLast()
                        message = nil
                    }
                } label: {
                    Image(systemName: "delete.left")
                        .frame(maxWidth: .infinity, minHeight: 64)
                }
                .accessibilityLabel("Delete digit")
            }
            .font(.title2)

            Spacer()
        }
        .padding(.horizontal, 38)
    }

    private func key(_ value: String) -> some View {
        Button {
            guard digits.count < PasscodePolicy.maximumLength else { return }
            digits.append(value)
            message = nil
        } label: {
            Text(value)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(.thinMaterial, in: Circle())
        }
    }

    private func submit() {
        guard PasscodePolicy.isValid(digits) else {
            message = "Use 6–20 digits."
            return
        }

        // SECURITY RELEASE GATE:
        // Route this passcode to VaultUnlockService only after the production
        // Argon2id implementation is integrated. Never persist or log `digits`.
        message = "Secure unlock engine is being configured."
        digits.removeAll(keepingCapacity: false)
    }
}

private struct VaultPlaceholderView: View {
    @EnvironmentObject private var session: VaultSession

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Encrypted Vault",
                systemImage: "photo.on.rectangle.angled",
                description: Text("Encrypted photo storage is the next implementation milestone.")
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Lock") { session.lock() }
                }
            }
        }
    }
}
