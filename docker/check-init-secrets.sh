#!/usr/bin/env bash
# init-secrets.sh makes each secret file on its own: a file that exists is left as it is, and one that exists never keeps the other from being made.
# The script once ended at the first line it read if internal_token was there (`exit 0`), so a checkout that already had it never got model_key and
# compose then stopped on a missing secret file. This runs the script in a scratch copy of its folder: no Docker, no stack, and docker/secrets is not
# touched. INIT_SECRETS=<path> checks another copy of the script (the earlier one, to see this fail).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp "${INIT_SECRETS:-$here/init-secrets.sh}" "$work/init-secrets.sh"
secrets="$work/secrets"
fail() { echo "FAIL: $1"; exit 1; }
run() { bash "$work/init-secrets.sh" > /dev/null; }
sum() { cksum < "$secrets/$1"; }

run
(( $(wc -l < "$secrets/internal_token") == 1 )) && grep -Eq '^X-Internal-Token: [0-9a-f]{64}$' "$secrets/internal_token" || fail "internal_token is not one line 'X-Internal-Token: <64 hex>'"
[[ -f $secrets/model_key ]] || fail "model_key was not created"
(( $(wc -l < "$secrets/model_key") == 1 )) && grep -Eq '^[0-9a-f]{64}$' "$secrets/model_key" || fail "model_key is not one line of 64 hex characters"
[[ $(sum internal_token) != "$(sum model_key)" ]] || fail "the two secrets are the same value"

token=$(sum internal_token); key=$(sum model_key)
run
[[ $(sum internal_token) == "$token" && $(sum model_key) == "$key" ]] || fail "a second run changed a file that exists"

rm "$secrets/model_key"
run
[[ -s $secrets/model_key ]] || fail "model_key was not created while internal_token exists"
[[ $(sum internal_token) == "$token" ]] || fail "creating model_key changed internal_token"

key=$(sum model_key)
rm "$secrets/internal_token"
run
grep -Eq '^X-Internal-Token: [0-9a-f]{64}$' "$secrets/internal_token" || fail "internal_token was not created while model_key exists"
[[ $(sum model_key) == "$key" ]] || fail "creating internal_token changed model_key"

echo "  SUCCESS: init-secrets.sh makes internal_token and model_key once each, and each on its own"
