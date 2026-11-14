#!/usr/bin/env bash
# check-copies-guards.sh shows that each guard of check-copies.sh fails when what it guards breaks, and that the one thing allowed to differ may. It copies
# api/*/src into a scratch folder, breaks one thing at a time there and runs the check on the copy: no stack, no Docker, nothing in the checkout is touched.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
bak="$(mktemp -d)"
trap 'rm -rf "$work" "$bak"' EXIT
(cd "$here/.." && find api -path '*/src/*' -type f ! -path '*/target/*' \( -name '*.java' -o -name '*.sql' -o -name '*.yaml' \) -print0 | xargs -0 cp --parents -t "$work")
find "$work" -type f -exec sed -i 's/\r$//' {} +   # a Windows checkout may hold CRLF; sed -i here would then change every line and fool "changed nothing"
J=src/main/java/ai/carmona
T=src/test/java/ai/carmona
fail() { echo "FAIL: $1"; exit 1; }
run() { bash "$here/check-copies.sh" "$work" 2>&1 || echo "exit $?"; }   # a failing check ends its output with "exit 1": CI reads the status

[[ $(run) == *SUCCESS* ]] || fail "the check does not pass on the unbroken copy: $(run)"

# breaks <expected text of the FAIL line> <sed script> <file under the copy>...: the script must change each file, the check must fail with that text, and the
# files are put back. A backup beside the file would be one more reader of every literal, so the backups live in $bak.
breaks() {
  local expect=$1 script=$2 f out; shift 2
  for f in "$@"; do
    cp "$work/$f" "$bak/${f//\//_}"
    sed -i "$script" "$work/$f"
    cmp -s "$work/$f" "$bak/${f//\//_}" && fail "the sed script changed nothing in $f: $script"
  done
  out=$(run)
  [[ $out == *"FAIL: $expect"* && $out == *"exit 1"* ]] || fail "nothing failed with '$expect' after: $script in $*"
  for f in "$@"; do cp "$bak/${f//\//_}" "$work/$f"; done
}

# 1. The internal-secret guard: the copies, their tests, and the sixth reader.
breaks 'InternalToken: ' 's/presented.size() == 1/presented.size() >= 1/' "api/model-service/$J/model/InternalToken.java"
breaks 'InternalToken: ' 's/^\/\/ BE-24 (SEC-04)/\/\/ BE-24/' "api/account-service/$J/account/InternalToken.java"
breaks 'InternalToken: ' 's/shared library would need/shared library needs/' "api/billing-service/$J/billing/InternalToken.java"
breaks 'InternalToken has lost' 's/MessageDigest.isEqual/Arrays.equals/' "api/auth-service/$J/auth/InternalToken.java"
breaks 'InternalToken has lost' 's/internalTokenOnInternalCalls/interceptor/' "api/auth-service/$J/auth/InternalToken.java"
breaks 'InternalTokenTest: ' 's/@Test/@org.junit.jupiter.api.Test/' "api/auth-service/$T/auth/InternalTokenTest.java"
breaks 'TestInternalToken: ' 's/new byte\[32\]/new byte[31]/' "api/organization-service/$T/organization/TestInternalToken.java"
breaks '"X-Internal-Token" is in' 's/^package .*/&\nclass Reader { static final String H = "X-Internal-Token"; }/' "api/usage-service/$J/usage/UsageResource.java"
breaks '": *([0-9a-fA-F]{64})" is in' 's/\[0-9a-fA-F\]{64}/[0-9a-fA-F]{65}/' "api/inference-service/$J/inference/InternalSecret.java"
breaks "' is missing or unreadable\" is in" "s/' is missing or unreadable/' cannot be read/" "api/inference-service/$J/inference/InternalSecret.java"
breaks "' must hold one line 'X-Internal-Token: ' and 64 hex characters\" is in" 's/and 64 hex characters/and 65 hex characters/' "api/account-service/$J/account/InternalToken.java"
breaks '"x-internal-token" is in' 's/"x-internal-token"/"x-internal-tokens"/' "api/gateway-service/$J/gateway/IdentityHeadersFilter.java"

