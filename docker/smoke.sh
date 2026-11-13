#!/usr/bin/env bash
# End-to-end check through the gateway. Run after the stack is up WITH the object-storage overlay, because the batch section
# needs it: docker compose -f compose.yaml -f compose.minio.yaml up -d --build --wait
# (add -f compose.gpu.yaml for ENGINE=vllm). The environment or .env must hold every name of .env.example: the usual ones plus
# GRAFANA_ADMIN_PASSWORD and the MINIO_* / STORAGE_* names, which compose refuses to start without.
# The internal secret file must exist before `up` (BE-24): run `bash docker/init-secrets.sh` once.
# The simulator image is a local build: run `bash docker/sim/build.sh` once before the first `up`, or compose stops (image not found).
# It ends by draining this IP's login bucket (refills 1/s): wait ~20 s before running it again.
# It starts by waiting, at most 60 s, until the console login route answers something other than 503: right after `up --wait`
# the gateway has answered 503 there once in four runs, before any assertion. The wait costs one login attempt of this IP's bucket.
# It stops and restarts valkey once (API-key lookups must fail closed with 503), runs chats on the engine
# (the simulator by default, vLLM with ENGINE=vllm), checks that inference-service counted their prompt tokens in the prompt cache
# counter, drains every engine replica through inference-service's management port and
# puts it back (503 engine_unavailable while drained; a running stream finishes), and greps every log and a database dump for a canary string.
# Late in the run it registers a model on model-service (the shared secret) on a second simulator that it starts for the purpose (engine-own, removed at the end of that section),
# calls it with its owner's key, shows that another organization's key cannot, and checks that the owner is not charged for it (ENGINE=sim only).
# Run it against another compose project with COMPOSE_PROJECT_NAME=... (compose reads it; the stack must run under it).
# On the two-simulator stack (compose.fleet.yaml) run it with FLEET=1, which adds that file to every compose call and asserts that two replicas are listed.
# Continue-on-fail: a failed assertion is counted (note_fail) and the run goes on, so one run lists every failure; the
# exit status is the number of failures (capped at 1). Later assertions that depend on a failed one can fail as a
# consequence; read the first FAIL of each chain.
# The simulator is the patched one (docker/sim/build.sh builds the image compose.yaml uses): it notices a client that hangs
# up (G1 of work/prototype-sim/FINDINGS-contract.md) and reports usage on every chunk (G3), so the engine-idle-after-a-
# hang-up and cancelled-stream-billed assertions run on it as on vLLM. Against upstream's own simulator image
# (ENGINE_IMAGE=ghcr.io/llm-d/llm-d-inference-sim:v0.11.4@sha256:d60f0fb0... when the stack was started) run with SIM_STOCK=1:
# the two are then printed as `skip-sim` with their reason and counted, and without it they fail, which is how this script
# shows the patch matters.
set -uo pipefail
NFAIL=0
NSKIP=0
note_fail() { NFAIL=$((NFAIL+1)); echo "  ^ FAIL #$NFAIL at smoke.sh line ${BASH_LINENO[0]}"; return 0; }
skip_sim() { NSKIP=$((NSKIP+1)); echo "skip-sim  $1 (NOT RUN: $2)"; }
G=${GATEWAY:-http://localhost:8080}
# ENGINE picks the engine the inference checks run against: the simulator by default (CI, compose.yaml), or
# ENGINE=vllm with the stack started from compose.yaml + compose.gpu.yaml. Both serve carmona/qwen3-4b.
M=${MODEL:-carmona/qwen3-4b}
ENGINE=${ENGINE:-sim}
# batch-service keeps its files in S3 (MinIO in compose): the batch section needs compose.minio.yaml, whose
# MINIO_* and STORAGE_* variables must be in the environment or .env, as when the stack was started.
DC=(docker compose -f "$(dirname "$0")/compose.yaml" -f "$(dirname "$0")/compose.minio.yaml")
if [[ $ENGINE == vllm ]]; then DC+=(-f "$(dirname "$0")/compose.gpu.yaml"); ENGINE_HOST=vllm; else ENGINE_HOST=engine; fi
# FLEET=1: the stack was started with compose.fleet.yaml as well (two named simulators, health gate on). Every compose call here has to carry
# that file too: the crash step's `up -d usage inference` would otherwise recreate inference from compose.yaml alone (one replica, gate off,
# the default `engine` started again), and the multi-replica branch of the drain section below could never run.
[[ ${FLEET:-0} == 1 ]] && DC+=(-f "$(dirname "$0")/compose.fleet.yaml")
# The same, with the profile of the one service that is no part of the stack: engine-own, the second simulator the registered-model section starts and removes.
DCO=(docker compose --profile own-engine "${DC[@]:2}")
# G2 of the findings: the simulator's output length is that of the prompt (echo mode), so a long stream needs a long
# prompt: 900 words = 905 prompt tokens (the chat template adds 5), so 905 output tokens ~ 22 s at 24 ms per token, well past the
# 10 s the idle check below allows a stream that nobody reads. The prompt must stay under max_tokens (1000): in echo mode the
# engine answers 400 if the whole prompt does not fit, which inference records as an error, not a cancel. vLLM is asked to count, as before.
if [[ $ENGINE == vllm ]]; then LONGP='Count from 1 to 1000, separated by commas.'; else LONGP=$(for i in $(seq 900); do printf 'w%d ' $i; done); fi
BODY=$(mktemp)
HDRS=$(mktemp)
trap 'rm -f "$BODY" "$HDRS"' EXIT

# expect <status> <curl args...>. Credentials (JWTs, API keys, refresh cookies, emailed tokens) never
# reach the output.
expect() {
  local want=$1; shift
  local got shown
  got=$(curl -s -o "$BODY" -w '%{http_code}' "$@")
  shown=$(sed -E 's/Bearer [^ ]+/Bearer <redacted>/g; s/(carmona-rt=)[^ ]+/\1<redacted>/g; s/("token":")[^"]+/\1<redacted>/g' <<<"$*")
  if [[ $got != "$want" ]]; then echo "FAIL want $want got $got: $shown"; head -c 600 "$BODY"; echo; note_fail; return 0; fi
  echo "ok   $want  $shown"
}
json() { sed -nE "s/.*\"$1\":\"([^\"]+)\".*/\1/p" "$BODY"; }

pass='correct-horse-battery'
J=(-H 'Content-Type: application/json')

# Readiness: poll the route the first assertions use (a wrong password is a 401) every 2 s; 503 (not routed yet) and 000 (not listening) mean wait.
ready=""
for _ in $(seq 30); do
  ready=$(curl -s -o /dev/null -w '%{http_code}' "${J[@]}" -X POST "$G/auth/login" -d '{"email":"ready@example.com","password":"wrong-password"}')
  [[ $ready != 503 && $ready != 000 ]] && break
  sleep 2
done
[[ $ready != 503 && $ready != 000 ]] && echo "ok   the console login route answers ($ready)" || { echo "FAIL the console login route still answers $ready after 60 s"; note_fail; }

# Mailpit, inside the network: every email to $1, newest first, as JSON.
mails() {
  local id
  for id in $("${DC[@]}" exec -T tools curl -s "http://mailpit:8025/api/v1/search?query=to:%22${1/@/%40}%22" | grep -oE '"ID":"[^"]+"' | cut -d'"' -f4); do
    "${DC[@]}" exec -T tools curl -s "http://mailpit:8025/api/v1/message/$id"
  done
}
# The token of the newest {$2} link (verify-email, reset-password) mailed to $1. The emails are captured
# before grepping: under pipefail, a reader that stops early (grep -q, head) fails the writer's pipe.
mail_token() {
  local token="" all
  for _ in $(seq 20); do
    all=$(mails "$1")
    token=$(grep -oE "/$2\?token=[A-Za-z0-9_-]+" <<<"$all" | sed -n '1s/.*=//p')
    [[ -n $token ]] && break
    sleep 0.5
  done
  [[ -n $token ]] || { echo "FAIL no $2 email for $1"; note_fail; }
  echo "$token"
}
# The refresh cookie the last response (-D "$HDRS") set.
cookie() { sed -nE 's/^set-cookie: (__Host-carmona-rt=[^;]+);.*/\1/ip' "$HDRS" | tr -d '\r' | tail -1; }

# register, verify the email (Mailpit), login a fresh account; sets $email, $token and $rt (refresh cookie)
account() {
  email="smoke-$RANDOM$RANDOM@example.com"
  expect 202 "${J[@]}" -X POST "$G/auth/register" -d "{\"name\":\"Smoke\",\"email\":\"$email\",\"password\":\"$pass\"}"
  expect 403 "${J[@]}" -X POST "$G/auth/login" -d "{\"email\":\"$email\",\"password\":\"$pass\"}"   # not verified yet
  expect 204 "${J[@]}" -X POST "$G/accounts/verify-email" -d "{\"token\":\"$(mail_token "$email" verify-email)\"}"
  expect 200 -D "$HDRS" "${J[@]}" -X POST "$G/auth/login" -d "{\"email\":\"$email\",\"password\":\"$pass\"}"
  token=$(json token)
  rt=$(cookie)
}

## Accounts and login
account
# A known email answers like a new one (no account enumeration); its owner gets an email instead.
expect 202 "${J[@]}" -X POST "$G/auth/register" -d "{\"name\":\"Smoke\",\"email\":\"${email^^}\",\"password\":\"$pass\"}"
for _ in $(seq 20); do all=$(mails "$email"); grep -q 'Você já tem uma conta na Carmona' <<<"$all" && break; sleep 0.5; done
grep -q 'Você já tem uma conta na Carmona' <<<"$all" && echo "ok   the owner of the known email was told by email" \
  || { echo "FAIL no 'already registered' email"; note_fail; }
expect 400 "${J[@]}" -X POST "$G/auth/register" -d '{"name":"Smoke","email":"not-an-email","password":"correct-horse"}'
expect 401 "${J[@]}" -X POST "$G/auth/login" -d "{\"email\":\"$email\",\"password\":\"wrong-password\"}"
expect 401 "${J[@]}" -X POST "$G/auth/login" -d '{"email":"nobody@example.com","password":"wrong-password"}'
A=(-H "Authorization: Bearer $token")

## Console sessions: the refresh cookie rotates, a copied one ends its session, logout ends it, other sites can't post
first=$rt
expect 200 -D "$HDRS" -X POST "$G/auth/refresh" -H "Cookie: $first"
rotated=$(cookie)
[[ -n $(json token) && -n $rotated && $rotated != "$first" ]] && echo "ok   refresh: a new access token and a rotated cookie" \
  || { echo "FAIL refresh did not rotate"; note_fail; }
expect 401 -X POST "$G/auth/refresh" -H "Cookie: $first"                 # used twice: it was copied
expect 401 -X POST "$G/auth/refresh" -H "Cookie: $rotated"               # so the session is gone for both
expect 200 -D "$HDRS" "${J[@]}" -X POST "$G/auth/login" -d "{\"email\":\"$email\",\"password\":\"$pass\"}"
live=$(cookie)
expect 403 -H 'Origin: https://evil.example' -X POST "$G/auth/refresh" -H "Cookie: $live"
expect 204 -H 'Origin: http://localhost:3000' -X POST "$G/auth/logout" -H "Cookie: $live"
expect 401 -X POST "$G/auth/refresh" -H "Cookie: $live"
expect 200 -D "$HDRS" "${J[@]}" -X POST "$G/auth/login" -d "{\"email\":\"$email\",\"password\":\"$pass\"}"
keep=$(cookie)                                                           # ends with the account (erasure)

expect 401 "$G/auth/whoami"
expect 401 -H "Authorization: Bearer ${token}x" "$G/auth/whoami"
expect 200 "${A[@]}" "$G/auth/whoami"
id=$(json id)
expect 200 "${A[@]}" "$G/accounts/$id"
other=00000000-0000-0000-0000-000000000000
expect 403 "${A[@]}" "$G/accounts/$other"
expect 403 "${A[@]}" -H "id-account: $other" "$G/accounts/$other"   # forged header is stripped
expect 404 "${A[@]}" "$G/accounts"                                  # list stays internal
expect 404 "${A[@]}" "${J[@]}" -X POST "$G/accounts/login" -d '{}'  # credential check stays internal
expect 404 "${A[@]}" "$G/auth/jwks"

## Organizations
expect 201 "${A[@]}" "${J[@]}" -X POST "$G/organizations" -d '{"name":"Smoke Org"}'
org=$(json id)

# Internal endpoints have no gateway route: the smoke test reaches them from inside the network (the
# tools container has curl). Prepaid credit (R$10, in micro-BRL) pays for the chats below.
internal() { MSYS_NO_PATHCONV=1 "${DC[@]}" exec -T tools curl -s -o /dev/null -w '%{http_code}' -H @/run/secrets/internal_token -H 'Content-Type: application/json' "$@"; }
grant() { internal -X POST http://billing:8080/billing/grants -d "{\"organizationId\":\"$1\",\"amountMicroBrl\":$2,\"reason\":\"smoke\",\"idempotencyKey\":\"$3\"}"; }
# S15 (BE-24): a guarded internal call without the shared secret is refused and changes nothing; with it, it is not refused.
# The tools container holds the file, so the no-secret call is made WITHOUT -H and the wrong-secret call with a made-up value.
code=$("${DC[@]}" exec -T tools curl -s -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' -X POST http://billing:8080/billing/grants -d '{}')
[[ $code == 401 ]] && echo "ok   401  S15 grant without the internal secret is refused" || { echo "FAIL S15 grant without the secret got $code"; note_fail; }
code=$("${DC[@]}" exec -T tools curl -s -o /dev/null -w '%{http_code}' -H 'X-Internal-Token: 0000000000000000000000000000000000000000000000000000000000000000' -H 'Content-Type: application/json' -X POST http://billing:8080/billing/grants -d '{}')
[[ $code == 401 ]] && echo "ok   401  S15 grant with a wrong internal secret is refused" || { echo "FAIL S15 grant with a wrong secret got $code"; note_fail; }
code=$(internal -X POST http://billing:8080/billing/grants -d '{}')
[[ $code != 401 ]] && echo "ok   $code  S15 grant with the internal secret passes the lock (an empty body is a validation error, not a 401)" || { echo "FAIL S15 grant with the secret got 401"; note_fail; }
code=$(grant "$org" 10000000 smoke-start)
[[ $code == 200 ]] && echo "ok   200  R\$10 of credit granted (internal)" || { echo "FAIL credit grant got $code"; note_fail; }
expect 200 "${A[@]}" "$G/organizations"
expect 200 "${A[@]}" "$G/organizations/$org"
expect 404 "${A[@]}" "$G/organizations/$org/tenant"                 # internal
expect 404 "${A[@]}" "$G/organizations/$org/members/$id"            # internal

## API keys: shown once, /v1 takes keys only, revocation is immediate
expect 201 "${A[@]}" "${J[@]}" -X POST "$G/organizations/$org/api-keys" -d '{"name":"smoke"}'
key=$(json key)
key_id=$(json id)
K=(-H "Authorization: Bearer $key")
expect 200 "${A[@]}" "$G/organizations/$org/api-keys"
if grep -q "$key" "$BODY"; then echo "FAIL the key is listed after creation"; note_fail; fi
expect 200 "${K[@]}" "$G/v1/models"
expect 200 "${K[@]}" -H "id-organization: $other" -H "tier: enterprise" "$G/v1/models"   # forged headers stripped
expect 401 "$G/v1/models"                                            # no key
expect 401 "${A[@]}" "$G/v1/models"                                  # a JWT is not an API key
[[ ${key: -1} == A ]] && typo="${key%?}B" || typo="${key%?}A"
expect 401 -H "Authorization: Bearer $typo" "$G/v1/models"           # a typo fails the checksum
expect 401 "${K[@]}" "$G/auth/whoami"                                # an API key is not a JWT
expect 404 "${A[@]}" "$G/api-keys/0"                                 # the lookup by hash stays internal
expect 204 "${A[@]}" -X DELETE "$G/organizations/$org/api-keys/$key_id"
expect 401 "${K[@]}" "$G/v1/models"                                  # revoked: refused at once

## API-key lookups fail closed when valkey is down
expect 201 "${A[@]}" "${J[@]}" -X POST "$G/organizations/$org/api-keys" -d '{"name":"smoke-2"}'
key2=$(json key)
"${DC[@]}" stop valkey >/dev/null 2>&1
expect 503 -H "Authorization: Bearer $key2" "$G/v1/models"
"${DC[@]}" up -d --wait valkey >/dev/null 2>&1
expect 200 -H "Authorization: Bearer $key2" "$G/v1/models"

## Inference through the gateway: $M on $ENGINE, behind inference-service
K2=(-H "Authorization: Bearer $key2")
chat() { echo "{\"model\":\"$M\",\"messages\":[{\"role\":\"user\",\"content\":\"$1\"}],\"max_tokens\":$2${3:-}}"; }
expect 200 "${K2[@]}" "$G/v1/models"
grep -q "\"$M\"" "$BODY" || { echo "FAIL $M is not listed"; note_fail; }
expect 200 "${K2[@]}" "${J[@]}" -X POST "$G/v1/chat/completions" -d "$(chat 'Say hi.' 8)"
grep -q '"usage"' "$BODY" || { echo "FAIL no usage in the answer"; note_fail; }
stream=$(curl -sN "${K2[@]}" "${J[@]}" -X POST "$G/v1/chat/completions" -d "$(chat 'Count to five.' 16 ',"stream":true')")
events=$(grep -c '^data:' <<<"$stream" || true)
if [[ $events -lt 3 ]] || ! grep -qE '^data: ?\[DONE\]' <<<"$stream"; then echo "FAIL stream: $events events"; note_fail; fi
echo "ok   200  streamed $events events, ending in [DONE]"
expect 404 "${K2[@]}" "${J[@]}" -X POST "$G/v1/chat/completions" -d '{"model":"nope","messages":[{"role":"user","content":"x"}]}'
expect 400 "${K2[@]}" "${J[@]}" -X POST "$G/v1/chat/completions" -d "$(chat 'x' 8 ',"n":2')"
expect 400 "${K2[@]}" "${J[@]}" -X POST "$G/v1/chat/completions" -d "{\"model\":\"$M\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"image_url\",\"image_url\":{\"url\":\"http://example.com/a.png\"}}]}]}"
expect 400 "${K2[@]}" "${J[@]}" -X POST "$G/v1/chat/completions" -d "$(chat 'x' 5000)"
expect 400 "${K2[@]}" "${J[@]}" -X POST "$G/v1/chat/completions" -d '{"model":'
expect 400 "${K2[@]}" "${J[@]}" -H 'Transfer-Encoding: chunked' -X POST "$G/v1/chat/completions" -d "$(chat 'x' 8)"
expect 400 "${K2[@]}" "$G/v1/models?api_key=cmn_test_x"

# A client that hangs up stops the generation upstream, and is recorded as cancelled with the tokens it had received.
# It hangs up after the first chunks, not after a timer: a cut 2 s after the request once came before the first byte on a slow
# start (E35 then saw a cancelled row with no tokens). `head` leaves after 12 lines (the role chunk and the first five tokens, two
# lines each); curl, writing to the closed pipe, closes its connection. --max-time only bounds a stack that never answers.
curl -sN --max-time 30 "${K2[@]}" "${J[@]}" -X POST "$G/v1/chat/completions" -d "$(chat "$LONGP" 1000 ',"stream":true,"temperature":0')" | head -n 12 >/dev/null || true
# Requests the engine is generating right now, from its own metrics (the engines have no shell: asked from the tools container).
engine_busy() {
  "${DC[@]}" exec -T tools curl -s -m 5 "http://$ENGINE_HOST:8000/metrics" \
    | sed -nE 's/^vllm:num_requests_running\{[^}]*\} ([0-9.]+).*/\1/p' | head -1
}
if [[ $ENGINE == sim && ${SIM_STOCK:-0} == 1 ]]; then
  skip_sim "engine idle again after the client hung up" "the stock simulator does not notice a hang-up and generates to the end, G1"
else
  # A wall-clock 10 s, not a count of polls (each poll is a `docker compose exec`, ~0.5 s): the stream outlives it by about 10 s on
  # the simulator, so an engine that has not noticed the hang-up is still busy at the deadline and this fails.
  deadline=$((SECONDS + 10))
  while :; do
    busy=$(engine_busy)
    [[ ${busy%.*} == 0 || $SECONDS -ge $deadline ]] && break
    sleep 0.5
  done
  [[ ${busy%.*} == 0 ]] && echo "ok   engine idle within 10 s of the client hanging up" || { echo "FAIL engine still busy ($busy)"; note_fail; }
fi

# Usage reaches usage-service once per request that reached the engine: 2 answered, 1 cancelled.
# The relay in inference-service is a 1 s tick loop: a pass that failed while a dependency restarted is
# simply retried by the next tick, so this polls briefly (and a failure here is never lost usage).
sql() { "${DC[@]}" exec -T db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tA -c "$1"' sh "$1"; }
usage=""
for _ in $(seq 20); do
  usage=$(sql "SELECT status || '=' || count(*) FROM usage.usage_event WHERE organization_id = '$org' GROUP BY status ORDER BY status" | tr -d '\r' | tr '\n' ' ')
  [[ $usage == "cancelled=1 ok=2 " ]] && break
  sleep 0.5
done
[[ $usage == "cancelled=1 ok=2 " ]] && echo "ok   usage recorded once each: $usage" || { echo "FAIL usage rows: '$usage'"; note_fail; }
if [[ $ENGINE == sim && ${SIM_STOCK:-0} == 1 ]]; then
  skip_sim "the cancelled stream is billed for its generated tokens" "the stock simulator reports usage only in the last chunk, so a cancelled stream has none, G3"
else
  cancelled=$(sql "SELECT output_tokens FROM usage.usage_event WHERE organization_id = '$org' AND status = 'cancelled'" | tr -d '\r')
  [[ ${cancelled:-0} -gt 0 ]] && echo "ok   the cancelled stream is billed for its $cancelled generated tokens" \
    || { row=$(sql "SELECT concat_ws('|', input_tokens, output_tokens, coalesce(ttft_ms::text, 'NULL'), duration_ms) FROM usage.usage_event WHERE organization_id = '$org' AND status = 'cancelled'" | tr -d '\r' | tr '\n' ' ')
         echo "FAIL the cancelled stream recorded no output tokens (row input|output|ttft_ms|duration_ms: $row)"; note_fail; }
fi

# The prompt cache counter (P0-1): the answered chats above ended with a final usage chunk, so inference-service counted their prompt
# tokens as hit or miss for the model. The simulator puts prompt_tokens_details.cached_tokens on that chunk (always 0 here: compose.yaml
# does not start it with --enable-kvcache), and a short prompt is under one cache block on vLLM too, so what is asserted is the miss
# series: it exists and is positive. The hit series is not asserted (0 on the simulator), and the cancelled stream is not counted by
# design (its final chunk never came). The management port is asked through the tools container, as the drain section below does; with
# several inference replicas the name answers as one of them, so this polls until that one has the series.
cache_miss_tokens() {
  "${DC[@]}" exec -T tools curl -s -m 5 http://inference:8081/actuator/prometheus | tr -d '\r' \
    | awk -v m="model=\"$M\"" '/^carmona_inference_prompt_cache_tokens_total\{/ && index($0, "result=\"miss\"") && index($0, m) { s += $NF } END { printf "%d\n", s }'
}
miss=0
for _ in $(seq 10); do
  miss=$(cache_miss_tokens)
  [[ ${miss:-0} -gt 0 ]] && break
  sleep 1
done
[[ ${miss:-0} -gt 0 ]] && echo "ok   prompt cache counter: $miss prompt tokens counted as result=miss for $M" \
  || { echo "FAIL carmona_inference_prompt_cache_tokens_total has no result=miss series for $M after answered chats"; note_fail; }

# Usage survives a crash: with usage-service down, the events wait in Valkey's stream; inference-service
# is killed (no graceful flush) and restarted; each event then reaches usage-service once.
"${DC[@]}" stop usage >/dev/null 2>&1
rids=()
for _ in 1 2 3; do
  expect 200 -D "$HDRS" "${K2[@]}" "${J[@]}" -X POST "$G/v1/chat/completions" -d "$(chat 'Say hi.' 8)"
  rids+=("'$(sed -nE 's/^x-request-id: ([0-9a-f-]{36}).*/\1/ip' "$HDRS")'")
done
sleep 1
"${DC[@]}" kill -s SIGKILL inference >/dev/null 2>&1
"${DC[@]}" up -d --wait usage inference >/dev/null 2>&1
stored=""
for _ in $(seq 40); do
  stored=$(sql "SELECT count(*) FROM usage.usage_event WHERE request_id IN ($(IFS=,; echo "${rids[*]}"))" | tr -d '\r')
  [[ $stored == 3 ]] && break
  sleep 1
done
[[ $stored == 3 ]] && echo "ok   usage-service down and inference-service killed: all 3 usage events arrived, once each" \
  || { echo "FAIL $stored of 3 usage events arrived after the crash"; note_fail; }

# Tool calls, and the engine's port stays off the host.
if true; then
  tools='"tools":[{"type":"function","function":{"name":"get_weather","description":"Current weather in a city","parameters":{"type":"object","properties":{"city":{"type":"string"}},"required":["city"]}}}],"tool_choice":{"type":"function","function":{"name":"get_weather"}}'
  expect 200 "${K2[@]}" "${J[@]}" -X POST "$G/v1/chat/completions" -d "$(chat 'What is the weather in Recife?' 64 ",$tools")"
  grep -q '"tool_calls"' "$BODY" && grep -q 'get_weather' "$BODY" || { echo "FAIL no tool call in the answer"; cat "$BODY"; note_fail; }
  echo "ok   tool call returned"
  if curl -s -m 2 -o /dev/null http://localhost:8000/health; then echo "FAIL the engine is reachable from the host"; note_fail; fi
  echo "ok   the engine's port is not published"
fi

# One request id from the gateway to the answer and the usage event (any client copy is replaced).
rid=$(curl -s -D - -o /dev/null "${K2[@]}" "${J[@]}" -H 'X-Request-Id: client-chosen' -X POST "$G/v1/chat/completions" -d "$(chat 'Say hi.' 8)" \
  | sed -nE 's/^x-request-id: ([0-9a-f-]{36}).*/\1/ip' | head -1)
[[ -n $rid ]] && echo "ok   200  X-Request-Id $rid (the gateway's)" || { echo "FAIL no gateway request id"; note_fail; }

## Admission: rate-limit headers, and each tier only gets its share of the engine
remaining=$(curl -s -D - -o /dev/null "${K2[@]}" "${J[@]}" -X POST "$G/v1/chat/completions" -d "$(chat 'Say hi.' 8)" | sed -nE 's/^x-ratelimit-remaining-requests: ([0-9]+).*/\1/ip')
[[ -n $remaining ]] && echo "ok   200  x-ratelimit-remaining-requests: $remaining" || { echo "FAIL no rate-limit headers"; note_fail; }
# Tiers are staff-set (no API yet): an enterprise organization, its tier set before its key is first used.
expect 201 "${A[@]}" "${J[@]}" -X POST "$G/organizations" -d '{"name":"Smoke Enterprise"}'
corp=$(json id)
sql "UPDATE organizations.organization SET tier = 'enterprise' WHERE id = '$corp'" >/dev/null
[[ $(grant "$corp" 10000000 corp-start) == 200 ]] || { echo "FAIL corp credit grant"; note_fail; }
expect 201 "${A[@]}" "${J[@]}" -X POST "$G/organizations/$corp/api-keys" -d '{"name":"corp"}'
K4=(-H "Authorization: Bearer $(json key)")
# Trial may fill half the engine's slots (4 -> 2). With those taken, one more trial request is refused at once,
# while an enterprise one still runs. On the fleet stack (FLEET=1) the trial share is 4 of 8 slots, above the organization's own cap of 2
# (carmona.inference.tiers.trial.max-in-flight), so the cap refuses first, as rate_limit_exceeded.
share=2
refusal=model_busy; [[ ${FLEET:-0} == 1 ]] && refusal=rate_limit_exceeded
for _ in $(seq $share); do
  curl -sN --max-time 8 "${K2[@]}" "${J[@]}" -X POST "$G/v1/chat/completions" -d "$(chat "$LONGP" 1000 ',"stream":true,"temperature":0')" >/dev/null &
done
sleep 2
read -r code took < <(curl -s -o "$BODY" -w '%{http_code} %{time_total}\n' "${K2[@]}" "${J[@]}" -X POST "$G/v1/chat/completions" -d "$(chat 'Say hi.' 8)")
[[ $code == 429 ]] && grep -q "\"$refusal\"" "$BODY" && awk "BEGIN { exit !($took < 0.5) }" \
  && echo "ok   429  trial over its share of the engine ($refusal), refused in ${took}s" \
  || { echo "FAIL trial over its share got $code in ${took}s"; cat "$BODY"; note_fail; }
expect 200 "${K4[@]}" "${J[@]}" -X POST "$G/v1/chat/completions" -d "$(chat 'Say hi.' 8)"   # enterprise still served
wait

## Replica drain (WP-09B): the owner takes the engine out of rotation. A stream that is running is not cut, a new request gets an
## honest 503 engine_unavailable with retry-after (nothing is charged), and READY puts the engine back. No GPU needed: the gate
## sits in front of the lease, so the simulator shows it as well as vLLM does. The health gate (WP-08) is off by default and is not
## asserted here: it needs an engine to be killed, which compose.fleet.yaml and a drill do, not a smoke run.
# The management port (8081) is never published and the JRE image has no curl, so the call is made from the tools container, which is on the
# compose network and has curl, as the reconcile call below is. Any inference-service replica will do: the states live in Valkey and every
# replica reads them once a second. The status goes to $dcode and the body to $BODY.
drain_call() {   # drain_call METHOD [JSON]
  local out
  out=$("${DC[@]}" exec -T tools curl -s -w '\n%{http_code}' -X "$1" -H 'Content-Type: application/json' ${2:+-d "$2"} http://inference:8081/actuator/drain)
  dcode=${out##*$'\n'}
  printf '%s' "${out%$'\n'*}" > "$BODY"
}
# drain_set REPLICA STATE [EXTRA JSON FIELDS]: POSTs the state for that replica of $M; expects 200 and the state in the answer.
drain_set() {
  drain_call POST "{\"model\":\"$M\",\"replica\":$1,\"state\":\"$2\"$3}"
  [[ $dcode == 200 ]] && grep -q "\"state\":\"$2\"" "$BODY" && echo "ok   200  replica $1 of $M is $2" \
    || { echo "FAIL replica $1 to $2 got '$dcode'"; head -c 300 "$BODY"; echo; note_fail; }
}
# The states live in Valkey and outlive this script. However it ends from here on (a Ctrl-C, a killed run, a docker call that fails), the
# replicas it drained are put back, or every client of the stack and the next run of this script are answered 503 engine_unavailable.
drained_by_smoke=0
undrain() {
  [[ $drained_by_smoke == 1 ]] || return 0
  local r
  for r in $(seq 0 $((${replicas:-1} - 1))); do
    "${DC[@]}" exec -T tools curl -s -o /dev/null -X POST -H 'Content-Type: application/json' \
      -d "{\"model\":\"$M\",\"replica\":$r,\"state\":\"READY\"}" http://inference:8081/actuator/drain || true
  done
}
longout=$(mktemp)
trap 'undrain; rm -f "$BODY" "$HDRS" "$longout"' EXIT
drain_call GET
replicas=$(grep -o "\"model\":\"$M\"" "$BODY" | wc -l | tr -d ' ')
[[ $dcode == 200 && ${replicas:-0} -ge 1 ]] && grep -q '"state":"READY"' "$BODY" && echo "ok   200  GET /actuator/drain lists $replicas replica(s) of $M, all READY" \
  || { echo "FAIL GET /actuator/drain got '$dcode', $replicas replica(s)"; head -c 300 "$BODY"; echo; note_fail; replicas=1; }
[[ ${FLEET:-0} == 1 && $replicas -lt 2 ]] && { echo "FAIL FLEET=1 but GET /actuator/drain lists $replicas replica(s) of $M"; note_fail; }
# Several replicas (compose.fleet.yaml): draining one leaves the rest serving.
if [[ $replicas -gt 1 ]]; then
  drained_by_smoke=1
  drain_set 0 DRAINING ',"grace":"60s"'
  sleep 2   # every inference-service replica refreshes its view of the states once a second
  expect 200 "${K2[@]}" "${J[@]}" -X POST "$G/v1/chat/completions" -d "$(chat 'Say hi.' 8)"
fi
# A stream is running when the drain starts: the long simulator answer (LONGP, about 22 s) outlives the drain call.
curl -sN --max-time 45 "${K2[@]}" "${J[@]}" -X POST "$G/v1/chat/completions" -d "$(chat "$LONGP" 1000 ',"stream":true,"temperature":0')" > "$longout" &
longpid=$!
sleep 3
drained_by_smoke=1
for r in $(seq 0 $((replicas - 1))); do drain_set "$r" DRAINING ',"grace":"60s"'; done
sleep 2
expect 503 -D "$HDRS" "${K2[@]}" "${J[@]}" -X POST "$G/v1/chat/completions" -d "$(chat 'Say hi.' 8)"
grep -q '"engine_unavailable"' "$BODY" && grep -qi '^retry-after:' "$HDRS" \
  && echo "ok   503  every replica drained: engine_unavailable with retry-after" \
  || { echo "FAIL the drained answer lacks engine_unavailable or retry-after"; head -c 300 "$BODY"; echo; note_fail; }
drain_call GET
grep -q '"drained":false' "$BODY" && echo "ok   the replica with the running stream is not drained yet" \
  || { echo "FAIL drained is true while a stream runs"; head -c 300 "$BODY"; echo; note_fail; }
wait "$longpid" || true
grep -qE '^data: ?\[DONE\]' "$longout" && echo "ok   the stream that was running when the drain began finished, [DONE] and all" \
  || { echo "FAIL the stream running at the drain was cut ($(grep -c '^data:' "$longout") events)"; note_fail; }
rm -f "$longout"
drained=0
for _ in $(seq 20); do
  drain_call GET
  drained=$(grep -o '{[^{}]*}' "$BODY" | grep "\"model\":\"$M\"" | grep -c '"drained":true')   # one object per replica, whatever the field order
  [[ $drained == "$replicas" ]] && break
  sleep 0.5
done
[[ $drained == "$replicas" ]] && echo "ok   drained is true on all $replicas replica(s) once the stream ended" || { echo "FAIL $drained of $replicas drained after the stream ended"; note_fail; }
for r in $(seq 0 $((replicas - 1))); do drain_set "$r" READY ''; done
drained_by_smoke=0
code=""
for _ in $(seq 10); do
  code=$(curl -s -o /dev/null -w '%{http_code}' "${K2[@]}" "${J[@]}" -X POST "$G/v1/chat/completions" -d "$(chat 'Say hi.' 8)")
  [[ $code == 200 ]] && break
  sleep 1
done
[[ $code == 200 ]] && echo "ok   200  READY restores service" || { echo "FAIL READY did not restore service (last status $code)"; note_fail; }

## Batch API: a JSONL file runs line by line at the lowest priority; the results come back as files
bline() { echo "{\"custom_id\":\"$1\",\"method\":\"POST\",\"url\":\"/v1/chat/completions\",\"body\":{\"model\":\"$M\",\"messages\":[{\"role\":\"user\",\"content\":\"Say hi.\"}],\"max_tokens\":$2}}"; }
input=$(mktemp)
{ bline one 8; bline two 8; bline too-long 5000; } > "$input"
expect 200 "${K2[@]}" -F purpose=batch -F "file=@-;filename=smoke.jsonl" "$G/v1/files" < "$input"   # stdin: no path translation on Windows
rm -f "$input"
input_id=$(json id)
expect 200 "${K2[@]}" "${J[@]}" -X POST "$G/v1/batches" -d "{\"input_file_id\":\"$input_id\",\"endpoint\":\"/v1/chat/completions\",\"completion_window\":\"24h\"}"
batch_id=$(json id)
status=""
for _ in $(seq 120); do
  curl -s -o "$BODY" "${K2[@]}" "$G/v1/batches/$batch_id"
  status=$(json status)
  [[ $status == completed ]] && break
  sleep 1
done
counts=$(sed -nE 's/.*"request_counts":\{([^}]*)\}.*/\1/p' "$BODY")
[[ $status == completed && $counts == '"total":3,"completed":2,"failed":1' ]] && echo "ok   batch completed: $counts" \
  || { echo "FAIL batch $status: $counts"; cat "$BODY"; note_fail; }
output_id=$(json output_file_id)
error_id=$(json error_file_id)
expect 200 "${K2[@]}" "$G/v1/files/$output_id/content"
[[ $(grep -c '"status_code":200' "$BODY") == 2 ]] && grep -q '"custom_id":"one"' "$BODY" || { echo "FAIL batch output"; cat "$BODY"; note_fail; }
expect 200 "${K2[@]}" "$G/v1/files/$error_id/content"
grep -q '"custom_id":"too-long".*"status_code":400' "$BODY" || { echo "FAIL batch error file"; cat "$BODY"; note_fail; }
batch_usage=""
for _ in $(seq 10); do
  batch_usage=$(sql "SELECT count(*) FROM usage.usage_event WHERE organization_id = '$org' AND mode = 'batch' AND status = 'ok'" | tr -d '\r')
  [[ $batch_usage == 2 ]] && break
  sleep 1
done
[[ $batch_usage == 2 ]] && echo "ok   usage: the 2 answered lines, mode=batch" || { echo "FAIL batch usage rows: $batch_usage"; note_fail; }
expect 404 "${K4[@]}" "$G/v1/batches/$batch_id"                       # another organization's batch
expect 404 "${K4[@]}" "$G/v1/files/$output_id/content"                 # and its files
expect 200 "${K2[@]}" -X DELETE "$G/v1/files/$input_id"
expect 404 "${K2[@]}" "$G/v1/files/$input_id"
# batch-line is batch-service's internal marker (batch prices, lowest priority): a client's copy is
# stripped by the gateway, so this malformed one never reaches inference-service (which would answer 400).
expect 200 "${K2[@]}" "${J[@]}" -H 'batch-line: forged' -X POST "$G/v1/chat/completions" -d "$(chat 'Say hi.' 8)"

## service_tier flex: a live request in the half-price lane (billed as mode batch); other tiers are refused
expect 200 -D "$HDRS" "${K2[@]}" "${J[@]}" -X POST "$G/v1/chat/completions" -d "$(chat 'Say hi.' 8 ',"service_tier":"flex"')"
flex_rid=$(sed -nE 's/^x-request-id: ([0-9a-f-]{36}).*/\1/ip' "$HDRS")
expect 400 "${K2[@]}" "${J[@]}" -X POST "$G/v1/chat/completions" -d "$(chat 'Say hi.' 8 ',"service_tier":"priority"')"
flex_mode=""
for _ in $(seq 20); do
  flex_mode=$(sql "SELECT mode FROM usage.usage_event WHERE request_id = '$flex_rid'" | tr -d '\r')
  [[ -n $flex_mode ]] && break
  sleep 0.5
done
[[ $flex_mode == batch ]] && echo "ok   the flex request is billed in the half-price lane (mode batch)" \
  || { echo "FAIL flex request usage mode '$flex_mode'"; note_fail; }

## Canary: sync prompts and keys never reach a log, the database or Valkey's file (batch files are stored on purpose, 30 days)
canary="CANARY-$RANDOM$RANDOM"
expect 200 "${K2[@]}" "${J[@]}" -X POST "$G/v1/chat/completions" -d "$(chat "Repeat exactly: $canary" 16)"
curl -sN "${K2[@]}" "${J[@]}" -X POST "$G/v1/chat/completions" -d "$(chat "Repeat exactly: $canary" 16 ',"stream":true')" >/dev/null
expect 400 "${K2[@]}" "${J[@]}" -X POST "$G/v1/chat/completions" -d "{\"model\":\"$M\",\"messages\":\"$canary"
big=$(mktemp)
chat "$canary $(head -c 70000 /dev/zero | tr '\0' x)" 8 > "$big"
code=$(curl -s -o /dev/null -w '%{http_code}' "${K2[@]}" "${J[@]}" -X POST "$G/v1/chat/completions" --data-binary @"$big")
rm -f "$big"
[[ $code == 413 ]] && echo "ok   413  over-context prompt" || { echo "FAIL over-context prompt got $code"; note_fail; }
curl -sN --max-time 1 "${K2[@]}" "${J[@]}" -X POST "$G/v1/chat/completions" -d "$(chat "$canary Write a long story." 500 ',"stream":true')" >/dev/null || true
expect 400 "${K2[@]}" "$G/v1/models?api_key=cmn_test_$canary"
sleep 2   # let batches and logs flush
access_log() { MSYS_NO_PATHCONV=1 "${DC[@]}" exec -T gateway sh -c 'cat /var/log/carmona/access.log'; }
valkey_file() { MSYS_NO_PATHCONV=1 "${DC[@]}" exec -T valkey sh -c 'cat /data/appendonlydir/*'; }
leaks=$( { "${DC[@]}" logs --no-color 2>&1; "${DC[@]}" exec -T db sh -c 'pg_dumpall -U "$POSTGRES_USER"'; access_log; valkey_file; } \
  | grep -acF -e "$canary" -e "Bearer " -e "$key2" -e "api_key=" -e "${keep#*=}" || true)
[[ $leaks == 0 ]] && echo "ok   the canary, bearer headers, the API key and query strings are in no log (access log included), nowhere in the database and nowhere in Valkey's file" \
  || { echo "FAIL $leaks lines leak the canary, a bearer header, the key or a query string"; note_fail; }
# Marco Civil access log: the request above, with its ids, in the gateway's own file (not on stdout).
grep -q "$rid" <(access_log) && grep "$rid" <(access_log) | grep -q "\"organization_id\":\"$org\"" \
  && echo "ok   access log: request $rid with its organization and key" || { echo "FAIL request $rid not in the access log"; note_fail; }
"${DC[@]}" logs --no-color gateway 2>&1 | grep -q "$rid" && { echo "FAIL the access log reached stdout"; note_fail; }
[[ $(sql "SELECT count(*) FROM usage.usage_event WHERE request_id = '$rid'" | tr -d '\r') == 1 ]] \
  && echo "ok   usage event carries the same request id" || { echo "FAIL usage has no event for $rid"; note_fail; }

## Money: sealed usage windows are billed, and a used-up balance gets 402 until credit is added
balance=""
for _ in $(seq 60); do
  balance=$(sql "SELECT amount FROM billing.balance WHERE organization_id = '$org'" | tr -d '\r')
  [[ -n $balance && $balance -lt 10000000 ]] && break
  sleep 1
done
[[ -n $balance && $balance -lt 10000000 ]] && echo "ok   usage billed: R\$10 credit is now $balance micro-BRL" \
  || { echo "FAIL the usage was not billed (balance '$balance')"; note_fail; }
same=$(sql "SELECT (SELECT amount FROM billing.balance WHERE organization_id = '$org') = (SELECT sum(amount) FROM billing.ledger_entry WHERE organization_id = '$org')" | tr -d '\r')
[[ $same == t ]] && echo "ok   balance = sum of the ledger" || { echo "FAIL balance differs from the ledger"; note_fail; }

## Visible money: a member reads the organization's own balance, usage summary and the books check; another
## account and a headerless caller read nothing. The gateway routes for the first two are task C's (see the
## reference): until they exist these endpoints are reachable inside the network only, which is what this does.
## The balance is bracketed: a debit landing between the two reads must not make this fail (it only falls).
before=$(sql "SELECT amount FROM billing.balance WHERE organization_id = '$org'" | tr -d '\r')
visible=$("${DC[@]}" exec -T tools curl -s -H "id-account: $id" "http://billing:8080/billing/organizations/$org/balance" | tr -d '\r')
after=$(sql "SELECT amount FROM billing.balance WHERE organization_id = '$org'" | tr -d '\r')
shown=$(sed -nE 's/.*"amountMicroBrl":(-?[0-9]+).*/\1/p' <<<"$visible")
[[ -n $shown && $shown -le $before && $shown -ge $after && $visible == *'"noCredit":false'* ]] \
  && echo "ok   200  a member reads the balance, the ledger's own number: $visible" \
  || { echo "FAIL visible balance '$visible' is outside [$after, $before]"; note_fail; }
code=$(internal -H "id-account: $other" "http://billing:8080/billing/organizations/$org/balance")
[[ $code == 404 ]] && echo "ok   404  another account reads no balance" || { echo "FAIL a non-member got $code"; note_fail; }
code=$(internal "http://billing:8080/billing/organizations/$org/balance")
[[ $code == 401 ]] && echo "ok   401  no id-account, no numbers" || { echo "FAIL a headerless call got $code"; note_fail; }
from=$(date -u -d '-2 hours' +%Y-%m-%dT%H:%M:%SZ)
to=$(date -u -d '+1 hour' +%Y-%m-%dT%H:%M:%SZ)
summary=$("${DC[@]}" exec -T tools curl -s -H "id-account: $id" "http://usage:8080/usage/organizations/$org/summary?from=$from&to=$to" | tr -d '\r')
grep -qE '"costMicroBrl":[0-9]+' <<<"$summary" && echo "ok   200  a member reads their own usage, priced: $summary" \
  || { echo "FAIL usage summary '$summary'"; note_fail; }
code=$(internal -H "id-account: $other" "http://usage:8080/usage/organizations/$org/summary?from=$from&to=$to")
[[ $code == 404 ]] && echo "ok   404  another account reads no usage" || { echo "FAIL a non-member got $code"; note_fail; }
code=$(internal "http://billing:8081/actuator/reconcile")
[[ $code == 200 ]] && echo "ok   200  the books are checked on demand (management port, internal)" || { echo "FAIL reconcile got $code"; note_fail; }

# A second organization gets 1 micro-BRL: one chat uses it up, then /v1 answers 402 until a grant.
expect 201 "${A[@]}" "${J[@]}" -X POST "$G/organizations" -d '{"name":"Smoke Tiny"}'
tiny=$(json id)
expect 201 "${A[@]}" "${J[@]}" -X POST "$G/organizations/$tiny/api-keys" -d '{"name":"tiny"}'
K3=(-H "Authorization: Bearer $(json key)")
code=$(grant "$tiny" 1 tiny-start)
[[ $code == 200 ]] || { echo "FAIL tiny grant got $code"; note_fail; }
expect 200 "${K3[@]}" "${J[@]}" -X POST "$G/v1/chat/completions" -d "$(chat 'Write two sentences about the sea.' 64)"
code=""
for _ in $(seq 60); do
  code=$(curl -s -o "$BODY" -w '%{http_code}' "${K3[@]}" "$G/v1/models")
  [[ $code == 402 ]] && break
  sleep 1
done
[[ $code == 402 ]] && grep -q '"insufficient_balance"' "$BODY" && echo "ok   402  balance used up, /v1 refused" \
  || { echo "FAIL expected 402 after the balance ran out, got $code"; cat "$BODY"; note_fail; }
code=$(grant "$tiny" 1000000 tiny-topup)
[[ $code == 200 ]] || { echo "FAIL top-up grant got $code"; note_fail; }
expect 200 "${K3[@]}" "$G/v1/models"                                 # credit back: allowed at once

## Any model by settings (round AM): the listing tells a client what the model takes, a reasoning level the model does not list is ignored (an SDK
## sends the field whether or not the model thinks, so a 400 would break it), and the usage summary has a place for the reasoning tokens. The sizes are
## this stack's own (compose.yaml: CARMONA_INFERENCE_MODELS_0_CONTEXTWINDOW and _MAXOUTPUT); against a model with other settings, say them:
## MODEL=... CONTEXT_WINDOW=... MAX_OUTPUT=... bash smoke.sh. The model of this stack lists no reasoning level, which the second check needs.
want_window=${CONTEXT_WINDOW:-4096}
want_output=${MAX_OUTPUT:-1024}
expect 200 "${K2[@]}" "$G/v1/models"
entry=$(grep -o '{[^{}]*}' "$BODY" | grep "\"id\":\"$M\"")   # one object per model, whatever the field order
if grep -q "\"context_window\":$want_window[,}]" <<<"$entry" && grep -q "\"max_output_tokens\":$want_output[,}]" <<<"$entry"; then
  echo "ok   the listing shows $M with context_window $want_window and max_output_tokens $want_output"
else
  echo "FAIL the listing shows '$entry' for $M, not context_window $want_window and max_output_tokens $want_output"; note_fail
fi
expect 200 "${K2[@]}" "${J[@]}" -X POST "$G/v1/chat/completions" -d "$(chat 'Say hi.' 8 ',"reasoning_effort":"high"')"
# The summary rows of the organization (the window of the money section above): each has the key, a number or null, never left out.
summary=$("${DC[@]}" exec -T tools curl -s -H "id-account: $id" "http://usage:8080/usage/organizations/$org/summary?from=$from&to=$to" | tr -d '\r')
rows=$(grep -o '"group":' <<<"$summary" | wc -l | tr -d ' ')
keyed=$(grep -oE '"reasoningTokens":(null|[0-9]+)' <<<"$summary" | wc -l | tr -d ' ')
[[ $rows -ge 1 && $rows == "$keyed" ]] && echo "ok   200  the usage summary's $rows row(s) all carry reasoningTokens" \
  || { echo "FAIL $keyed of $rows usage summary rows carry reasoningTokens: $summary"; note_fail; }

## A model registered while the stack runs (round AM, step B). model-service keeps the list behind internal calls (the shared secret, no gateway
## route), inference-service follows it, a model registered for an organization is listed and callable by that organization's keys only, and what an
## organization runs on its own model is metered and never charged per token. The engine is the stand-in for a rented GPU: a second simulator
## (compose.yaml, engine-own) that this section starts, because the simulator answers 404 to a model name it does not serve and the name of an
## organization's own model holds the organization's id, which exists only now. A run that is killed here leaves it: `docker compose --profile own-engine
## down` removes it. The two organizations are new, so that the balance asserted is exactly the credit granted. inference-service reads the list every
## few seconds (carmona.inference.registry.refresh-every, 5 s), so each wait below polls.
# registry METHOD PATH [JSON]: a call to model-service from the tools container with the shared secret; the status goes to $rcode, the body to $BODY.
registry() {
  local out
  out=$(MSYS_NO_PATHCONV=1 "${DC[@]}" exec -T tools curl -s -w '\n%{http_code}' -H @/run/secrets/internal_token -H 'Content-Type: application/json' -X "$1" ${3:+-d "$3"} "http://model:8080$2")
  rcode=${out##*$'\n'}
  printf '%s' "${out%$'\n'*}" > "$BODY"
}
# registry_want STATUS METHOD PATH [JSON]: the same call, asserted.
registry_want() {
  local want=$1; shift
  registry "$@"
  if [[ $rcode == "$want" ]]; then echo "ok   $want  $1 $2 on model-service"; else echo "FAIL want $want got $rcode: $1 $2 on model-service"; head -c 300 "$BODY"; echo; note_fail; fi
}
# chat_for MODEL CONTENT MAX_TOKENS: a chat request body for any model.
chat_for() { echo "{\"model\":\"$1\",\"messages\":[{\"role\":\"user\",\"content\":\"$2\"}],\"max_tokens\":$3}"; }
# wait_status STATUS KEY_ARRAY_NAME MODEL: polls a chat to MODEL with the key until it answers STATUS, at most 40 s; the last status is left in $code.
wait_status() {
  local -n hdr=$2
  code=""
  for _ in $(seq 40); do
    code=$(curl -s -o "$BODY" -w '%{http_code}' "${hdr[@]}" "${J[@]}" -X POST "$G/v1/chat/completions" -d "$(chat_for "$3" 'Say hi.' 8)")
    [[ $code == "$1" ]] && break
    sleep 1
  done
}
if [[ $ENGINE != sim ]]; then
  echo "skip  the registered-model section starts a simulator engine: it runs with ENGINE=sim only"
else
  # A new account owns the two organizations: the first one is at the most organizations an account may own (carmona.organization.max-organizations-per-account). account() sets
  # token, email and rt, which the sections after this one still read as the first account's, so they are put back.
  saved_token=$token; saved_email=$email; saved_rt=$rt
  account
  OT=(-H "Authorization: Bearer $token")
  token=$saved_token; email=$saved_email; rt=$saved_rt
  expect 200 "${OT[@]}" "$G/auth/whoami"
  oid=$(json id)
  expect 201 "${OT[@]}" "${J[@]}" -X POST "$G/organizations" -d '{"name":"Smoke Owner"}'
  oa=$(json id)
  sql "UPDATE organizations.organization SET tier = 'enterprise' WHERE id = '$oa'" >/dev/null   # a short wait for the one slot instead of an instant refusal
  expect 201 "${OT[@]}" "${J[@]}" -X POST "$G/organizations/$oa/api-keys" -d '{"name":"owner"}'
  KOA=(-H "Authorization: Bearer $(json key)")
  expect 201 "${OT[@]}" "${J[@]}" -X POST "$G/organizations" -d '{"name":"Smoke Neighbour"}'
  ob=$(json id)
  expect 201 "${OT[@]}" "${J[@]}" -X POST "$G/organizations/$ob/api-keys" -d '{"name":"neighbour"}'
  KOB=(-H "Authorization: Bearer $(json key)")
  [[ $(grant "$oa" 5000000 own-owner-start) == 200 && $(grant "$ob" 5000000 own-neighbour-start) == 200 ]] || { echo "FAIL the credit grants of the registered-model section"; note_fail; }
  OM="org-$oa/smoke-echo"
  regkey="CANARY-engine-key-$RANDOM$RANDOM$RANDOM"   # the engine's key as the registering tool states it; the simulator takes any
  entry="{\"modelId\":\"$OM\",\"ownerOrganizationId\":\"$oa\",\"apiKey\":\"$regkey\",\"spec\":{\"contextWindow\":4096,\"maxOutput\":1024,\"replicas\":[{\"url\":\"http://engine-own:8000\"}]}}"

  OWN_ENGINE_MODEL=$OM "${DCO[@]}" up -d --no-deps engine-own >/dev/null 2>&1 || { echo "FAIL the simulator for $OM did not start"; note_fail; }
  up=""
  for _ in $(seq 30); do
    up=$("${DC[@]}" exec -T tools curl -s -m 2 -o /dev/null -w '%{http_code}' http://engine-own:8000/metrics)
    [[ $up == 200 ]] && break
    sleep 1
  done
  [[ $up == 200 ]] && echo "ok   200  the simulator that serves $OM answers" || { echo "FAIL the simulator that serves $OM answered '$up'"; note_fail; }

  # The secret: without it, or with a made-up one, nothing is registered and nothing is listed (the list holds every engine key).
  code=$("${DC[@]}" exec -T tools curl -s -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' -X POST http://model:8080/models -d "$entry")
  [[ $code == 401 ]] && echo "ok   401  registering a model without the internal secret is refused" || { echo "FAIL registering without the secret got $code"; note_fail; }
  code=$("${DC[@]}" exec -T tools curl -s -o /dev/null -w '%{http_code}' -H 'X-Internal-Token: 0000000000000000000000000000000000000000000000000000000000000000' -H 'Content-Type: application/json' -X POST http://model:8080/models -d "$entry")
  [[ $code == 401 ]] && echo "ok   401  registering a model with a wrong internal secret is refused" || { echo "FAIL registering with a wrong secret got $code"; note_fail; }
  code=$("${DC[@]}" exec -T tools curl -s -o /dev/null -w '%{http_code}' http://model:8080/models/active)
  [[ $code == 401 ]] && echo "ok   401  the list of active models, which holds the engine keys, is refused without the internal secret" || { echo "FAIL the list without the secret got $code"; note_fail; }

  # Register: a new entry is 201 and shows the placeholders for a replica that named no slots and no queue (one slot, no queue), and no key.
  registry_want 201 POST /models "$entry"
  entry_id=$(json id)
  if grep -q '"slots":1' "$BODY" && grep -q '"queue":0' "$BODY" && ! grep -q "$regkey" "$BODY"; then
    echo "ok   the entry shows slots 1 and queue 0 for a replica that named none, and no key"
  else
    echo "FAIL the 201 body is not the entry with slots 1, queue 0 and no key"; head -c 400 "$BODY"; echo; note_fail
  fi
  registry_want 200 POST /models "$entry"                                              # the same content again: the same entry
  [[ $(json id) == "$entry_id" ]] && echo "ok   the replay is the same entry" || { echo "FAIL the replay is another entry"; note_fail; }
  registry_want 422 POST /models "${entry/\"contextWindow\":4096/\"contextWindow\":2048}"   # other content for an active id
  grep -q '"idempotency_conflict"' "$BODY" || { echo "FAIL the refusal of other content is not idempotency_conflict"; head -c 300 "$BODY"; echo; note_fail; }
  registry_want 200 GET "/models/$entry_id"
  if grep -q "\"modelId\":\"$OM\"" "$BODY" && ! grep -qi 'apikey' "$BODY" && ! grep -q "$regkey" "$BODY"; then
    echo "ok   reading the entry shows its model id and no key"
  else
    echo "FAIL reading the entry shows no model id or shows a key"; head -c 300 "$BODY"; echo; note_fail
  fi

  # Visibility: inference-service follows the list, and only the owner's keys see the model.
  listed=""
  for _ in $(seq 40); do
    curl -s -o "$BODY" "${KOA[@]}" "$G/v1/models"
    grep -q "\"id\":\"$OM\"" "$BODY" && { listed=1; break; }
    sleep 1
  done
  [[ -n $listed ]] && echo "ok   200  the model is listed for the organization that owns it" || { echo "FAIL $OM is not listed for its owner after 40 s"; head -c 300 "$BODY"; echo; note_fail; }
  expect 200 "${KOA[@]}" "$G/v1/models/$OM"
  wait_status 200 KOA "$OM"
  if [[ $code == 200 ]] && grep -q '"usage"' "$BODY"; then echo "ok   200  the owner's key chats with $OM on its own engine"; else echo "FAIL the owner's chat with $OM got '$code'"; head -c 300 "$BODY"; echo; note_fail; fi
  expect 200 "${KOB[@]}" "$G/v1/models"
  if grep -q "$OM" "$BODY"; then echo "FAIL the other organization's listing shows $OM"; note_fail; else echo "ok   the other organization's listing does not show it"; fi
  expect 404 "${KOB[@]}" "$G/v1/models/$OM"
  expect 404 "${KOB[@]}" "${J[@]}" -X POST "$G/v1/chat/completions" -d "$(chat_for "$OM" 'Say hi.' 8)"
  grep -q '"model_not_found"' "$BODY" || { echo "FAIL the other organization's chat is not the unknown-model answer"; head -c 300 "$BODY"; echo; note_fail; }

  # Money: the owner's use is metered and costs nothing. Wait until the usage is sealed into a window and the debit job has gone past it, then read:
  # no ledger entry besides the grant, the balance as granted, nothing set aside as unpriced, and no "no price" error in billing's log.
  sealed=""
  for _ in $(seq 60); do
    sealed=$(sql "SELECT max(window_start) FROM usage.usage_window WHERE organization_id = '$oa' AND model = '$OM'" | tr -d '\r')
    [[ -n $sealed ]] && break
    sleep 1
  done
  passed=""
  for _ in $(seq 60); do
    [[ -n $sealed ]] && passed=$(sql "SELECT last_window_start >= '$sealed' FROM billing.billing_cursor" | tr -d '\r')
    [[ $passed == t || -z $sealed ]] && break
    sleep 1
  done
  [[ -n $sealed && $passed == t ]] && echo "ok   the usage of $OM was sealed into a window and the debit job has gone past it" \
    || { echo "FAIL the usage window of $OM was not sealed or not passed by billing (sealed '$sealed', passed '$passed')"; note_fail; }
  balance=$(sql "SELECT amount FROM billing.balance WHERE organization_id = '$oa'" | tr -d '\r')
  charged=$(sql "SELECT count(*) FROM billing.ledger_entry WHERE organization_id = '$oa' AND type <> 'grant'" | tr -d '\r')
  unpriced=$(sql "SELECT count(*) FROM billing.unpriced_charge WHERE organization_id = '$oa'" | tr -d '\r')
  noprice=$("${DC[@]}" logs --no-color billing 2>&1 | grep -c "no price for $OM" || true)
  if [[ $balance == 5000000 && $charged == 0 && $unpriced == 0 && $noprice == 0 ]]; then
    echo "ok   the owner's own model cost nothing: balance $balance as granted, no ledger entry, nothing set aside, no 'no price' error"
  else
    echo "FAIL the owner's own model was charged or set aside: balance '$balance', $charged ledger entries, $unpriced set aside, $noprice 'no price' log lines"; note_fail
  fi
  summary=$("${DC[@]}" exec -T tools curl -s -H "id-account: $oid" "http://usage:8080/usage/organizations/$oa/summary?from=$from&to=$to" | tr -d '\r')
  row=$(grep -o '{[^{}]*}' <<<"$summary" | grep "\"group\":\"$OM\"" || true)
  if grep -q '"costMicroBrl":0[,}]' <<<"$row" && grep -qE '"outputTokens":[1-9]' <<<"$row"; then
    echo "ok   200  the usage summary shows $OM with its tokens and cost 0"
  else
    echo "FAIL the usage summary row of $OM is '$row'"; note_fail
  fi

  # No route: the registry's calls are internal, so the gateway answers 404 to a console token on every one of them (with an invented secret as well:
  # the gateway strips the header and holds no secret).
  expect 404 "${OT[@]}" "$G/models/active"
  expect 404 "${OT[@]}" "$G/models/$entry_id"
  expect 404 "${OT[@]}" "${J[@]}" -H "X-Internal-Token: $(printf '0%.0s' {1..64})" -X POST "$G/models" -d '{}'

  # Retire: the owner's key gets the unknown-model answer within a read, the entry stays as a retired one, and the same id registers again: a GPU rented
  # for part of the day comes back under its name.
  registry_want 204 DELETE "/models/$entry_id"
  registry_want 204 DELETE "/models/$entry_id"                                         # again: still 204, nothing changes
  wait_status 404 KOA "$OM"
  [[ $code == 404 ]] && grep -q '"model_not_found"' "$BODY" && echo "ok   404  after the retire the owner's key gets the unknown-model answer" \
    || { echo "FAIL after the retire the owner's chat got '$code'"; head -c 300 "$BODY"; echo; note_fail; }
  expect 404 "${KOA[@]}" "$G/v1/models/$OM"
  registry_want 200 GET "/models/$entry_id"
  grep -q '"status":"retired"' "$BODY" || { echo "FAIL the entry is not shown as retired"; head -c 300 "$BODY"; echo; note_fail; }
  registry_want 201 POST /models "$entry"
  [[ $(json id) == "$entry_id" ]] && echo "ok   the retired id registered again as the same entry" || { echo "FAIL the retired id registered again as another entry"; note_fail; }
  wait_status 200 KOA "$OM"
  [[ $code == 200 ]] && echo "ok   200  the owner's key chats with $OM again" || { echo "FAIL the owner's chat after the second registration got '$code'"; head -c 300 "$BODY"; echo; note_fail; }

  # The engine key of the model never reaches a log or the database in clear (the simulator is still up, so its log is read too).
  leaks=$( { "${DC[@]}" logs --no-color 2>&1; "${DC[@]}" exec -T db sh -c 'pg_dumpall -U "$POSTGRES_USER"'; } | grep -acF -e "$regkey" || true)
  [[ $leaks == 0 ]] && echo "ok   the engine key of the registered model is in no log and not in the database in clear" || { echo "FAIL $leaks lines hold the engine key of the registered model"; note_fail; }

  # Closing the organization retires the models it owns (the sweep of model-service, 5 s here), so no address or key outlives the customer.
  expect 204 "${OT[@]}" -X DELETE "$G/organizations/$oa"
  expect 204 "${OT[@]}" -X DELETE "$G/organizations/$ob"
  swept=""
  for _ in $(seq 40); do
    registry GET "/models/$entry_id"
    grep -q '"status":"retired"' "$BODY" && { swept=1; break; }
    sleep 1
  done
  [[ -n $swept ]] && echo "ok   closing the organization retired the model it owned" || { echo "FAIL the model of a closed organization is still active after 40 s"; note_fail; }
  "${DCO[@]}" rm -sf engine-own >/dev/null 2>&1 || true
fi

## LGPD access: the account and its organizations, to its owner only
expect 200 "${A[@]}" "$G/accounts/$id/export"
grep -q "\"email\":\"$email\"" "$BODY" && grep -q "\"id\":\"$org\"" "$BODY" && ! grep -qi 'password' "$BODY" \
  || { echo "FAIL export content"; cat "$BODY"; note_fail; }

## Someone else's organization is invisible to a stranger
first_token=$token
first_email=$email
account
S=(-H "Authorization: Bearer $token")
expect 404 "${S[@]}" "$G/organizations/$org"
expect 404 "${S[@]}" "${J[@]}" -X POST "$G/organizations/$org/api-keys" -d '{"name":"x"}'
expect 404 "${S[@]}" -X DELETE "$G/organizations/$org"
expect 403 "${S[@]}" "$G/accounts/$id/export"

## Password reset: always 202; the link sets a new password and ends every session of the account
expect 202 "${J[@]}" -X POST "$G/accounts/password-reset" -d '{"email":"nobody-at-all@example.com"}'
expect 202 "${J[@]}" -X POST "$G/accounts/password-reset" -d "{\"email\":\"$email\"}"
expect 204 "${J[@]}" -X POST "$G/accounts/password-reset/confirm" \
  -d "{\"token\":\"$(mail_token "$email" reset-password)\",\"password\":\"a-new-smoke-passphrase\"}"
expect 401 -X POST "$G/auth/refresh" -H "Cookie: $rt"                    # the stranger's session ended
expect 401 "${J[@]}" -X POST "$G/auth/login" -d "{\"email\":\"$email\",\"password\":\"$pass\"}"
expect 200 "${J[@]}" -X POST "$G/auth/login" -d "{\"email\":\"$email\",\"password\":\"a-new-smoke-passphrase\"}"
token=$first_token

## Erasure waits until no open organization would be left without an owner
expect 409 "${A[@]}" -X DELETE "$G/accounts/$id"
expect 204 "${A[@]}" -X DELETE "$G/organizations/$org"               # close all three
expect 204 "${A[@]}" -X DELETE "$G/organizations/$tiny"
expect 204 "${A[@]}" -X DELETE "$G/organizations/$corp"
# Closing deletes the organization's batch files (the batch section left its output and error files).
files=""
for _ in $(seq 30); do
  files=$(sql "SELECT count(*) FROM batch.file WHERE organization_id = '$org'" | tr -d '\r')
  [[ $files == 0 ]] && break
  sleep 1
done
[[ $files == 0 ]] && echo "ok   closing the organization erased its batch files" || { echo "FAIL $files batch files left after closing"; note_fail; }
expect 204 "${A[@]}" -X DELETE "$G/accounts/$id"
expect 401 -X POST "$G/auth/refresh" -H "Cookie: $keep"                  # its sessions ended with it
expect 404 "${A[@]}" "$G/accounts/$id"
expect 401 "${J[@]}" -X POST "$G/auth/login" -d "{\"email\":\"$first_email\",\"password\":\"$pass\"}"   # erased: gone

codes=$(for _ in $(seq 40); do curl -s -o /dev/null -w '%{http_code}\n' "${J[@]}" -X POST "$G/auth/login" -d '{}'; done)
grep -q 429 <<<"$codes" && echo "ok   429  burst of 40 logins is rate limited" || { echo "FAIL no 429 in burst"; note_fail; }

echo "smoke finished: $NFAIL failed, $NSKIP skip-sim"
[[ $NFAIL == 0 ]] && echo "smoke passed" || exit 1
