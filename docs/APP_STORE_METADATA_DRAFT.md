# KeyHollow App Store Metadata

**Public legal pages:**

- Privacy Policy: https://www.keyhollow.com/privacy
- Support: https://www.keyhollow.com/support
- Terms of Use: https://www.keyhollow.com/terms

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

## Review notes

KeyHollow does not require an account. On first launch, create an 8–20 digit vault passcode that does not contain a blocked predictable pattern. Import testing uses Apple's photo picker. The **Move to Vault** flow asks for Photos read/write authorization only after the selected items have been encrypted and verified locally.

The app intentionally does not offer Face ID, Touch ID, or the iPhone device passcode as a vault-passcode replacement.

## Release consistency checklist

- Confirm the name, subtitle, description, categories, price, and screenshots in App Store Connect.
- Confirm App Store Connect points to the public support and privacy-policy URLs above.
- Confirm app-privacy answers state that KeyHollow does not collect data, consistent with the shipped local-only build.
- Confirm age-rating and encryption/export-compliance answers against the shipped build.
- Recheck these answers whenever analytics, accounts, cloud features, or other data handling is added.
