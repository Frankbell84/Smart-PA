# KeyHollow Architecture Boundaries

KeyHollow is intentionally organized around replaceable responsibilities. The
goal is not a collection of independent features sharing global state; it is a
small local core with narrow adapters around it.

## Responsibility map

| Area | Owns | Must not own |
| --- | --- | --- |
| `Security` | Key derivation, envelopes, rate limits, cryptographic primitives | Screens, Photos authorization, network clients |
| `Storage` | Opaque credential-envelope persistence | Decrypted media, user-interface state, transfer presentation |
| `Session` | Active-vault capability, lock revocation, sensitive-task lifetime | Photos permission prompts, navigation, cloud services |
| `Photos/VaultPhoto*` | Encrypted photo records, manifests, blob persistence | SwiftUI, UIKit, Photos framework calls |
| `Transfer` | `.khvault` format, authenticated streaming, staging, rollback | Screens, Photos library calls, network clients |
| `Photos/SecurePhotoPicker` | The narrow Apple Photos adapter | Vault keys, archive format, credential persistence |
| `UI` and gallery view | User interaction and presentation | Cryptographic algorithms or direct persistence formats |
| `App` | Composition and lifecycle entry | Feature implementation details |

## Enforced rules

The CI architecture check fails when:

- SwiftUI, UIKit, Photos, PhotosUI, or document-picker frameworks leak into
  core cryptography, storage, session, transfer, or encrypted-photo files;
- core code directly invokes Photos or UIKit presentation types;
- a core layer introduces `URLSession`;
- a known analytics, cloud-storage, authentication, advertising, or purchase
  SDK enters the current local-only application.

These rules make accidental coupling visible at review time. They do not claim
that every folder is a separate compiled Swift module. `KeyHollowCryptoCore`
owns the authenticated-encryption primitive and vendored Argon2id
implementation. `KeyHollowVaultCore` owns passcode policy, key derivation,
opaque vault locators, credential envelopes, and local credential persistence.
The vault module depends on the crypto module; neither may import the app, UI,
Photos, session, or transfer code. Keychain access remains a platform adapter.
Additional module extraction remains incremental and must continue in its own
review so it cannot destabilize the tested core.

`KeyHollowPhotoCore` owns encrypted photo records, key scheduling, manifests,
and blob persistence. It receives cryptographic operations through a narrow
interface, allowing the app session to retain revocation ownership without the
storage module importing session, UI, Photos, or transfer code.

`KeyHollowTransferCore` owns the `.khvault` security header, authenticated
streaming container, encrypted payload catalog, restore staging, transaction
journal, rollback, and transfer coordinator. It receives only a narrow,
revocable export-access interface from the app session and returns a neutral
vault payload after installation. It does not import the app session,
`UnlockedVault`, UI, Photos, networking, or remote services.

`KeyHollowPhotosAdapter` is the only non-presentation boundary allowed to
import the Apple Photos and PhotosUI frameworks. It owns picker-item loading,
in-memory image normalization, Photos authorization, save, and deletion calls.
The minimal SwiftUI picker wrapper remains in the app target and may import
PhotosUI solely to present Apple's picker. The adapter receives and returns
plain in-memory data and identifiers; it does not own vault keys, encrypted
storage, transfer formats, sessions, or navigation.

The app target remains the composition and presentation layer. It selects the
concrete vault service at `KeyHollowApp`, injects its factory into `RootView`,
and keeps the gallery and navigation outside every core module and platform
adapter.

## Change policy

1. New functionality enters through a feature branch and draft review.
2. Core security behavior is covered by regression tests before adapters or UI
   are changed.
3. Networked or subscription features must use new adapters; they may not add
   remote-service dependencies to the local vault core.
4. A module-extraction refactor must preserve `.khvault` compatibility and
   existing encrypted vault data byte-for-byte.
5. No architecture cleanup and customer-facing feature expansion share the
   same production merge.

