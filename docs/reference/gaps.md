# Known gaps

**What is missing, ranked by what blocks a paying customer rather than by how long the fix would take, and
labelled for what it is: a defect, a deliberate deferral, or unbuilt scope.**

## What it is

Every honest gap in the platform, in one place, each with the concrete fix and a label that says which kind
of gap it is. The ranking is by customer impact: something that stops money changing hands, or stops a
customer being served at all, ranks above something that makes an engineer's afternoon worse. Effort is not
part of the ranking — a one-line fix that blocks launch outranks a week of work nobody notices.

<figure class="cmn-figure">
<div class="cmn-flow" markdown="0">
<svg viewBox="0 0 760 280" role="img" aria-labelledby="gap-title" aria-describedby="gap-desc"
     xmlns="http://www.w3.org/2000/svg">
  <title id="gap-title">A gap map: what runs, what waits, and what is not there</title>
  <desc id="gap-desc">Three lanes. The top lane is built and a packet runs along its rail: the gateway,
  admission, the relay to the engine, and the path from usage to ledger. The middle lane is deferred with a
  named trigger — object storage, Kafka, a second replica, console invitations. The bottom lane is unbuilt:
  the payment rail, the customer console, embeddings and an alerting destination. Neither lower lane has a
  rail or a packet, because nothing runs there.</desc>

  <defs>
    <marker id="gap-arrow-flow" viewBox="0 0 10 10" refX="9" refY="5"
            markerWidth="6" markerHeight="6" orient="auto-start-reverse">
      <path class="cmn-arrow" d="M0 0 L10 5 L0 10 z"/>
    </marker>
  </defs>

  <!-- The rail under the built lane: structure, and the path the packet travels. -->
  <g id="gap-rail" aria-hidden="true">
    <path class="cmn-link" d="M136 94 H732" marker-end="url(#gap-arrow-flow)"/>
    <path class="cmn-link" d="M206 78 V94"/>
    <path class="cmn-link" d="M358 78 V94"/>
    <path class="cmn-link" d="M510 78 V94"/>
    <path class="cmn-link" d="M662 78 V94"/>
  </g>

  <!-- The packet: one journey along the built lane, and no journey anywhere else. -->
  <circle class="cmn-packet cmn-travel" r="5"
          style="offset-path: path('M136 94 H732'); --cmn-travel: 2.2s; --cmn-delay: 0s;"></circle>

  <!-- Lane labels -->
  <g class="cmn-node" id="gap-lane-built" aria-labelledby="gap-lane-built-label">
    <text id="gap-lane-built-label" x="64" y="54">Built</text>
  </g>
  <g class="cmn-node" id="gap-lane-deferred" aria-labelledby="gap-lane-deferred-label">
    <text id="gap-lane-deferred-label" x="64" y="128">Deferred</text>
  </g>
  <g class="cmn-node" id="gap-lane-unbuilt" aria-labelledby="gap-lane-unbuilt-label">
    <text id="gap-lane-unbuilt-label" x="64" y="202">Unbuilt</text>
  </g>

  <!-- Lane 1: built -->
  <g class="cmn-node cmn-node--flow" id="gap-gateway" aria-labelledby="gap-gateway-label">
    <rect x="136" y="30" width="140" height="48" rx="10"/>
    <text id="gap-gateway-label" x="206" y="48">Gateway</text>
    <text class="cmn-sub" x="206" y="64">the only public port</text>
  </g>
  <g class="cmn-node cmn-node--flow" id="gap-admission" aria-labelledby="gap-admission-label">
    <rect x="288" y="30" width="140" height="48" rx="10"/>
    <text id="gap-admission-label" x="358" y="48">Admission</text>
    <text class="cmn-sub" x="358" y="64">buckets, tier caps</text>
  </g>
  <g class="cmn-node cmn-node--flow" id="gap-relay" aria-labelledby="gap-relay-label">
    <rect x="440" y="30" width="140" height="48" rx="10"/>
    <text id="gap-relay-label" x="510" y="48">Relay to engine</text>
    <text class="cmn-sub" x="510" y="64">tokens stream back</text>
  </g>
  <g class="cmn-node cmn-node--flow" id="gap-ledger" aria-labelledby="gap-ledger-label">
    <rect x="592" y="30" width="140" height="48" rx="10"/>
    <text id="gap-ledger-label" x="662" y="48">Usage to ledger</text>
    <text class="cmn-sub" x="662" y="64">billed once</text>
  </g>

  <!-- Lane 2: deferred, with a named trigger -->
  <g class="cmn-node cmn-node--soft" id="gap-objectstore" aria-labelledby="gap-objectstore-label">
    <rect x="136" y="104" width="140" height="48" rx="10"/>
    <text id="gap-objectstore-label" x="206" y="122">Object storage</text>
    <text class="cmn-sub" x="206" y="138">files above 4 MB</text>
  </g>
  <g class="cmn-node cmn-node--soft" id="gap-kafka" aria-labelledby="gap-kafka-label">
    <rect x="288" y="104" width="140" height="48" rx="10"/>
    <text id="gap-kafka-label" x="358" y="122">Kafka</text>
    <text class="cmn-sub" x="358" y="138">a second consumer</text>
  </g>
  <g class="cmn-node cmn-node--soft" id="gap-replica" aria-labelledby="gap-replica-label">
    <rect x="440" y="104" width="140" height="48" rx="10"/>
    <text id="gap-replica-label" x="510" y="122">Second replica</text>
    <text class="cmn-sub" x="510" y="138">shared counters first</text>
  </g>
  <g class="cmn-node cmn-node--soft" id="gap-invites" aria-labelledby="gap-invites-label">
    <rect x="592" y="104" width="140" height="48" rx="10"/>
    <text id="gap-invites-label" x="662" y="122">Console invites</text>
    <text class="cmn-sub" x="662" y="138">waits for hosting</text>
  </g>

  <!-- Lane 3: unbuilt -->
  <g class="cmn-node cmn-node--danger" id="gap-payments" aria-labelledby="gap-payments-label">
    <rect x="136" y="178" width="140" height="48" rx="10"/>
    <text id="gap-payments-label" x="206" y="196">Payment rail</text>
    <text class="cmn-sub" x="206" y="212">credit is a grant</text>
  </g>
  <g class="cmn-node cmn-node--danger" id="gap-console" aria-labelledby="gap-console-label">
    <rect x="288" y="178" width="140" height="48" rx="10"/>
    <text id="gap-console-label" x="358" y="196">Customer console</text>
    <text class="cmn-sub" x="358" y="212">there is no UI</text>
  </g>
  <g class="cmn-node cmn-node--danger" id="gap-embeddings" aria-labelledby="gap-embeddings-label">
    <rect x="440" y="178" width="140" height="48" rx="10"/>
    <text id="gap-embeddings-label" x="510" y="196">/v1/embeddings</text>
    <text class="cmn-sub" x="510" y="212">chat and models only</text>
  </g>
  <g class="cmn-node cmn-node--danger" id="gap-alerting" aria-labelledby="gap-alerting-label">
    <rect x="592" y="178" width="140" height="48" rx="10"/>
    <text id="gap-alerting-label" x="662" y="196">Alerting</text>
    <text class="cmn-sub" x="662" y="212">no destination chosen</text>
  </g>
