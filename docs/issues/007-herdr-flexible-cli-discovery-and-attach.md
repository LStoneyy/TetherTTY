# 007: Herdr Flexible CLI Discovery And Attach

Labels: `ready-for-agent`

## Parent

`docs/prd/tethertty-mvp.md`

## What to build

Add first-class Herdr support through flexible remote CLI discovery. For each connection, TetherTTY should be able to run a Herdr discovery command, parse the output into the same session model used by `tmux`, show Herdr workspaces/tabs/agents in the session picker, and attach or enter the selected Herdr context in the terminal.

This slice should not require a remote daemon. It should make Herdr useful in the MVP while keeping the command surface configurable enough to adapt as Herdr evolves.

## Acceptance criteria

- [ ] Herdr discovery can be configured or internally overridden per connection.
- [ ] After SSH connection succeeds, Herdr discovery runs alongside or after `tmux` discovery.
- [ ] Discovered Herdr workspaces, tabs, or agents appear in the session picker as Herdr entries.
- [ ] Herdr entries use the common session model and show visible names plus useful metadata where available.
- [ ] Selecting a Herdr entry opens the corresponding terminal context.
- [ ] Herdr discovery failure does not prevent `tmux` entries or plain shell fallback from working.
- [ ] Tests cover representative Herdr output, empty output, malformed output, and command failure.

## User stories covered

- 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 34

## Blocked by

- `docs/issues/006-tmux-session-picker-and-attach.md`
