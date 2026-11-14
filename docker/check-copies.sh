#!/usr/bin/env bash
# check-copies.sh: what two Carmona modules must spell alike is copied, not shared (a library holds a contract and no behaviour), so this check is what keeps
# the copies equal. It reads source files only: no stack, no Docker, no build. CI runs it before the build (ci.yaml); run it from anywhere.
#   bash docker/check-copies.sh [root]      root = a checkout, or a scratch copy of api/*/src (check-copies-guards.sh), default the superproject
set -euo pipefail
cd "${1:-$(dirname "$0")/..}"
bad=0
fail() { echo "FAIL: $1"; bad=1; }

# ponytail: two ceilings, no code for them. `spelled` does not see a rename inside a file that keeps another occurrence of the literal (count the occurrences per file if
# that bites), and in the InternalToken copies the CALLEES range and the `import ai.carmona.*` lines may differ in anything (compare their shape if one drifts).

# same <label> <sed script> <file>...: each file, once the sed script has run on it, must equal the first. Fewer than two files means the submodules are not
# checked out. `cat -s` squeezes the blank line that a deleted import group leaves behind.
# A script that leaves nothing of the first file (a range whose start was renamed) would compare empty with empty, so that fails too.
same() {
  local label=$1 script=$2 first f; shift 2
  (( $# >= 2 )) || { fail "$label: found $# file, expected at least two (are the submodules checked out?)"; return 0; }
  first=$1
  [[ -n $(sed "$script" "$first" | tr -d '[:space:]') ]] || fail "$label: nothing is left of $first to compare"
  for f in "$@"; do
    cmp -s <(sed "$script" "$first" | tr -d '\015' | cat -s) <(sed "$script" "$f" | tr -d '\015' | cat -s) || fail "$label: $f differs from $first in more than it is allowed to"
  done
}

# spelled <only|has> <literal> <file>...: `only` = exactly these files of api/*/src/main hold the literal (a new reader fails until it is listed here, a
# renamed literal fails at once); `has` = these files hold it (for a word too common to sweep).
spelled() {
  local mode=$1 lit=$2 want got f; shift 2
  want=$(printf '%s\n' "$@" | sort)
  if [[ $mode == only ]]; then got=$(grep -rlF -- "$lit" api/*/src/main | sort || true)
  else got=$(for f in "$@"; do { grep -qF -- "$lit" "$f" && echo "$f" || true; }; done | sort); fi
  [[ $got == "$want" ]] || fail "$lit is in [$(echo $got)], expected [$(echo $want)]"
}

J=src/main/java/ai/carmona
GW=api/gateway-service/$J/gateway
AUTH=api/auth-service/$J/auth
INF=api/inference-service/$J/inference
BATCH=api/batch-service/$J/batch

# 1. The internal-secret guard. The five copies differ in the imports of the callees and in the CALLEES set with the comment above it, and in nothing else.
guards=(api/*-service/$J/*/InternalToken.java)
same InternalToken '/^package /d;/^import ai\.carmona\./d;/^    \/\/ The Feign clients of this service/,/);$/d' "${guards[@]}"
for f in "${guards[@]}"; do   # a script that deleted everything would make the copies equal
  grep -q 'MessageDigest.isEqual' "$f" && grep -q 'internalTokenOnInternalCalls' "$f" || fail "InternalToken has lost the compare or the client interceptor: $f"
done
same InternalTokenTest '/^package /d' api/*-service/src/test/java/ai/carmona/*/InternalTokenTest.java
same TestInternalToken '/^package /d;/^ *\/\//d' api/*-service/src/test/java/ai/carmona/*/TestInternalToken.java
# the sixth reader (inference-service reads the file to send the header and checks nothing) spells the same header, line and fixed texts
spelled only '"X-Internal-Token"' "${guards[@]}" $INF/InternalSecret.java
spelled has '": *([0-9a-fA-F]{64})"' "${guards[@]}" $INF/InternalSecret.java
spelled has "' is missing or unreadable\"" "${guards[@]}" $INF/InternalSecret.java
spelled has "' must hold one line 'X-Internal-Token: ' and 64 hex characters\"" "${guards[@]}" $INF/InternalSecret.java
spelled only '"x-internal-token"' $GW/IdentityHeadersFilter.java

# 2. The API key: auth-service mints it, the gateway checks it.
same 'ApiKeys.checksum' '/static String checksum/,/^    }$/!d' $AUTH/ApiKeys.java $GW/ApiKeyFormat.java
same 'ApiKeys.sha256' '/static String sha256/,/^    }$/!d' $AUTH/ApiKeys.java $GW/ApiKeyFormat.java
spelled only '"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"' $AUTH/ApiKeys.java $GW/ApiKeyFormat.java
spelled only '"cmn_[a-z]+_"' $AUTH/ApiKeys.java $GW/ApiKeyFormat.java
# the prefix auth-service mints with must be one the gateway accepts: the same value in production, a member of the list in development
pre() { sed -nE "s/^ *$2: *([a-z_,]+).*/\1/p" "api/$1/src/main/resources/$3.yaml"; }
minted=$(pre auth-service prefix application-prod) accepted=$(pre gateway-service key-prefixes application-prod)
[[ -n $minted && $minted == "$accepted" ]] || fail "carmona.keys.prefix and carmona.gateway.key-prefixes differ in application-prod.yaml"
minted=$(pre auth-service prefix application) accepted=$(pre gateway-service key-prefixes application)
[[ -n $minted && ,$accepted, == *,"$minted",* ]] || fail "carmona.keys.prefix of application.yaml is not in carmona.gateway.key-prefixes"
spelled only '"apikey:"' $AUTH/ApiKeyService.java $GW/ApiKeyAuthenticationManager.java
spelled only '"no_credit:"' api/billing-service/$J/billing/CreditFlags.java $GW/ApiKeyAuthenticationManager.java $INF/Admission.java

# 3. The identity headers: set and stripped by the gateway, read by inference-service and batch-service, sent by the batch worker, read by the controllers.
spelled only '"id-account"' $GW/IdentityHeadersFilter.java api/{account,auth,billing,organization,usage}/$J/*/*Controller.java
spelled only '"id-organization"' $GW/IdentityHeadersFilter.java $INF/Caller.java $BATCH/Caller.java $BATCH/BatchWorker.java
spelled only '"id-api-key"' $GW/IdentityHeadersFilter.java $INF/Caller.java $BATCH/Caller.java $BATCH/BatchWorker.java
spelled only '"batch-line"' $GW/IdentityHeadersFilter.java $INF/Caller.java $BATCH/BatchWorker.java
spelled has '"tier"' $GW/IdentityHeadersFilter.java $INF/Caller.java $BATCH/Caller.java $BATCH/BatchWorker.java

# 4. The model id: the shape, and the org- namespace of the models an organization registers for itself.
shape='[a-z0-9][a-z0-9._-]{0,62}/[a-z0-9][a-z0-9._-]{0,63}'
spelled only "$shape" api/model-service/$J/model/ModelId.java api/model-service/src/main/resources/db/migration/V2026.11.12.001__create_tables.sql $INF/ModelRoster.java
spelled only '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' api/model-service/$J/model/ModelId.java $INF/ModelRoster.java
spelled only '"org-"' api/billing/$J/billing/Price.java api/model-service/$J/model/ModelId.java $INF/InferenceProperties.java
spelled has "'org-'" api/model-service/src/main/resources/db/migration/V2026.11.12.001__create_tables.sql

(( bad == 0 )) || exit 1
echo "  SUCCESS: the copies of the internal-secret guard agree, and the key, header, Valkey and model id spellings are where they should be"