</svg>
</div>
<figcaption>The top lane is the only one with a rail, because it is the only one a request can travel
today: gateway, admission, relay, and the path from usage into the ledger. The middle lane holds shortcuts
that were deferred on purpose, each with a trigger written down. The bottom lane holds capabilities that do
not exist at all. A red outline marks a box in the bottom lane; the label inside it says what is missing.</figcaption>
</figure>

<div class="cmn-legend">
  <span><i class="is-flow"></i> built, and a packet travels it (solid)</span>
  <span><i class="is-async"></i> nothing there; no rail and no packet</span>
  <span>red outline: unbuilt, and the label inside says what is missing</span>
</div>

1. The top lane is what is built, and the only lane with a rail: gateway, admission, the relay to the engine, and the path from usage into the ledger — in the order a request meets them.
2. The middle lane is deliberately deferred: each box names what it waits for, so nothing there is waiting on somebody's memory.
3. The bottom lane is unbuilt: no rail and no packet, because the capability does not exist yet.
4. A box moves up a lane when its work lands. The lane a box sits in is the honest answer to "does this exist today?", and it is the first thing a reader should check before assuming a capability is present.

## The ranking, and what the ranking is not

Three tiers, in the order below: **what blocks taking money from anyone**, **what blocks the second
customer or the second engineer**, and **recorded ceilings that block nothing today**. Nothing here is
estimated in weeks, because an estimate is a different kind of number and this page is about impact.

