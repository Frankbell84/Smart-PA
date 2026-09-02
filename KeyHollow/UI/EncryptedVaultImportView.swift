import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct EncryptedVaultImportView: View {
    @EnvironmentObject private var session: VaultSession
    @Environment(\.dismiss) private var dismiss

    let service: VaultUnlockService

    @State private var selectedArchive: SelectedPortableArchive?
    @State private var recoveryCode = ""
    @State private var validatedRestore: ValidatedPortableVaultRestore?
    @State private var tier: PasscodeTier = .enhanced
    @State private var customLength = 10
    @State private var newPasscode = ""
    @State private var passcodeConfirmation = ""
    @State private var acknowledgesNoRecovery = false
    @State private var showingFilePicker = false
    @State private var systemInteractionOpen = false
    @State private var isWorking = false
    @State private var message: String?
    @FocusState private var focusedField: ImportField?

    private var requiredLength: Int { tier.fixedLength ?? customLength }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Import creates a new independent local vault. It never replaces, merges with, or deletes an existing vault.")
                        .foregroundStyle(.secondary)
                }

                Section("1. Choose encrypted export") {
                    Button(selectedArchive == nil ? "Choose .khvault File" : "Choose a Different File") {
                        beginFileSelection()
                    }
                    .disabled(isWorking || validatedRestore != nil)

                    if let selectedArchive {
                        LabeledContent("Selected", value: selectedArchive.displayName)
                        LabeledContent("Size", value: Self.formattedBytes(selectedArchive.byteCount))
                    }
                }

                Section("2. Authenticate export") {
                    TextField("Recovery code", text: $recoveryCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                        .privacySensitive()
                        .submitLabel(.done)
                        .focused($focusedField, equals: .recoveryCode)
                        .onSubmit {
                            dismissKeyboard()
                        }
                        .onChange(of: recoveryCode) { _, value in
                            recoveryCode = Self.sanitizeRecoveryCode(value)
                        }
                        .disabled(validatedRestore != nil)

                    if let validatedRestore {
                        Label(
                            "Authenticated and verified: \(validatedRestore.manifest.photos.count) photos",
                            systemImage: "checkmark.shield.fill"
                        )
                        .foregroundStyle(.green)
                    } else {
                        Button("Authenticate and Verify") {
                            dismissKeyboard()
                            validateArchive()
                        }
                        .disabled(!canValidate || isWorking)
                    }
                }

                if validatedRestore != nil {
                    Section("3. Create a new local LowKey") {
                        Picker("Security level", selection: $tier) {
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
                            LabeledContent("LowKey length", value: "\(requiredLength) digits")
                        }

                        SecureField("Enter \(requiredLength)-digit LowKey", text: $newPasscode)
                            .keyboardType(.numberPad)
                            .textContentType(.newPassword)
                            .focused($focusedField, equals: .newPasscode)
                            .onChange(of: newPasscode) { _, value in
                                let sanitized = Self.sanitizePasscode(value, limit: requiredLength)
                                newPasscode = sanitized
                                if sanitized.count == requiredLength,
                                   focusedField == .newPasscode {
                                    focusedField = .passcodeConfirmation
                                }
                            }

                        SecureField("Confirm new LowKey", text: $passcodeConfirmation)
                            .keyboardType(.numberPad)
                            .textContentType(.newPassword)
                            .focused($focusedField, equals: .passcodeConfirmation)
                            .onChange(of: passcodeConfirmation) { _, value in
                                let sanitized = Self.sanitizePasscode(value, limit: requiredLength)
                                passcodeConfirmation = sanitized
                                if sanitized.count == requiredLength,
                                   sanitized == newPasscode {
                                    dismissKeyboard()
                                }
                            }

                        Text("The recovery code authenticates the file only. It will never unlock KeyHollow. This new LowKey is required on this iPhone.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        if let rejectionMessage {
                            Text(rejectionMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }

                    Section("Important: No LowKey recovery") {
                        Text("KeyHollow cannot recover or reset the new LowKey. Keep the original .khvault file and its separate recovery code if you want a portable backup.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Toggle("I understand the new LowKey cannot be recovered", isOn: $acknowledgesNoRecovery)
                    }
                }

                if let message {
                    Section { Text(message).foregroundStyle(.secondary) }
                }

                if validatedRestore != nil {
                    Section {
                        Button("Install as New Vault") {
                            dismissKeyboard()
                            installRestore()
                        }
                        .frame(maxWidth: .infinity)
                        .disabled(!canInstall || isWorking)
                    }
                }
            }
            .navigationTitle("Import Encrypted Vault")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { cancelAndDismiss() }
                        .disabled(isWorking)
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(focusedField == .newPasscode ? "Continue" : "Done") {
                        finishKeyboardEntry()
                    }
                }
            }
            .overlay {
                if isWorking {
                    ProgressView(validatedRestore == nil ? "Authenticating every file…" : "Installing verified vault…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .interactiveDismissDisabled(isWorking)
            .sheet(isPresented: $showingFilePicker) {
                EncryptedVaultDocumentImporter { url in
                    finishFileSelection(url)
                }
            }
        }
        .onDisappear {
            guard !showingFilePicker else { return }
            clearSensitiveState()
            discardUninstalledMaterial()
        }
    }

    private func clearSensitiveState() {
        recoveryCode = ""
        newPasscode = ""
        passcodeConfirmation = ""
    }

    private func finishKeyboardEntry() {
        if focusedField == .newPasscode {
            focusedField = .passcodeConfirmation
        } else {
            dismissKeyboard()
        }
    }

    private func dismissKeyboard() {
        focusedField = nil
        KeyboardDismissal.dismiss()
    }

    private var canValidate: Bool {
        selectedArchive != nil &&
        (try? PortableArchiveRecoveryCode.canonicalize(recoveryCode)) != nil
    }

    private var canInstall: Bool {
        newPasscode.count == requiredLength &&
        newPasscode == passcodeConfirmation &&
        acknowledgesNoRecovery &&
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

    private func beginFileSelection() {
        dismissKeyboard()
        message = nil
        systemInteractionOpen = true
        session.beginSystemInteraction()
        showingFilePicker = true
    }

    private func finishFileSelection(_ url: URL?) {
        showingFilePicker = false
        if systemInteractionOpen {
            systemInteractionOpen = false
            session.endSystemInteraction()
        }
        guard let url else {
            message = "File selection canceled."
            return
        }

        discardUninstalledMaterial()
        do {
            selectedArchive = try Self.copyIntoProtectedTemporaryStorage(url)
            recoveryCode = ""
            message = nil
        } catch PortableArchiveSelectionError.unsupportedFile {
            message = "Choose a KeyHollow .khvault file."
        } catch PortableArchiveSelectionError.insufficientStorage {
            message = "This iPhone does not have enough free space to authenticate and install that export safely."
        } catch {
            message = "The selected export could not be copied into protected temporary storage."
        }
    }

    private func validateArchive() {
        guard canValidate, let selectedArchive, !isWorking else { return }
        dismissKeyboard()
        let credential = PortableArchiveCredential.recoveryCode(recoveryCode)
        isWorking = true
        message = nil

        Task {
            do {
                let restore = try await EncryptedVaultTransferCoordinator().stageAndValidateRestore(
                    archiveURL: selectedArchive.url,
                    credential: credential
                )
                Self.discardTemporaryArchive(selectedArchive)
                self.selectedArchive = nil
                recoveryCode = ""
                validatedRestore = restore
                isWorking = false
            } catch {
                isWorking = false
                recoveryCode = ""
                message = "The export could not be authenticated. Check the recovery code and confirm the .khvault file is unchanged."
            }
        }
    }

    private func installRestore() {
        guard canInstall, let validatedRestore, !isWorking else { return }
        dismissKeyboard()
        let passcode = newPasscode
        newPasscode = ""
        passcodeConfirmation = ""
        isWorking = true
        message = nil

        Task {
            do {
                let unlocked = try await service.installValidatedPortableVault(
                    validatedRestore,
                    newPasscode: passcode
                )
                self.validatedRestore = nil
                isWorking = false
                session.unlock(vaultID: unlocked.vaultID, key: unlocked.vaultKey)
                dismiss()
            } catch VaultUnlockError.passcodeAlreadyUsed {
                isWorking = false
                message = "That LowKey is already in use. Choose a different unpredictable LowKey."
            } catch {
                validatedRestore.discard()
                self.validatedRestore = nil
                isWorking = false
                message = "The vault could not be installed safely. The incomplete install was rolled back; select the export and try again."
            }
        }
    }

    private func cancelAndDismiss() {
        dismissKeyboard()
        clearSensitiveState()
        discardUninstalledMaterial()
        dismiss()
    }

    private func discardUninstalledMaterial() {
        validatedRestore?.discard()
        validatedRestore = nil
        if let selectedArchive {
            Self.discardTemporaryArchive(selectedArchive)
        }
        selectedArchive = nil
    }

    private static func copyIntoProtectedTemporaryStorage(
        _ sourceURL: URL
    ) throws -> SelectedPortableArchive {
        guard sourceURL.pathExtension.lowercased() == "khvault" else {
            throw PortableArchiveSelectionError.unsupportedFile
        }

        let fileManager = FileManager.default
        let sourceValues = try sourceURL.resourceValues(forKeys: [.fileSizeKey])
        guard let sourceSize = sourceValues.fileSize, sourceSize > 0 else {
            throw PortableArchiveSelectionError.unsupportedFile
        }

        let importRoot = fileManager.temporaryDirectory
            .appendingPathComponent("KeyHollowPortableImports", isDirectory: true)
        try? fileManager.removeItem(at: importRoot)
        let root = importRoot
            .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
        let capacityValues = try fileManager.temporaryDirectory.resourceValues(
            forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityKey
            ]
        )
        let available = capacityValues.volumeAvailableCapacityForImportantUsage ??
            Int64(capacityValues.volumeAvailableCapacity ?? 0)
        let doubled = Int64(sourceSize).multipliedReportingOverflow(by: 2)
        let withHeadroom = doubled.partialValue.addingReportingOverflow(67_108_864)
        guard !doubled.overflow,
              !withHeadroom.overflow,
              available >= withHeadroom.partialValue else {
            throw PortableArchiveSelectionError.insufficientStorage
        }

        try fileManager.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        var protectedRoot = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try protectedRoot.setResourceValues(values)

        let destination = root.appendingPathComponent("Selected.khvault")
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { sourceURL.stopAccessingSecurityScopedResource() }
        }
        do {
            try fileManager.copyItem(at: sourceURL, to: destination)
        } catch {
            try? fileManager.removeItem(at: root)
            throw error
        }
        return SelectedPortableArchive(
            url: destination,
            displayName: sourceURL.lastPathComponent,
            byteCount: UInt64(sourceSize)
        )
    }

    private static func discardTemporaryArchive(_ archive: SelectedPortableArchive) {
        try? FileManager.default.removeItem(at: archive.url.deletingLastPathComponent())
    }

    private static func sanitizeRecoveryCode(_ value: String) -> String {
        let allowed = value.uppercased().filter { character in
            character == "-" || character.isLetter || character.isNumber
        }
        return String(allowed.prefix(39))
    }

    private static func sanitizePasscode(_ value: String, limit: Int) -> String {
        String(value.filter(\.isNumber).prefix(limit))
    }

    private static func formattedBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

private enum ImportField: Hashable {
    case recoveryCode
    case newPasscode
    case passcodeConfirmation
}

private struct SelectedPortableArchive {
    let url: URL
    let displayName: String
    let byteCount: UInt64
}

private enum PortableArchiveSelectionError: Error {
    case unsupportedFile
    case insufficientStorage
}

private struct EncryptedVaultDocumentImporter: UIViewControllerRepresentable {
    let onComplete: (URL?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let type = UTType(
            exportedAs: "com.keyhollow.encrypted-vault",
            conformingTo: .data
        )
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [type],
            asCopy: true
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController,
        context: Context
    ) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onComplete: (URL?) -> Void
        private var completed = false

        init(onComplete: @escaping (URL?) -> Void) {
            self.onComplete = onComplete
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            finish(urls.first)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            finish(nil)
        }

        private func finish(_ url: URL?) {
            guard !completed else { return }
            completed = true
            onComplete(url)
        }
    }
}
