FROM alpine:3.22

# Minimal package set (Alpine 3.22 branch; package versions are not
# pinned). No compilers or package managers are left reachable by the
# "review" user (apk itself is only usable by root, and root login over SSH
# is disabled; see sshd_config and entrypoint.sh).
RUN apk add --no-cache \
      openssh-server \
      tmux \
      bash \
      iptables \
      ip6tables \
      tini \
      util-linux \
      ncurses-terminfo-base \
    && rm -rf /var/cache/apk/*

# One unprivileged user for the App Review demo. No sudo, no extra groups.
RUN addgroup -S review \
    && adduser -S -D -h /home/review -s /bin/bash -G review review \
    && passwd -l root

# Defense in depth: strip every setuid/setgid bit in the image. sshd runs
# as root (PermitRootLogin is handled by sshd_config, not by a setuid
# helper) and reads /etc/shadow directly as root, so it needs none of
# these bits at runtime; removing them closes off a class of
# privilege-escalation primitives even if something else in the image
# turns out to rely on a bug rather than a setuid binary.
RUN find / -xdev -type f -perm /6000 -exec chmod a-s {} +

# Host keys live on a named volume (mounted at /etc/ssh/keys by compose) so
# they survive rebuilds/redeploys; entrypoint.sh generates them on first run.
RUN mkdir -p /etc/ssh/keys /opt/demo \
    && chown root:root /etc/ssh/keys /opt/demo \
    && chmod 700 /etc/ssh/keys \
    && chmod 755 /opt/demo

COPY sshd_config /etc/ssh/sshd_config
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY reset-demo.sh /usr/local/bin/reset-demo
COPY demo/ /opt/demo/

RUN chmod 755 /usr/local/bin/entrypoint.sh /usr/local/bin/reset-demo \
    && chmod 755 /opt/demo/*.sh \
    && chown -R root:root /opt/demo \
    && echo "This is the TetherTTY App Review demo server. Sandboxed. Reset nightly." > /etc/motd

# Validate sshd_config at build time. sshd -t refuses to run with no host
# keys present, so generate throwaway keys just for the check, then remove
# them again: the real keys are generated at container start into the
# /etc/ssh/keys volume (see entrypoint.sh) so they can persist across
# rebuilds/redeploys.
RUN ssh-keygen -q -t ed25519 -N '' -f /etc/ssh/keys/ssh_host_ed25519_key \
    && ssh-keygen -q -t ecdsa -b 256 -N '' -f /etc/ssh/keys/ssh_host_ecdsa_key \
    && sshd -t \
    && rm -f /etc/ssh/keys/ssh_host_ed25519_key /etc/ssh/keys/ssh_host_ed25519_key.pub \
             /etc/ssh/keys/ssh_host_ecdsa_key /etc/ssh/keys/ssh_host_ecdsa_key.pub

EXPOSE 2222

ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/entrypoint.sh"]