# 2. The API key: auth-service mints it, the gateway checks it.
breaks '"apikey:" is in' 's/"apikey:"/"apikeys:"/' "api/gateway-service/$J/gateway/ApiKeyAuthenticationManager.java"
breaks '"no_credit:" is in' 's/^package .*/&\nclass Reader { static final String P = "no_credit:"; }/' "api/usage-service/$J/usage/UsageResource.java"
breaks 'ApiKeys.checksum' 's/value % 62/value % 61/' "api/gateway-service/$J/gateway/ApiKeyFormat.java"
breaks 'ApiKeys.sha256' 's/"SHA-256"/"SHA-512"/' "api/gateway-service/$J/gateway/ApiKeyFormat.java"
breaks 'ApiKeys.checksum: nothing is left' 's/static String checksum/static String crc/' "api/auth-service/$J/auth/ApiKeys.java" "api/gateway-service/$J/gateway/ApiKeyFormat.java"
breaks 'ApiKeys.sha256: nothing is left' 's/static String sha256/static String digest/' "api/auth-service/$J/auth/ApiKeys.java" "api/gateway-service/$J/gateway/ApiKeyFormat.java"
breaks '"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz" is in' 's/ABCDEFGHIJ/ABCDEFGHIK/' "api/gateway-service/$J/gateway/ApiKeyFormat.java"
breaks '"cmn_[a-z]+_" is in' 's/cmn_\[a-z\]+_/cmn_[a-z0-9]+_/' "api/auth-service/$J/auth/ApiKeys.java"
breaks 'carmona.keys.prefix and carmona.gateway.key-prefixes differ' 's/key-prefixes: cmn_live_/key-prefixes: cmn_live_,cmn_test_/' "api/gateway-service/src/main/resources/application-prod.yaml"
breaks 'carmona.keys.prefix and carmona.gateway.key-prefixes differ' 's/key-prefixes:/key-prefix-x:/;s/^\( *\)prefix:/\1prefix-x:/' "api/gateway-service/src/main/resources/application-prod.yaml" "api/auth-service/src/main/resources/application-prod.yaml"
breaks 'carmona.keys.prefix of application.yaml is not' 's/prefix: cmn_test_/prefix: cmn_dev_/' "api/auth-service/src/main/resources/application.yaml"
breaks 'carmona.keys.prefix of application.yaml is not' 's/key-prefixes:/key-prefix-x:/;s/^\( *\)prefix:/\1prefix-x:/' "api/gateway-service/src/main/resources/application.yaml" "api/auth-service/src/main/resources/application.yaml"

# 3. The identity headers.
breaks '"id-account" is in' 's/"id-account"/"id-accounts"/g' "api/usage/$J/usage/UsageController.java"
breaks '"id-organization" is in' 's/"id-organization"/"id-organisation"/g' "api/batch-service/$J/batch/Caller.java"
breaks '"id-api-key" is in' 's/"id-api-key"/"id-api-keys"/g' "api/gateway-service/$J/gateway/IdentityHeadersFilter.java"
breaks '"batch-line" is in' 's/"batch-line"/"batch-lines"/g' "api/inference-service/$J/inference/Caller.java"
breaks '"tier" is in' 's/"tier"/"tiers"/g' "api/batch-service/$J/batch/Caller.java"

# 4. The model id.
breaks '[a-z0-9][a-z0-9._-]{0,62}/' 's/{0,63}/{0,64}/' "api/inference-service/$J/inference/ModelRoster.java"
breaks '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12} is in' 's/-\[0-9a-f\]{12}/-[0-9a-f]{13}/' "api/inference-service/$J/inference/ModelRoster.java"
breaks '"org-" is in' 's/"org-"/"org_"/' "api/billing/$J/billing/Price.java"
breaks "'org-' is in" "s/'org-'/'org_'/g" "api/model-service/src/main/resources/db/migration/V2026.11.12.001__create_tables.sql"

# the one thing that may differ: the callees
f="$work/api/account-service/$J/account/InternalToken.java"
cp "$f" "$bak/callees"
sed -i 's/Set.of(AuthController.class, OrganizationController.class)/Set.of(AuthController.class)/' "$f"
cmp -s "$f" "$bak/callees" && fail "the sed script changed nothing in the CALLEES set of account-service's InternalToken"
[[ $(run) == *SUCCESS* ]] || fail "a different CALLEES set made the check fail: $(run)"

# no submodules, no check: a checkout without the modules must not pass for lack of copies to compare
rm -f "$work"/api/*-service/$J/*/InternalToken.java
[[ $(run) == *"are the submodules checked out"* ]] || fail "an empty checkout did not fail the check"

echo "  SUCCESS: every guard of check-copies.sh fails on the break it exists for, and a different CALLEES set passes"
