# TetherTTY App Review demo server

## Purpose

A small, throwaway SSH server for Apple App Review to test the TetherTTY iOS
SSH client against. It is not a real production system: it exists only so a
reviewer can log in with a password, see TetherTTY discover tmux sessions,
and attach to one. There is nothing sensitive on the box and nothing it talks
to.

## Security model

- **Password-only auth, one user.** `review`, no sudo, no pubkey/keyboard-
  interactive auth, no root login, no sftp subsystem. `MaxAuthTries 3`,
  `LoginGraceTime 20`, `PerSourcePenalties yes` throttle brute forcing.
- **No forwarding.** `DisableForwarding yes` plus explicit
  `AllowTcpForwarding/AllowStreamLocalForwarding/AllowAgentForwarding/
  X11Forwarding/PermitTunnel/GatewayPorts no`. A client requesting `-L`/`-R`
  gets a local listener that always fails ("administratively prohibited")
  the moment it's used; nothing ever actually forwards.
- **Fail-closed firewall, applied before anything review-owned starts.**
  Before `reset-demo` creates the review user's first tmux session (and
  before `sshd` starts), `entrypoint.sh` sets the container's `OUTPUT`
  chain to policy `DROP`, allowing only loopback and `ESTABLISHED/RELATED`
  replies -- this blocks all new outbound connections, including DNS, from
  anything running in the container, including a reviewer's shell. `INPUT`
  is also set to policy `DROP`, allowing only loopback, `ESTABLISHED/
  RELATED` traffic, and new inbound TCP to port 2222 (the sshd port, which
  Docker's published-port DNAT delivers inbound connections to). Both
  policies are applied for iptables and ip6tables. Nothing runs before the
  firewall is in place, so there is no window during container start in
  which a review-owned process could run unrestricted.
- **The firewall can't be undone from an SSH session.** After the rules are
  applied, `entrypoint.sh` runs
  `setpriv --bounding-set -net_admin -- sshd -D -e`, which permanently
  removes `CAP_NET_ADMIN` from the bounding set of `sshd` and everything it
  forks (including a reviewer's shell). No process reachable via SSH, even
  as `review`, can re-run `iptables` with effect. (`docker exec` as root
  *can* undo this — see Acceptance tests #7 for exactly what that does and
  does not prove.)
- **Tight resource limits.** `cap_drop: [ALL]` plus a short, justified
  `cap_add` list (below); `no-new-privileges:true`; `mem_limit: 256m`;
  `cpus: 0.5`; `pids_limit: 128`; bounded JSON logging.
- **No setuid/setgid binaries anywhere in the image.** The `Dockerfile`
  strips every setuid/setgid bit (`find / -xdev -type f -perm /6000 -exec
  chmod a-s {} +`) after packages and the `review` user are set up, as
  defense in depth. `sshd` runs as root and reads `/etc/shadow` directly,
  so it needs none of these bits at runtime.
- **Nightly reset kills every `review`-owned process, with no exceptions.**
  A Coolify Scheduled Task runs `reset-demo` inside the container once a
  day: it kills the `review` user's tmux server and then *every* process
  whose real UID is `review`'s (repeating the kill pass a few times to
  catch forks), wipes `/home/review` back to a clean skeleton, clears
  `/tmp` files owned by `review`, and recreates the `build`/`logs` tmux
  sessions. There is deliberately no exception for "the process backing a
  live SSH session": a process's name (`comm`) is attacker-controlled (a
  reviewer could `cp /bin/bash /tmp/sshd` and run it to dodge a
  name-based exception), so the only safe rule is "every process owned by
  `review` dies". **A nightly reset therefore disconnects any active
  review session** -- an acceptable trade-off for not leaving that hole
  open. Because the kill step completes before any of the root-privileged
  file cleanup runs, there is no race in which a surviving `review`
  process could interfere with (or be the target of a TOCTOU race against)
  that cleanup. `reset-demo` never touches `/etc/ssh/keys` and now runs
  under `set -euo pipefail`: the home-directory reset and session-recreate
  steps fail the whole script (non-zero exit, no trailing "done" log line)
  if they don't succeed, rather than silently leaving a half-reset demo.
- **herdr is intentionally absent.** TetherTTY's `herdr` probe should show
  its neutral "not installed" state.
- **Nothing sensitive is on the box.** The only persistent state is the SSH
  host key pair (public by design) and ephemeral demo content regenerated
  every reset.

### Final `cap_add` set and why

`cap_drop: [ALL]` first, then only:

