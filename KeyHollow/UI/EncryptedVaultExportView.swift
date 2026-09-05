import SwiftUI
import KeyHollowTransferCore
import UIKit
import UniformTypeIdentifiers
import KeyHollowVaultCore

struct EncryptedVaultExportView: View {
    @EnvironmentObject private var session: VaultSession
    @Environment(\.dismiss) private var dismiss

    let service: VaultUnlockService

    @State private var currentPasscode = ""
    @State private var recoveryCode = ""
    @State private var recoveryConfirmation = ""
    @State private var isWorking = false
    @State private var pendingExport: PendingEncryptedVaultExport?
    @State private var message: String?
    @State private var systemInteractionOpen = false
    @FocusState private var focusedField: ExportField?

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Form {
                    Section {
                        Text("This creates a portable .khvault copy of only the vault that is currently open. Its photos and files remain in KeyHollow.")
                            .foregroundStyle(.secondary)
                    }

                    Section("Verify this vault") {
                        SecureField("Current passcode", text: $currentPasscode)
                            .keyboardType(.numberPad)
                            .textContentType(.password)
                            .focused($focusedField, equals: .currentPasscode)
                            .onChange(of: currentPasscode) { _, value in
                                currentPasscode = String(
                                    value.filter(\.isNumber).prefix(PasscodePolicy.maximumLength)
                                )
                            }
                    }
                    .id(ExportSection.verification)

                    Section {
                        if recoveryCode.isEmpty {
                            Button("Generate Recovery Code") {
                                focusedField = nil
                                generateRecoveryCode()
                            }
                            Text("The export uses a new random recovery code—not your KeyHollow passcode.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(recoveryCode)
                                .font(.system(.body, design: .monospaced).weight(.semibold))
                                .privacySensitive()

                            Button {
                                copyRecoveryCode()
                            } label: {
                                Label("Copy Recovery Code", systemImage: "doc.on.doc")
                            }

                            Text("Write this code down and keep it somewhere separate from the .khvault file. KeyHollow cannot recover or reset it.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            TextField("Enter the final 8 characters", text: $recoveryConfirmation)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .submitLabel(.done)
                                .focused($focusedField, equals: .recoveryConfirmation)
                                .onSubmit {
                                    finishKeyboardEntry(using: proxy)
                                }
                                .onChange(of: recoveryConfirmation) { _, value in
                                    recoveryConfirmation = String(
                                        value.uppercased()
                                            .filter { $0.isLetter || $0.isNumber }
                                            .prefix(8)
                                    )
                                }

                            Button("Replace Recovery Code", role: .destructive) {
                                focusedField = nil
                                generateRecoveryCode()
                            }
                        }
                    } header: {
                        Text("Separate recovery code")
                    } footer: {
                        Text("Anyone who has both the .khvault file and this recovery code can attempt to restore the vault. Never store them together.")
                    }
                    .id(ExportSection.recovery)

                    if let message {
                        Section { Text(message).foregroundStyle(.secondary) }
                    }

                    Section {
                        Button("Create Encrypted Export") {
                            focusedField = nil
                            createExport()
                        }
                        .frame(maxWidth: .infinity)
                        .disabled(!canExport || isWorking || pendingExport != nil)
                    }
                    .id(ExportSection.createExport)
                }
                .scrollDismissesKeyboard(.interactively)
                .navigationTitle("Export Encrypted Vault")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
                            focusedField = nil
                            clearSensitiveState()
                            dismiss()
                        }
                        .disabled(isWorking || pendingExport != nil)
                    }

                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button(focusedField == .currentPasscode ? "Continue" : "Done") {
                            finishKeyboardEntry(using: proxy)
                        }
                    }
                }
                .overlay {
                    if isWorking {
                        ProgressView("Encrypting and verifying…")
                            .padding()
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .interactiveDismissDisabled(isWorking || pendingExport != nil)
                .sheet(item: $pendingExport) { item in
                    EncryptedVaultDocumentExporter(archiveURL: item.archiveURL) { saved in
                        finishDocumentExport(item, saved: saved)
                    }
                }
                .onDisappear {
                    guard !isWorking, pendingExport == nil else { return }
                    clearSensitiveState()
                }
            }
        }
    }

    private func clearSensitiveState() {
        currentPasscode = ""
        recoveryCode = ""
        recoveryConfirmation = ""
    }

    private var canExport: Bool {
        PasscodePolicy.isValidForUnlock(currentPasscode) &&
        !recoveryCode.isEmpty &&
        recoveryConfirmation == expectedRecoveryConfirmation
    }

    private var expectedRecoveryConfirmation: String {
        String(recoveryCode.filter { $0.isLetter || $0.isNumber }.suffix(8))
    }

    private func finishKeyboardEntry(using proxy: ScrollViewProxy) {
        let destination: ExportSection = focusedField == .currentPasscode
            ? .recovery
            : .createExport
        focusedField = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation {
                proxy.scrollTo(destination, anchor: .center)
            }
        }
    }

    private func generateRecoveryCode() {
        do {
            recoveryCode = try PortableArchiveRecoveryCode.generate()
            recoveryConfirmation = ""
            message = nil
        } catch {
            recoveryCode = ""
            message = "A secure recovery code could not be generated. No export was created."
        }
    }

    private func copyRecoveryCode() {
        guard !recoveryCode.isEmpty else { return }

        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: recoveryCode]],
            options: [
                .localOnly: true,
                .expirationDate: Date().addingTimeInterval(120)
            ]
        )
        message = "Recovery code copied on this iPhone for two minutes. Keep it separate from the .khvault file."
    }

    private func createExport() {
        guard canExport,
              let context = session.activeVaultContext(),
              !isWorking else { return }

        let vaultID = context.id
        let passcode = currentPasscode
        let credential = PortableArchiveCredential.recoveryCode(recoveryCode)
        currentPasscode = ""
        message = nil
        isWorking = true

        let started = session.startSensitiveTask { access in
            var temporaryDestination: URL?
            do {
                try Task.checkCancellation()
                let reauthenticated = try await service.reauthenticateCurrentVault(
                    passcode: passcode,
                    expectedVaultID: vaultID
                )
                try Task.checkCancellation()
                let destination = try Self.makeTemporaryExportURL()
                temporaryDestination = destination
                let receipt = try await EncryptedVaultTransferCoordinator().exportVault(
                    vaultID: reauthenticated.vaultID,
                    createdAt: reauthenticated.createdAt,
                    access: access,
                    credential: credential,
                    destinationURL: destination,
                    supplementalContent: GeneralFilePortableTransferBridge(
                        access: SessionGeneralFileAccess(capability: access)
                    )
                )
                try Task.checkCancellation()

                isWorking = false
                systemInteractionOpen = true
                session.beginSystemInteraction()
                pendingExport = PendingEncryptedVaultExport(
                    archiveURL: receipt.archiveURL,
                    encryptedFileCount: receipt.encryptedFileCount,
                    archiveByteCount: receipt.archiveByteCount
                )
            } catch is CancellationError {
                Self.discardTemporaryExport(at: temporaryDestination)
                isWorking = false
                clearSensitiveState()
            } catch VaultUnlockError.invalidCredentials {
                Self.discardTemporaryExport(at: temporaryDestination)
                isWorking = false
                clearSensitiveState()
                message = "The current passcode was not recognized for this vault."
            } catch {
                Self.discardTemporaryExport(at: temporaryDestination)
                isWorking = false
                clearSensitiveState()
                message = "The encrypted export could not be created and verified. No incomplete export was kept."
            }
        }
        if started == nil {
            isWorking = false
            clearSensitiveState()
        }
    }

    private func finishDocumentExport(
        _ item: PendingEncryptedVaultExport,
        saved: Bool
    ) {
        if systemInteractionOpen {
            systemInteractionOpen = false
            session.endSystemInteraction()
        }
        Self.discardTemporaryExport(at: item.archiveURL)
        pendingExport = nil
        clearSensitiveState()

        if saved {
            message = nil
            DispatchQueue.main.async {
                dismiss()
            }
        } else {
            message = "Export canceled. The temporary .khvault file was deleted."
        }
    }

    private static func makeTemporaryExportURL() throws -> URL {
        let fileManager = FileManager.default
        let exportRoot = fileManager.temporaryDirectory
            .appendingPathComponent("KeyHollowPortableExports", isDirectory: true)
        try? fileManager.removeItem(at: exportRoot)
        let directory = exportRoot
            .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)

        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        var protectedDirectory = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try protectedDirectory.setResourceValues(values)

        return directory.appendingPathComponent("KeyHollow-Encrypted-Vault.khvault")
    }

    private static func formattedBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private static func discardTemporaryExport(at archiveURL: URL?) {
        guard let archiveURL else { return }
        try? FileManager.default.removeItem(
            at: archiveURL.deletingLastPathComponent()
        )
    }
}

private enum ExportField: Hashable {
    case currentPasscode
    case recoveryConfirmation
}

private enum ExportSection: Hashable {
    case verification
    case recovery
    case createExport
}

private struct PendingEncryptedVaultExport: Identifiable {
    let id = UUID()
    let archiveURL: URL
    let encryptedFileCount: Int
    let archiveByteCount: UInt64
}

private struct EncryptedVaultDocumentExporter: UIViewControllerRepresentable {
    let archiveURL: URL
    let onComplete: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forExporting: [archiveURL],
            asCopy: true
        )
        picker.delegate = context.coordinator
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController,
        context: Context
    ) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onComplete: (Bool) -> Void
        private var completed = false

        init(onComplete: @escaping (Bool) -> Void) {
            self.onComplete = onComplete
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            finish(saved: !urls.isEmpty)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            finish(saved: false)
        }

        private func finish(saved: Bool) {
            guard !completed else { return }
            completed = true
            onComplete(saved)
        }
    }
}

