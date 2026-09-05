# General File Support Add-on

General File Support is an independently compiled, local-only KeyHollow add-on.
It expands a vault beyond photos without changing the existing photo manifest,
photo blobs, credential envelopes, or `.khvault` version-one decoder.

## First release scope

- Import up to 50 regular files per selection from Apple's Files interface.
- Open the Files picker directly from the vault's primary import menu; the
  capability is not hidden inside security or overflow settings.
- Review the pending selection before import. No selected file is committed to
  the encrypted vault until the user taps the explicit Import into Vault action;
  canceling or removing a pending item leaves the vault unchanged.
- After a successful import launched from the primary Vault screen, discard the
  pending review state and return to the unified Vault grid after the user
  acknowledges the result. Opening `Vault Files` intentionally remains the
  management path for stored-file export and deletion.
- Accept common documents, PDFs, audio, archives, text, and other data files.
- Encrypt the file bytes and authenticated metadata before committing the item
  to the add-on manifest.
- Show only the authenticated display name, type, and size after unlock.
- Compose authenticated general-file records into the primary Vault screen so a
  file-only vault never appears empty; the photo and general-file manifests
  remain independently stored and compiled behind the presentation layer.
- Present photos and general files in one consistent square-tile grid; file
  tiles retain a type icon, name, and size while opening the dedicated file
  manager for file-specific actions.
- Select one or many files, export authenticated copies through the system share
  interface, or permanently delete their encrypted vault copies.
- Keep every source file unchanged during import.

The first release intentionally excludes folders, packages, executable formats,
`.khvault` backups, empty files, and individual files larger than 100 MB. Video
and streaming large-file encryption remain a separately reviewed add-on.

## Security and architecture boundaries

- Implementation lives in `KeyHollow/AddOns/GeneralFileSupport` and compiles as
  `KeyHollowGeneralFileSupportAddOn`.
- The add-on receives authenticated seal/open operations through
  `VaultGeneralFileCryptographicAccess`; it never receives or retains a vault
  key.
- The add-on owns the security-scoped file-selection lifetime during import
  review; the presentation layer receives only bounded candidate metadata and
  explicit confirm/discard actions.
- The app session derives domain-separated keys and retains synchronous
  revocation ownership.
- Incoming files are copied from security-scoped URLs into protected temporary
  storage before encryption. The protected copy is removed after import.
- Blob names are random. File names, content types, sizes, and timestamps exist
  only inside the encrypted manifest.
- Exports are authenticated before a protected temporary copy is shared, then
  the temporary export directory is removed when the system sheet closes.
- Interrupted import and export staging is purged the next time the encrypted
  file store opens, covering app termination before normal cleanup completes.
- Vault deletion invokes an injected add-on cleanup boundary after credential
  destruction, without making the protected vault core import the add-on.

## Transfer compatibility

Existing `.khvault` exports and restores remain byte-format compatible and
continue to transfer the existing encrypted photo store. General files are not
silently inserted into version one. Adding general files to portable whole-vault
transfer requires a separately reviewed, versioned catalog extension with old-
archive decoding, hostile-input, interruption, rollback, and device tests.

The add-on is not eligible to merge until its own CI, security analysis,
production-identity TestFlight, physical-device, interruption, low-storage, and
data-integrity gates have passed.
