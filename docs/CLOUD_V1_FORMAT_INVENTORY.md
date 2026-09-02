# KeyHollow Cloud v1 Format Inventory

Status: Gate A baseline. This inventory is tied to production commit
`6ca9656c7a7d4dd627004ea76c6947545afa13de` (App Store build 11). Cloud v1
must preserve these formats without changing the True Core application model.

## Boundary decision

Cloud v1 backs up an immutable snapshot of a selected vault's existing
encrypted photo store. It does not upload the device-bound LowKey credential
envelope and does not use a LowKey as a cloud recovery credential.

The cloud service stores only opaque, independently cloud-encrypted objects.
Photo roles, local storage names, manifest contents, and future folder or file
metadata exist only inside an authenticated encrypted cloud manifest.

## Device-local credential envelope

| Item | Current format | Cloud v1 treatment |
|---|---|---|
| Credential file | JSON-encoded `VaultEnvelope`, version 1, `.khv` | Never uploaded |
| Locator | HMAC-SHA256-derived opaque filename | Never used as a cloud identifier |
| Unlock KDF | HMAC-SHA256 with 32-byte device pepper, then Argon2id | Remains local only |
| Argon2id profile | 65,536 KiB, 3 iterations, parallelism 2 | Not reused for cloud recovery without a separate profile identifier |
| Wrapped payload | Vault UUID, 32-byte vault key, creation date | Vault key may be read only after local authentication and then wrapped under the cloud hierarchy |
| Persistent protection | Complete file protection; excluded from backup | Unchanged |

The installation salt and device pepper are device-local. Copying `.khv` files
cannot serve as cloud recovery and must never be presented as such.

## Device-local encrypted photo store

The selected vault's encrypted content is stored beneath an opaque vault UUID.

| File | Plaintext before local encryption | Local encryption key |
|---|---|---|
| `manifest.khm` | JSON `VaultPhotoManifest` version 1 | HKDF-SHA256 label `keyhollow.photos.manifest.v1` |
| Random `.khp` | Original photo bytes | HKDF-SHA256 label `keyhollow.photos.original.v1.<photo UUID>` |
| Random `.kht` | JPEG thumbnail bytes | HKDF-SHA256 label `keyhollow.photos.thumbnail.v1.<photo UUID>` |

All three file classes use CryptoKit AES-256-GCM combined representation with
CryptoKit-generated nonces. Files use complete file protection and are excluded
from ordinary device backup.

`VaultPhotoManifest` version 1 contains an ordered array of records with:

- photo UUID;
- import timestamp;
- random original-blob storage name;
- random thumbnail storage name.

The manifest is photo-specific, but it remains client-side encrypted. Cloud
database rows and object keys must not duplicate or interpret any of these
fields.

## Portable `.khvault` archive

The portable archive is a separate version 1 protocol and remains supported.
Cloud v1 does not silently redefine it.

| Layer | Current format |
|---|---|
| Container magic | `KHVAULT` plus NUL |
| Container version | UInt32 little-endian `1` |
| Public header | Bounded JSON `EncryptedVaultArchiveHeader` |
| Recovery credential | 20 secure-random bytes encoded as 32 Crockford Base32 characters |
| Header KDF | Argon2id v1.3; 65,536 KiB; 3 iterations; parallelism 2; 16-byte salt; 32-byte output |
| Secret wrapper | AES-256-GCM with authenticated KDF fields |
| Content stream | Authenticated 1 MiB chunks with sequence and final flag |
| Payload | Encrypted catalog followed by the existing encrypted `.khm`, `.khp`, and `.kht` bytes |

Portable archives include the local vault key inside their recovery-protected
secret payload. Cloud v1 instead uses the independent CRK -> AMK -> CVK key
hierarchy defined in `CLOUD_V1_GATE_A_PROTOCOL.md`.

## Snapshot requirement

Cloud backup input must be a stable snapshot, not live paths that can change
during upload.

1. Authenticate and open only the selected vault.
2. Inside the `VaultPhotoStore` serialization boundary, authenticate the local
   manifest and resolve exactly its referenced files.
3. Materialize a protected, backup-excluded staging snapshot while vault
   mutations are blocked for the capture transaction.
4. Hash every staged encrypted file and bind its opaque cloud object reference,
   role, local storage name, length, and digest inside the encrypted cloud
   manifest.
5. Release the vault mutation boundary only after the snapshot is complete.
6. Remove staging after verified commit, cancellation, failure, or relaunch.

If protected data is unavailable because the device is locked, capture or
resume must defer. Cloud v1 must not weaken the current complete-file-protection
policy merely to run in the background.

## Compatibility invariants

- Build 11 local vaults remain readable without a cloud account.
- Existing `.khvault` version 1 imports and exports remain unchanged.
- Cloud v1 introduces new protocol identifiers and never overloads a local or
  portable version number.
- A cloud restore creates a new local LowKey envelope and never overwrites an
  existing vault.
- The server stores no filename, photo ID, media role, MIME type, caption,
  thumbnail semantics, folder path, LowKey, CRK, AMK, CVK, or decrypted
  manifest.
- Future folders and arbitrary file formats use a new encrypted manifest
  version while reusing the opaque server object model.

## Source map

- `KeyHollow/Security/KeyDerivation.swift`
- `KeyHollow/Security/VaultEnvelope.swift`
- `KeyHollow/Storage/VaultStore.swift`
- `KeyHollow/Photos/VaultPhotoModels.swift`
- `KeyHollow/Photos/VaultPhotoStore.swift`
- `KeyHollow/Transfer/PortableArchiveSecurity.swift`
- `KeyHollow/Transfer/PortableArchiveContainer.swift`
- `KeyHollow/Transfer/PortableArchivePayload.swift`
- `docs/ENCRYPTED_VAULT_ARCHIVE_SPEC.md`
- `docs/ENCRYPTED_VAULT_TEST_VECTORS.md`
