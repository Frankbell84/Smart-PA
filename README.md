# NoxLock

NoxLock is a native iOS privacy application built around multiple independent encrypted photo vaults. A valid passcode opens only the vault associated with that passcode; the normal locked interface does not enumerate other vaults.

## Product principle

**One keypad. Multiple private vaults.**

## Security-first V1

- Native Swift / SwiftUI
- Local-only encrypted photo storage
- Independent cryptographic key material per vault
- Authenticated encryption for photo data and thumbnails
- iOS Keychain and Data Protection where appropriate
- Automatic lock when the app leaves the foreground
- No cloud backend in V1
- No analytics or advertising SDKs in the secure application path
- No plaintext vault index exposed by the UI
- No claims of absolute coercion or forensic resistance

## Engineering rule

NoxLock is a security product first. Cryptographic design, key derivation, secure storage, import/export behavior, caches, thumbnails, backups, logging, and lifecycle handling must be threat-modeled before release. Production security claims require independent review.

## Status

Initial architecture and native iOS implementation are in progress.
