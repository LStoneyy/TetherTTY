# 006: Tmux Session Picker And Attach

Labels: `ready-for-agent`

## Parent

`docs/prd/tethertty-mvp.md`

## What to build

Add `tmux` discovery after a successful SSH connection and route the user through the explicit session picker before terminal entry. TetherTTY should run a remote `tmux` discovery command, parse available sessions into the common session model, show them in the picker, and attach the selected session in the terminal. If no sessions are found or discovery fails, the user should still be able to open a plain shell.

This slice proves the primary TetherTTY value loop for existing terminal sessions.

## Acceptance criteria

- [ ] After SSH connection succeeds, the app runs `tmux` session discovery before opening the terminal.
- [ ] Discovered `tmux` sessions appear in the session picker with visible names and useful metadata where available.
- [ ] The session picker always appears before terminal entry.
- [ ] Selecting a `tmux` session attaches that session in the terminal.
- [ ] If no `tmux` sessions are found, the picker shows a useful empty state and offers plain shell fallback.
- [ ] If `tmux` discovery fails, the user can still open a plain shell.
- [ ] Tests cover representative `tmux` output, empty output, malformed output, and command failure.

## User stories covered

- 22, 25, 26, 27, 28, 29, 30, 31, 32, 33

## Blocked by

- `docs/issues/005-openssh-style-host-key-trust.md`
