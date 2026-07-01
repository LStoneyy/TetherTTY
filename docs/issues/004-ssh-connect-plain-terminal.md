# 004: SSH Connect To Plain Terminal

Labels: `ready-for-agent`

## Parent

`docs/prd/tethertty-mvp.md`

## What to build

Provide the first real SSH tracer bullet: select a saved host, connect with the stored password, and open a plain interactive terminal. This slice proves the core product path before session discovery is added. The user should see clear connection states for connecting, authenticating, terminal-open, disconnected, and failed.

The terminal should be full-screen, readable, scrollable enough for basic output, and include the fixed extra-key row for common terminal input.

## Acceptance criteria

- [ ] A user can select a saved host and start an SSH connection using the stored username/password.
- [ ] The UI shows clear connecting, authenticating, terminal-open, disconnected, and failed states.
- [ ] Successful connection opens a full-screen plain shell terminal.
- [ ] The terminal uses a readable monospace presentation.
- [ ] The terminal supports basic input, output, scrolling, copy, and paste.
- [ ] The terminal includes an extra-key row with `Esc`, `Ctrl`, `Tab`, arrow keys, and common shell symbols.
- [ ] Connection failures show understandable user-facing errors.

## User stories covered

- 15, 20, 21, 32, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45

## Blocked by

- `docs/issues/003-face-id-vault-unlock.md`
