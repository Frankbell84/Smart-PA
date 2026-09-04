# `.khvault` File Recognition

## User outcome

iOS can identify a `.khvault` file as a KeyHollow encrypted vault. Tapping the
file in Files launches KeyHollow and routes directly to the existing encrypted-
vault import screen with that file already selected.

On current iOS versions, Files uses the exported type's `UTTypeIcons`
metadata to build the document tile with KeyHollow's app icon as its badge.
Legacy document icon PNGs remain declared as a compatibility fallback.

## Security boundary

`KeyHollowFileRecognitionAddOn` recognizes only local file URLs whose final
extension is `.khvault`. It does not parse, decrypt, authenticate, move, or
install vault data.

The existing import flow remains authoritative. Open-in-place access is used
only long enough to copy the incoming file into protected temporary storage;
KeyHollow never edits or deletes the original. It checks available capacity,
authenticates the
complete archive with the recovery code, re-authenticates immediately before
installation, and rolls back an incomplete install. A recognized filename is
never treated as proof that the file is a valid KeyHollow archive.

The app composition layer owns the concrete recognizer. The presentation layer
receives only a narrow `(URL) -> URL?` function and hands accepted URLs to the
existing import screen. No protected core target imports the add-on.

## Compatibility and removal

- Existing vaults and the `.khvault` container format are unchanged.
- Manual import continues to work whether or not file recognition is present.
- Removing the add-on removes only the iOS open-in entry point.
- Unsupported or remote URLs are rejected before reaching the import screen.

## Release evidence required

In addition to the complete KeyHollow regression suite and security scan:

1. Confirm Files shows KeyHollow as an available handler for `.khvault`.
2. Open a valid export from Files with KeyHollow locked and unlocked.
3. Confirm the chosen filename and size are shown without opening a second
   picker.
4. Confirm the correct recovery code restores a new independent vault.
5. Confirm a wrong recovery code, renamed non-vault file, corrupted archive,
   low-storage condition, cancellation, and interruption fail safely.
6. Confirm the original `.khvault` file and all existing vaults remain intact.
