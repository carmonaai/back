# Observability: metrics, dashboards, alerts

Built 2026-10-05 (task B). Prometheus scrapes every service's management port and the engine's own
`/metrics`; Grafana provisions its datasource, three dashboards and its list of alert rules from files in
`docker/`. Nothing is clicked into a container, and nothing that matters is published: metrics stay on the
internal compose network, like the management port they come from (override 6).

**Updated 2026-10-15 for pass 2 and the MVP backend.** The engine is the simulated engine (job `engine`) or vLLM (job `vllm`); there is no llama.cpp job, panel or rule any more (ADR 0002). `inference` and `gateway` are scraped replica by replica through DNS service discovery. The `carmona_*` contract below is published (the three money gauges came with pass 2). The alert list is the twenty-one alerts of `docker/prometheus/rules.yml` (33 rules with the twelve recording rules; 2026-10-23: the OPEN-15 alerts, the queue-wait and queue-places fixes, and one alert for each new signal of the DeepInfer packages WP-03, WP-07, WP-08 and WP-09B; 2026-10-24: the prompt cache hit ratio, `PromptCacheHitRatioLow` and the four `prompt_cache:` records, throughput item P0-1b). What this page does not claim: a scrape of a running stack after 2026-10-05; the checks since then are `docker/check-prometheus.sh` (config valid, 33 rules, `promtool test rules` with 97 promtool cases, the four DNS-discovered jobs) and `docker/check-fleet-targets.sh` (the live replica count). None of the alerts or metrics added since 2026-10-15 has been seen on a running stack or a real engine: the rules are tested against hand-made series, the metric names were read from the Java. The prompt cache thresholds (0.30, 300000 tokens, 15 m) are placeholders that Day A tunes.

The gaps are in §Gaps, named rather than papered over. An empty panel on a dashboard that says so is a
finding; a substitute metric that animates is a lie.

## What runs

| Container | Image | Job | Limits |
|---|---|---|---|
| `prometheus` | `prom/prometheus:v3.15.0` (digest-pinned) | scrape every 15 s, evaluate rules every 60 s, 15 days of local TSDB | 512m / 0.5 cpu |
| `grafana` | `grafana/grafana:13.2.3` (digest-pinned) | provisioned datasource, three dashboards, the Prometheus alert list | 384m / 0.5 cpu |

- Scrape interval **15 s**. The plan's 1 s pipeline belongs to multi-replica autoscaling (§7) and is not
  built; 15 s is the resolution at which an incident is still visible and the VM stays cheap.
- Files: `docker/prometheus/{prometheus.yml,rules.yml}` (mounted read-only), `docker/grafana/provisioning/`
  and `docker/grafana/dashboards/` (read-only, `allowUiUpdates: false` — a change made in the browser would
  not survive the next container restart, so it is not allowed to look like it did).
- Grafana's admin password comes from `GRAFANA_ADMIN_PASSWORD` in `.env`, with no default: compose refuses
  to start without it. Grafana runs as its image's own non-root user (472).
- The engine jobs send `bearer_token_file: /tmp/engine-key` (the simulator ignores it, vLLM does not guard `/metrics`
  with `--api-key`, a future engine may). Prometheus expands no environment variable in a scrape config, so the
  container entrypoint writes the key from the environment to that file and then execs prometheus. The key is never
  in a repo file.
