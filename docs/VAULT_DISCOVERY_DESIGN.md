# NoxLock Vault Discovery Design — Draft 0.2

## Goal

Entering a NoxLock passcode should open exactly the vault associated with that passcode without presenting a normal plaintext directory of vault names/counts to the locked UI.

## Current V1 design: opaque locator files

NoxLock does not maintain a plaintext vault directory for the locked UI. Instead, each vault envelope is stored under a 256-bit opaque locator derived only after the entered passcode has completed the expensive Argon2id path.

This design intentionally prioritizes cryptographic simplicity and uniform unlock work over pretending to provide perfect forensic deniability. A sophisticated forensic examiner may still infer that encrypted NoxLock data exists from filesystem/storage artifacts. NoxLock must not claim otherwise.

## Unlock derivation

For every entered passcode:

1. Load the device-local 256-bit pepper from Keychain.
2. Load the random installation salt from Keychain.
3. Validate only the public 6–20 digit format.
4. HMAC-SHA256 the passcode with the device pepper to create fixed-width secret KDF input.
5. Run Argon2id v1.3 with the installation salt. **This happens before any vault-file existence check.**
6. Expand the resulting unlock key with HKDF into independent subkeys:
   - locator key
   - vault-envelope wrapping key
7. Derive the 256-bit opaque locator from the locator key.
8. Attempt to read the envelope at that opaque locator.
9. If present, authenticate/decrypt it with AES-256-GCM under the wrapping key.
10. A valid envelope contains a random vault identifier and that vault's independently random 256-bit data-encryption key.
11. Missing files, malformed envelopes, authentication failure, and other credential-path errors produce the same user-visible invalid-credential result.

Running Argon2id before the file lookup avoids a simple timing distinction where random guesses would otherwise fail almost instantly while a real passcode incurred KDF work.

## Vault data key

The vault data-encryption key is independently random and is not deterministically derived from the numeric passcode. The passcode-derived wrapping key protects the envelope containing the random vault key. This permits a future passcode change without re-encrypting every photo: unwrap the existing vault key with the old credential and re-wrap it under the new credential.

## Locator collisions

The locator uses the full 256-bit HMAC-SHA256 output, making accidental collisions negligible for realistic vault counts. Creation still checks whether the derived locator is already occupied and rejects re-use of an existing passcode.

## Metadata / deniability boundary

The normal lock-screen experience does not enumerate vaults, names, security tiers, or counts. However, V1 does not claim perfect deniability against forensic inspection of the device or app container. Optional metadata-padding approaches can be evaluated later only if they do not weaken the core cryptography or reliability.

## Rate limiting

Online attempts inside NoxLock are rate limited with increasing delays persisted across relaunches. Rate limiting is defense-in-depth for interactive guessing. It does not replace KDF strength because a sufficiently capable attacker with extracted secrets/material may bypass application-level delays.

## Six-digit warning

A six-digit PIN contains only one million possible numeric strings. NoxLock therefore labels six digits as the lowest security tier. Argon2id, the Keychain pepper, iOS Data Protection, and online rate limiting improve resistance, but NoxLock must not represent a six-digit PIN as equivalent to a high-entropy secret.

## No alternate unlock

Neither Face ID, Touch ID, nor the Apple device passcode can unwrap or substitute for a NoxLock vault passcode. Platform security still protects the app sandbox/Keychain at the operating-system layer.
