<!--
Thanks for contributing! Please read CONTRIBUTING.md.
Do NOT use a public PR to disclose a security vulnerability — see SECURITY.md.
-->

## Summary

<!-- What does this change and why? -->

Closes #

## Type of change

- [ ] Bug fix
- [ ] New feature
- [ ] Refactor / internal
- [ ] Documentation
- [ ] CI / tooling

## Testing

- [ ] `xcodebuild test` passes locally (all tests green)
- [ ] Added or updated tests for the change (or explained why not)

## Security & quality checklist

- [ ] No `print()` of sensitive data (hostnames, usernames, key material, command output) in the app target
- [ ] Untrusted remote terminal output handled safely (clipboard / links / startup commands), if touched
- [ ] Persistence and security layers stay decoupled (e.g. `ConnectionRepository` does not reference `KnownHostStore`)
- [ ] Follows the code style and conventions in CONTRIBUTING.md
