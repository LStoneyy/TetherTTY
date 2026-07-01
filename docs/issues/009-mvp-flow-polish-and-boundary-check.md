# 009: MVP Flow Polish And Boundary Check

Labels: `ready-for-agent`

## Parent

`docs/prd/tethertty-mvp.md`

## What to build

Polish the complete iPhone MVP flow end-to-end and verify that TetherTTY remains within the PRD boundary. The user should be able to unlock the app, manage a saved host, connect safely, confirm host trust, discover `tmux` and Herdr sessions, choose a session or plain shell, use the terminal with the extra-key row, and recover from disconnection.

This slice is not for adding new product scope. It is for making the tracer bullets cohere into a reliable MVP and ensuring out-of-scope features did not creep in.

## Acceptance criteria

- [ ] The full app flow is demoable from unlock through terminal session entry.
- [ ] The dark-fantasy visual system is applied consistently without compromising terminal readability.
- [ ] Error, warning, empty, connecting, discovering, terminal-open, and disconnected states are visually distinct.
- [ ] The app remains local-only with no account, backend, cloud sync, Android, iPad-specific layout, SFTP, port forwarding, or SSH config import scope.
- [ ] The highest-value app-flow test covers unlock, host selection, connection, discovery, session picker, and terminal opening.
- [ ] The MVP can be described accurately by the existing README and PRD without major contradictions.

## User stories covered

- 49, 50, 51, 52, 53, 54, 55, 56, 57

## Blocked by

- `docs/issues/008-explicit-reconnect-flow.md`
