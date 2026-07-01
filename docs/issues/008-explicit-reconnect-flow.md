# 008: Explicit Reconnect Flow

Labels: `ready-for-agent`

## Parent

`docs/prd/tethertty-mvp.md`

## What to build

Add the MVP reconnect behavior for interrupted terminal sessions. When the SSH connection drops or the app returns from a state where the connection is no longer usable, TetherTTY should show a clear disconnected state. The user can explicitly reconnect to the host; after reconnecting, TetherTTY returns to the session picker rather than silently auto-attaching.

This slice keeps reconnection robust and transparent instead of attempting full terminal-state preservation.

## Acceptance criteria

- [ ] A dropped or unusable SSH connection moves the terminal to a clear disconnected state.
- [ ] The disconnected state explains that terminal input is no longer live.
- [ ] The user can explicitly reconnect from the disconnected state.
- [ ] After reconnecting, the app runs discovery again and returns to the session picker.
- [ ] The app does not silently auto-attach to the previous session in the MVP.
- [ ] Tests cover disconnect, explicit reconnect, rediscovery, and return to the session picker.

## User stories covered

- 46, 47, 48, 21

## Blocked by

- `docs/issues/007-herdr-flexible-cli-discovery-and-attach.md`
