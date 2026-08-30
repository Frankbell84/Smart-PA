# NoxLock Security Architecture — Draft 0.2

## Security objective

NoxLock stores user-imported photos locally in multiple cryptographically independent vaults. Possession of one valid vault passcode must not grant access to the plaintext contents of another vault.

## Hard access rule

A NoxLock vault is unlocked only by its own NoxLock passcode.

- No Face ID unlock.
- No Touch ID unlock.
- No Apple device-passcode fallback.
- No recovery flow that substitutes the iPhone passcode for a NoxLock vault passcode.

The operating system may still protect the application container and Keychain at the platform level, but platform authentication must never become an alternate NoxLock vault-unlock path.

## Threat model

V1 explicitly considers:

1. Lost or stolen locked iPhone.
2. Another person knowing one valid NoxLock passcode.
3. Offline inspection of the app container or device backup.
4. Brute-force attempts against short numeric passcodes.
5. Plaintext leakage through thumbnails, temporary files, logs, caches, app-switcher snapshots, or backups.
6. App backgrounding while a vault is open.
7. Accidental persistence of imported source metadata.
8. Partial failure during a requested move from Apple Photos into NoxLock.

V1 does **not** promise protection against every compromised/jailbroken device, malicious OS, sophisticated live-memory extraction, or physical coercion. Marketing must not claim otherwise.

## Vault isolation

Each vault receives independent random key material. Photos, thumbnails, and vault metadata are encrypted before persistent storage. A vault opened with passcode A must not expose a plaintext master list of other vaults.

The implementation must avoid a design in which compromise of a single global encryption key automatically compromises every vault.

## Encryption

Use authenticated encryption from Apple CryptoKit, initially AES.GCM with a 256-bit symmetric key. Nonces must never be intentionally reused with the same key. Authentication failures fail closed.

No custom cryptographic primitive is permitted.

## Passcode derivation

Numeric passcodes have low entropy. Production release therefore requires a vetted, memory-hard password derivation design and rate limiting. Argon2id is the preferred candidate pending iOS dependency/security review. Parameters must be benchmarked on supported iPhones rather than chosen arbitrarily.

The raw passcode is never persisted.

## Key handling

Sensitive long-lived key material uses iOS Keychain only where doing so is compatible with vault isolation and the passcode-routing design. Keychain accessibility must be restricted appropriately. Keychain storage must not introduce Face ID, Touch ID, or device-passcode fallback as a vault-unlock mechanism.

Decrypted vault keys should live in memory only for the active session and be discarded when locking/backgrounding.

## Files

Encrypted blobs receive iOS Data Protection. Plaintext photos and thumbnails must not be written to persistent caches. Encrypted vault files should be excluded from ordinary backup for V1 unless a separately designed encrypted backup feature is introduced.

## App lifecycle

Entering background/inactive state locks the active vault and clears decrypted session state. The app-switcher presentation must not reveal vault contents.

## Import behavior

Every import presents two explicit modes:

### Copy to Vault

1. Read the selected photo through the permitted Apple Photos interface.
2. Encrypt the photo into the active vault.
3. Verify that the encrypted object and required metadata were committed successfully.
4. Leave the source photo in Apple Photos untouched.

### Move to Vault

"Move" is implemented as a verified encrypted import followed by a separate request to delete the source asset from Apple Photos.

1. Read the selected source photo.
2. Encrypt it into the active vault.
3. Verify the encrypted object can be authenticated/decrypted and that required metadata was committed.
4. Only after successful verification, request deletion of the original through Apple's supported Photos APIs.
5. If deletion is denied, cancelled, or fails, report the operation as **Copied**, never **Moved**.
6. NoxLock must never delete the source first and attempt encryption afterward.

Any Apple-provided authorization or confirmation UI required for deletion is respected; NoxLock must not attempt to bypass it.

Temporary plaintext buffers/files must be minimized and destroyed/released promptly. Importing must never imply that the original disappeared unless deletion actually succeeded.

## Logging and telemetry

Never log passcodes, derived keys, plaintext filenames, photo data, sensitive metadata, or decrypted vault manifests. V1 ships without third-party analytics or advertising SDKs.

## Release gate

Before describing NoxLock publicly as a secure photo vault, perform:

- unit and integration security tests;
- backup/container inspection;
- lifecycle/snapshot leakage tests;
- brute-force/rate-limit testing;
- copy/move transaction failure testing;
- Photos permission/deletion behavior testing;
- dependency review;
- independent security review of cryptographic architecture and implementation.
