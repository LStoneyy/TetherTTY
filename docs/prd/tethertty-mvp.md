# PRD: TetherTTY iPhone MVP

## Problem Statement

Developers often keep important work running inside terminal sessions on a laptop, desktop, or remote machine. When they are away from their keyboard and only have an iPhone, reconnecting to that work through a generic SSH client is usually too slow, too broad, or too awkward.

TetherTTY solves one focused problem: open the app, connect to a known machine, see the running `tmux` and `herdr` sessions, and jump directly into the right terminal context. It should not become a full cloud IDE, remote desktop app, hosted dashboard, or heavyweight SSH client.

The app must feel safe enough to store credentials locally, fast enough for quick checks, and usable enough on iPhone that controlling terminal sessions does not feel like fighting the keyboard.

## Solution

TetherTTY will start as a native SwiftUI iPhone app. The MVP provides local saved SSH connections, password-first authentication, Face ID-protected local credential access, OpenSSH-style host-key verification, live `tmux` and `herdr` session discovery after connecting, an explicit session picker, and a mobile terminal with a fixed extra-key row.

After unlocking the app with Face ID or device passcode, the user sees a host list. Selecting a host starts an SSH connection. Once connected, TetherTTY runs session discovery commands on the remote host, normalizes discovered `tmux` and `herdr` sessions, and shows a picker. The user can attach to a discovered session or open a plain shell fallback.

The design direction is subtle dark fantasy: abyssal dark surfaces, teal and mint highlights, restrained glow, and sigil-like accents where useful. Terminal readability and trustworthiness remain more important than decoration.

## User Stories

1. As a developer, I want to save an SSH connection, so that I can reconnect to my laptop quickly from my phone.
2. As a developer, I want to store a host alias, so that I can recognize machines without remembering IP addresses.
3. As a developer, I want to store a host address, so that TetherTTY knows where to connect.
4. As a developer, I want to store a port, so that I can connect to machines that do not use the default SSH port.
5. As a developer, I want to store a username, so that I do not need to type it every time.
6. As a developer, I want password authentication in the MVP, so that setup works with the simplest possible remote SSH configuration.
7. As a developer, I want my saved password stored securely, so that my credentials are not exposed as plain app data.
8. As a developer, I want the app to require Face ID when opened, so that stored credentials are protected when someone else has my phone.
9. As a developer, I want device passcode fallback, so that I can still unlock TetherTTY if biometric authentication fails.
10. As a developer, I want a list of saved hosts, so that I can choose the machine I need quickly.
11. As a developer, I want recently used hosts to be prominent, so that repeated reconnects are fast.
12. As a developer, I want favorite hosts, so that my primary machines are easy to reach.
13. As a developer, I want to edit a saved connection, so that I can update host, port, username, or password.
14. As a developer, I want to delete a saved connection, so that stale machines do not clutter the app.
15. As a developer, I want connection errors to be understandable, so that I can tell whether credentials, network, SSH, or host-key validation failed.
16. As a developer, I want TetherTTY to remember known host fingerprints, so that I can detect suspicious host changes.
17. As a developer, I want to confirm a new host fingerprint on first connection, so that I explicitly trust the machine.
18. As a developer, I want changed host keys to block the connection, so that man-in-the-middle risk is not silently accepted.
19. As a developer, I want a clear changed-host-key warning, so that I understand why the app refuses to connect.
20. As a developer, I want to select a host and connect with one obvious action, so that getting back to work feels quick.
21. As a developer, I want clear connection states, so that I know when TetherTTY is connecting, authenticating, discovering sessions, ready, disconnected, or failed.
22. As a developer, I want `tmux` session discovery after connecting, so that I can attach to existing work.
23. As a developer, I want `herdr` session discovery after connecting, so that I can control Herdr workspaces, tabs, or agents from my phone.
24. As a developer, I want Herdr discovery to use flexible CLI commands, so that TetherTTY can support my setup without requiring a daemon.
25. As a developer, I want session discovery to tolerate command failures, so that I can still open a plain shell if `tmux` or `herdr` is unavailable.
26. As a developer, I want `tmux` and `herdr` results normalized into one picker, so that the app feels coherent even though the tools differ.
27. As a developer, I want the session picker to always appear after connecting, so that I do not accidentally attach to the wrong session.
28. As a developer, I want the session picker to show `tmux` and `herdr` sessions separately, so that I understand the type of context I am entering.
29. As a developer, I want visible session names, so that I can choose the correct running context.
30. As a developer, I want useful session metadata where available, so that I can distinguish similar sessions.
31. As a developer, I want an empty state when no sessions are found, so that I know I can still open a shell.
32. As a developer, I want a plain shell fallback, so that TetherTTY remains useful even without running sessions.
33. As a developer, I want to attach to a selected `tmux` session, so that I can continue terminal work.
34. As a developer, I want to attach to a selected `herdr` workspace, tab, or agent, so that I can continue agent-driven work.
35. As a developer, I want a full-screen terminal, so that the limited iPhone display is used efficiently.
36. As a developer, I want a readable monospace terminal font, so that command output stays legible.
37. As a developer, I want a fixed extra-key row, so that important terminal keys are always available.
38. As a developer, I want `Esc` available in the extra-key row, so that editors and terminal tools are usable.
39. As a developer, I want `Ctrl` available in the extra-key row, so that shell shortcuts work on mobile.
40. As a developer, I want `Tab` available in the extra-key row, so that completion works without switching keyboards.
41. As a developer, I want arrow keys available in the extra-key row, so that shell history and cursor movement work.
42. As a developer, I want common shell symbols available in the extra-key row, so that typing commands is not tedious.
43. As a developer, I want copy support, so that I can reuse command output.
44. As a developer, I want paste support, so that I can send commands or tokens into the terminal when needed.
45. As a developer, I want terminal scrolling to work reliably, so that I can inspect previous output.
46. As a developer, I want a clear disconnected state, so that I do not type into a dead terminal.
47. As a developer, I want reconnect to be explicit, so that I understand when a connection was interrupted.
48. As a developer, I want reconnect to return to the session picker, so that I can safely choose the right session again.
49. As a privacy-conscious user, I want no account requirement, so that my terminal access does not depend on a hosted service.
50. As a privacy-conscious user, I want local-only storage, so that credentials and host data do not sync unexpectedly.
51. As an open-source user, I want the app to be understandable and focused, so that I can trust what it is doing.
52. As a user, I want TetherTTY to feel distinctive, so that it does not look like a generic SSH utility.
53. As a user, I want the dark-fantasy theme to stay subtle, so that terminal readability and product trust are preserved.
54. As a user, I want teal and mint highlights on important actions, so that the interface feels coherent and expressive.
55. As a user, I want dangerous and failed states to be visually distinct, so that security and connection problems are obvious.
56. As a future iPad user, I want the architecture to allow iPadOS support later, so that larger-screen workflows can be added without rewriting the app.
57. As a future Android user, I want the core product model to remain portable, so that Android can be considered after the iPhone MVP proves useful.

