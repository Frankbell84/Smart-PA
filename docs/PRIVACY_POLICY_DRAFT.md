# KeyHollow Privacy Policy — Draft

**Last updated:** August 30, 2026

KeyHollow is designed as a local-only encrypted photo vault. This draft describes the planned behavior of KeyHollow V1 and must be checked against the final App Store build before publication.

## Information KeyHollow collects

KeyHollow V1 does not require an account and is not designed to collect personal information. The app does not include advertising or analytics SDKs and does not send vault contents, passcodes, encryption keys, usage history, or device identifiers to a KeyHollow server.

## Photos access

KeyHollow uses Apple's system photo picker so you can choose images to copy or move into a vault. Selected images are processed on your device. KeyHollow re-encodes selected images to reduce embedded metadata, encrypts them locally, and stores the encrypted files in the app's protected container.

When you choose **Copy to Vault**, the original remains in Apple Photos. When you choose **Move to Vault**, KeyHollow first encrypts and verifies the local vault copy, then asks iOS to delete the selected original. If deletion is denied or cannot be completed for every eligible item, KeyHollow reports the operation as copied.

Apple may process permission requests and photo-library changes under Apple's own terms and privacy policy.

## Local storage and security

Vault photos, thumbnails, and manifests are stored using authenticated encryption. Each vault has independent cryptographic key material. Vault passcodes and usable vault encryption keys are not stored as plaintext files.

No security system can guarantee protection against every threat. A compromised, modified, or already-unlocked device may weaken the protections described here. Users are responsible for remembering their KeyHollow vault passcodes; KeyHollow V1 has no account-based passcode recovery.

## Cloud storage and backups

KeyHollow V1 does not provide KeyHollow-operated cloud storage or synchronization. Its protected vault-data directory is marked to be excluded from ordinary device backup. Users should not assume that encrypted vault contents can be restored after deleting the app, erasing the device, losing the device, or deleting a vault.

## Data sharing and sale

Because KeyHollow V1 is not designed to collect personal information, KeyHollow does not sell personal information or share it for cross-context behavioral advertising.

## Children's privacy

KeyHollow is not directed to children under 13, and KeyHollow V1 is not designed to knowingly collect personal information from children.

## Changes to this policy

This policy may be updated when KeyHollow's features or legal obligations change. The published policy will show its effective date.

## Contact

Before App Store submission, replace this section with the final support contact and publish this policy at the final privacy-policy URL.

