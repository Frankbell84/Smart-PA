import SwiftUI

struct VaultSecuritySettingsView: View {
    @EnvironmentObject private var session: VaultSession
    @Environment(\.dismiss) private var dismiss

    let service: VaultUnlockService

    @State private var showingChangePasscode = false
    @State private var showingDeleteVault = false
    @State private var showingEncryptedExport = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Export Encrypted Vault") {
                        showingEncryptedExport = true
                    }

                    Button("Change This Vault Passcode") {
                        showingChangePasscode = true
                    }

                    Button("Delete This Vault", role: .destructive) {
                        showingDeleteVault = true
                    }
                } footer: {
                    Text("These controls affect only the vault that is currently open. KeyHollow does not display other vaults or how many exist.")
                }
            }
            .navigationTitle("Vault Security")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingChangePasscode) {
                ChangeVaultPasscodeView(service: service)
                    .environmentObject(session)
            }
            .sheet(isPresented: $showingEncryptedExport) {
                EncryptedVaultExportView(service: service)
                    .environmentObject(session)
            }
            .sheet(isPresented: $showingDeleteVault) {
                DeleteCurrentVaultView(service: service) {
                    dismiss()
                }
                .environmentObject(session)
            }
        }
    }
}

private struct ChangeVaultPasscodeView: View {
    @EnvironmentObject private var session: VaultSession
    @Environment(\.dismiss) private var dismiss

    let service: VaultUnlockService

    @State private var currentPasscode = ""
    @State private var tier: PasscodeTier = .enhanced
    @State private var customLength = 10
    @State private var newPasscode = ""
    @State private var confirmation = ""
    @State private var message: String?
    @State private var isWorking = false

    private var requiredLength: Int { tier.fixedLength ?? customLength }

    var body: some View {
        NavigationStack {
            Form {
                Section("Verify current passcode") {
                    SecureField("Current passcode", text: $currentPasscode)
                        .keyboardType(.numberPad)
                        .textContentType(.password)
                        .onChange(of: currentPasscode) { _, value in
                            currentPasscode = sanitize(value, limit: PasscodePolicy.maximumLength)
                        }
                }

                Section("New security level") {
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
                }

                Section("New passcode") {
                    SecureField("Enter \(requiredLength)-digit passcode", text: $newPasscode)
                        .keyboardType(.numberPad)
                        .textContentType(.newPassword)
                        .onChange(of: newPasscode) { _, value in
                            newPasscode = sanitize(value, limit: requiredLength)
                        }

                    SecureField("Confirm new passcode", text: $confirmation)
                        .keyboardType(.numberPad)
                        .textContentType(.newPassword)
                        .onChange(of: confirmation) { _, value in
                            confirmation = sanitize(value, limit: requiredLength)
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
                    Section { Text(message).foregroundStyle(.secondary) }
                }

                Section {
                    Button("Change Passcode") { changePasscode() }
                        .frame(maxWidth: .infinity)
                        .disabled(!canSubmit || isWorking)
                }
            }
            .navigationTitle("Change Passcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.disabled(isWorking)
                }
            }
            .interactiveDismissDisabled(isWorking)
        }
    }

    private var canSubmit: Bool {
        PasscodePolicy.isValidForUnlock(currentPasscode) &&
        newPasscode.count == requiredLength &&
        newPasscode == confirmation &&
        PasscodePolicy.isAcceptableNewPasscode(
            newPasscode,
            tier: tier,
            customLength: tier == .custom ? customLength : nil
        )
    }

    private var rejectionMessage: String? {
        guard newPasscode.count == requiredLength else { return nil }
        return PasscodePolicy.rejectionReason(forNewPasscode: newPasscode)?.message
    }

    private func changePasscode() {
        guard canSubmit,
              let vaultID = session.activeVaultID,
              !isWorking else { return }

        let old = currentPasscode
        let new = newPasscode
        currentPasscode = ""
        newPasscode = ""
        confirmation = ""
        message = nil
        isWorking = true

        Task {
            do {
                let unlocked = try await service.changePasscode(
                    currentPasscode: old,
                    newPasscode: new,
                    expectedVaultID: vaultID
                )
                session.unlock(vaultID: unlocked.vaultID, key: unlocked.vaultKey)
                isWorking = false
                dismiss()
            } catch VaultUnlockError.passcodeAlreadyUsed {
                message = "That new passcode cannot be used. Choose a different passcode."
                isWorking = false
            } catch VaultUnlockError.invalidCredentials {
                message = "The current passcode was not recognized for this vault."
                isWorking = false
            } catch {
                message = "The passcode could not be changed safely. The existing passcode should be treated as unchanged."
                isWorking = false
            }
        }
    }

    private func sanitize(_ value: String, limit: Int) -> String {
        String(value.filter(\.isNumber).prefix(limit))
    }
}

private struct DeleteCurrentVaultView: View {
    @EnvironmentObject private var session: VaultSession
    @Environment(\.dismiss) private var dismiss

    let service: VaultUnlockService
    let onDeleted: () -> Void

    @State private var currentPasscode = ""
    @State private var confirmationText = ""
    @State private var message: String?
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Deleting this vault removes its KeyHollow credential envelope and its encrypted photo data. This action cannot be undone.")
                        .foregroundStyle(.secondary)
                }

                Section("Verify current passcode") {
                    SecureField("Current passcode", text: $currentPasscode)
                        .keyboardType(.numberPad)
                        .textContentType(.password)
                        .onChange(of: currentPasscode) { _, value in
                            currentPasscode = String(value.filter(\.isNumber).prefix(PasscodePolicy.maximumLength))
                        }
                }

                Section("Confirm deletion") {
                    TextField("Type DELETE", text: $confirmationText)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }

                if let message {
                    Section { Text(message).foregroundStyle(.secondary) }
                }

                Section {
                    Button("Permanently Delete This Vault", role: .destructive) {
                        deleteVault()
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(!canDelete || isWorking)
                }
            }
            .navigationTitle("Delete Vault")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.disabled(isWorking)
                }
            }
            .interactiveDismissDisabled(isWorking)
        }
    }

    private var canDelete: Bool {
        PasscodePolicy.isValidForUnlock(currentPasscode) &&
        confirmationText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "DELETE"
    }

    private func deleteVault() {
        guard canDelete,
              let vaultID = session.activeVaultID,
              !isWorking else { return }

        let passcode = currentPasscode
        currentPasscode = ""
        confirmationText = ""
        message = nil
        isWorking = true

        Task {
            do {
                try await service.deleteVault(
                    currentPasscode: passcode,
                    expectedVaultID: vaultID
                )
                session.lock()
                isWorking = false
                dismiss()
                onDeleted()
            } catch VaultUnlockError.invalidCredentials {
                message = "The current passcode was not recognized for this vault."
                isWorking = false
            } catch {
                message = "KeyHollow could not complete vault deletion cleanly. Do not assume the operation succeeded until the vault state is rechecked."
                isWorking = false
            }
        }
    }
}