| Capability | Why |
|---|---|
| `NET_ADMIN` | `entrypoint.sh` needs it to apply the `iptables`/`ip6tables` egress rules. It is then dropped from the bounding set before `sshd` ever starts (see above), so it is not available to SSH sessions. |
| `SETUID`, `SETGID` | `sshd` privilege separation and setuid/setgid to `review` on login. |
| `SYS_CHROOT` | `sshd`'s privilege-separation (pre-auth) sandbox uses a chroot internally. |
| `CHOWN` | `chpasswd` updates `/etc/shadow`; `reset-demo` chowns the rebuilt `/home/review` to `review:review`. |
| `FOWNER` | `reset-demo`/`entrypoint.sh` `chmod`/`chown` files whose owner is not the acting (root) process — e.g. locking `/home/review` down to `0700` after chowning it to `review`. |
| `DAC_OVERRIDE` | **Empirically required**, not just "expected": a *first* reset against a freshly-created, root-owned `/home/review` works without it, but every *subsequent* (idempotent/nightly) run must read, write, and unlink inside the now `review`-owned, mode-`0700` `/home/review` left by the previous reset — which root cannot do without this capability. Verified by removing it and watching the second `reset-demo` run fail with `Permission denied` on `cp`/`chmod`/`chown` inside that directory, then confirmed clean (no errors, two consecutive idempotent runs, login still works) once it was restored. |
| `AUDIT_WRITE` | PAM/login audit records written by `sshd` on each login. |
| `KILL` | `reset-demo` (running as root) sends `SIGKILL` to processes owned by the `review` uid, a different uid than the signaling process; this needs `CAP_KILL`. |

`SYS_CHROOT` wasn't separately re-verified by removal (sshd's build-time
`sshd -t` plus live logins never showed a `SYS_CHROOT`-related failure, and
it is OpenSSH's documented requirement for its privsep sandbox), but every
other capability in this list was confirmed necessary by removing it and
observing a concrete failure, then restoring it.

`read_only: true` on the root filesystem was deliberately **not** set:
`chpasswd` needs a writable `/etc` (shadow/passwd), and `reset-demo` rewrites
`/home/review` and clears files under `/tmp` in place. Everything else the
container needs persisted (the host keys) already lives on its own named
volume, so the trade-off is narrow and limited to `/etc`, `/home`, and
`/tmp`. `tmpfs` is used for `/run` and `/var/run`, which is harmless.

## Coolify setup steps

1. **New Resource → Docker Compose**, from the public GitHub repo
   `https://github.com/LStoneyy/TetherTTY`, branch `main`.
2. **Base Directory**: `/ops/review-demo`. **Compose file**: `docker-compose.yml`.
3. **No domain** — this is plain TCP SSH, not HTTP, so it is not routed
   through Coolify's reverse proxy. The compose file's `ports: ["2222:2222"]`
   publishes it directly on the host.
4. Do **NOT** enable "Connect to Predefined Network" (no reason for this
   service to share a network with other apps on the box).
5. Set `REVIEW_PASSWORD` as a **locked/secret** environment variable (16+
   characters). Coolify will show it as required because of the compose
   file's `${REVIEW_PASSWORD:?REVIEW_PASSWORD must be set}`.
6. **Watch Paths**: `ops/review-demo/**`, so unrelated changes elsewhere in
   the repo don't trigger a redeploy of this service.
7. **Scheduled Task**: command `reset-demo`, cron `0 4 * * *`, container/
   service `review-demo`.

## Host firewall / DNS

- DNS: an A record for `tethertty-demo.webcommits.info` pointing at the VPS.
- The hosting provider's firewall must allow inbound TCP on port **2222**
  (in addition to whatever it already allows for Coolify/HTTP).

## Post-deploy checklist

After every deploy to the VPS (not just locally):

