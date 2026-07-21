# TetherTTY

TetherTTY is a simple, open-source iPhone SSH app for reconnecting to your laptop’s running terminal sessions.

It is designed for one focused use case: open the app, connect to your laptop, and jump straight back into an existing `tmux` or `herdr` session. No heavy server dashboard, no complex workspace system, no account required — just a lightweight mobile terminal companion for your own machine.

TetherTTY is meant for developers who already live in the terminal and want a clean way to check, resume, or control long-running work from their phone.

## Goals

* Simple SSH access from iPhone
* Fast reconnecting to existing terminal sessions
* First-class support for `tmux` and `herdr`
* Minimal setup and no hosted backend
* Open source, privacy-friendly, and free to use

## Development status

The current iPhone MVP is implemented as a native SwiftUI app with local host management, Face ID unlock, OpenSSH-style host-key trust, tmux and Herdr session discovery, a session picker, and a terminal with extra-key row. SSH connectivity, session discovery, and host-key fingerprint resolution use simulated development layers that will be replaced with a real SSH library before release. The architecture is designed for this substitution without affecting the UI or data layers.

## Non-goals

TetherTTY is not trying to replace full-featured SSH clients, cloud IDEs, or remote desktop tools. It is intentionally small: a focused bridge from your phone to your running terminal.

