# 002: Local Vault And Host Management

Labels: `ready-for-agent`

## Parent

`docs/prd/tethertty-mvp.md`

## What to build

Let the user create, view, edit, favorite, and delete saved SSH connections locally, with password-first credential storage protected by the app's vault boundary. The host list should become real: saved connections appear after creation, recently used and favorite metadata can be represented, and editing a connection updates the list.

This slice should keep the app local-only. It should not add cloud sync, account handling, SSH key import, or real SSH connection yet. The important end-to-end behavior is: unlock app, add a host with credentials, return to the host list, edit/delete/favorite it, and keep the stored password out of normal app-readable model data.

## Acceptance criteria

- [ ] A user can add a connection with alias, host address, port, username, and password.
- [ ] A saved connection appears in the host list after creation.
- [ ] A user can edit a saved connection and see the updated values in the host list/detail UI.
- [ ] A user can delete a saved connection and it is removed from the host list.
- [ ] A user can mark a connection as favorite and see that reflected in the host list.
- [ ] Password material is stored through a secure local credential boundary rather than as plain display model data.
- [ ] The app still works without accounts, backend, or sync.

## User stories covered

- 1, 2, 3, 4, 5, 6, 7, 10, 11, 12, 13, 14, 49, 50

## Blocked by

- `docs/issues/001-native-iphone-app-shell.md`
