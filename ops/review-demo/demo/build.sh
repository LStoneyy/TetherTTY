#!/bin/bash
# Fake, harmless "build/test" log for the TetherTTY App Review demo.
# Purely cosmetic: no network access, no real compilation, nothing sensitive.
set -u

steps=(
  "Resolving dependencies"
  "Fetching cached packages"
  "Compiling core module"
  "Compiling network module"
  "Compiling ui module"
  "Linking artifacts"
  "Running unit tests: auth"
  "Running unit tests: storage"
  "Running unit tests: session"
  "Running integration tests"
  "Packaging release artifact"
  "Uploading build report"
)

spinner=('|' '/' '-' '\')

# Size the divider to the pane so it never wraps on narrow (iPhone) terminals.
divider() {
  local cols
  cols=$(tput cols 2>/dev/null || echo 40)
  (( cols > 64 )) && cols=64
  printf '%*s\n' "$cols" '' | tr ' ' '-'
}

while true; do
  divider
  printf '[demo-ci] build #%s (simulated, offline)\n' "$RANDOM"
  divider

  for step in "${steps[@]}"; do
    printf '[%s] %s...' "$(date '+%H:%M:%S')" "$step"
    for i in 0 1 2 3 4 5; do
      printf '\r[%s] %s... %s' "$(date '+%H:%M:%S')" "$step" "${spinner[$((i % 4))]}"
      sleep 0.3
    done
    printf '\r[%s] %s... ok\n' "$(date '+%H:%M:%S')" "$step"
  done

  passed=$(( (RANDOM % 5) + 36 ))
  printf '\n[%s] %d/%d tests passed\n' "$(date '+%H:%M:%S')" "$passed" "$passed"
  printf '[%s] BUILD SUCCESS\n' "$(date '+%H:%M:%S')"
  printf '\nThis is demo content for TetherTTY App Review. No real build is happening.\n'
  printf 'Restarting in 8s...\n\n'
  sleep 8
done
