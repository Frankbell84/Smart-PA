# KeyHollow App Store Metadata — Draft

## Name

KeyHollow

## Subtitle

Private encrypted photo vaults

## Promotional text

Keep selected photos in independent, locally encrypted vaults protected by separate KeyHollow passcodes.

## Description

KeyHollow is a local-only encrypted photo vault built around a simple idea: one keypad can open multiple independent vaults, and each vault has its own passcode and encryption key.

Choose **Copy to Vault** to keep an original in Photos, or choose **Move to Vault** to encrypt and verify the vault copy before iOS is asked to delete the original.

KeyHollow V1 includes:

- Multiple independent encrypted photo vaults
- 8–20 digit passcodes with safeguards against common predictable patterns
- Authenticated encryption for photos, thumbnails, and vault manifests
- Automatic locking when KeyHollow leaves the foreground
- An opaque app-switcher privacy cover
- Local-only storage with no KeyHollow account or cloud service
- No advertising or analytics SDKs
- No Face ID, Touch ID, or device-passcode fallback for vault access

KeyHollow passcodes cannot be recovered. Deleting the app, deleting a vault, erasing the device, or losing the device can permanently remove access to locally stored vault contents.

## Keywords

photo vault,privacy,encrypted photos,local storage,private album,secure photos

## Primary category

Utilities

## Secondary category

Photo & Video

## Review notes — draft

KeyHollow does not require an account. On first launch, create an 8–20 digit vault passcode that does not contain a blocked predictable pattern. Import testing uses Apple's photo picker. The **Move to Vault** flow asks for Photos read/write authorization only after the selected items have been encrypted and verified locally.

The app intentionally does not offer Face ID, Touch ID, or the iPhone device passcode as a vault-passcode replacement.

## Required before submission

- Confirm the name and subtitle in App Store Connect.
- Add final support and privacy-policy HTTPS URLs.
- Supply final screenshots captured from the signed build.
- Complete age-rating, app-privacy, and encryption/export-compliance answers against the final build.
- Replace any draft text that no longer matches tested behavior.

