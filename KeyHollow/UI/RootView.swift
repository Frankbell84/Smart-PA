import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: VaultSession

    @State private var service: VaultUnlockService?
    @State private var setupRequired = false
    @State private var isChecking = true
    @State private var startupError: String?

    var body: some View {
        Group {
            if session.isUnlocked, let service {
                VaultGalleryView(service: service)
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
        .onChange(of: session.isUnlocked) { _, unlocked in
            guard !unlocked, let service else { return }
            Task {
                do {
                    setupRequired = !(try await service.hasAnyVaults())
                } catch {
                    startupError = "Secure local storage could not be rechecked."
                }
            }
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

            KeyHollowLockMark()
                .frame(width: 68, height: 48)
                .accessibilityHidden(true)

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
        guard PasscodePolicy.isValidForUnlock(digits), !isWorking else {
            message = "Use 8–20 digits."
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

private struct KeyHollowLockMark: View {
    var body: some View {
        Canvas { context, size in
            let stroke = StrokeStyle(
                lineWidth: max(2.8, size.height * 0.072),
                lineCap: .round,
                lineJoin: .round
            )

            var eye = Path()
            eye.move(to: CGPoint(x: size.width * 0.06, y: size.height * 0.50))
            eye.addCurve(
                to: CGPoint(x: size.width * 0.94, y: size.height * 0.50),
                control1: CGPoint(x: size.width * 0.27, y: size.height * 0.03),
                control2: CGPoint(x: size.width * 0.73, y: size.height * 0.03)
            )
            eye.addCurve(
                to: CGPoint(x: size.width * 0.06, y: size.height * 0.50),
                control1: CGPoint(x: size.width * 0.73, y: size.height * 0.97),
                control2: CGPoint(x: size.width * 0.27, y: size.height * 0.97)
            )
            context.stroke(eye, with: .color(.white), style: stroke)

            let circleRadius = size.height * 0.145
            let circleCenter = CGPoint(x: size.width * 0.50, y: size.height * 0.38)
            let circleRect = CGRect(
                x: circleCenter.x - circleRadius,
                y: circleCenter.y - circleRadius,
                width: circleRadius * 2,
                height: circleRadius * 2
            )

            var keyhole = Path()
            keyhole.addEllipse(in: circleRect)
            keyhole.move(to: CGPoint(x: circleCenter.x - circleRadius * 0.58, y: circleCenter.y + circleRadius * 0.80))
            keyhole.addLine(to: CGPoint(x: size.width * 0.43, y: size.height * 0.79))
            keyhole.addLine(to: CGPoint(x: size.width * 0.57, y: size.height * 0.79))
            keyhole.addLine(to: CGPoint(x: circleCenter.x + circleRadius * 0.58, y: circleCenter.y + circleRadius * 0.80))
            context.stroke(keyhole, with: .color(.white), style: stroke)
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
    @State private var acknowledgesNoRecovery = false
    @FocusState private var isPasscodeEntryFocused: Bool

    private var requiredLength: Int {
        tier.fixedLength ?? customLength
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Set Up KeyHollow")
                    .font(.largeTitle.bold())
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 6)

            Divider()

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
                        Text("Eight digits is KeyHollow's minimum. Longer unpredictable passcodes are substantially stronger.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Create first vault") {
                    SecureField("Enter \(requiredLength)-digit passcode", text: $passcode)
                        .keyboardType(.numberPad)
                        .textContentType(.newPassword)
                        .focused($isPasscodeEntryFocused)
                        .onChange(of: passcode) { _, newValue in
                            passcode = sanitize(newValue, limit: requiredLength)
                        }

                    SecureField("Confirm passcode", text: $confirmation)
                        .keyboardType(.numberPad)
                        .textContentType(.newPassword)
                        .focused($isPasscodeEntryFocused)
                        .onChange(of: confirmation) { _, newValue in
                            confirmation = sanitize(newValue, limit: requiredLength)
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
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isPasscodeEntryFocused = false
                    }
                }
            }
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
