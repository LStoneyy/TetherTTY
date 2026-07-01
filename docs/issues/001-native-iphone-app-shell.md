# 001: Native iPhone App Shell And Abyssal Theme Baseline

Labels: `ready-for-agent`

## Parent

`docs/prd/tethertty-mvp.md`

## What to build

Create the native SwiftUI iPhone app baseline for TetherTTY with a minimal locked/unlocked app shell, host-list landing screen, and the first pass of the subtle dark-fantasy visual system. This slice should make the product direction visible without requiring real SSH yet: after launch, the app can show the future Face ID gate state, then an empty host list with clear calls to add a connection.

The visual baseline should establish abyssal dark surfaces, teal and mint highlights, restrained glow, readable typography, and distinct error/warning/action colors. The app should feel like a focused terminal companion rather than a generic SSH utility.

## Acceptance criteria

- [ ] A native SwiftUI iPhone app can be opened in the simulator or on device.
- [ ] The app has a locked/unlocked shell state, even if biometric enforcement is stubbed for this slice.
- [ ] The unlocked start screen is a host list with a useful empty state and an add-connection entry point.
- [ ] The app uses a reusable dark-fantasy theme baseline with dark surfaces, teal/mint action color, and readable text contrast.
- [ ] The shell includes user-visible states for empty, normal, warning, and error styling.
- [ ] The app does not introduce account, backend, sync, Android, or iPad-specific scope.

## User stories covered

- 10, 49, 50, 51, 52, 53, 54, 55, 56, 57

## Blocked by

None - can start immediately
