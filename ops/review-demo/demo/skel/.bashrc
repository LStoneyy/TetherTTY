# Minimal, friendly shell for the TetherTTY App Review demo account.

[ -z "$PS1" ] && return

PS1='\[\e[1;32m\]review@tethertty-demo\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]\$ '

alias ll='ls -la'

cat <<'EOF'
Welcome to the TetherTTY App Review demo server.

This box is sandboxed (no outbound network access) and is reset nightly.
Two tmux sessions are kept running for you:
  build  - a simulated build/test log
  logs   - a simulated service log stream

Try:  tmux attach -t build
EOF
