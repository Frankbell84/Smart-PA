import SwiftUI

struct AdditionalVaultSetupView: View {
    @EnvironmentObject private var session: VaultSession
    @Environment(\.dismiss) private var dismiss

    let service: VaultUnlockService

    @State private var tier: PasscodeTier = .enhanced
    @State private var customLength = 10
    @State private var passcode = ""
    @State private var confirmation = ""
    @State private var message: String?
    @State private var isWorking = false
    @State private var acknowledgesNoRecovery = false
    @FocusState private var isPasscodeEntryFocused: Bool

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
                        Stepper(
                            "Length: \(customLength) digits",
                            value: $customLength,
                            in: PasscodePolicy.minimumLength...PasscodePolicy.maximumLength
                        )
                    } else {
                        LabeledContent("Passcode length", value: "\(requiredLength) digits")
                    }

                    Text("Each passcode opens only its own encrypted vault. KeyHollow does not show a vault list or vault count.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("New vault passcode") {
                    SecureField("Enter \(requiredLength)-digit passcode", text: $passcode)
                        .keyboardType(.numberPad)
                        .textContentType(.newPassword)
                        .focused($isPasscodeEntryFocused)
                        .onChange(of: passcode) { _, newValue in
                            passcode = sanitize(newValue, limit: requiredLength)
                            message = nil
                        }

                    SecureField("Confirm passcode", text: $confirmation)
                        .keyboardType(.numberPad)
                        .textContentType(.newPassword)
                        .focused($isPasscodeEntryFocused)
                        .onChange(of: confirmation) { _, newValue in
                            confirmation = sanitize(newValue, limit: requiredLength)
                            message = nil
                        }

                    Text("Avoid birthdays, phone numbers, repeated digits, counting sequences, and repeated patterns.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if let rejectionMessage {
                        Text(rejectionMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                if let message {
                    Section {
                        Text(message)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Important: No recovery") {
                    Text("KeyHollow cannot recover or reset a forgotten vault passcode. Deleting this app or vault, erasing or losing this iPhone, or device failure may permanently eliminate access to the vault's contents.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Toggle("I understand this vault cannot be recovered", isOn: $acknowledgesNoRecovery)
                }

                Section {
                    Button {
                        createVault()
                    } label: {
                        if isWorking {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Create New Vault")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(!canCreate || isWorking)
                }
            }
            .navigationTitle("New Vault")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isWorking)
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isPasscodeEntryFocused = false
                    }
                }
            }
            .interactiveDismissDisabled(isWorking)
        }
    }

    private var canCreate: Bool {
        passcode.count == requiredLength &&
        confirmation == passcode &&
        acknowledgesNoRecovery &&
        PasscodePolicy.isAcceptableNewPasscode(
            passcode,
            tier: tier,
            customLength: tier == .custom ? customLength : nil
        )
    }

    private var rejectionMessage: String? {
        guard passcode.count == requiredLength else { return nil }
        return PasscodePolicy.rejectionReason(forNewPasscode: passcode)?.message
    }

    private func sanitize(_ value: String, limit: Int) -> String {
        String(value.filter(\.isNumber).prefix(limit))
    }

    private func createVault() {
        guard canCreate, !isWorking else { return }

        let selectedPasscode = passcode
        passcode = ""
        confirmation = ""
        message = nil
        isWorking = true

        Task {
            do {
                let unlocked = try await service.createVault(passcode: selectedPasscode)

                // Switch directly into the newly created vault. No vault index,
                // count, name, or other discovery surface is introduced.
                session.unlock(vaultID: unlocked.vaultID, key: unlocked.vaultKey)
                isWorking = false
                dismiss()
            } catch VaultUnlockError.passcodeAlreadyUsed {
                // Deliberately avoid saying that another vault exists for this
                // passcode. The creation UI exposes no vault discovery metadata.
                message = "That passcode cannot be used. Choose a different passcode."
                isWorking = false
            } catch {
                message = "The new encrypted vault could not be created."
                isWorking = false
            }
        }
    }
}
