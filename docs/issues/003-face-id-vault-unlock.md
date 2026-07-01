# 003: Face ID Vault Unlock

Labels: `ready-for-agent`

## Parent

`docs/prd/tethertty-mvp.md`

## What to build

Turn the vault boundary into a real app-opening unlock flow. When TetherTTY opens, protected host credential access should require Face ID or device passcode. After successful unlock, the host list becomes available. If biometric authentication fails or is unavailable, the app should present a clear fallback/error path rather than exposing credentials.

This slice should make credential protection user-visible without changing the local-only product model.

## Acceptance criteria

- [ ] Opening the app requires Face ID or device passcode before protected connection data is usable.
- [ ] Successful unlock leads to the host list.
- [ ] Failed or canceled unlock keeps protected data inaccessible and shows a clear state.
- [ ] Device passcode fallback is supported when available through the platform.
- [ ] The app does not expose stored passwords in UI, logs, or debug-facing model output.
- [ ] Tests cover locked and unlocked credential-access behavior from the user's perspective.

## User stories covered

- 7, 8, 9, 49, 50, 51

## Blocked by

- `docs/issues/002-local-vault-host-management.md`