- The jobs: one per service on `<service>:8081/actuator/prometheus`; `inference` and `gateway` through `dns_sd_configs`
  (one target and one `instance` per replica); `engine` (the simulator, `:8000/metrics`) and `vllm` (the GPU overlay,
  and later the rented GPU's static target) likewise; `prometheus` itself. The engine job that has no container has no
  series and no alert, never a DOWN target.

## SLIs, SLOs, and where every number comes from

| SLI | SLO | Source of the number |
|---|---|---|
| TTFT p95, streamed | ≤ 2 s | Phase-3 bench goodput definition (TTFT ≤ 2 s and TPOT ≤ 100 ms); plan §8 |
| TTFT goodput (share within 2 s) | ≥ 95% | Phase-4/5 exit check ("enterprise goodput ≥ 95%") |
| Inter-token latency (TPOT) p95 | ≤ 100 ms | Phase-3 bench (measured 24 ms at C = 4) |
| Engine queue depth | full when the waiting requests reach the queue places inference-service admits (`carmona_engine_queue_places`, 2 per replica behind 4 slots) | `EngineQueueSustained`. vLLM's `--max-num-queued-reqs` counts running + waiting, so it is slots + places (6 in `compose.gpu.yaml`); the simulator's own `--max-waiting-queue-length=8` counts waiting only and never fills behind admission |
| Error share (inference) | ≤ 5% over 5 m | Same 5% as the goodput target above |
| Refusals on paying tiers (429) | ≤ 5% over 5 m | Phase-4/5 exit check, enterprise goodput ≥ 95% |
| Service reachability | every target UP; `up == 0` for 2 m alerts | This stack. No numeric availability SLO exists yet (plan §8 leaves it per model class) |
| Reconciliation (engine counters vs stored usage) | any disagreement | `Reconciler`: more than max(0.5%, (slots + queue) × context) |
| Usage ingestion | ≥ 1 stored event per served `/v1` request | Every answered request is billable |
| Metering lag (seal and debit) | seal lag ≤ grace + seal-every (120 s at the defaults), debit lag ≤ grace + seal-every + debit-every (180 s) | `Overshoot` in the `billing` library: the 8-minute overshoot bound minus the 5-minute window. `SealLagHigh` (180 s) and `DebitLagHigh` (300 s) alert above them; `LagGaugeMissing` when a live service reports no gauge |
| Prompt cache hit ratio | no SLO yet; `PromptCacheHitRatioLow` alerts under 0.30 over 30 m with at least 300000 measured prompt tokens (placeholders until Day A) | Capacity per card goes with 1 / (1 − hit ratio): for 32000-token requests, 75 an hour per customer, on one RTX 8000, about 3 customers at 0, 7 at 0.6 and 30 at 0.9 [CALC, pending Day A]. The only request-level measure of it is `carmona_inference_prompt_cache_tokens_total` |
| Per-service RED latency | no SLO | Plan §8 sets SLOs per model class on the inference path, not per internal service |

No number above was invented for this stack: each is the one the code, the compose file or a recorded bench
already uses. If a target looks wrong, it is wrong in the same place it was before — say so there.

## The metric contract (inference-service, usage-service and billing-service publish it; this stack consumes it)

Status on 2026-10-05, measured against the running CPU stack of that day: every `carmona_*` metric was absent
and the SLO panels were empty. The code publishes them now: the inference ones since 2026-10-06 (`Metrics`), the
engine ones with the scaling signals of pass 2, the three money gauges with pass 2 (`UsageGauges`,
`BillingGauges`). Names and tags below were read from that code on 2026-10-15; they were not measured on a running
stack.

| Metric | Tags | Published |
|---|---|---|
| `carmona_inference_ttft_seconds` (explicit `le` buckets 0.05…30 s) | `model`, `tier` | yes, inference-service (2026-10-06) |
| `carmona_inference_itl_seconds` (0.005…5 s) | `model`, `tier` | yes |
| `carmona_inference_queue_wait_seconds` (0.005…10 s) | `model`, `tier` | yes |
| `carmona_inference_request_seconds` (0.05…600 s) | `model`, `tier` | yes |
| `carmona_inference_requests_total` | `model`, `tier`, `outcome`, `code` | yes |
| `carmona_inference_tokens_total` | `model`, `mode`, `kind` | yes |
| `carmona_inference_inflight` | `model` | yes |
| `carmona_inference_capacity` | `model`, `tier` | yes |
| `carmona_inference_lease_store_unavailable` (1 while this replica admits on its own share because Valkey is away) | none | yes (pass 2) |
| `carmona_engine_requests_running` / `_waiting` / `_cache_usage` / `_tokens_in_flight` (aggregate `_tokens_in_flight` with `max`, every inference replica reports the fleet's number) | `model`, `replica` | yes (pass 2: `replica` is the engine replica's place in the model's list) |
| `carmona_engine_prefix_cache_hit_ratio` | `model` | yes (pass 2) |
| `carmona_inference_reconcile_mismatch` (1 = engine counters and stored usage disagree, 0 = agree; absent until two readings exist) | `model` | yes |
| `carmona_usage_seal_lag_seconds` | none | yes, usage-service (pass 2) |
| `carmona_billing_debit_lag_seconds` | none | yes, billing-service (pass 2) |
| `carmona_billing_no_credit_organizations` | none | yes, billing-service (pass 2) |
| `carmona_inference_finish_total` (how a request ended by the engine's finish_reason: stop, length, tool_calls, content_filter, other, none) | `model`, `reason` | yes (WP-01) |
| `carmona_inference_first_output_seconds` (from the request to the first thing the engine produced; a long prompt's cold and warm prefill are separate series) | `model`, `cache` (`none`, `partial`, `full`) | yes (WP-01); a panel after Day A, not an alert |
| `carmona_engine_contract_ok` (1 the engine meets the check, 0 it does not; absent until the check has run and while it cannot be made) | `model`, `replica`, `check` (`models`, `models_len`, `metrics`, `kv_tokens`, `capacity`, `prefix_caching`) | yes (WP-03) |
| `carmona_engine_slots`, `carmona_engine_queue_places` (the model's sums over its replicas; every inference replica reports the same number, aggregate with `max by (model)`) | `model` | yes (WP-03) |
| `carmona_replica_health_state` (0 ready, 1 unhealthy; **absent** while `carmona.inference.health.enabled` is false) | `model`, `replica` | yes (WP-08) |
| `carmona_replica_health_transitions_total` (absent when the gate is off; both directions start at 0) | `model`, `to` (`ready`, `unhealthy`) | yes (WP-08) |
| `carmona_replica_drain_state` (0 ready, 1 draining, 2 off), `carmona_replica_drain_inflight` (live leases on the replica), `carmona_replica_drain_overdue` (1 past the grace with requests still running; NaN while Valkey cannot say). The last two are fleet-wide numbers that every inference replica exports: aggregate with `max by (model, replica)`, **never `sum`** | `model`, `replica` | yes (WP-09B) |
| `carmona_inference_control_tokens_total` (a request held a control string; once per request and class) | `model`, `class` (`hard`, `soft`), `action` (`neutralized`, `rejected`) | yes (WP-07) |
| `carmona_inference_guard_rejected_total` | `model`, `guard` (`control_tokens`), `code` (`control_token_in_content`, `invalid_role`, `nesting_too_deep`) | yes (WP-07) |
| `carmona_inference_prompt_cache_tokens_total` (the prompt tokens of a request whose engine usage was seen, split into `hit`, served from the engine's prefix cache, and `miss`, the rest; counted once per request, only when the final usage chunk was seen and `prompt_tokens > 0`, so a request cut before it is not in it; **not** the billed input, which stays `carmona_inference_tokens_total{kind="input"}`; a series appears with the first measured request) | `model`, `mode`, `result` (`hit`, `miss`) | yes (P0-1a, inference-service branch `throughput/p0-1`) |

The hit ratio is `sum(rate(...{result="hit"})) / sum(rate(...))` by `model` and `mode`; the records `prompt_cache:hit_ratio_15m`, `prompt_cache:hit_ratio_30m`, `prompt_cache:tokens_rate_15m` (tokens per second) and `prompt_cache:tokens_30m` (tokens in the window) hold it. inference-service creates the `hit` and `miss` series together (both are touched on every request, at 0 if need be), so a dead cache shows a `hit` series at 0; the records do not depend on that: a model and mode with `miss` traffic and no `hit` series reads a ratio of 0 (a dead cache must alert), not nothing.

A value the code cannot compute is absent, never 0 (the lag gauges, the engine gauges and the reconcile gauge remove
their series instead of exporting NaN or a false "healthy"). The engine panels and the queue alert read the engine's
own exposition (`vllm:num_requests_running`, `vllm:num_requests_waiting`, `vllm:kv_cache_usage_perc`), which the
simulated engine serves under the same names, so that half of the stack does not depend on inference-service.

## Dashboards

| Dashboard | Panels |
|---|---|
| **Carmona — SLO & golden signals** (`carmona-slo`) | availability, request rate, error share; TTFT p50/p95/p99 against the 2 s line, TTFT goodput, ITL p95 against 100 ms, queue wait, whole-request p95/p99; in-flight vs capacity, engine running/waiting, engine KV cache, tokens/s by mode and kind; engine preemptions; prompt cache hit ratio (30 m and 15 m, with the 0.30 line) and prompt tokens/s by cache result (hit, miss) |
| **Carmona — service RED (per service)** (`carmona-red`) | one repeated row per service: rate by route, error share against the 5% line, duration (max and mean); plus a gateway row by `routeId` for the reason in §Gaps |
| **Carmona — revenue integrity** (`carmona-revenue`) | 402s served, usage events received vs `/v1` requests served against "at least one event per request", events rejected in the last hour; a collapsed row for the seal lag, the debit lag and the number of organizations flagged `no_credit`, which the code now publishes (the row was written when no service did) |

Every panel carries its threshold on the panel and its reasoning in its description, so red/green is
readable without a key.

## Alerts and what an operator does

Prometheus owns the rules (`docker/prometheus/rules.yml`); Grafana lists them and their firing state beside
its own alerting (`manageAlerts: true`) and never copies them. **There is no Alertmanager**: no destination
has been chosen, so firing state in Grafana and Prometheus is the deliverable, and a notification channel is
a decision for the user, not a default we pick for them.

Severities are labels only (nothing routes them until Alertmanager exists, HOST-12): `critical` is a stopped or unbilled service, `warning` is something
degraded or to look at, `info` is a signal. Every alert has the same text in its `description` in `rules.yml`; a change to the wording is a change in both places.
Alerts on replica-level signals (`ReplicaUnhealthy`, `ReplicaDrainOverdue`, `EngineContractMismatch`) take the max or min over the inference-service replicas that
report the same thing, so they name an engine replica once. A metric of a feature that is off does not exist, so its alert is silent and says nothing about it.

| Alert | Fires when | What the operator does |
|---|---|---|
| `ServiceDown` (critical) | a service's scrape fails for 2 m (one series per replica for `inference` and `gateway`, so it names the replica) | Container down, restarting, or its management port not listening. Check the container's health and logs. Metrics gone means every other SLI for that service is gone too |
| `ReplicatedServiceAbsent` (critical) | `inference` or `gateway` has no scrape target at all for 2 m | Every replica is gone from DNS discovery, so there is no `up` series for `ServiceDown` to test. Check `docker compose ps` for that service |
| `ReplicaMissing` (warning) | `inference`, `gateway`, `engine` or `vllm` has fewer targets than its maximum over the last 30 m, for 1 m | One replica left discovery while the rest still answer, so no `up == 0` exists (with two vLLM cards, the only alert that sees one gone). Compare `docker compose ps` with the replicas you asked for. A `ponytail:` in the rule: an intended scale-down alerts for 30 m |
| `EngineUnreachable` (critical) | every target of the `engine` or `vllm` job fails its scrape, or neither job has any target, for 1 m | Inference answers 503 after one retry. Check the engine container (the real one downloads the model on first start: slow is not broken) and that `.env`'s key is the one the engine started with |
| `EngineQueueSustained` (warning) | the engine job's waiting requests, summed over its replicas (`engine:requests_waiting_total`), reach the queue places inference-service admits (`engine:queue_places`, from `carmona_engine_queue_places`), for 2 m | Admission is running the engine at its full stretch; TTFT is paying for it. Check TTFT p95 and refusals; if the engine is healthy, revisit C (slots). The engine's own cap `--max-num-queued-reqs` must be slots + places or it refuses first. Quiet while the places gauge is absent or 0 |
| `QueueWaitHigh` (warning) | p95 of `carmona_inference_queue_wait_seconds` by model and tier is above 1 s for 10 m (meaningful since WP-01 moved the clock to "request understood") | Admitted requests wait over a second for a slot, the buckets or a slow Valkey. Engine busy: capacity, see `EngineQueueSustained` and `PayingTierRefusals`. Engine idle: look at Valkey (`LeaseStoreDown`, its latency) and inference-service CPU. Refused requests are not in this number |
| `ReconciliationMismatch` (critical) | the hourly reconcile disagrees (any occurrence) | Tokens the engine processed are not in usage-service: revenue that will never be billed. `GET /actuator/reconcile` on inference-service (management port, internal) gives the delta; check usage-service ingestion and the `usage:events` stream in Valkey |
| `UsageIngestionStalled` (critical) | `/v1` requests are being served and usage-service has received nothing for 5 m | Every one of those requests is unbilled right now. Events wait in the Valkey stream, so nothing is lost yet: look for a dead relay or a full stream, and at the usage container |
| `ErrorShareHigh` (warning) | more than 5% of inference requests fail for 5 m | Read the `code` tag: 502/503 are the engine or the connection pool; 500 is a defect in inference-service. `engine_unavailable` has two sources with two messages (the gate: "No engine replica is available; retry shortly.", with `retry-after`; the engine connection: "The model engine is unavailable; try again shortly."): see the runbook in `docs/operations/running.md` |
| `PayingTierRefusals` (warning) | more than 5% of standard/enterprise requests are refused (429) for 5 m | Capacity (C), a tier's share, or one organization holding the slots (gap 4, VTC). Trial being refused is by design and is not this alert |
| `LeaseStoreDown` (warning) | `carmona_inference_lease_store_unavailable` is 1 on a replica for 1 m | Valkey does not answer that replica. Requests are still served (ADR 0001: degraded): the replica admits against its share of the slots and queue places, each divided by the `expected-replicas` setting (not by the replicas that run) and without the token budget, so the caps are only approximate. Check the valkey container and its health, then the replica's log for "lease store unavailable" |
| `SealLagHigh` (warning) | `carmona_usage_seal_lag_seconds` is above 180 for 5 m (healthy: at most about 130) | usage-service is not sealing the windows that are due, so billing waits and the credit check runs on old balances. Nothing is lost. Check the usage log for seal errors, the database, and whether the seal job is held up behind another scheduled job |
| `DebitLagHigh` (critical) | `carmona_billing_debit_lag_seconds` is above 300 for 5 m (healthy: at most about 190) | Sealed windows are not being debited, so a customer whose credit ran out is served longer than the 8-minute overshoot bound. Check the billing log for debit errors, whether usage-service answers it, and the database; a backlog drains 100 windows per run |
| `LagGaugeMissing` (warning) | usage or billing answers its scrape but exports no lag gauge for 5 m | The service cannot compute its lag (the database, or for billing usage-service, does not answer), so `SealLagHigh` and `DebitLagHigh` read nothing and a stuck pipeline would pass unnoticed. Check the service's log and the database. A service that does not answer its scrape is `ServiceDown` |
| `ReplicaUnhealthy` (warning) | `carmona_replica_health_state` is 1 for an engine replica, on any inference replica, for 1 m (only when `health.enabled`) | The health gate stopped sending requests to the replica because nobody answered it (three scrapes in a row, or three refused connections). With one replica every request is a 503 `engine_unavailable` and `EngineUnreachable` fires too. A loading engine is unreachable for minutes and returns after two answered scrapes: nothing to reset. Check the engine container and its log |
| `ReplicaWentUnhealthy` (warning) | `increase(carmona_replica_health_transitions_total{to="unhealthy"}[10m]) > 0`, summed over the inference replicas, no `for` | An outage began and may have ended between two 15 s samples of the gauge. Once is an incident, a repeat is a flapping engine or a flaky link: look at the engine's restarts and uptime and at the network between inference and the engine |
| `ReplicaDrainOverdue` (warning) | `carmona_replica_drain_overdue` is 1 (max over the inference replicas, never sum) for 2 m | A drained replica passed its grace with requests still running. Carmona never cuts them; the operator decides: wait (`GET /actuator/drain` shows `inFlight` and `drained`), or destroy the card and accept that the rest end with an error event and bill what they produced. The engine works; this is not a failure |
| `EngineContractMismatch` (warning) | `carmona_engine_contract_ok` is 0 for a check of an engine replica (min over the inference replicas) for 5 m | The engine and Carmona's assumptions disagree; nothing is refused. The `check` label names it: `models` (served id not listed), `models_len` (`max_model_len` below the context window), `metrics` (a required family missing), `kv_tokens` (no KV-cache size), `capacity` (a full-context request takes more than `capacity-ratio` of the KV cache), `prefix_caching` (off, and the shared-prefix workload needs it). The WARN in the log has the numbers; it clears after the next recheck (10 m) once fixed |
| `ControlTokensInContent` (info) | `increase(carmona_inference_control_tokens_total{class="hard"}[1h]) > 0` | Client text held a role-marker-like string (hard class). By default it is neutralized and served, so this is a signal: a document quoting a template, or an injection attempt. No organization is on the metric; ask the customer or look at the access log by time. Switching a model to `reject` waits for the GPU check G-05. The soft class (think and tool tags) never alerts: a client replaying reasoning sends it every turn |
| `GuardRejections` (warning) | ten or more guard refusals (400) in 10 m for a model and code | A client keeps sending what the guard refuses: `invalid_role` (for example `developer`), `nesting_too_deep`, or `control_token_in_content` (only where a mode is `reject`). Each is a 400 for the customer: a new SDK or a changed template is the first suspect. The 400 text names the problem and never repeats the content |
| `PromptCacheHitRatioLow` (info) | the 30 m hit ratio `prompt_cache:hit_ratio_30m` is under 0.30 for a model and mode for 15 m, with at least 300000 prompt tokens measured in the window (`prompt_cache:tokens_30m`) and some of them in the last 5 m (`increase(...[5m]) > 0`), unless the engine contract says prefix caching is off for that model (`min by (model) (carmona_engine_contract_ok{check="prefix_caching"})` is 0). Quiet while the series does not exist, while the traffic is under the floor, and when nothing was measured in the last 5 m (the 30 m window remembers a burst for 30 minutes; without the recency a cold burst that reaches the floor, then silence, fired on an idle card, and now the alert resolves 5 m after the traffic stops). A cold start does not fire it as long as hits follow within the 15 m. 0.30, 300000 and 15 m are placeholders that Day A tunes; the 5 m is a ceiling: a gap of more than 5 m between two requests of one model and mode restarts the 15 m | Capacity per card goes with 1 / (1 − hit ratio), so this is customers the card no longer carries, not an outage. (1) Confirm the engine flags: `carmona_engine_contract_ok{check="prefix_caching"}` must read 1 or be absent (a 0 is `EngineContractMismatch`'s case and this alert is quiet then), and the engine must run with `--enable-prompt-tokens-details` (as `compose.gpu.yaml` does): without it the engine reports no `cached_tokens` and every request reads as a miss [CODE, vLLM v0.30.0 `vllm/entrypoints/openai/chat_completion/serving.py:97`: `_make_prompt_tokens_details` returns nothing unless the flag is on]. No gauge flags that on its own, but the engine's own ratio tells it from a cold cache: `carmona_engine_prefix_cache_hit_ratio{model}` (hits over queries of the engine's `vllm:prefix_cache_*` counters since the last scrape, absent when no query came in [CODE, `Reconciler.prefixCache`]; the counter names are [UNVERIFIED] on the pinned image, G-01) clearly above 0 while this alert's ratio is near 0 means the flag is missing, both near 0 means a cold or dead cache. (2) Engine restarts (a restart empties the cache, and the first request of each prefix after it is cold; the daily window opens cold by design and the runbook warms it) and evictions: `engine:cache_usage` near 1 and `vllm:num_preemptions_total` rising mean blocks are dropped to make room [INFER]. (3) The customer's prompt layout against the contract page `docs/inference/prompt-caching.md`: anything that changes per request above the shared part (a timestamp, an id, a name) breaks the cache from that point on; one organization, one model name, one `cache_salt` per cache. No organization is on the metric, so the customer is found in usage data (`cachedInputTokens` against `inputTokens` per organization). (4) Read the first-output split, `carmona_inference_first_output_seconds` by `cache`: mostly `none` means the cache is not hit at all (flag, restart, salt), `partial` a prefix hits and something early in the prompt changes, `full` is healthy. If the cache is dead on this hybrid model whatever the layout, that is the Day A question G-07, not an incident: capacity falls to the zero-cache row |

## Gaps

Named, with the owner. None of these is worked around in a dashboard.

1. **Closed (2026-10-06).** Task A's `carmona_inference_*` metrics did not exist on 2026-10-05 (not one
   series). `Metrics` in inference-service publishes them now; the SLO panels and the alerts read them.
2. **Closed (2026-10-06).** The reconciliation had no metric, only a WARN in `Reconciler`;
   `carmona_inference_reconcile_mismatch{model}` (1 = the check disagrees, 0 = it agrees; the tolerance
   stays in Java, not duplicated in PromQL) feeds `ReconciliationMismatch`, and the on-demand
   `GET /actuator/reconcile` carries the token delta.
3. **Closed (pass 2, alerts 2026-10-23).** The three revenue panels had no source; the code now
   publishes `carmona_usage_seal_lag_seconds`, `carmona_billing_debit_lag_seconds` and
   `carmona_billing_no_credit_organizations`. `SealLagHigh` and `DebitLagHigh` alert above the ceilings in
   `Overshoot`, `LagGaugeMissing` covers a service that is up and reports neither. See gap 8.
4. **No percentiles for the built-in HTTP metrics.** Micrometer publishes `http_server_requests_seconds`
   with `_count`, `_sum` and `_max` but no `_bucket` — so per-service p95/p99 is not computable until each
   service sets `management.metrics.distribution.percentiles-histogram.http.server.requests: true`. That is
   an `api/*/application.yaml` change, outside task B; the RED dashboard shows max and mean meanwhile. The
   inference SLOs are unaffected: the contract's timers publish explicit buckets.
5. **The gateway's `uri` tag is `UNKNOWN` for every public request** (measured: 3 of 3). Spring Cloud
   Gateway sets no path pattern on the exchange, so `http_server_requests_seconds` cannot break public
   traffic down by route. Route-level RED for the gateway uses its own
   `spring_cloud_gateway_requests_seconds_count{routeId, routeUri, status, outcome}` instead, which exists
   and carries no personal data. Fixing the `uri` tag would mean a filter in `api/gateway-service` (task C).
6. **Obsolete (2026-10-09).** llama.cpp exposed no KV-cache ratio; llama.cpp is gone. The simulated engine
   reports `vllm:kv_cache_usage_perc` at 0 unless it runs with `--enable-kvcache`, so on the default stack the
   cache panels read a true 0 that means "not modelled". A gauge the engine does not expose stays absent, never 0.
7. **The task A brief names the wrong vLLM metric.** It asks for `vllm:gpu_cache_usage_perc`; vLLM v0.30.0
   (the pinned image) exposes `vllm:kv_cache_usage_perc`, whose help text is "KV-cache usage. 1 means 100
   percent usage" — a 0-1 ratio, not a percentage, so it must not be divided by 100. Checked directly
   against the running GPU container on 2026-10-05. `vllm:num_requests_running` and
   `vllm:num_requests_waiting` are correct as written in the brief.
8. **Closed (2026-10-23).** ADR 0001 says an alert fires when the cache store is down: `LeaseStoreDown` reads
   `carmona_inference_lease_store_unavailable`, `SealLagHigh` and `DebitLagHigh` read the two lag gauges, each with
   `rules.test.yml` cases at the three edges of its `for`. Still true: nothing pages anybody until Alertmanager
   exists (HOST-12).
9. **vLLM's abort counter is not a signal.** The simulated engine counts an aborted request
   (`finish_reason="abort"`); vLLM v0.30.0 leaves that series at 0. No rule or check that must also hold on vLLM reads it.
10. **The GPU host is invisible until it exists.** The rented GPU adds a static `vllm` target, a node exporter and a GPU
   exporter (design: [inference-plan.md](inference-plan.md) §6); today there is no GPU, memory, temperature or
   throttling telemetry and `check-prometheus.sh` expects the DNS-discovered `vllm` job.

11. **The first-output cold share has no panel yet.** `carmona_inference_first_output_seconds{cache}` separates a long
   prompt's cold prefill (`none`) from a warm one (`full`). No alert reads it until Day A shows a baseline; the query to
   look at on a GPU day is `histogram_quantile(0.95, sum by (le, cache) (rate(carmona_inference_first_output_seconds_bucket[15m])))`.
   A panel belongs on the SLO board once there is a baseline to draw the line from.
12. **The health gate, the drain and the control-token guard are unseen on a real engine.** Their metrics and the
   alerts above were written from the Java and tested on hand-made series; GPU checks G-05, G-08 and G-13 are what
   confirm the thresholds. `carmona_replica_health_*` does not exist while `health.enabled` is false, which is the default.
13. **`engine_unavailable` is one code with two messages.** The health and drain gates answer it with "No engine replica is
   available; retry shortly." and a `retry-after`; a refused or timed-out connection to the engine answers it with "The model
   engine is unavailable; try again shortly.". Both are 503 and one series of `carmona_inference_requests_total`. The log line
   or the message tells them apart; `ReplicaUnhealthy` and the drain state say which gate it is.
14. **The prompt cache alert and records are untested against a real engine.** `PromptCacheHitRatioLow` (0.30, 300000
   prompt tokens in 30 m, some of them in the last 5 m, `for` 15 m) was written from the counter's definition and tested on
   hand-made series: 27 promtool cases in `docker/prometheus/rules.test.yml`, and a mutation check of the group (65 mutants of
   a flipped line, a wrong window, a dropped floor, recency or guard: 60 killed by the suite, 5 equivalent). The mutation
   script is a review tool and lives outside this repo, so write those mutants again when the Prometheus image is bumped: two
   cases (exactly 30 %, exactly the 300000 floor) rest on the float rounding of the pinned image, and a newer one can move
   them. 0.30, 300000 and 15 m are placeholders until Day A shows the first measured ratio of this model. Prefix caching on
   the hybrid Qwen3.6 model is itself unverified (G-07, BENCHMARK-PLAN Q5), so a ratio near 0 may be the engine and not a
   layout. The counter exists once inference-service branch `throughput/p0-1` is merged and deployed; until then the records
   and the alert are silent. On the simulator `cached_tokens` is 0 (`--enable-kvcache` is not set), so there the ratio reads
   0 and the alert can fire if the volume reaches the floor and keeps coming: no `carmona_engine_contract_ok` label says
   caching is off there. The engine's eviction counter, if the pinned vLLM has one, is not known; `engine:cache_usage` and
   preemptions stand in for it.

## Deliberately not built

- **Tracing / OpenTelemetry.** A real gap, but a separate decision with a real cost (agent, collector,
  backend, sampling policy) and this pass is one task wide. `trace_id`/`span_id` in the JSON logs (platform.md)
  remain the only correlation.
- **Alertmanager, email, Slack, PagerDuty.** No destination has been chosen. Rules and firing state only.
- **Long-term metric storage** (Thanos, S3, remote write). 15 days of local TSDB is enough to investigate an
  incident on one VM; anything more is infrastructure nobody asked for yet.
- **A 1 s scrape pipeline** (see §What runs).
- **Postgres and Valkey exporters.** The two things they would show that matter — balance vs ledger and the
  `no_credit` flags — are better asserted by the services that own them (D4), and two more containers on a
  7.6 GB VM is a real cost for a startup.

## Verification, 2026-10-05, CPU stack (history; the llama.cpp parts no longer exist)

`docker compose up -d --build --wait` (14 containers, all healthy), then `docker compose down`:

- 10 of 10 Prometheus targets UP: the eight services on `:8081/actuator/prometheus`, the engine (llama.cpp then, gone since ADR 0002)
  at `llama:8080/metrics` (the key was written at container start, so the authenticated engine scrape worked) and Prometheus itself.
- 13 rules loaded in 5 groups, every one `health=ok`; `engine:requests_running` and
  `engine:requests_waiting` produce real samples, `engine:cache_usage` correctly produces none (gap 6).
- 33 dashboard panel expressions executed against Prometheus: 0 errors, the rest empty only where §Gaps
  1–3 say so (or where no traffic has reached the route yet).
- Grafana: datasource provisioned and read-only (`manageAlerts: true`), three dashboards in folder
  *Carmona*, login required (an unauthenticated request gets 401), and the seven alerting rules listed
  through the same API its Alerting UI uses.
- No label carries personal data: `uri` values are mapped patterns (`/v1/models`, `/usage/events`,
  `/organizations/{id}/tenant`) or `UNKNOWN` on the gateway, the only `id` label is the JVM's memory pools,
  and the gateway's route tags are route names and upstream URLs.
- The engine names were checked against the running containers, which is how gap 7 was found: vLLM v0.30.0
  exposes `kv_cache_usage_perc` (0-1), not the `gpu_cache_usage_perc` the task A brief names.

A temporary published port (9090, 3000) was used only for the acceptance curls above; it is reverted, and
`docker compose config` shows the gateway's 8080 as the only host binding in the whole file.
