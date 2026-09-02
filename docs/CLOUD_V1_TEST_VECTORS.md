# KeyHollow Cloud v1 Deterministic Test Vectors

Status: Gate A, protocol version 1. These fixtures contain no production
secrets. Production encryption never accepts a caller-supplied nonce; the fixed
nonces below are available only to debug tests.

All integers are unsigned little-endian. Hex strings are continuous bytes even
when wrapped for readability.

## Common fixture values

| Value | Bytes or canonical value |
|---|---|
| Account ID | `00112233-4455-6677-8899-aabbccddeeff` |
| Vault ID | `ffeeddcc-bbaa-9988-7766-554433221100` |
| Object/key ID | `aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee` |
| Created milliseconds | `1720000000123` |
| AMK | `404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f` |
| CVK | `606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f` |

## Cloud Recovery Key

- Raw CRK: `000102030405060708090a0b0c0d0e0f10111213`
- Display: `KH1-000G-40R4-0M30-E209-185G-R38E-1W81-24GK-DN`
- Canonical key material:
  `6b6579686f6c6c6f772e636c6f75642d7265636f766572792d6b65792e76313a3030304734305234304d3330453230393138354752333845315738313234474b`
- Salt: `000102030405060708090a0b0c0d0e0f`
- Argon2id associated data:
  `6b6579686f6c6c6f772e636c6f75642e7265636f766572792d72776b2e7631`
- Derived RWK:
  `294f2a4dd45c12989e92826390f8fba4cf942a6d6d22af98d1886abc7468adbd`

Profile: Argon2id v1.3, 65,536 KiB, three iterations, parallelism two,
32-byte output.

## Recovery envelope

- Account-key ID: common account ID
- Envelope generation: `7`
- Nonce: `000102030405060708090a0b`
- Plaintext AMK generation: `2`
- Canonical plaintext:
  `4b4843414d4b310001000000404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f7b30fd77900100000200000000000000`
- AES-GCM combined value:
  `000102030405060708090a0b9c00af664a0f4d4466843e6483743f36d284adbd691bacd89ba722a78f9b33ae6a276438362aabbd371409f320477808746e0ef8b40aae5a98e69cdfca5945e6535207be3a3949250d9c7804`
- Complete stored envelope:
  `4b4843524543310001000000010000000100000000112233445566778899aabbccddeeff0700000000000000000102030405060708090a0b0c0d0e0f58000000000102030405060708090a0b9c00af664a0f4d4466843e6483743f36d284adbd691bacd89ba722a78f9b33ae6a276438362aabbd371409f320477808746e0ef8b40aae5a98e69cdfca5945e6535207be3a3949250d9c7804`

## Vault-key envelope

- AMK generation in header: `3`
- CVK generation in plaintext: `4`
- HKDF salt: ASCII `keyhollow.cloud.vault-key-wrapper.v1`
- Derived wrapping key:
  `94e8084a011e9a2193735ba548f6ec997fb3b08e6e065e10e9d3fd4f1e539f94`
- Nonce: `0c0d0e0f1011121314151617`
- Canonical plaintext:
  `4b484343564b310001000000606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f7b30fd77900100000400000000000000`
- AES-GCM combined value:
  `0c0d0e0f10111213141516170bcdc1bcea37fdc1de7dd568b314de318530ca3b01df0cb1977009bbf2c2fe529ab9dccba38ca54838eaba125106af1a6c1738a8f441a8d25efffe3bc6a46c058c8a9d0db5f82df55bd98805`
- Complete stored envelope:
  `4b4843564b455900010000000100000000112233445566778899aabbccddeeffffeeddccbbaa99887766554433221100aaaaaaaabbbbccccddddeeeeeeeeeeee0300000000000000580000000c0d0e0f10111213141516170bcdc1bcea37fdc1de7dd568b314de318530ca3b01df0cb1977009bbf2c2fe529ab9dccba38ca54838eaba125106af1a6c1738a8f441a8d25efffe3bc6a46c058c8a9d0db5f82df55bd98805`

## One cloud-object chunk

- Purpose: content (`2`)
- Object version: `4`
- Plaintext: bytes `00` through `1f`
- HKDF salt: ASCII `keyhollow.cloud.object-chunk-key.v1`
- Derived chunk key:
  `570b11cf7273923ef782de722c2e0f66f4e205896f0a99fd5e2d636232624b55`
- Nonce: `18191a1b1c1d1e1f20212223`
- Complete frame:
  `0000000001200000003c00000018191a1b1c1d1e1f202122235fd8ccfd9c25c287df23ad1daf43b765621f56949c40495c4dfa9c82c25abcd7176125b93ebd2fe2f99594efed45c53a`

The authenticated context includes the complete object header, sequence zero,
final flag one, and plaintext length 32. Changing account, vault, object,
version, sequence, final state, or length must fail authentication.

## Manifest

The canonical one-entry manifest is 278 bytes. It includes the fixed
`CloudLocalVaultSecretV1` (`KHCLVK1`, version 1, local vault key bytes
`80...9f`, and source creation timestamp) before the entry count:

```text
4b48434d414e31000100000000112233445566778899aabbccddeeffffeeddcc
bbaa99887766554433221100102030405060708090a0b0c0d0e0f00001000000
00000000007b30fd7790010000010000004b48434c564b310001000000808182
838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f414df1
238e0100000100000011111111222233334444555555555555010c0000006d61
6e69666573742e6b686daaaaaaaabbbbccccddddeeeeeeeeeeee010000000000
00001c00000000000000000102030405060708090a0b0c0d0e0f101112131415
161718191a1b1c1d1e1f9e00000000000000202122232425262728292a2b2c2d
2e2f303132333435363738393a3b3c3d3e3f01000000
```

SHA-256:
`0a6e8c0e391e884dcd4262e2c0f6f2e0e630aaf93ae044c27d0816c9e5fad579`.

## Required negative interpretations

Tests must reject wrong recovery codes, wrong AMKs/CVKs, one-byte mutations,
cross-account or cross-vault use, wrong generation or purpose, unsupported
versions, invalid counts and lengths, duplicates, unsafe local names,
truncation, and trailing input. These vectors are compatibility fixtures, not
permission to use fixed keys or nonces outside tests.
