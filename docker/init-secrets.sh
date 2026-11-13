#!/usr/bin/env bash
# Makes the two secret files of the stack when they are missing, each on its own: a file that exists is never overwritten, and one that exists never
# keeps the other from being made (rotation = delete the file, run this, restart the services that hold it).
#   secrets/internal_token (BE-24, SEC-04): one line "X-Internal-Token: <64 hex>", so that `curl -H @/run/secrets/internal_token` sends it without the
#     value ever appearing on a command line. Held by billing, organization, account, auth, model, inference and tools.
#   secrets/model_key: one line of 64 hex characters, the data key model-service seals the engine keys of registered models with (AES-256-GCM). Held by
#     model only. Losing it loses every stored key: the models must be registered again, and a database restored without it holds keys nobody can open.
# Run it once before the first `docker compose up`. The values are random, stored in no repo file and shared by no other secret.
# Mode 0444 is for this local/CI harness only: the services run as uid 10001 and a compose file secret keeps the host owner and
# mode, so 0400 owned by the host user would not be readable inside the container. Production sets owner 10001 and mode 0400 (HOST-05).
# check-init-secrets.sh runs this script in a scratch folder and fails if either file is not made on its own.
set -euo pipefail
dir="$(cd "$(dirname "$0")" && pwd)/secrets"
mkdir -p "$dir"

# make NAME PREFIX: the file NAME holds one line, PREFIX and 64 random hex characters, unless it exists and is not empty.
make() {
  local file="$dir/$1"
  if [ -s "$file" ]; then echo "init-secrets: $file exists, left as it is"; return 0; fi
  printf '%s%s\n' "$2" "$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')" > "$file"
  chmod 0444 "$file"
  echo "init-secrets: created $file"
}

make internal_token 'X-Internal-Token: '
make model_key ''