One caveat about the sources. The handoff's own ranked list is a snapshot from 2026-10-04, and the code has moved since: the flood brake now answers an OpenAI-shaped 429 from a shared Valkey bucket, the `api-keys/{id}/rotate` route and the customer balance and usage routes exist at the gateway, an expired key is refused from the cache, waiting requests are ordered by the virtual token counter, and a paying tier waits for a slot instead of taking an instant 429. Those are not listed below as open, and [which notes to trust](status.md) records where each source lags. Where a gap turned out to be already closed, the entry says so rather than keeping a stale row alive.

## 1 · What blocks taking money from anyone

| # | The gap | Kind | The concrete fix |
|---|---|---|---|
| 1 | **No payment rail.** Credit enters the system only through `POST /billing/grants`, an internal, idempotent staff call; there is no way for a stranger to pay | unbuilt scope, and an open decision | Choose a PSP and an NFS-e provider, then treat the webhook as a hint and re-fetch the charge before crediting the balance — [Billing](../services/billing.md) has the current grant path |
| 2 | **No customer console.** The only UI in the repository is `demo/`, a one-page console used to record the walkthrough videos; nothing lets a customer mint a key, rotate it, read usage or see a balance | unbuilt scope | Phase 7b's console SPA on the same origin as the console API — the endpoints behind it exist and are already routed, and [Money](../data/money.md) describes what they return |
| 3 | **No legal entity, DPA, acceptable-use policy, ROPA or named data-protection contact, and no decided retention periods** | unbuilt scope, waiting on counsel and on the user | The plan's "before real customer data reaches any GPU" checklist, plus a retention decision per data class |
| 4 | **No Alertmanager, so nothing pages anybody.** Prometheus evaluates the rules and Grafana shows their firing state; no destination has been chosen | deliberate deferral | Pick a destination. The rules, the metrics and the on-demand `GET /actuator/reconcile` already exist — [Observability](../operations/observability.md) lists them |
| 5 | **One GPU, one engine endpoint per model, no replica routing.** Deployment config holds one engine URL per model, so [Inference](../services/inference.md) has nothing to route between | deliberate deferral | Multi-replica routing with more GPUs — fewest-waiting first, or the llm-d router on Kubernetes |
| 6 | **In-flight caps live in one JVM's memory**, so a second replica would double every cap | deliberate deferral | Shared counters in Valkey, or a fixed share per replica, **before** a second inference-service exists |
| 7 | **No Kubernetes and no second replica**, so there is no rolling deploy and no availability target that means anything | unbuilt scope, platform decision deferred | The phase-7 decision: Kubernetes with KEDA autoscaling and nginx at the edge. The observability half is already provisioned from files in `docker/` |
| 8 | **Tracing is not wired.** No `micrometer-tracing`, no OpenTelemetry agent or collector, no backend; `trace_id` and `span_id` in the JSON logs are the only correlation | deliberate deferral that became permanent | The OTel Java agent in each image with `OTEL_EXPORTER_OTLP_ENDPOINT` and a 0.1 sampler, body and header capture off — and a backend to look at |
| 9 | **Batch files are capped at 4 MB and stored in Postgres `bytea`**; OpenAI allows 200 MB, so a real batch upload fails at the gateway | deliberate deferral | Object storage once hosting is decided. The cap itself is one setting, `carmona.gateway.request-body.max-size` (a chat completion has its own, `chat-max-size`), and batch-service's multipart limit of 4MB has to rise with it; [Batch API design](../operations/batch-api.md) covers the rest of the surface |
| 10 | **`GET /v1/embeddings` does not exist.** The inference service has exactly two routes: `POST /v1/chat/completions` and `GET /v1/models` — see [Inference](../services/inference.md) | unbuilt scope, out of scope until there is a reason | A decision first, then an engine that serves it. Note that a batch file whose `endpoint` is `/v1/embeddings` is already refused at creation with `invalid_line` |

