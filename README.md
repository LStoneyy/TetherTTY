<div align="center">

<img src="docs/logo.svg" alt="TetherTTY" width="560">

**A lightweight iPhone SSH companion for reconnecting to your `tmux` and `herdr` sessions.**

![Platform](https://img.shields.io/badge/iOS-18.0%2B-0ABD8A?style=flat-square)
![UI](https://img.shields.io/badge/SwiftUI-46DEDE?style=flat-square)
![SSH](https://img.shields.io/badge/SwiftNIO_SSH-4F8A91?style=flat-square)
![Terminal](https://img.shields.io/badge/SwiftTerm-4F8A91?style=flat-square)
![License](https://img.shields.io/badge/License-Apache_2.0-D6E8DE?style=flat-square)

</div>

## Overview

TetherTTY is a small, open-source iPhone SSH app designed for one focused use case: open the app, connect to your laptop or server, and jump straight back into an existing `tmux` or `herdr` session. No hosted backend. No account required. Just a lightweight mobile terminal companion.

Built with native SwiftUI, real SSH via SwiftNIO, and terminal emulation from SwiftTerm, TetherTTY brings your long-running terminal sessions to your pocket. It's meant for developers who already live in the terminal and want a clean way to check, resume, or control work in progress from their phone.

All data stays local — connections, credentials, and host-key trust are stored on-device only. Direct SSH from your iPhone to your own machine.

## Features

* **Real SSH over SwiftNIO** — authenticated, password-based SSH connections using the SwiftNIO SSH library (0.14.1), no mock layers.
* **Terminal emulation** — full VT100/xterm terminal (SwiftTerm 1.15.0) rendered natively in SwiftUI, with keyboard accessory row for control characters.
* **Session discovery** — automatic discovery of running `tmux` and `herdr` sessions by executing real CLI commands and parsing output; attach with a single tap.
* **Seamless reattach** — lock your phone or background the app, then come back and pick up exactly where you left off: TetherTTY silently re-establishes the SSH connection and re-attaches to the same `tmux`/`herdr` session, no manual re-selection. See [Persistent Sessions](#persistent-sessions).
* **Host-key trust** — OpenSSH-style trust-on-first-use (TOFU); SHA256 host-key fingerprints are locally pinned and verified on each connection.
* **Face ID app lock** — biometric unlock gate before accessing your host list, adding a security layer for sensitive credentials.
* **Keychain credentials** — SSH passwords are encrypted and stored per connection using iOS Keychain.
* **Session picker** — clean UI to select between available tmux/Herdr sessions or open a plain shell.
* **Abyssal design** — a custom dark theme with a deep teal/aqua/mint palette ("The Loom" for your host list, "tethers" for connections, a circular sigil mark).
* **No backend, no account** — everything runs on your phone; no server required.

## How It Works

1. **Unlock** — Face ID prompts you to unlock the app.
2. **Select host** — browse "The Loom" (your stored SSH connections).
3. **Add or connect** — provide host, port, username, and password (stored securely in Keychain).
4. **Verify host key** — on first connection, you review and trust the host's SSH key fingerprint (TOFU model). On subsequent connections, the fingerprint is verified automatically; if changed, you are warned and the connection is refused.
5. **Discover sessions** — TetherTTY queries the server for running tmux and Herdr sessions by running real CLI commands.
6. **Pick a session** — select an existing session or open a plain shell.
7. **Terminal** — SSH shell opens with full terminal emulation and keyboard extras.
8. **Reconnect** — disconnect or reconnect at any time; returns to the session picker.
9. **Lock & resume** — lock your phone and unlock later; TetherTTY reattaches to the same session automatically (see below).

## Persistent Sessions

Lock your phone in the middle of a build, unlock it later, and your session is still right there — TetherTTY reconnects and re-attaches without sending you back to the session picker.

**Why it works this way.** iOS suspends an app shortly after it goes to the background, which closes the underlying SSH socket — a truly always-open connection is not possible on iOS. TetherTTY does not pretend otherwise. Instead it leans on the fact that your session lives on the **server**: `tmux` and `herdr` keep running regardless of whether a client is attached. When you return to the app, TetherTTY opens a fresh SSH connection and re-runs the same attach command, dropping you back into the exact session you left. This is more robust than a nominally "kept-open" connection — it also survives network changes and idle timeouts.

**Behavior:**

- A short grace period (~2s) means a quick glance at your phone won't force a reconnect.
- On return, a **Reconnecting…** indicator is shown while the session is restored. Reconnection is silent — no re-entering credentials within the same app session.
- If reattach fails, TetherTTY retries a few times with exponential backoff, then falls back to a manual reconnect option.
- **TCP keepalive** is enabled on the interactive connection so mid-session drops (e.g. Wi-Fi → cellular handoff) are detected in a bounded time rather than hanging.

If iOS fully terminates the app in the background (e.g. under memory pressure), the next launch starts locked as usual — your server-side session is of course untouched and waiting.

## Architecture

TetherTTY follows an **MVVM structure** organized by feature:

- **Models** — data types for connections, sessions, app state, app-lock state.
- **ViewModels** — view logic for the host list, session picker, terminal, app lock, and connection flows.
- **Features** — SwiftUI views (SSHTerminalView, session picker, connection form, etc.).
- **Networking** — `SSHClient.swift` defines the protocol with two implementations:
  - `SwiftNIOSSHClient` — real SSH (production).
  - `SimulatedSSHClient` — mock for testing/development.
  - Shell channel with PTY (`xterm-256color`), plus one-shot `execute` for session discovery.
- **Providers** — session discovery via `TmuxSessionProvider` and `HerdrSessionProvider`; parsers extract session names from CLI output.
- **Security** — host-key trust evaluation and TOFU implementation.
  - `KnownHostStore` — local storage of pinned host-key fingerprints.
  - `HostKeyTrustEvaluator` — SHA256 fingerprint verification.
  - `VerifyingHostKeyDelegate` — SSH server key delegate.
- **Persistence** — `ConnectionRepository` for local on-device storage of host configurations.
- **Credentials** — `CredentialStore` manages SSH passwords via iOS Keychain (no plain-text storage).
- **Theme** — `AbyssalTheme` provides the custom dark palette and design tokens.

Swift Package dependencies (resolved automatically):
- `swift-nio-ssh` (0.14.1) — SSH protocol implementation.
- `SwiftTerm` (1.15.0) — VT100/xterm terminal emulation.
- Transitive: swift-nio, swift-crypto, swift-collections, etc.

## Getting Started

### Requirements

- **Xcode** (recent version; project targets Swift 5+ and uses object version 77).
- **iOS 18.0+** deployment target.
- Mac with Xcode, or Xcode on macOS.

### Build & Run

1. Clone the repository.
2. Open `TetherTTY.xcodeproj` in Xcode.
3. Allow Swift Package Manager to resolve dependencies (swift-nio-ssh, SwiftTerm, etc.).
4. Select your build target (simulator or device).
5. Press Cmd-U to run tests, or Cmd-R to build and run on your device/simulator.

Alternatively, use `xcodebuild` from the command line:
```bash
xcodebuild build -project TetherTTY.xcodeproj -scheme TetherTTY \
  -destination 'generic/platform=iOS Simulator'
```

### Tests

Unit tests are located in `TetherTTYTests/` and cover:
- Connection repository persistence.
- Theme logic.
- App-flow integration.
- Terminal view model.
- Session parsers (tmux and Herdr).
- App-lock state.
- Host-key trust evaluation.

Run tests with Cmd-U in Xcode or (pick any available simulator for the destination):
```bash
xcodebuild test -project TetherTTY.xcodeproj -scheme TetherTTY \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Security & Privacy

- **No backend.** All traffic is a direct SSH connection from your phone to your own machine. We do not run a server, collect telemetry, or track user activity.
- **On-device storage.** Connections, host-key trust, and app state are stored locally on your iPhone.
- **Keychain encryption.** SSH passwords are encrypted by iOS Keychain; not stored in plain text.
- **Host-key pinning.** SSH host keys are verified using OpenSSH-style TOFU (trust-on-first-use); fingerprints are SHA256 and stored locally. A changed host key is rejected.
- **Biometric gate.** Face ID protects access to your host list and credentials.

## Non-Goals

TetherTTY is not trying to replace full-featured SSH clients, cloud IDEs, or remote desktop tools. It is intentionally small: a focused bridge from your phone to your running terminal.

## License

TetherTTY is open source under the **Apache License 2.0**. See `LICENSE` for details.