## Implementation Decisions

- The MVP is a native SwiftUI iPhone app.
- iPadOS-specific layouts are deferred, but the architecture should not make them difficult later.
- Android is deferred until after the iPhone MVP proves the product loop.
- The app has no backend, no account system, and no cloud sync in the MVP.
- The start screen is a host list.
- Sessions are discovered only after the user selects a host and SSH connection succeeds.
- The app always shows a session picker after connecting.
- The session picker includes `tmux`, `herdr`, and a plain shell fallback.
- `tmux` support is first-class in the MVP.
- `herdr` support is first-class in the MVP through flexible remote CLI discovery.
- Herdr discovery must not require a remote daemon for the MVP.
- Discovery commands should be configurable or internally overridable per connection.
- Session discovery normalizes remote command output into a common session model.
- The common session model should capture identity, display name, provider type, status, optional metadata, and the command needed to enter the session.
- Password authentication is the first supported authentication path.
- SSH key authentication is out of scope unless the selected SSH library or early implementation reality makes it cheap to include.
- Stored passwords are protected through local secure storage.
- The app requires Face ID or device passcode when opened.
- Host-key verification follows an OpenSSH-style trust-on-first-use model.
- First-time host keys require explicit confirmation.
- Changed host keys block the connection and show a clear warning.
- Reconnect is explicit and user-visible.
- After reconnecting, the user returns to the session picker rather than silently auto-attaching.
- The terminal UI includes a fixed extra-key row.
- Terminal readability takes priority over theme decoration.
- The visual design uses dark abyssal surfaces, teal and mint accents, restrained glow, and subtle sigil-like shapes.
- The MVP must not expand into a full SSH client.
- The core domain concepts are Connection, Credential, Known Host, Session Provider, Session, Discovery Result, and Terminal Session.

## Testing Decisions

- Tests should verify external behavior and user-visible outcomes, not implementation details.
- The highest-value test seam is the full app flow: unlock app, select host, connect, discover sessions, pick session, and open terminal.
- Session discovery should be tested using representative `tmux` output and representative `herdr` output.
- Discovery tests should cover empty results, malformed output, command failure, and mixed `tmux`/`herdr` results.
- Security tests should cover first-time host trust, known host reuse, and changed host-key blocking.
- Vault behavior should be tested from the perspective of locked and unlocked credential access.
- Connection state tests should cover connecting, authenticating, discovering, session-ready, terminal-open, disconnected, and failed states.
- Terminal tests should focus on user-visible input behavior, especially that the extra-key row sends the expected terminal control sequences.
- Reconnect tests should verify that disconnection leads to an explicit reconnect state and then returns to the session picker after reconnection.
- Visual tests should cover the locked app, host list, connection error, session picker, terminal, and disconnected state.
- Because the repository currently has no app framework or existing test suite, there is no prior test structure to reuse yet.
- Once the SwiftUI project exists, tests should be organized around the highest stable app-flow seam rather than many low-level seams.

## Out of Scope

- Android support.
- iPad-specific layouts.
- iCloud sync.
- Account system.
- Hosted backend.
- SFTP or SCP file browser.
- Port forwarding.
- Jump hosts and ProxyJump.
- SSH config import.
- SSH agent forwarding.
- Terminal session recording.
- Full terminal-state preservation across iOS backgrounding.
- Auto-attach to the last session.
- Remote daemon or bridge for Herdr.
- Full customization marketplace or theme editor.
- Push notifications.
- Multi-device credential sync.

## Further Notes

The current repository is minimal and contains only README and license material. This PRD defines the first product baseline rather than extending an existing implementation.

The existing README aligns with this direction: TetherTTY should remain small, privacy-friendly, open source, and focused on reconnecting to running terminal sessions.

The most important technical unknown is the exact Herdr command surface. The MVP avoids blocking on that by choosing flexible CLI discovery, but a stable expected output format should be defined before implementation starts.

The biggest UX risk is mobile terminal input. The extra-key row is central to making SSH usable on iPhone and should be treated as part of the core MVP.

The biggest security risk is password-first authentication. This is acceptable for the MVP only if Face ID unlock, secure local storage, and strict host-key validation are treated as core requirements rather than polish.
