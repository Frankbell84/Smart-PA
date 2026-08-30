# NoxLock Vault Discovery Design — Draft 0.1

## Goal

Entering a NoxLock passcode should open exactly the vault associated with that passcode without presenting a normal plaintext directory of vault names/counts to the locked UI.

## Fixed opaque slot bank

NoxLock maintains a fixed-size bank of opaque records rather than a variable-length plaintext vault list. Unused records are filled with cryptographically random padding so the ordinary on-disk structure does not simply expose `N vaults exist`.

This design is intended to reduce obvious metadata leakage. It is not a claim of perfect forensic deniability; filesystem history, storage usage, device state, backups, or sophisticated analysis can leak information and must be evaluated independently.

## Unlock derivation

For an entered passcode:

1. Load the device-local 256-bit pepper from Keychain.
2. Run the production Argon2id KDF using the passcode, public installation salt, and pepper as inputs according to the reviewed implementation design.
3. Expand the resulting unlock key with HKDF into independent subkeys:
   - locator key
   - vault-envelope wrapping key
4. Derive one or more deterministic slot candidates from the locator key.
5. Attempt authenticated decryption of the candidate envelope using the wrapping key.
6. A valid authenticated envelope contains a versioned NoxLock marker, random vault identifier, and that vault's independent random data-encryption key.
7. If authentication/validation fails, treat the attempt as an invalid passcode and reveal no slot/vault-specific information.

## Vault data key

The vault data-encryption key is independently random and is not deterministically derived from the numeric passcode. The passcode-derived wrapping key protects the envelope containing the random vault key. This permits a future passcode change without re-encrypting every photo: unwrap the existing vault key with the old credential and re-wrap it under the new credential.

## Collision handling

Slot selection must support collisions without exposing which slots are occupied. Candidate probing must be deterministic from the locator key. The exact slot count/probe strategy is a security parameter to be set after implementation testing and review.

## Rate limiting

Online attempts inside NoxLock are rate limited with increasing delays. Rate-limit state must itself be tamper-resistant enough to prevent trivial reset-by-relaunch behavior where practical. Rate limiting does not replace KDF strength because an attacker who obtains sufficient offline material may bypass application-level delays.

## Six-digit warning

A six-digit PIN contains only one million possible numeric strings. NoxLock therefore labels six digits as the lowest security tier. Argon2id, the Keychain pepper, iOS Data Protection, and online rate limiting improve resistance, but NoxLock must not represent a six-digit PIN as equivalent to a high-entropy secret.

## No alternate unlock

Neither Face ID, Touch ID, nor the Apple device passcode can unwrap or substitute for a NoxLock vault passcode. Platform security still protects the app sandbox/Keychain at the operating-system layer.
