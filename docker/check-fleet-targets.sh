#!/usr/bin/env bash
# Live check on a running stack (compose project from COMPOSE_PROJECT_NAME or the default): for every replicated job Prometheus
# has exactly as many targets as the stack has running replicas, and every one of them is up.
#   bash docker/check-fleet-targets.sh          # waits up to 90 s for the 15 s discovery refresh
set -euo pipefail
cd "$(dirname "$0")"
DC=(docker compose -f compose.yaml)
fail=0
for j in inference gateway engine; do
  want=$("${DC[@]}" ps --status running -q "$j" | wc -l)
  for _ in $(seq 1 18); do
    got=$("${DC[@]}" exec -T prometheus /bin/promtool query instant http://127.0.0.1:9090 "count(up{job=\"$j\"} == 1)" | awk '/=>/ {print $3}' | head -1)
    [[ ${got:-0} == "$want" ]] && break
    sleep 5
  done
  echo "$j: $want running, ${got:-0} targets up"
  [[ ${got:-0} == "$want" ]] || fail=1
done
exit $fail