- [ ] `docker inspect` the running `review-demo` container and confirm
      `HostConfig.Memory` = `268435456`, `NanoCpus` = `500000000`,
      `PidsLimit` = `128`, and `CapAdd`/`CapDrop`/`SecurityOpt` match
      `docker-compose.yml` (see Acceptance test #13).
- [ ] Re-run the egress acceptance test (#6 below) against the real host
      (`tethertty-demo.webcommits.info:2222`, not `127.0.0.1`), since Coolify
      and the hosting provider's own networking are not exercised by a
      local `docker compose up`.

## Acceptance tests

All of these were run locally against `docker compose` before writing this
README. Commands below assume a shell variable
`REVIEW_PASSWORD` set to a throwaway value, e.g.:

```sh
export REVIEW_PASSWORD=$(openssl rand -base64 24)
```

Never write this value to a file.

1. `docker compose build` — succeeds; `sshd -t` (run at build time against
   throwaway host keys that are deleted immediately after) passes;
   `find / -xdev -perm /6000 -type f` inside the built image prints nothing
   (no setuid/setgid binaries survive the Dockerfile's stripping step).
2. `docker compose up -d` — starts; becomes `healthy`; logs show both host
   key SHA256 fingerprints and never the password.
3. The healthcheck (a raw TCP connect to `127.0.0.1:2222`) passes.
4. `ssh -p 2222 review@127.0.0.1` with the password succeeds;
   `tmux list-sessions` shows `build` and `logs`; `ssh ... -t tmux attach -t
   build` attaches and renders the simulated build log.
5. `ssh -N -L 9999:127.0.0.1:2222 ...`: the client still binds its local
   listening socket (normal, client-side-only behavior), but any actual use
   of it is rejected by the server as soon as it's attempted —
   client: `channel 2: open failed: administratively prohibited`;
   server log: `refused local port forward: originator ... target ...`.
6. From an authenticated shell: `which herdr` → not found (exit 1, as
   intended); `bash -c 'exec 3<>/dev/tcp/1.1.1.1/443'` hangs and is killed by
   a client-side timeout rather than completing — the `OUTPUT DROP` policy
   silently drops the SYN, it never gets a response. This egress test must
   be re-run after every deploy against the real VPS host (not just
   locally), since the local Docker network path doesn't prove the
   production host's network/NAT setup doesn't leak traffic some other way.
7. `docker compose exec review-demo iptables -S` (as root) shows both the
   `INPUT` and `OUTPUT` chain policies as `DROP`, plus the `lo`/
   `ESTABLISHED,RELATED`/`tcp dpt:2222` allow rules on `INPUT` and the
   `lo`/`ESTABLISHED,RELATED` allow rules on `OUTPUT`.
8. `docker compose exec review-demo iptables -P OUTPUT ACCEPT` **succeeds**
   as root (exit 0) and visibly flips the policy. This is expected and does
   **not** indicate the egress block is broken: `docker exec` spawns a new
   process with the container's own configured capability set (our
   `cap_add` list, which includes `NET_ADMIN` for `entrypoint.sh`'s own use)
   — it is not constrained by the bounding-set drop that happens only to
   `sshd` and its descendants after the firewall is applied. The property
   that actually matters — that an SSH session, including one as `review`,
   cannot re-enable egress — holds: `review` is never root and has no path
   to `iptables`/`CAP_NET_ADMIN`, and even root reached via `sshd` (which
   doesn't happen anyway, since `PermitRootLogin no`) would lack
   `CAP_NET_ADMIN` in its bounding set. (The test script restores
   `OUTPUT DROP` immediately after checking this.)
9. Root login (`ssh ... root@127.0.0.1`) is rejected
   (`Permission denied (password)`); a wrong password is rejected the same
   way; after `MaxAuthTries` (3) bad passwords the server disconnects with
   `Too many authentication failures`.
10. `docker compose down` (without `-v`), rebuild, `up` — the ed25519/ecdsa
    SHA256 fingerprints in the logs are byte-for-byte identical to before,
    confirming the volume-backed host keys survive rebuilds/redeploys.
11. `docker compose exec review-demo reset-demo` — runs cleanly and
    idempotently (verified across multiple consecutive runs, including
    against an already-reset, locked-down `/home/review`); the `build`/
    `logs` tmux sessions come back with fresh timestamps. As a hostile-input
    check: over SSH as `review`, run `cp /bin/bash /tmp/sshd; nohup
    /tmp/sshd -c 'sleep 10000' &` to simulate a reviewer trying to survive a
    reset by disguising a process as `sshd`, then run `reset-demo` again —
    it exits 0, `/tmp/sshd` is gone, no process with uid `review` survives
    except the freshly recreated `build`/`logs` tmux sessions and their
    children, and the SSH session used to set this up is itself
    disconnected (there is no comm-based exception for it; see "Nightly
    reset" above).
12. Omitting `REVIEW_PASSWORD` entirely makes `docker compose` itself refuse
    to start the service (`required variable REVIEW_PASSWORD is missing a
    value`). Setting it to fewer than 16 characters lets the container start
    but `entrypoint.sh` fails fast with a clear message
    (`REVIEW_PASSWORD is too short (must be at least 16 characters).
    Refusing to start.`) and the container restart-loops without ever
    starting `sshd` or leaking the value.
13. On the VPS after a real deploy, `docker inspect` on the running
    container confirms the resource/isolation settings actually took
    effect: `HostConfig.Memory` is `268435456` (256 MiB), `NanoCpus` is
    `500000000` (0.5 CPU), `PidsLimit` is `128`, and `CapAdd`/`CapDrop`/
    `SecurityOpt` match `docker-compose.yml` (`CapDrop: ["ALL"]`, the
    `cap_add` list above, `SecurityOpt: ["no-new-privileges:true"]`).

## App Review notes template

Use this (adjusted as needed) in App Store Connect's review notes:

```
This app requires an SSH server to connect to. We've set up a sandboxed demo
server for review purposes:

Host:     tethertty-demo.webcommits.info
Port:     2222
Username: review
Password: <set in Coolify>

Steps:
1. Unlock the device (Face ID / passcode) if prompted by the app.
2. In TetherTTY, add a new connection with the host/port/username/password
   above.
3. On first connect, TetherTTY will show the server's host key fingerprint
   (TOFU pinning) — trust it to continue.
4. TetherTTY will discover two tmux sessions, "build" and "logs". Pick
   "build" to attach to a simulated build/test log.

This server has no outbound network access and is reset automatically every
night, so it's safe to explore freely.
```

### Fingerprint rotation note

The host key fingerprint TetherTTY pins is derived from the keys stored on
the `review-demo-host-keys` named volume. If that volume is ever deleted
(e.g. `docker compose down -v`, or removing/recreating the Coolify
resource's volume), new host keys are generated on next start and the
fingerprint changes — any reviewer (or anyone) who already pinned the old
one will see a "host key changed" warning on their next connection and will
need to re-trust the new fingerprint.
