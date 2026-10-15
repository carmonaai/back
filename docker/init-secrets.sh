#!/usr/bin/env bash
# Creates docker/secrets/internal_token (BE-24, SEC-04) when it is missing: one line "X-Internal-Token: <64 hex>", so that
# `curl -H @/run/secrets/internal_token` sends it without the value ever appearing on a command line.
# Run it once before the first `docker compose up`; it never overwrites an existing file (rotation = delete, run, restart
# billing, organization, account, auth and tools together). The value is random, stored in no repo file and shared by no other secret.
# Mode 0444 is for this local/CI harness only: the services run as uid 10001 and a compose file secret keeps the host owner and
# mode, so 0400 owned by the host user would not be readable inside the container. Production sets owner 10001 and mode 0400 (HOST-05).
set -euo pipefail
dir="$(cd "$(dirname "$0")" && pwd)/secrets"
file="$dir/internal_token"
if [ -s "$file" ]; then echo "init-secrets: $file exists, left as it is"; exit 0; fi
mkdir -p "$dir"
printf 'X-Internal-Token: %s\n' "$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')" > "$file"
chmod 0444 "$file"
echo "init-secrets: created $file"
