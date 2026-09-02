# KeyHollow Security Policy

KeyHollow protects private user content. Please report suspected security
issues privately so they can be investigated before technical details become
public.

## Supported versions

| Version | Security updates |
|---|---|
| Current App Store release | Supported |
| Current `main` branch | Supported |
| Older builds and development branches | Not supported |

The `security/vault-hardening` branch and its draft pull request are active
review work, not a production release.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting flow for this repository:

1. Open the repository's **Security** tab.
2. Select **Advisories** and **Report a vulnerability**.
3. Include the affected version, reproduction steps, security impact, and any
   suggested remediation.

If private reporting is unavailable, open a public issue titled **Security
contact request** without exploit details. A maintainer will establish a
private channel. Never place a real vault, Low Key, passcode, recovery code,
personal media, signing credential, or other sensitive data in a public issue.

## Response targets

- Acknowledge a complete report within three business days.
- Triage severity and reproducibility within seven business days.
- Keep the reporter informed when the investigation materially changes.
- Coordinate disclosure after a fix or mitigation is available.

These are response goals, not a guarantee that every issue can be resolved
within a fixed period.

## Scope priorities

High-priority reports include:

- recovery of plaintext without the correct credential;
- Low Key, recovery-code, or vault-key disclosure;
- AES-GCM nonce reuse or authentication bypass;
- unauthenticated archive metadata that changes security behavior;
- path traversal, arbitrary file writes, or resource exhaustion during import;
- Keychain, backup, logging, clipboard, notification, or screenshot leakage;
- signing, TestFlight, GitHub Actions, or dependency compromise.

Reports about marketing claims, general feature requests, or attacks that
require the reporter's own already-unlocked device without crossing a security
boundary may be handled as ordinary issues.

## Research guidelines

- Test only with data and accounts you own or are explicitly authorized to use.
- Do not access, modify, retain, or disclose another person's data.
- Do not degrade availability, perform denial-of-service testing, or target
  Apple, GitHub, or other third-party infrastructure.
- Stop testing and report privately if you encounter real user data or secrets.
- Allow reasonable time for investigation and remediation before disclosure.

The KeyHollow project welcomes good-faith research that follows these
guidelines.
