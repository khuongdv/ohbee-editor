# Security Policy

Ohbee Editor is designed for local handling of messy or sensitive text. The app should work fully offline and should not send document text outside the Mac.

## Supported Versions

Security fixes are expected to target the latest public release line.

| Version | Supported |
|---|---|
| 1.1.x | Yes |
| 1.0.x | Best effort |

## Reporting a Vulnerability

Please report security or privacy issues privately first.

Email: `hi@ohbee.link`

Include:

- A short description of the issue.
- Steps to reproduce.
- Impact, especially whether local document text could be exposed, lost, or written unexpectedly.
- App version and macOS version.

Please do not open a public GitHub issue for vulnerabilities that could expose sensitive text.

## Security Scope

In scope:

- Document text being sent over the network unexpectedly.
- Telemetry, analytics, or background upload behavior.
- Unsafe file writes or silent destructive changes.
- Session persistence bugs that expose or lose sensitive local text.
- Safe Share masking bugs that reveal selected findings after masking.

Out of scope:

- Claims that Safe Share detects every possible secret.
- General macOS clipboard behavior after the user explicitly copies text.
- Vulnerabilities caused by modified local builds or third-party forks.

## Privacy Model

Ohbee Editor is local-first:

- No account.
- No cloud sync.
- No telemetry.
- No remote AI calls.
- No background upload.
- Session restore is stored locally in Application Support.

Safe Share is conservative and best-effort. It helps notice likely sensitive text, but it does not guarantee complete secret detection.
