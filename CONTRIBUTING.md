# Contributing to TetherTTY

Thanks for your interest in improving TetherTTY — a lightweight iPhone SSH
companion for reconnecting to `tmux` and `herdr` sessions. Contributions of all
sizes are welcome: bug reports, fixes, tests, and documentation.

## Reporting security issues

**Do not open a public issue for security vulnerabilities.** TetherTTY handles
SSH credentials and host-key trust, so please report vulnerabilities privately
via GitHub Private Vulnerability Reporting — see [`SECURITY.md`](SECURITY.md).

## Prerequisites

- **Xcode** (recent version) with the iOS 18+ SDK and an iOS Simulator.
- No manual dependency setup — Swift Package Manager resolves everything
  (SwiftNIO-SSH, SwiftTerm, and their transitive packages) on first build.

## Building and testing

Open `TetherTTY.xcodeproj` in Xcode and run the tests with **Cmd-U**, or from
the command line (pick any available iPhone simulator for the destination):

```bash
xcodebuild test -project TetherTTY.xcodeproj -scheme TetherTTY \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

CI runs the same build-and-test on every push and pull request (see
`.github/workflows/build-test.yml`) and selects an available simulator
automatically.

**All tests must pass before a pull request can be merged.** If you change
behavior, add or update tests to cover it.

## Pull request workflow

1. Fork the repository and create a topic branch off `main`
   (e.g. `fix/host-key-timeout` or `feat/session-search`).
2. Make your change with focused commits and matching tests.
3. Push and open a pull request against `main`.
4. CI (`Build & Test`) must be green, and the change requires review approval
   from the code owner before it can be merged.
5. Keep pull requests scoped to one logical change where possible — it makes
   review faster and reverts safer.

`main` is protected: no direct pushes or force-pushes, required status checks,
and required review.

## Commit messages

This project follows [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <summary>
```

Common types: `feat`, `fix`, `chore`, `docs`, `test`, `refactor`, `ci`.
Examples from this repo:

- `fix(ssh): make host-key verification fail-closed`
- `fix(terminal): restrict URL schemes to https-only`
- `ci: select simulator by UDID to fix destination matching`

Write a concise summary describing the user-visible or architectural change.

## Code style and conventions

- Match the style of the surrounding Swift code: SwiftUI views, `@MainActor`
  view models, and an MVVM-ish layering (`Models`, `ViewModels`, `Features`,
  `Networking`, `Security`, `Persistence`, `Providers`).
- **No `print()` in production code.** Sensitive values (hostnames, usernames,
  key material, command output) must never be logged. CI/tests guard against
  reintroducing `print(` in the app target.
- Treat remote terminal output as untrusted. Be careful with anything that
  crosses the terminal boundary (clipboard, links, startup commands) — see the
  hardening notes in `README.md` and `security-audit.md`.
- Keep persistence and security layers decoupled (for example,
  `ConnectionRepository` must not reference `KnownHostStore`).

## Adding files to the Xcode project

`TetherTTY.xcodeproj/project.pbxproj` uses a hand-maintained, sequential object
ID scheme rather than Xcode's random identifiers. If you add a source or test
file, register it consistently (build file, file reference, the owning group,
and the target's Sources/Resources phase) and confirm the project still builds.

## License

By contributing, you agree that your contributions are licensed under the
project's [Apache License 2.0](LICENSE).