## 2 · What blocks the second customer, or the second engineer

| # | The gap | Kind | The concrete fix |
|---|---|---|---|
| 11 | **Password-reset mail has a per-IP throttle and no per-email one**, so the per-IP bucket is the only ceiling on reset mail to one address | deliberate deferral | A per-email counter in Valkey beside the per-IP bucket |
| 12 | **Invitations are not built, and the SMTP credentials for a real provider wait for hosting.** Registration, verification, reset and the "already registered" notice all work, through Mailpit in compose | unbuilt scope | Invitations, and a real SMTP provider — the mail path itself already exists |
| 13 | **No `last_used_at` on API keys**, so a customer cannot tell which key is safe to revoke | deliberate deferral | A throttled writer fed by usage events rather than a write on the request path: `UsageEvent` already carries `api_key_id` |
| 14 | **Per-service p95/p99 is not computable**: Micrometer publishes `http_server_requests_seconds` with `_count`, `_sum` and `_max` and no `_bucket` | deliberate deferral, recorded with the exact property | `management.metrics.distribution.percentiles-histogram.http.server.requests: true` in each `api/*/application.yaml`. The inference SLOs are unaffected; those timers publish their own buckets |
| 15 | **Three revenue panels have no metric behind them**: `carmona_usage_seal_lag_seconds`, `carmona_billing_debit_lag_seconds` and `carmona_billing_no_credit_organizations` are named in a dashboard and published by no service | unbuilt scope | Instrument the seal job, the debit job and `CreditFlags`; the panels light up as soon as the series exist |
| 16 | **The gateway's `uri` tag is `UNKNOWN` for every public request**, so `http_server_requests_seconds` cannot break public traffic down by route | deliberate deferral | Set the route pattern on the exchange in gateway-service; the gateway's own `spring_cloud_gateway_requests_seconds_count{routeId,…}` covers route-level RED meanwhile |
| 17 | **The two pinned-version advisories were never independently verified.** The review names a vLLM error-message path leak and a Netty request-smuggling family, and says itself that it did not verify them | defect in the record, not in the code | Open both advisories against the pinned image and the resolved Netty version, then either bump or record that the pin is already past them |
| 18 | **vLLM's own key protects only `/v1`, `/v2`, `/inference` and `/cohere`**; `/invocations`, `/pause`, `/abort_requests` and `/update_weights` stay open to anything that can reach the port | deliberate deferral, safe only on a private network | A path allowlist (`/v1/*`, `/health`, `/metrics`) at the edge of any host where the engine is not on an internal network |
| 19 | **The bench's workers ignore `retry-after-ms`.** The service side is fixed — a paying tier now waits up to 1.5 s for a slot — but `docker/bench.sh`'s curl workers retry immediately, so a start race can still show a goodput number the service did not cause | deliberate deferral, offered as the next fix | Make the bench workers honour the header, as an SDK does, and re-run the three-tier check |
| 20 | **The engine gauges refresh once an hour**, because they are read by the reconciler's scrape rather than a per-second pipeline | deliberate deferral | The per-second scrape into memory that the plan places with the multi-replica work; until then `EngineQueueSustained` is a slow trend, and a metric the engine does not expose stays absent rather than reading a false 0 |

## 3 · Recorded ceilings that block nothing today

