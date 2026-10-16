# Observability: metrics, dashboards, alerts

Built 2026-10-05 (task B). Prometheus scrapes every service's management port and the engine's own
`/metrics`; Grafana provisions its datasource, three dashboards and its list of alert rules from files in
`docker/`. Nothing is clicked into a container, and nothing that matters is published: metrics stay on the
internal compose network, like the management port they come from (override 6).

**Updated 2026-10-15 for pass 2 and the MVP backend.** The engine is the simulated engine (job `engine`) or vLLM (job `vllm`); there is no llama.cpp job, panel or rule any more (ADR 0002). `inference` and `gateway` are scraped replica by replica through DNS service discovery. The `carmona_*` contract below is published (the three money gauges came with pass 2). The alert list is the nine rules of `docker/prometheus/rules.yml`. What this page does not claim: a scrape of a running stack after 2026-10-05; the checks since then are `docker/check-prometheus.sh` (config valid, 15 rules, `promtool test rules`, the four DNS-discovered jobs) and `docker/check-fleet-targets.sh` (the live replica count), both run by the harness chain on 2026-10-09.

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
| Engine queue depth | full at 8 waiting (the engine refuses past it) | vLLM `--max-num-queued-reqs 8` in `compose.gpu.yaml`; the simulator's `--max-waiting-queue-length=8`; admission lets 2 wait per replica behind 4 slots |
| Error share (inference) | ≤ 5% over 5 m | Same 5% as the goodput target above |
| Refusals on paying tiers (429) | ≤ 5% over 5 m | Phase-4/5 exit check, enterprise goodput ≥ 95% |
| Service reachability | every target UP; `up == 0` for 2 m alerts | This stack. No numeric availability SLO exists yet (plan §8 leaves it per model class) |
| Reconciliation (engine counters vs stored usage) | any disagreement | `Reconciler`: more than max(0.5%, (slots + queue) × context) |
| Usage ingestion | ≥ 1 stored event per served `/v1` request | Every answered request is billable |
| Metering lag (seal and debit) | seal lag ≤ grace + seal-every (120 s at the defaults), debit lag ≤ grace + seal-every + debit-every (180 s) | `Overshoot` in the `billing` library: the 8-minute overshoot bound minus the 5-minute window. Gauges only; no alert on them yet |
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

A value the code cannot compute is absent, never 0 (the lag gauges, the engine gauges and the reconcile gauge remove
their series instead of exporting NaN or a false "healthy"). The engine panels and the queue alert read the engine's
own exposition (`vllm:num_requests_running`, `vllm:num_requests_waiting`, `vllm:kv_cache_usage_perc`), which the
simulated engine serves under the same names, so that half of the stack does not depend on inference-service.

## Dashboards

| Dashboard | Panels |
|---|---|
| **Carmona — SLO & golden signals** (`carmona-slo`) | availability, request rate, error share; TTFT p50/p95/p99 against the 2 s line, TTFT goodput, ITL p95 against 100 ms, queue wait, whole-request p95/p99; in-flight vs capacity, engine running/waiting, engine KV cache, tokens/s by mode and kind |
| **Carmona — service RED (per service)** (`carmona-red`) | one repeated row per service: rate by route, error share against the 5% line, duration (max and mean); plus a gateway row by `routeId` for the reason in §Gaps |
| **Carmona — revenue integrity** (`carmona-revenue`) | 402s served, usage events received vs `/v1` requests served against "at least one event per request", events rejected in the last hour; a collapsed row for the seal lag, the debit lag and the number of organizations flagged `no_credit`, which the code now publishes (the row was written when no service did) |

Every panel carries its threshold on the panel and its reasoning in its description, so red/green is
readable without a key.

## Alerts and what an operator does

Prometheus owns the rules (`docker/prometheus/rules.yml`); Grafana lists them and their firing state beside
its own alerting (`manageAlerts: true`) and never copies them. **There is no Alertmanager**: no destination
has been chosen, so firing state in Grafana and Prometheus is the deliverable, and a notification channel is
a decision for the user, not a default we pick for them.

