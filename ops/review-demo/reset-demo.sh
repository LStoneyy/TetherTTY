#!/bin/bash
# /usr/local/bin/reset-demo
#
# Idempotent reset of the review user's environment: kills the tmux server
# and every process owned by the review user (including any live SSH
# session -- see below), wipes /home/review back to a clean skeleton, clears
# /tmp files owned by review, and recreates the 'build' and 'logs' demo
# tmux sessions.
#
# There is deliberately no exception for "the current SSH session's sshd
# process": a process's name (comm) is attacker-controlled (`review` could
# `cp /bin/bash /tmp/sshd` and run it so it matches a comm-based exception),
# so the only safe rule is "every process whose real UID is review's dies".
# A nightly reset therefore disconnects any active review session; that is
# an acceptable trade-off for not leaving a hole an attacker can walk through.
#
# Run at container start (by entrypoint.sh) and nightly via a Coolify
# Scheduled Task (`reset-demo`, executed as root inside the running
# container). Must never touch /etc/ssh/keys (host keys).
set -euo pipefail

log() {
  printf '[reset-demo] %s\n' "$1"
}

if [ "$(id -u)" -ne 0 ]; then
  log "ERROR: must be run as root"
  exit 1
fi

review_uid=$(id -u review)

# ---------------------------------------------------------------------------
# 1. Kill every review-owned process. This must complete before any of the
#    steps below run, so there is no window in which a review-owned process
#    is still alive while root is rewriting files review owns (no race with
#    the root-privileged cleanup that follows).
# ---------------------------------------------------------------------------
log "stopping review user's tmux server (best effort)"
su -s /bin/sh review -c 'tmux kill-server' >/dev/null 2>&1 || true

log "killing all review-owned processes"
round=1
while [ "$round" -le 5 ]; do
  remaining=0
  for pid_path in /proc/[0-9]*; do
    [ -d "$pid_path" ] || continue
    pid=${pid_path#/proc/}
    [ "$pid" = "$$" ] && continue
    # busybox's pkill mishandles -u combined with -v (it has been observed
    # to kill unrelated root-owned processes), so walk /proc by hand
    # instead. Match on real UID only -- never on comm/cmdline, which the
    # review user fully controls.
    proc_uid=$(awk '/^Uid:/{print $2; exit}' "$pid_path/status" 2>/dev/null) || continue
    [ "$proc_uid" = "$review_uid" ] || continue
    remaining=$((remaining + 1))
    kill -9 "$pid" 2>/dev/null || true
  done
  [ "$remaining" -eq 0 ] && break
  round=$((round + 1))
  sleep 0.2
done

# Fail closed: the root-privileged cleanup below is only race-free once no
# review-owned process is left. If something survived all rounds (e.g. a
# fork loop), abort instead of operating on review-controlled paths.
for pid_path in /proc/[0-9]*; do
  [ -d "$pid_path" ] || continue
  proc_uid=$(awk '/^Uid:/{print $2; exit}' "$pid_path/status" 2>/dev/null) || continue
  if [ "$proc_uid" = "$review_uid" ]; then
    log "ERROR: review-owned processes survived the kill rounds; aborting reset"
    exit 1
  fi
done

# ---------------------------------------------------------------------------
# 2. Wipe /home/review back to a clean skeleton. Never touch /etc/ssh/keys.
#    No `|| true` here: a failure must stop the script (and the "done" log
#    line below must not be reached) rather than silently leaving the demo
#    half-reset.
# ---------------------------------------------------------------------------
log "resetting /home/review"
rm -rf /home/review
mkdir -p /home/review
cp -f /opt/demo/skel/.bashrc /home/review/.bashrc
cp -f /opt/demo/skel/.tmux.conf /home/review/.tmux.conf
# Set file permissions while they are still root-owned (no extra capability
# needed), *before* chowning and locking down the directory itself. Doing it
# in this order means we never need CAP_DAC_OVERRIDE to traverse a
# review-owned 0700 directory as root.
chmod 600 /home/review/.bashrc /home/review/.tmux.conf
chown -R review:review /home/review
chmod 700 /home/review

# ---------------------------------------------------------------------------
# 3. Clear /tmp files owned by review (e.g. tmux sockets, scratch files,
#    anything review dropped there such as a copied binary). BusyBox find
#    supports `-delete`. If a review-owned directory also contains entries
#    owned by someone else, BusyBox's `-delete` can't remove that directory
#    (it isn't empty once review's own entries inside it are gone), but it
#    still deletes everything it can and exits 0 rather than aborting --
#    exactly the "handle it sensibly" behavior we want here.
# ---------------------------------------------------------------------------
log "clearing /tmp files owned by review"
find /tmp -xdev -mindepth 1 -user review -delete

# ---------------------------------------------------------------------------
# 4. Recreate the demo tmux sessions as the review user.
# ---------------------------------------------------------------------------
log "recreating 'build' and 'logs' tmux sessions"
su -s /bin/sh review -c '
  set -e
  tmux new-session -d -s build "/opt/demo/build.sh"
  tmux new-session -d -s logs "/opt/demo/logs.sh"
'

log "done"
