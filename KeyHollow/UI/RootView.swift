import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: VaultSession

    @State private var service: VaultUnlockService?
    @State private var setupRequired = false
    @State private var isChecking = true
    @State private var startupError: String?

    var body: some View {
        Group {
            if session.isUnlocked {
                VaultGalleryView()
            } else if isChecking {
                ProgressView("Preparing KeyHollow…")
            } else if let startupError {
                ContentUnavailableView(
                    "KeyHollow unavailable",
                    systemImage: "exclamationmark.shield",
                    description: Text(startupError)
                )
            } else if setupRequired, let service {
                InitialVaultSetupView(service: service) {
                    setupRequired = false
                }
            } else if let service {
                LockView(service: service)
            }
        }
        .task {
            guard service == nil else { return }
            do {
                let createdService = try VaultUnlockService()
                let hasVaults = try await createdService.hasAnyVaults()
                service = createdService
                setupRequired = !hasVaults
            } catch {
                startupError = "Secure local storage could not be initialized."
            }
            isChecking = false
        }
    }
}

private struct LockView: View {
    @EnvironmentObject private var session: VaultSession

    let service: VaultUnlockService

    @State private var digits = ""
    @State private var message: String?
    @State private var isWorking = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 18), count: 3)

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 52))

            Text("KEYHOLLOW")
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
                    .multilineTextAlignment(.center)
            }

            if isWorking {
                ProgressView()
            }

            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(1...9, id: \.self) { value in key(String(value)) }

                Button {
                    submit()
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity, minHeight: 64)
                }
                .disabled(digits.count < PasscodePolicy.minimumLength || isWorking)
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
                .disabled(isWorking)
                .accessibilityLabel("Delete digit")
            }
            .font(.title2)

            Spacer()
        }
        .padding(.horizontal, 38)
        .disabled(isWorking)
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
        guard PasscodePolicy.isValid(digits), !isWorking else {
            message = "Use 6–20 digits."
            return
        }

        let entered = digits
        digits.removeAll(keepingCapacity: false)
        isWorking = true
        message = nil

        Task {
            do {
                let unlocked = try await service.unlock(passcode: entered)
                session.unlock(vaultID: unlocked.vaultID, key: unlocked.vaultKey)
                isWorking = false
            } catch VaultUnlockError.temporarilyLocked(let until) {
                let wait = max(1, Int(ceil(until.timeIntervalSinceNow)))
                message = "Too many attempts. Try again in about \(wait) seconds."
                isWorking = false
            } catch {
                message = "Passcode not recognized."
                isWorking = false
            }
        }
    }
}

private struct InitialVaultSetupView: View {
    @EnvironmentObject private var session: VaultSession

    let service: VaultUnlockService
    let onCreated: () -> Void

    @State private var tier: PasscodeTier = .standard
    @State private var customLength = 10
    @State private var passcode = ""
    @State private var confirmation = ""
    @State private var message: String?
    @State private var isWorking = false

    private var requiredLength: Int {
        tier.fixedLength ?? customLength
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Security level") {
                    Picker("Level", selection: $tier) {
                        ForEach(PasscodeTier.allCases) { tier in
                            Text(tier.displayName).tag(tier)
                        }
                    }

                    if tier == .custom {
                        Stepper("Length: \(customLength) digits", value: $customLength, in: PasscodePolicy.minimumLength...PasscodePolicy.maximumLength)
                    } else {
                        LabeledContent("Passcode length", value: "\(requiredLength) digits")
                    }

                    if tier == .standard {
                        Text("Six digits is KeyHollow's lowest security tier. Longer random passcodes are substantially stronger.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Create first vault") {
                    SecureField("Enter \(requiredLength)-digit passcode", text: $passcode)
                        .keyboardType(.numberPad)
                        .textContentType(.newPassword)
                        .onChange(of: passcode) { _, newValue in
                            passcode = sanitize(newValue, limit: requiredLength)
                        }

                    SecureField("Confirm passcode", text: $confirmation)
                        .keyboardType(.numberPad)
                        .textContentType(.newPassword)
                        .onChange(of: confirmation) { _, newValue in
                            confirmation = sanitize(newValue, limit: requiredLength)
                        }
                }

                if let message {
                    Section {
                        Text(message)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                        create()
                    } label: {
                        if isWorking {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Create Encrypted Vault")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(!canCreate || isWorking)
                }
            }
            .navigationTitle("Set Up KeyHollow")
        }
    }

    private var canCreate: Bool {
        passcode.count == requiredLength &&
        confirmation == passcode &&
        PasscodePolicy.isValid(passcode, tier: tier, customLength: tier == .custom ? customLength : nil)
    }

    private func sanitize(_ value: String, limit: Int) -> String {
        String(value.filter(\.isNumber).prefix(limit))
    }

    private func create() {
        guard canCreate, !isWorking else { return }
        let selectedPasscode = passcode
        passcode = ""
        confirmation = ""
        message = nil
        isWorking = true

        Task {
            do {
                let unlocked = try await service.createVault(passcode: selectedPasscode)
                session.unlock(vaultID: unlocked.vaultID, key: unlocked.vaultKey)
                onCreated()
                isWorking = false
            } catch {
                message = "The vault could not be created."
                isWorking = false
            }
        }
    }
}
