#!/bin/bash
# Fake, harmless service log stream for the TetherTTY App Review demo.
# Purely cosmetic: no network access, no real services, nothing sensitive.
set -u

services=(api worker scheduler cache gateway)
levels=(INFO INFO INFO INFO WARN DEBUG)
messages=(
  "request handled"
  "health check ok"
  "cache hit"
  "cache miss, refetching"
  "background job finished"
  "connection pool at %d%% capacity"
  "queued %d jobs"
  "heartbeat"
  "rotating local log file"
  "no-op: nothing to reconcile"
)

while true; do
  svc=${services[$((RANDOM % ${#services[@]}))]}
  lvl=${levels[$((RANDOM % ${#levels[@]}))]}
  msg=${messages[$((RANDOM % ${#messages[@]}))]}

  if [[ "$msg" == *%d* ]]; then
    msg=$(printf "$msg" "$((RANDOM % 100))")
  fi

  printf '%s %-5s %-10s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$lvl" "$svc" "$msg"
  sleep "0.$((RANDOM % 8 + 2))"
done