| # | The gap | Kind | The concrete fix |
|---|---|---|---|
| 21 | **A new organization can call `/v1` until its first debit**, because it has no balance row and therefore no flag. The overshoot is at most one window of usage | deliberate deferral | Trial credit at organization creation — a decision, not a bug |
| 22 | **Flex usage is recorded as mode `batch`**, so a flex request appears in a batch report and is priced like a batch line | deliberate deferral | A `flex` mode of its own: CHECK constraints, price rows and `UsageService.MODES` |
| 23 | **The usage summary prices per day, not per window.** A price that changes inside a day misprices that day's earlier tokens, by under 1 micro-BRL per window; the ledger charge itself stays exact | deliberate deferral | Per-window pricing in the summary, when the price history or the read needs bounding |
| 24 | **No maximum API key lifetime**: the caller decides, and null means never | deliberate deferral | A policy in the console; the server takes what the caller asks for, on purpose |
| 25 | **A crash between an answer's last byte and its `XADD` still loses that event**, about a millisecond of window | accepted risk | None wanted: billing before answering would put a write in front of every request. The reconciliation is what makes it visible |
| 26 | **The reconciliation warns rather than alerts.** Past `max(0.5%, the tokens that can be in flight)` it logs a WARN and sets `carmona_inference_reconcile_mismatch`; the rule fires and, with no destination, nobody is paged | deliberate deferral | The alerting destination in row 4. The metric and the rule are already there |
| 27 | **The gateway's flood brake falls back to per-replica memory when Valkey is down.** It fails open by design, so an outage multiplies the effective limit by the number of replicas — one today | deliberate deferral | None: the checks that must fail closed are the API-key lookup and the credit flag, and they do |
| 28 | **`client_ip` in the access log is the TCP peer**, so a request that arrived through a proxy would be logged as the proxy | deliberate deferral | nginx with `X-Forwarded-For $remote_addr` (overwritten, never appended) plus the gateway's forwarded-headers strategy, before the log is relied on for a Marco Civil request |
| 29 | **A cancelled stream on the CPU engine is estimated** — input from body bytes, output from content chunks — because llama.cpp reports usage only at the end of a stream | deliberate deferral, CPU only | Nothing while the CPU engine is the CI engine; vLLM reports running usage, so the GPU path is measured, not estimated |
| 30 | **The Batch API's shape differs from OpenAI's in three places**: validation happens at creation with a 400 naming the bad line instead of an asynchronous `validating` → `failed`, there are no list endpoints and no `metadata`, and a file must POST to `/v1/chat/completions` | deliberate deviation | Only if a customer's client depends on the polling state; the deviation is deliberate and cheaper |
| 31 | **`BillingJobs` logs only the exception class**, which hides the cause | defect | Log the root cause's class too. It is one line, and this is the job whose failure means nobody is billed |
| 32 | **Leftover synthetic data in the local database** — bench accounts and organizations, files of experiment organizations | local only, harmless | Nothing; it is the developer's database, and deleting user data is not an agent's decision |
| 33 | **The model registry keeps no local copy of its list.** A model registered while the system runs is read from model-service every few seconds, and a model-service that is down changes nothing for what runs; but a restart of inference-service while it is down serves the configured models only, and a registered one is a 404 until the first read succeeds. A retired model leaves a few numbers in memory until a restart (the lease budgets, an engine-timeouts object, its counters), and a change is a retire and a register ([Model](../services/model.md)) | deliberate deferral | A copy of the list written when it changes and read at a cold start; the per-id objects dropped at a retire if rented models ever come by the thousand; stable replica ids in the lease keys |
| 34 | **No keep-alive bytes during a long prefill.** Nothing goes to the client until the engine's first event, so the time to the first byte is the prefill. The prefill allowance can be set per model and its ceiling is 55 s as shipped, under the 60 s read timeout of the edge that is planned, but a prompt that takes longer than a proxy or a client waits is cut | unbuilt scope | SSE comment lines sent while the engine reads the prompt. The stream then starts, with a 200, before the engine's first event, so an engine failure after that can no longer be answered with a status |
| 35 | **Prometheus has no job for a remote engine.** It finds its engine jobs by DNS name (`docker/prometheus/prometheus.yml`), so an engine on a rented node is not scraped there; inference-service's own `carmona_engine_*` gauges still show it | deliberate deferral | A job per remote engine, with a static or file-based target and the engine's key |
| 36 | **The JVM services have no heap flag and no memory limit.** The maximum heap is whatever the JVM picks from the memory it finds, and the budget for request bodies in flight is a tenth of it, so it moves with the host. The budget's relation to the heap is derived from the copies the code makes, not measured | deliberate deferral | A heap flag and a container memory limit in `docker/compose.yaml`, set after a heap histogram of a request of the largest size says what a body costs |
| 37 | **The contract check, the health gate and `admission-wait` are global, not per model.** The startup grace, the capacity ratio, the health thresholds and the wait of a paying tier are the same for every model, so a model that loads for much longer than another cannot have its own; `contract.fail-fast` ends the whole JVM for every model | deliberate deferral | Per-model keys with the global value as the fallback, as the timeouts and the prefill allowance have, the day a model needs them |
| 38 | **JSON output stays refused.** `response_format` other than text, `logprobs`, `top_logprobs` and `logit_bias` answer 400 `unsupported_parameter` before the first byte | deliberate deferral | A real test on the chosen model that shows the engine honours them; until then the refusal is the contract |
| 39 | **A streamed request to an engine that answers 200 and ends with no data line is still a 200 with an empty event stream, and an `ok` event billed on the input estimate.** A non-streamed answer that is no answer has been the engine's failure since AM-15, the follow-up of the live check of 2026-11-13 (an empty 200 had been billed as `ok`); the streamed case is not covered, because the tracker runs once per data line and with none no code of it runs. Measured on a stub engine: 22 estimated tokens billed for nothing | defect, found while fixing the live check's empty 200 | `switchIfEmpty(Flux.error(ApiError.engineError()))` ahead of `onErrorResume` in `ChatHandler.relayErrors`, so that nothing having started the caller gets the 502, with a test: the stub engine in its raw mode answering `text/event-stream` with an empty body. It needs its own task |
| 40 | **A body with no declared length is cut at the bound as it is read, and the rest of it is not read first.** A refused declared length is read to its end and thrown away before its 413 (up to `body.drain-up-to`); a chunked body is not. Measured with 20 MiB sent in chunks against a bound of 16 MiB: 413, every chunk taken, the connection kept, the next request answered, so there is no failing case, and no caller sends such a body (the gateway requires a length, batch-service sends a string) | deliberate deferral | A counting wrapper on the request's body ahead of the codecs, answering after the rest has been read and dropped, if a caller that streams without a length ever appears |
| 41 | **The 413 that reached a caller as the gateway's 503 was not reproduced, so the drain is not shown to cure it.** In the live check of 2026-11-13 the same 17 MiB chat request got the 413 in two runs and the gateway's own 503 `inference_unavailable` in the third (its connection to inference-service closed before it had read the answer). On the laptop, which runs Windows and the NIO transport, 0 of 109 such requests failed before the drain and 0 after. Whether a direct caller that sends `Expect: 100-continue` now uploads its whole body before the 413 was not run | defect, with a fix that is not shown to work | The 17 MiB request through the gateway on the compose stack on Linux, three times or more, after the merge, and one with `Expect: 100-continue` straight to inference-service |
| 42 | **The input bucket lets one request far above a tier's limit pass.** Admission asks only that each bucket holds at least 1 and charges the whole estimate: a body of 5 MiB (1,310,720 estimated tokens) was admitted for a trial organization whose limit is 20,000, and its header read 0. The estimate is corrected to the engine's own count when the request ends, so what stays owed is the real prompt's. What a second request of that organization gets was not tried; by `buckets.lua` it is refused while the bucket is below 1 | deliberate deferral, the rule `Admission` states for the output bucket | A decision for the first model with a large window: refuse a request whose estimate exceeds the tier's whole per-minute input limit (it then can never pass), or leave it and size that model's own `tiers` from the bench ([Adding a model](../services/inference.md#adding-a-model)) |
| 43 | **The start log of inference-service does not state the request-size bound or the body budget.** The 21 lines of its start in the live check have nothing about either, so an operator cannot read from them what a model's window made of the bound | unbuilt scope | One INFO line at start: each model's bound in bytes, the largest bound, the body budget and `drain-up-to` |
| 44 | **An organization with no credit cannot call its own model.** The gateway applies the credit flag to every `/v1` request before any model is looked at, so it cannot tell a model the caller rented from a public one. An organization's own model never lowers its balance, but a new organization has the flag until its first grant | open decision, the owner's | Keep it (a customer needs credit on the account even for his own GPU), or a small grant when the model is registered, or let the gateway know the models a caller owns, which it does not today |
| 45 | **A registered model has no roles or control-token patterns of its own.** It runs on the global ones. A pattern a customer registers would be compiled and run over every request body of the shared JVM, and the check that exists refuses only an invalid or empty-matching one | deliberate deferral | Patterns bounded at registration (a length cap, a compile check, an adversarial probe) and a counting wrapper at match time, about thirty lines on each side |
| 46 | **The url of a replica is checked by its name, not by what it resolves to.** A public name that later resolves to an internal address is not caught at registration, nor is a name such as `x.internal`, and inference-service calls the url from inside the network with the engine's key | deliberate deferral | Egress filtering of inference-service, which is not in this repository |