| Alert | Fires when | What the operator does |
|---|---|---|
| `ServiceDown` | a service's scrape fails for 2 m (one series per replica for `inference` and `gateway`, so it names the replica) | Container down, restarting, or its management port not listening. Check the container's health and logs. Metrics gone means every other SLI for that service is gone too |
| `ReplicatedServiceAbsent` | `inference` or `gateway` has no scrape target at all for 2 m | Every replica is gone from DNS discovery, so there is no `up` series for `ServiceDown` to test. Check `docker compose ps` for that service |
| `ReplicaMissing` | `inference`, `gateway` or `engine` has fewer targets than its maximum over the last 30 m, for 1 m | One replica left discovery while the rest still answer, so no `up == 0` exists. Compare `docker compose ps` with the replicas you asked for. A `ponytail:` in the rule: an intended scale-down alerts for 30 m |
| `EngineUnreachable` | every target of the `engine` or `vllm` job fails its scrape, or neither job has any target, for 1 m | Inference answers 503 after one retry. Check the engine container (the real one downloads the model on first start: slow is not broken) and that `.env`'s key is the one the engine started with |
| `EngineQueueSustained` | `engine:requests_waiting` is 8 or more (the engine's queue is full and it refuses the next request) for 2 m | Admission is letting more through than the engine can start; TTFT is paying for it. Check TTFT p95 and refusals; if the engine is healthy, revisit C (slots) |
| `ReconciliationMismatch` | the hourly reconcile disagrees (any occurrence) | Tokens the engine processed are not in usage-service: revenue that will never be billed. `GET /actuator/reconcile` on inference-service (management port, internal) gives the delta; check usage-service ingestion and the `usage:events` stream in Valkey |
| `UsageIngestionStalled` | `/v1` requests are being served and usage-service has received nothing for 5 m | Every one of those requests is unbilled right now. Events wait in the Valkey stream, so nothing is lost yet: look for a dead relay or a full stream, and at the usage container |
| `ErrorShareHigh` | more than 5% of inference requests fail for 5 m | Read the `code` tag: 502/503 are the engine or the connection pool; 500 is a defect in inference-service |
| `PayingTierRefusals` | more than 5% of standard/enterprise requests are refused (429) for 5 m | Capacity (C), a tier's share, or one organization holding the slots (gap 4, VTC). Trial being refused is by design and is not this alert |

## Gaps

Named, with the owner. None of these is worked around in a dashboard.

1. **Closed (2026-10-06).** Task A's `carmona_inference_*` metrics did not exist on 2026-10-05 (not one
   series). `Metrics` in inference-service publishes them now; the SLO panels and the alerts read them.
2. **Closed (2026-10-06).** The reconciliation had no metric, only a WARN in `Reconciler`;
   `carmona_inference_reconcile_mismatch{model}` (1 = the check disagrees, 0 = it agrees; the tolerance
   stays in Java, not duplicated in PromQL) feeds `ReconciliationMismatch`, and the on-demand
   `GET /actuator/reconcile` carries the token delta.
3. **Closed for the series, open for the alerts (pass 2).** The three revenue panels had no source; the code now
   publishes `carmona_usage_seal_lag_seconds`, `carmona_billing_debit_lag_seconds` and
   `carmona_billing_no_credit_organizations`. No rule uses them yet: the ceilings (seal lag above grace +
   seal-every, debit lag above grace + seal-every + debit-every) are in `Overshoot`, and an alert above them is the
   bound made observable. See gap 8.
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
8. **No alert on the pass-2 gauges.** ADR 0001 says an alert fires when the cache store is down: the gauge
   `carmona_inference_lease_store_unavailable` exists and no rule reads it (nor the two lag gauges). Rules to add, with
   `rules.test.yml` cases: the lease gauge at 1 for 1 m; seal lag above grace + seal-every; debit lag above
   grace + seal-every + debit-every. Nothing pages anybody until Alertmanager exists (HOST-12).
9. **vLLM's abort counter is not a signal.** The simulated engine counts an aborted request
   (`finish_reason="abort"`); vLLM v0.30.0 leaves that series at 0. No rule or check that must also hold on vLLM reads it.
10. **The GPU host is invisible until it exists.** The rented GPU adds a static `vllm` target, a node exporter and a GPU
   exporter (design: [inference-plan.md](inference-plan.md) §6); today there is no GPU, memory, temperature or
   throttling telemetry and `check-prometheus.sh` expects the DNS-discovered `vllm` job.

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
