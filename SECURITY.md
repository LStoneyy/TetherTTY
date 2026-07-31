# Security Policy

## Reporting a Vulnerability

**Please report security vulnerabilities privately — do not open a public issue.**

The primary and preferred channel is **GitHub Private Vulnerability Reporting**:

1. Go to the repository's **Security** tab.
2. Click **Report a vulnerability** (Private vulnerability reporting).
3. Describe the issue, affected version/commit, and reproduction steps.

This keeps the report private between you and the maintainer until a fix is available.

> Note for the maintainer: Private Vulnerability Reporting must be enabled under
> **Settings → Code security and analysis → Private vulnerability reporting**
> for the button above to appear.

Please include, where possible:

- A clear description of the vulnerability and its impact.
- The affected file(s), commit hash, or release.
- Step-by-step reproduction or a proof of concept.
- Any suggested remediation.

We ask that you give us a reasonable opportunity to investigate and address the
issue before any public disclosure. We do not currently offer a bug bounty.

## Supported Versions

TetherTTY is an actively developed, pre-1.0 project. Security fixes are applied
to the `main` branch. There is no long-term-support branch; please test against
the latest `main`.

## Scope

TetherTTY is an iOS SSH companion app. Relevant trust boundaries and the threat
model are summarized in the project `README.md` ("Security & Privacy") and
documented in detail in `security-audit.md`.

In scope:

- The SSH transport trust boundary (host-key verification / TOFU pinning).
- Terminal-emulation handling of untrusted remote output (escape sequences,
  OSC commands, links).
- Local handling of credentials and connection metadata on the device.
- Resource handling of remote command output.

Out of scope (documented residual risks, see `security-audit.md`):

- **TOFU first-contact MITM** without out-of-band fingerprint verification.
- A **fully compromised remote server** controlling its own terminal output.
- **Physical access to an unlocked, backgrounded device** (see the SEC-04
  residual-risk note in `security-audit.md` — the app-lock is an entry gate and
  is not re-challenged on return from background).
- iOS platform / jailbreak scenarios.

## Disclosure

Once a fix is prepared, we will publish it on `main` and, where warranted, a
GitHub Security Advisory describing the issue and the fixed version. We will
credit reporters who wish to be named.
