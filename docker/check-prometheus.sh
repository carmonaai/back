#!/usr/bin/env bash
# promtool in the pinned Prometheus image: the config and rules are valid and rules.test.yml passes. Needs Docker, no stack.
# `check config` only needs bearer_token_file to exist, so it gets a dummy file (the real key never leaves .env).
set -euo pipefail
cd "$(dirname "$0")"
IMG=$(sed -nE 's#^[[:space:]]*image: (prom/prometheus:[^[:space:]]+).*#\1#p' compose.yaml | head -1)
export MSYS_NO_PATHCONV=1
docker run --rm --entrypoint /bin/sh -v "$PWD/prometheus:/etc/prometheus:ro" "$IMG" -c '
  printf dummy > /tmp/engine-key
  /bin/promtool check config /etc/prometheus/prometheus.yml &&
  /bin/promtool check rules /etc/prometheus/rules.yml &&
  /bin/promtool test rules /etc/prometheus/rules.test.yml'

# The replicated services (and both engine jobs) must be scraped replica by replica: a static name is ONE target whatever the
# replica count (each scrape lands on whichever replica Docker's DNS returns), so per-replica `up` and gauges would merge.
for j in inference gateway engine vllm; do
  awk -v j="$j" '$0 ~ "job_name: "j"$" {f=1; next} /job_name:/ {f=0} f && /dns_sd_configs/ {ok=1} END {exit !ok}' prometheus/prometheus.yml     || { echo "FAIL: job $j is not scraped through dns_sd_configs (one target per replica)"; exit 1; }
done
echo "  SUCCESS: inference, gateway, engine and vllm use dns_sd_configs"
