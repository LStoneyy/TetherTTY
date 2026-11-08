#!/bin/bash
# Entrypoint for the TetherTTY App Review demo server.
#
# - Validates REVIEW_PASSWORD and sets it (never logged/echoed).
# - Generates stable host keys on first run (persisted on a volume).
# - Applies a fail-closed firewall (iptables/ip6tables): OUTPUT DROP (egress)
#   and INPUT DROP except lo/established/tcp-2222, before anything
#   review-owned starts.
# - Drops CAP_NET_ADMIN from the bounding set so a shell on the box cannot
#   undo the firewall, then execs sshd in the foreground.
#
# Intentionally no `set -x` anywhere in this script or any script it calls.
set -euo pipefail

log() {
  printf '[entrypoint] %s\n' "$1"
}

fail() {
  printf '[entrypoint] ERROR: %s\n' "$1" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# 1. Password
# ---------------------------------------------------------------------------
if [ -z "${REVIEW_PASSWORD:-}" ]; then
  fail "REVIEW_PASSWORD is not set. Refusing to start. Set REVIEW_PASSWORD in the environment (e.g. as a Coolify secret variable)."
fi

if [ "${#REVIEW_PASSWORD}" -lt 16 ]; then
  fail "REVIEW_PASSWORD is too short (must be at least 16 characters). Refusing to start."
fi

# chpasswd reads "user:password" from stdin; the value never touches argv,
# logs, or disk beyond the shadow database.
printf 'review:%s\n' "$REVIEW_PASSWORD" | chpasswd
unset REVIEW_PASSWORD
log "password set for user 'review'"

# ---------------------------------------------------------------------------
# 2. Host keys (persisted on the /etc/ssh/keys volume)
# ---------------------------------------------------------------------------
mkdir -p /etc/ssh/keys
chmod 700 /etc/ssh/keys

if [ ! -f /etc/ssh/keys/ssh_host_ed25519_key ]; then
  log "generating ed25519 host key"
  ssh-keygen -q -t ed25519 -N '' -f /etc/ssh/keys/ssh_host_ed25519_key
fi

if [ ! -f /etc/ssh/keys/ssh_host_ecdsa_key ]; then
  log "generating ecdsa (p256) host key"
  ssh-keygen -q -t ecdsa -b 256 -N '' -f /etc/ssh/keys/ssh_host_ecdsa_key
fi

chmod 600 /etc/ssh/keys/ssh_host_ed25519_key /etc/ssh/keys/ssh_host_ecdsa_key
chmod 644 /etc/ssh/keys/ssh_host_ed25519_key.pub /etc/ssh/keys/ssh_host_ecdsa_key.pub

log "host key fingerprints (public, safe to log):"
ssh-keygen -lf /etc/ssh/keys/ssh_host_ed25519_key.pub
ssh-keygen -lf /etc/ssh/keys/ssh_host_ecdsa_key.pub

# ---------------------------------------------------------------------------
# 3. Fail-closed firewall -- applied before anything review-owned starts
#
# This must run before reset-demo (step 4 below) creates the review user's
# tmux sessions: nothing before this point needs network access, so there is
# no window in which a review-owned process can run before the firewall is
# in place.
#
# OUTPUT policy: DROP all new outbound connections (including DNS), but
# still allow loopback and established/related traffic so SSH replies flow.
# INPUT policy: DROP everything except loopback, established/related
# traffic, and new inbound TCP to port 2222 (the sshd port). Docker's
# published-port DNAT (`ports: ["2222:2222"]` in docker-compose.yml)
# delivers inbound connections to the container on port 2222, so this rule
# is required to keep logins working.
# ---------------------------------------------------------------------------
log "applying firewall (iptables)"
iptables -F OUTPUT
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -P OUTPUT DROP

iptables -F INPUT
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p tcp --dport 2222 -j ACCEPT
iptables -P INPUT DROP
log "iptables policy applied: OUTPUT DROP / INPUT DROP, lo + ESTABLISHED/RELATED allowed, INPUT also allows tcp/2222"

# IPv6: best-effort. If ip6tables cannot run (e.g. no ip6 support in the
# kernel/netns), only continue when the container has no routable (non
# link-local, non-loopback) IPv6 address -- in that case there is nothing to
# protect. Otherwise this is a real gap and we must not start.
v6_ok=1
if ! ip6tables -F OUTPUT 2>/dev/null; then
  v6_ok=0
fi

if [ "$v6_ok" -eq 1 ]; then
  ip6tables -A OUTPUT -o lo -j ACCEPT
  ip6tables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  ip6tables -P OUTPUT DROP

  ip6tables -F INPUT
  ip6tables -A INPUT -i lo -j ACCEPT
  ip6tables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  ip6tables -A INPUT -p tcp --dport 2222 -j ACCEPT
  ip6tables -P INPUT DROP
  log "ip6tables policy applied: OUTPUT DROP / INPUT DROP, lo + ESTABLISHED/RELATED allowed, INPUT also allows tcp/2222"
else
  log "ip6tables unavailable; checking for routable IPv6 addresses"
  routable_v6=$(ip -6 addr show scope global 2>/dev/null | grep -c 'inet6' || true)
  if [ "${routable_v6:-0}" -gt 0 ]; then
    fail "ip6tables failed to apply and a routable IPv6 address is present; refusing to start with an unprotected firewall."
  fi
  log "no routable IPv6 address present; continuing without ip6tables"
fi

# ---------------------------------------------------------------------------
# 4. Demo content (tmux sessions for the 'review' user)
# ---------------------------------------------------------------------------
/usr/local/bin/reset-demo

# ---------------------------------------------------------------------------
# 5. Drop CAP_NET_ADMIN from the bounding set, then exec sshd
#
# Once the firewall is in place, no process started from here on (including
# anything a reviewer's SSH session execs) can re-acquire CAP_NET_ADMIN, even
# as root, because it is removed from the bounding set for this process tree.
# ---------------------------------------------------------------------------
log "dropping CAP_NET_ADMIN from the bounding set"
exec setpriv --bounding-set -net_admin -- /usr/sbin/sshd -D -e
