# App Store Connect listing — TetherTTY 1.0.0

Copy-paste source for App Store Connect. Character limits noted in brackets.
Language: English (U.S.) as primary localization.

## App information

| Field | Value |
| --- | --- |
| Name [30] | `TetherTTY - SSH` |
| Subtitle [30] | `Reattach to tmux & herdr` |
| Bundle ID | `info.webcommits.tethertty` |
| SKU | `tethertty-ios` |
| Primary category | Developer Tools |
| Secondary category | Utilities |
| Content rights | Does not contain, show, or access third-party content |
| Age rating | Answer "None"/"No" to every question → 4+ (no in-app web browser: links open in Safari) |
| Copyright | `2026 webCommits web Designs` |

## URLs

| Field | Value |
| --- | --- |
| Privacy Policy URL | https://tethertty.webcommits.info/privacy/ |
| Support URL | https://tethertty.webcommits.info/support/ |
| Marketing URL | https://tethertty.webcommits.info/ |

## Pricing and availability

- Price: Free (Tier 0)
- Availability: all countries/regions **except France** (encryption declaration not filed)
- Devices: iPhone and iPad. Uncheck "Make available on Apple Silicon Mac" and "Apple Vision Pro" unless tested.

## App Privacy

- Data collection: **"No, we do not collect data from this app."** → label "Data Not Collected"
- Privacy Policy URL as above

## Export compliance (per build, or answered once via `ITSAppUsesNonExemptEncryption = YES`)

1. Does your app use encryption? **Yes**
2. Does it qualify for any of the exemptions (e.g. only Apple OS encryption)? **No**. SSH crypto comes from swift-crypto/BoringSSL, not iOS.
3. Does it implement proprietary or non-standard encryption algorithms? **No**
4. Does it implement standard encryption algorithms instead of, or in addition to, Apple's OS encryption? **Yes**
5. Is it going to be available in France? **No**, excluded in availability.

Mass-market classification 5D992.c (EAR §740.17(b)(1)). No annual self-classification report is required for mass-market items since the March 2021 EAR change.

## Promotional text [170]

```
Lock your phone mid-build, come back, and you're still in the same tmux session. TetherTTY reconnects and reattaches for you — direct SSH, no account, no backend.
```

## Description [4000]

```
TetherTTY is a small, focused SSH client for one job: getting you back into the terminal sessions already running on your own machine.

Open the app, pick a host, and TetherTTY lists the tmux and herdr sessions on that server. Tap one and you're attached. Lock your phone, switch apps, come back later — TetherTTY silently reconnects and reattaches to the same session, so a long build or a running agent is right where you left it.

DIRECT SSH, NOTHING IN BETWEEN
• Real SSH connections straight from your iPhone or iPad to your server. No relay, no cloud, no account.
• Password authentication, stored in the iOS Keychain.
• Trust-on-first-use host keys: SHA256 fingerprints are pinned, and a changed key is refused, not silently accepted.

MADE FOR TMUX AND HERDR
• Automatic session discovery on the server.
• One tap to attach, or open a plain shell.
• Seamless reattach after the app was in the background.

A REAL TERMINAL
• Full xterm-256color emulation.
• Keyboard accessory row for Esc, Ctrl, Tab, arrows and more.
• Optional "keep screen awake" while you watch output.

PRIVATE BY DESIGN
• Face ID / passcode app lock, with a privacy cover in the app switcher and re-lock after 5 minutes in the background.
• No analytics, no tracking, no ads. Your connections never leave your device.
• Remote output is treated as untrusted: no clipboard writes from the server, links only open over https after you tap them.

OPEN SOURCE
TetherTTY is open source under the Apache 2.0 license. Read the code, the security audit, or contribute on GitHub.

TetherTTY is not a replacement for a full-featured SSH suite. It is a quiet tether back to the terminal you already live in.
```

## Keywords [100 bytes, comma-separated, no spaces]

```
terminal,shell,server,remote,console,devops,sysadmin,xterm,session,linux,client,reconnect,cli
```

Words already in the name or subtitle (`TetherTTY`, `SSH`, `tmux`, `herdr`) are indexed by App Store search and must not be repeated here. `mosh` is deliberately omitted: TetherTTY does not speak mosh.

## App Review Information

- Sign-in required: **Yes**
- User name: `review`
- Password: the value of `REVIEW_PASSWORD` set in Coolify (never commit it)
- Contact: Lukas Schaffrath, webcommitswebdesigns@gmail.com, +49 1520 7282881

Notes:

```
TetherTTY is an SSH client. To test it, please use our sandboxed demo server:

Host: tethertty-demo.webcommits.info
Port: 2222
Username: review
Password: (see the Sign-In Information fields)

Steps:
1. Launch the app and unlock with Face ID or the device passcode (the app lock uses the device owner authentication; on a device without Face ID the passcode is used).
2. Tap "+" (Add Connection) to add a connection and enter the host, port, username and password above. Save.
3. Tap the connection. On first connect the app shows the server's SSH host key fingerprint; tap "Trust" (expected: SHA256:DxIPalOmuDNSu6pw50aoqY9HITxe0ufjakl2LtxWEVk=).
4. The session picker lists the tmux sessions "build" and "logs" under "Tmux Sessions". Tap "build" to attach — you will see a simulated build log. herdr is intentionally not installed, so the app shows a neutral "herdr isn't installed on this host" note.
5. Optional: send the app to the background and return; the app reconnects and reattaches to the same session automatically.

The demo server is isolated (no outbound network access) and reset nightly. The app has no backend, accounts or in-app purchases; it only connects to SSH servers the user enters.
```

## Screenshots

Required sizes (portrait):

| Display | Device to capture on | Pixels |
| --- | --- | --- |
| iPhone 6.9" | iPhone 18 Pro Max simulator (or any 6.9" device) | 1320 × 2868 |
| iPad 13" | iPad Pro 13-inch (M5) simulator | 2064 × 2752 |

Suggested set, 3 to 5 each, connected to the demo server:

1. Host list ("The Loom") with one or two connections
2. Session picker showing `build` / `logs`
3. Terminal attached to `build` with the keyboard accessory row
4. Host-key trust prompt with the fingerprint
5. Unlock screen (sigil)

Do not show real hostnames, usernames or IPs of private machines. Use the demo server only.
