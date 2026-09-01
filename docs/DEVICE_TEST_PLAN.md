# KeyHollow Real-Device Security Test Plan

This checklist must be executed on a physical iPhone before external TestFlight distribution.

## Install and first launch

- Install a signed development/TestFlight build on a clean device.
- Confirm first launch offers first-vault setup and does not expose any vault count.
- Create a Standard 8-digit vault and verify successful entry.
- Lock and confirm the same passcode reopens the same vault.
- Confirm an incorrect 8–20 digit passcode shows only the generic failure state.
- Confirm passcodes shorter than 8 digits cannot be submitted or used to create a vault.
- Confirm repeated digits, ascending/descending sequences, and repeated short patterns are rejected during creation and passcode changes.

## Multiple vaults

- From the locked home screen, tap **Create New Vault** without unlocking an existing vault.
- Confirm the action opens new-vault setup without displaying a vault list, vault count, or any existing-vault details.
- From Vault A, create Vault B with a different passcode.
- Import distinct photos into A and B.
- Lock KeyHollow.
- Confirm Passcode A opens only A and Passcode B opens only B.
- Confirm neither vault UI reveals the existence, passcode length, name, count, or contents of the other vault.
- Create vaults using 8, 10, 12, 16, and custom-length passcodes.

## Brute-force throttling

- Enter enough invalid passcodes to trigger each configured delay tier.
- Verify a known valid vault passcode does not erase global failed-guess history.
- Verify the throttle eventually decays according to policy.
- Verify the lock screen does not reveal whether a guessed locator existed.

## Copy to Vault

- Select one photo and Copy to Vault.
- Confirm the encrypted vault copy appears and opens.
- Confirm the original remains in Apple Photos.
- Repeat with multiple photos and limited Photos permission.

## Move to Vault

- Select one photo and Move to Vault.
- Confirm KeyHollow encrypts and verifies the vault copy before requesting deletion from Photos.
- Approve deletion and confirm the original is removed from Photos while the vault copy remains readable.
- Deny/cancel deletion and confirm KeyHollow reports the operation as copied, not moved.
- Test a mixed batch where one item cannot be represented by a deletable asset identifier; verify KeyHollow deletes none of the originals for that batch and treats it as copied.

## Photo integrity and tamper behavior

- Import photos of different sizes/orientations.
- Force-quit and reopen; confirm gallery and images decrypt correctly.
- Confirm encrypted thumbnails reload correctly.
- Modify/corrupt a test vault blob in a development environment and verify authentication fails closed rather than displaying partial/corrupt plaintext.

## Background and app-switcher privacy

- Open a sensitive photo and send KeyHollow to the background.
- Confirm the active vault session is destroyed.
- Confirm the app-switcher preview shows only the opaque KeyHollow privacy shield and never the photo/gallery.
- Return to KeyHollow and confirm a passcode is required again.
- Repeat during photo import, gallery view, and full-screen photo view.

## Device authentication exclusion

- Confirm there is no Face ID prompt anywhere in the app.
- Confirm there is no Touch ID prompt on supported hardware.
- Confirm the iPhone device passcode cannot substitute for a KeyHollow vault passcode.
- Confirm Keychain access used by KeyHollow does not present a biometric/device-passcode unlock path to the user.

## Passcode change

- Change Vault A's passcode using the current passcode.
- Confirm the old passcode no longer opens the vault.
- Confirm the new passcode opens the same photos with no re-import required.
- Confirm attempting to change to a passcode already associated with another vault fails without revealing why.

## Vault deletion

- Delete a non-final vault only after current-passcode verification and explicit DELETE confirmation.
- Confirm its passcode no longer opens anything.
- Confirm its encrypted photo directory is removed.
- Confirm other vaults are unchanged.
- Delete the final vault and confirm KeyHollow returns to first-vault setup.

## Permissions and interruptions

- Test Photos permission states: full, limited, denied, and changed in Settings while KeyHollow is installed.
- Interrupt imports by backgrounding the app.
- Force-quit during import and verify no committed manifest entry points to missing plaintext/ciphertext data.
- Test low-storage behavior and verify operations fail without falsely reporting success.

## Backup/container inspection

- Confirm KeyHollow encrypted storage directories/files carry complete file protection.
- Confirm protected vault data is excluded from ordinary backup as designed.
- Inspect the app container in a development environment and verify no plaintext photos, thumbnails, passcodes, keys, sensitive filenames, or manifest contents are persistently stored.

## Release gate

External TestFlight distribution should not begin until all critical items above pass or have a documented accepted risk. App Store security claims require the separate independent security review described in `SECURITY_ARCHITECTURE.md`.
