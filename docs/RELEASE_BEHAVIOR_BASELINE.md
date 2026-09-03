# KeyHollow Release Behavior Baseline

This document freezes the user-visible and security-relevant behavior of the
KeyHollow 1.0 Build 11 release before later architectural cleanup. Refactors
must preserve this behavior unless a separately reviewed product change says
otherwise.

## Vault identity and access

- A new vault requires an acceptable 8–20 digit LowKey. Predictable patterns
  such as repeated or sequential digits are rejected.
- Each accepted LowKey creates one independent vault with a random vault ID and
  random data-encryption key.
- A LowKey opens only its matching vault. The locked interface does not list
  existing vaults or reveal their count.
- The locked interface always offers creation of another independent vault.
- Face ID, Touch ID, and the device PIN are not alternate vault credentials.

## Lifecycle and persistence

- Vault creation is complete only after its authenticated credential envelope
  has been written successfully. A later service instance must detect and open
  the completed vault.
- Locking clears the active vault ID and active key from the in-memory session.
- Changing a LowKey rewraps the same random vault key. It does not create a new
  vault or re-encrypt the photo library.
- A failed LowKey change must leave the original vault accessible and must not
  replace another vault's credential.
- Deleting a vault first removes its credential envelope, then removes that
  vault's encrypted photo directory. Other vaults remain accessible.
- A wrong LowKey or a mismatched expected vault ID cannot change or delete a
  vault.

## Photos and app lifecycle

- Imported originals, thumbnails, and the manifest are stored only as
  authenticated ciphertext.
- Copy preserves the source in Photos. Move verifies the encrypted vault copy
  before asking iOS to delete the source.
- The app locks on a true background transition. A system Photos or Files
  handoff must not be mistaken for leaving the app while that interaction is
  active.
- Selected vault photos can be saved back to Photos or deleted from the open
  vault; unselected encrypted items remain intact.

## Portable encrypted vaults

- Export operates only on the currently open vault and leaves its local source
  unchanged.
- A `.khvault` archive is authenticated and encrypted with a separate recovery
  code. That recovery code never unlocks the normal local keypad.
- Restore validates and stages the complete archive before installing a new
  local vault identity and LowKey wrapper.
- Wrong recovery codes, tampering, truncation, path traversal, credential
  collision, cancellation, or an interrupted restore must fail closed without
  exposing plaintext or replacing an existing vault.

## Automated Stage One evidence

- `VaultLifecycleBaselineTests` covers create, persistence across service
  recreation, session lock, unlock, LowKey change, deletion, encrypted-photo
  cleanup, rejected creation, duplicate LowKeys, cross-vault mutation attempts,
  and continued access to unaffected vaults.
- Existing crypto, photo-store, archive, restore-transaction, lifecycle-policy,
  and launch tests remain part of the required release suite.
- Later architecture work should add coverage thresholds and expand device/UI
  testing for PhotoKit failures, background cancellation, large batches, and
  memory pressure; those are explicitly outside this baseline-only stage.