## Why it is like this

- **A gap is labelled by kind, because "future work" flattens three different things.** A **defect** is a bug
  and should be fixed. A **deliberate deferral** is a decision with a trigger, and it should be revisited when
  the trigger fires rather than when somebody notices the note. **Unbuilt scope** is a product that does not
  exist, and the only question worth asking is whether to build it at all.
- **A deferral is not a defect.** Row 9 (batch files in Postgres) and row 6 (in-flight caps in one JVM) are
  shortcuts taken on purpose, with their ceilings written into the code as `ponytail:` comments. Calling them
  bugs would make the honest rows harder to find.
- **Dates are kept because a closed gap is information.** "This was broken and now is not" is worth as much to the next engineer as an open row, so a closed gap stays on the page for a while instead of vanishing.
- **Nothing is worked around in a dashboard.** Where a panel has no metric behind it, the panel is empty and says which metric it is waiting for, rather than animating a substitute.

## What would change it

A gap leaves this page when the code changes, and the rows above name their own triggers: a hosting decision closes rows 9 and 12 together and unblocks rows 5 and 18; a payment provider closes row 1; a console closes row 2 and with it row 13; a second replica must close row 6 first, which is why row 6 is ranked above row 7; an alerting destination closes rows 4 and 26 at once; and the legal checklist closes row 3, the only row here that no amount of engineering can close.

## Where to look

- [inference-plan.md](https://github.com/carmonaai/back/blob/main/.claude/skills/carmona-architecture/references/inference-plan.md) — §13 is the backlog, and the "Phase N built" blocks name each deliberate deviation and its reason.
- [observability.md](https://github.com/carmonaai/back/blob/main/.claude/skills/carmona-architecture/references/observability.md) — the metrics contract, the gaps it names against itself, and the exact wording of each alert rule.
- [plan-review-2026-10-02.md](https://github.com/carmonaai/back/blob/main/.claude/skills/carmona-architecture/references/plan-review-2026-10-02.md) — where the ranked findings came from, including the unverified advisories.
- [docker/prometheus/rules.yml](https://github.com/carmonaai/back/blob/main/docker/prometheus/rules.yml) — the alerts that fire into nothing.
- [docker/revenue-check.sh](https://github.com/carmonaai/back/blob/main/docker/revenue-check.sh) — the check that exits non-zero when the books and the ledger disagree.
