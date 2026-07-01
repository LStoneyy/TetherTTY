# 005: OpenSSH-Style Host Key Trust

Labels: `ready-for-agent`

## Parent

`docs/prd/tethertty-mvp.md`

## What to build

Add strict host-key verification to the SSH connection path. On first connection to a host, TetherTTY should show the host fingerprint and require explicit trust before continuing. On later connections, the known fingerprint should be reused. If the host key changes, the connection must be blocked with a clear warning.

This slice should preserve the plain-terminal path while making it safe enough for password-first SSH.

## Acceptance criteria

- [ ] First-time connection to an unknown host shows the fingerprint and requires explicit confirmation.
- [ ] Confirmed host fingerprints are stored locally as known hosts.
- [ ] Reconnecting to a known host with the same fingerprint proceeds without asking again.
- [ ] A changed host key blocks the connection.
- [ ] The changed-host-key warning clearly explains the risk and does not silently allow bypass.
- [ ] Tests cover first trust, known-host reuse, and changed-host blocking behavior.

## User stories covered

- 16, 17, 18, 19, 21, 55

## Blocked by

- `docs/issues/004-ssh-connect-plain-terminal.md`
