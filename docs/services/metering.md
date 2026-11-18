# Metering

## What it is

`usage-service` owns the `usage` schema and turns finished requests into a number that can be billed. It
receives events from inference-service, stores them in daily partitions, seals arrival-time windows of five
minutes into permanent totals, and hands those totals to billing in order. The same rows also hold what an
organization reads about each request of its own deployments (the request record), a second and separate table
holds the requests the platform refused (the refusal record), and the app's numbers for a deployment are read from both.

<figure class="cmn-figure">
<div class="cmn-flow" markdown="0">
<svg viewBox="0 0 760 280" role="img" aria-labelledby="usage-title" aria-describedby="usage-desc"
     xmlns="http://www.w3.org/2000/svg">
  <title id="usage-title">An event stored in a daily partition, and sealed into a five-minute window</title>
  <desc id="usage-desc">A relay posts events to usage-service, which stores them in a daily partition of
  usage_event. A seal job sums whole five-minute windows by arrival time after a grace period and writes
  them to usage_window, which billing pulls in order; partitions older than 90 days are dropped.</desc>
  <defs>
    <marker id="usage-arrow-flow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse"><path class="cmn-arrow" d="M0 0 L10 5 L0 10 z"/></marker>
    <marker id="usage-arrow-quiet" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse"><path class="cmn-arrow" d="M0 0 L10 5 L0 10 z"/></marker>
  </defs>
  <!-- Hops in reading order: the batch in, the row stored, the seal, the sealed total, the pull, the prune. -->
  <g id="usage-hops">
    <path id="usage-hop1" class="cmn-link cmn-link--flow cmn-dash" d="M140 68 H190" marker-end="url(#usage-arrow-flow)"/>
    <path id="usage-hop2" class="cmn-link cmn-link--flow cmn-dash" d="M360 68 H410" marker-end="url(#usage-arrow-flow)"/>
    <path id="usage-hop3" class="cmn-link cmn-link--flow cmn-dash" d="M560 68 H610" marker-end="url(#usage-arrow-flow)"/>
    <path id="usage-hop4" class="cmn-link cmn-link--flow cmn-dash" d="M675 96 V140 H550 V176" marker-end="url(#usage-arrow-flow)"/>
    <path id="usage-hop5" class="cmn-link cmn-link--money cmn-dash" d="M560 204 H610" marker-end="url(#usage-arrow-flow)"/>
    <path id="usage-hop6" class="cmn-link cmn-link--quiet" d="M485 96 V140 H95 V176" marker-end="url(#usage-arrow-quiet)"/>
  </g>
  <g class="cmn-node cmn-node--entry cmn-node--soft" id="usage-relay" aria-labelledby="usage-relay-label"><rect x="20" y="40" width="120" height="56" rx="10"/><text id="usage-relay-label" x="80" y="60">Relay</text><text class="cmn-sub" x="80" y="78">inference-service</text></g>
  <g class="cmn-node cmn-node--flow" id="usage-ingest" aria-labelledby="usage-ingest-label"><rect x="190" y="40" width="170" height="56" rx="10"/><text id="usage-ingest-label" x="275" y="60">Ingest</text><text class="cmn-sub" x="275" y="78">POST /usage/events, 1 to 1000</text></g>
  <g class="cmn-node cmn-node--flow" id="usage-event" aria-labelledby="usage-event-label"><rect x="410" y="40" width="150" height="56" rx="10"/><text id="usage-event-label" x="485" y="60">usage_event</text><text class="cmn-sub" x="485" y="78">one daily partition</text></g>
  <g class="cmn-node cmn-node--flow" id="usage-seal" aria-labelledby="usage-seal-label"><rect x="610" y="40" width="130" height="56" rx="10"/><text id="usage-seal-label" x="675" y="60">SealJob</text><text class="cmn-sub" x="675" y="78">every 60 s</text></g>
  <g class="cmn-node cmn-node--soft" id="usage-pruned" aria-labelledby="usage-pruned-label"><rect x="20" y="176" width="150" height="56" rx="10"/><text id="usage-pruned-label" x="95" y="196">Dropped</text><text class="cmn-sub" x="95" y="214">past 90 days</text></g>
  <g class="cmn-node cmn-node--flow" id="usage-window" aria-labelledby="usage-window-label"><rect x="410" y="176" width="150" height="56" rx="10"/><text id="usage-window-label" x="485" y="196">usage_window</text><text class="cmn-sub" x="485" y="214">five minutes, sealed</text></g>
  <g class="cmn-node cmn-node--money" id="usage-billing" aria-labelledby="usage-billing-label"><rect x="610" y="176" width="130" height="56" rx="10"/><text id="usage-billing-label" x="675" y="196">Billing pulls</text><text class="cmn-sub" x="675" y="214">in cursor order</text></g>
  <circle class="cmn-packet cmn-travel" r="5" style="offset-path: path('M140 68 H190'); --cmn-travel: 0.9s; --cmn-delay: 0s;"></circle>
  <circle class="cmn-packet cmn-travel" r="5" style="offset-path: path('M360 68 H410'); --cmn-travel: 0.9s; --cmn-delay: 0.15s;"></circle>
  <circle class="cmn-packet cmn-travel" r="5" style="offset-path: path('M560 68 H610'); --cmn-travel: 0.9s; --cmn-delay: 0.3s;"></circle>
  <circle class="cmn-packet cmn-travel" r="5" style="offset-path: path('M675 96 V140 H550 V176'); --cmn-travel: 1.3s; --cmn-delay: 0.5s;"></circle>
  <circle class="cmn-packet cmn-packet--money cmn-travel" r="4.5" style="offset-path: path('M560 204 H610'); --cmn-travel: 0.9s; --cmn-delay: 0.8s;"></circle>
  <circle class="cmn-packet cmn-travel" r="4.5" style="offset-path: path('M485 96 V140 H95 V176'); --cmn-travel: 1.5s; --cmn-delay: 1.1s;"></circle>
  <rect class="cmn-label-plate" x="144" y="46" width="42" height="16" rx="4"/><text class="cmn-label" x="165" y="58">batch</text>
  <rect class="cmn-label-plate" x="392" y="108" width="88" height="16" rx="4"/><text class="cmn-label" x="436" y="120">after 90 days</text>
  <rect class="cmn-label-plate" x="567" y="182" width="42" height="16" rx="4"/><text class="cmn-label" x="588" y="194">cost</text>
</svg>
</div>
<figcaption>Events arrive in batches from the relay and are stored in the day's partition. A seal job sums
whole five-minute windows by arrival time, a grace period after they end, and writes them as permanent totals;
billing reads those totals in order. The raw events are dropped once they are ninety days old, because the
windows already hold what was billed.</figcaption>
</figure>

<div class="cmn-legend">
  <span><i class="is-flow"></i> data travelling inward, then to billing (solid)</span>
  <span><i class="is-async"></i> the scheduled retention job (dotted)</span>
  <span><i class="is-money"></i> what billing reads as money (dashed, gold)</span>
</div>

1. **The relay posts a batch of events** — at most 1000 — to `POST /usage/events`, which answers 202 once they
   are stored.
2. **The whole batch is validated first.** One bad event rejects the batch with 400 and stores nothing.
3. **Each event lands in the day's partition** of `usage_event`, keyed by `(event_id, started_at)`, so a
   resend is a duplicate rather than a second row.
4. **`SealJob` sums complete windows.** Every 60 s it takes every whole five-minute window that ended at least
   60 s ago and writes one row per `(organization, API key, model, mode)` into `usage_window`.
5. **Billing pulls the sealed rows** in cursor order, so a window is billed once and in sequence.
6. **`PartitionJob` drops raw partitions older than 90 days**, which loses no money: the sealed windows keep
   the totals.

## Ingestion, and what idempotent means here

`POST /usage/events` takes a list of 1 to 1000 events. `UsageService.record` validates **every** event in the
batch before inserting any of them: a single bad one rejects the whole request with 400 and the table is
untouched. The insert is then a batch insert.

Idempotency is the primary key, not a dedupe table: `PRIMARY KEY (event_id, started_at)` on a table
`PARTITION BY RANGE (started_at)`. Because `started_at` is fixed for a given event — for a batch line it is the
batch's creation time — a resend lands in the same partition and collides on the same key. The relay can
therefore retry as naively as it likes.

A `DEFAULT` partition exists as a safety net, so an event whose timestamp falls outside every daily partition
still lands instead of failing the batch. Partitions are created a week ahead, so that should never be needed.

Validation is narrow and explicit: `eventId` must parse as a UUID; `requestId` (≤ 64), `organizationId`
(≤ 36), `apiKeyId` (≤ 36) and `model` (≤ 128) must be non-blank; `mode`, `tier` and `status` must be one of the
known words; token counts must be non-negative with `cachedInputTokens ≤ inputTokens`; `startedAt` must be
present, `durationMs` non-negative and `ttftMs` either absent or non-negative. Two fields are the exception to
"narrow and explicit": `reasoningTokens` and `firstOutputMs` are never checked. A figure that does not fit (reasoning
below 0 or above `outputTokens`, a first output below 0) is stored as null, "not reported", because an event refused
over a number that only describes the request is dropped by the relay and its tokens are never billed. Unknown fields
are ignored and missing ones are null, which is what lets inference-service and usage-service be rolled one at a time.

## What an event carries

| Field | Example | Note |
|---|---|---|
| `eventId` | a UUID | name-based for a batch line, so a re-run is one event |
| `requestId` | a UUID | the gateway's, the same one in the access log |
| `organizationId`, `apiKeyId` | ids | who spent |
| `model`, `mode`, `tier` | `carmona/qwen3-4b`, `sync`, `standard` | `mode` is `sync` or `batch` |
| `inputTokens` | 812 | includes the cached ones |
| `cachedInputTokens` | 640 | priced separately |
| `outputTokens` | 233 | what the customer read |
| `status` | `ok` | `ok`, `error` (ours, not billed), `cancelled` |
| `startedAt`, `ttftMs`, `durationMs` | instants and milliseconds | latency, not content |
| `reasoningTokens` | a count, or null | the part of `outputTokens` the engine reported as reasoning: already inside the output and its price, never added to either; null when not reported, never 0 |
| `firstOutputMs` | milliseconds, or null | from the start of a stream to its first content, tool call or reasoning; null for a non-streamed answer; `ttftMs` keeps its own meaning, the first content or tool call |

### The request record: thirteen more columns of the same row

A request record is the usage event's own row. `V2026.11.15.001__request_record.sql` adds thirteen nullable columns to
`usage_event` and two indexes, `(model, started_at DESC)` and `(request_id)`. Nothing is backfilled and nothing has a
`CHECK`: a value that does not fit is stored as null, "not reported", for the reason `reasoningTokens` is. The seal,
`usage_window` and the statements billing reads do not change.

| Columns | What they hold |
|---|---|
| `passedOnMs`, `understoodMs`, `engineCallMs` | whole milliseconds from the start of the request's clock, which is the gateway accepting it, to the gateway having passed it on, the body being read and parsed, and the engine call starting |
| `firstTokenMs`, `firstAnswerTokenMs`, `lastTokenMs` | the same clock to the first token of any kind (reasoning included), to the first token of content or of a tool call, and to the last token; null when the request was not streamed |
| `streamed` | whether the call was streamed |
| `engineQueueMs`, `enginePrefillMs`, `engineGenerationMs` | the engine's own timing report, on the engine's clock; null when the engine sent none |
| `httpStatus`, `errorCode`, `finishReason` | what inference-service answered (200 for a stream that failed midway), the platform's code, and a closed list of finish reasons, never the engine's own text |

A batch line is left out of every read of records (it has no request of its own to show); a flex request is a request
like any other. Time to first token, in the operator's histogram and in these columns, runs from the gateway's
acceptance of the request to the first token of any kind, so a thinking model reads shorter than its first answer token
and the gateway's own time is inside it.

### The refusal record: a table of its own

A request the platform refused is not a usage event. The seal counts every row of `usage_event` as a request of a
billing window, and the totals compared with the engines' counters count every row too, and nothing was generated or
billed for a refusal. So `V2026.11.17.001__refused_request.sql` makes a table, `refused_request`, keyed by
`(request_id, started_at)` and partitioned by day like `usage_event`, with one index `(model, started_at DESC)`.
A row holds four ids, an HTTP status, a code, the two moments the request reached (`passed_on_ms`, `understood_ms`,
null when not reached) and the duration to the refusal; no prompt, no answer, no message.

`POST /usage/refusals` takes 1 to 1000 records, beside `POST /usage/events`, internal and without a gateway route. It is
best effort, the opposite of the events: a record that does not fit (a text blank or too long, a status outside 100 to
599, a code outside the fifteen of `RefusalRecord`, a missing start or duration) is left out, the rest is stored, and the
answer is 202 whatever was left out. A resend is stored once. Only refusals of an organization's own deployment get a
record: inference-service sends at most 60 a minute for a deployment (`carmona.inference.refusal-records.per-minute`),
and usage-service reads its own `carmona.usage.refusal-records-per-minute` (60) to tell a capped minute, in which the
count is a floor. A refusal of a public model, of a batch line or by the gateway leaves none.

And what it deliberately never carries: **no prompt, no answer, no client address, no headers.** The columns
are ids, counts and timings, and the three word columns are `CHECK`-constrained so a typo becomes a rejected
batch rather than a row that breaks the pricing. This is the platform's standing rule rather than a
preference — ids and counts only, and a smoke test greps every log, the access log and a database dump for a
canary string to prove it.

## Partitions and retention

`PartitionJob` runs at startup and then daily at 00:05 UTC. For `usage_event` and then for `refused_request`, each in a
transaction of its own so that a failure of one never costs the other its run, it creates one partition per day from
yesterday to seven days ahead, and drops any partition older than 90 days. The request records and the refusal records
are therefore kept for the same 90 days. A Postgres advisory lock (`7514215`) means only
one instance does the work; the rest return immediately.

Ninety days of raw events is what the retention rule asks for, and dropping a partition is one statement rather
than a delete that has to find rows. The totals survive it: `usage_window` is not partitioned and holds what
billing actually consumed. The code notes the one way this can fail: if a row is already sitting in the
`DEFAULT` partition for a day being created, Postgres refuses to attach the new partition and the whole run
fails — which takes a badly wrong clock, and would need the rows moved by hand.

## Sealing by arrival

`SealJob` turns events into money. Its settings are `carmona.usage.window` (5 minutes),
`carmona.usage.grace` (60 seconds) and `carmona.usage.seal-every` (60 seconds); the compose stack uses 10
second windows and a 2 second grace so billing shows up within seconds of a request.

The rule is: **every whole window that ended at least `grace` ago is summed once.** In one transaction it locks
the single row of `usage_seal`, reads `sealed_until` as `from`, computes `to = floor(now - grace)`, writes the
windows in `[from, to)` and moves `sealed_until` to `to`. Windows are aligned to
`date_bin(window, received_at, origin)` with one origin, `2000-01-01T00:00:00Z`, defined once in `SealJob`: the seal's SQL
takes it as a parameter and the `floor` that computes `to` reads the same constant, so windows are stable across instances and restarts. The migration that seeds the cursor at first start wrote the same date once as a zone-less literal and is frozen.

**By arrival time, not by event time.** The seal reads `received_at`. A late event therefore falls into the
next open window instead of reopening a closed one — and that matters more than it looks: a sealed window has
already been billed, so reopening one would mean billing it twice or correcting a ledger that is append-only
by database trigger. The cost is that a request's cost lands in the window it was *reported* in, not the one it
started in.

The row lock on `usage_seal` is what makes the job safe to run on every replica: instances take turns, and a
re-run of an already-sealed range writes nothing.

`usage_window` is keyed by `(organization_id, api_key_id, model, mode, window_start)`, with an index on
`window_start` because billing walks it in that order. Failed requests are counted in `errors` and left out of
the token sums, because an error of ours is not billed. The window has no column for reasoning tokens on purpose:
billing reads only its three token sums, the summary reads events, and an older instance's seal statement, which
does not list a new column, keeps working while a roll is in progress.

## The customer-facing summary

`GET /usage/organizations/{id}/summary` is the one endpoint here a customer reaches, through the gateway's
`usage-summary` route, with a console session rather than an API key.

It does three things in a fixed order. First it requires `id-account` — a caller that forgets it gets 401
rather than everybody's numbers. Then it calls organization-service's `member(id, idAccount)`, so a stranger
reads exactly the 404 organization-service gives and never discovers that an organization exists. Only then
does it read `dailySums` for a period of at most 31 days, grouped by `model` or by `day`, capped at 100 groups.

The prices come from billing-service's `GET /billing/prices` and the arithmetic from the library's `Price`
record — `Price.at` picks the row in effect, `Price.cost` does the rounding — so the number a customer reads is
produced by the same code as the number in the ledger. If pricing cannot be reached, every cost comes back
`null`: the customer still reads their tokens, and never a number the platform made up. One unpriced row makes
its whole group's cost `null` rather than a partial sum, because a partial sum understates a bill.

Each group also carries `reasoningTokens`: the part of its output tokens that engines reported as reasoning, summed
with the same filter as the output tokens (an error of ours is left out). It is already inside `outputTokens` and
inside the price and is never added to either, so the cost does not change. It adds up only the requests that
reported it, and a group in which none did shows `null`, not 0, because 0 would claim that its model did not think.
The consequence is a known ceiling: a share taken against all of a group's output tokens understates the real one
when some of the group's engines report none, for instance an engine started without a reasoning parser. Summing the
output tokens of the events that did report, as the denominator, is the upgrade.

## What a deployment's reads return

A deployment's records are addressed by its name: its model id is `org-<organization id>/<name>`, built in
`UsageService.modelId` from the path, so a path names the records it may read and no other service is asked. Three reads
sit behind the gateway's route `usage-deployment` (one path each, 30 s), for a member of the organization with any role
and whatever the organization's state. They run in this order: a missing `id-account` is a bare 401, then
organization-service's `member`, whose 404 a stranger reads as it is, then the parameters (400 `invalid_request`), then
the permit, then the statements.

- `GET /usage/organizations/{organization}/deployments/{name}/requests` is the list: request records and refusal
  records in one list, newest first, 25 rows a page by default and 100 at most, with a cursor towards older rows. A
  `state` of `ok`, `error` or `cancelled` picks the request records and `refused` the refusal records. The first page
  says whether a refusal minute was capped (`refusalsCapped`).
- `GET /usage/organizations/{organization}/deployments/{name}/requests/{requestId}` is one request by its id, in either
  table. No record for that id and that deployment, whatever the reason, is a 404 `request_not_found`.
- `GET /usage/organizations/{organization}/deployments/{name}/window?from&to&bucket` is the window read, below.

A statement of the list or the lookup cut at the 5 s cap of the JDBC URL is a 503 `read_timeout`. Each of the three takes
one of four permits in a replica (`carmona.usage.record-reads-at-once`); a fifth read is refused at once with a 503
`server_busy` and `Retry-After: 2`. A call refused for who it is or for a bad parameter never uses a permit.

### The window read

The window read is what Visão geral of a deployment shows. `from` is required and at most 90 days back, `to` is optional
(a `to` after now is taken as now), the range is at least 300 s, and `bucket` is one of 60, 300, 900, 3600, 7200, 21600
or 86400 seconds, with at most 120 buckets in the range. A request is in the window by the start of its clock, `from`
included and `to` excluded. The answer is a 200 whenever the caller is a member and the parameters are right, with six
parts and the range it used:

| Part | What it is |
|---|---|
| `totals` | the counts by outcome and HTTP status, the rates over the range, the groups of percentiles (duration, queue wait, time to first token, time per output token, prefill, generation, generation speed), the throughput and the averages; the error rate and the throughput have no value when the window has no request |
| `series` | one entry for every bucket, an empty one included, with the bucket's requests, errors, percentiles, output throughput, peak concurrency and refused count |
| `concurrency` | the highest of the buckets' peaks |
| `refused` | the Refused count: the total, the count by error code, and whether a capped minute makes it a floor |
| `previousTotals` | the totals of the stretch of the same length that ends at `from`, with its two ends |
| `previousRefused` | that stretch's Refused count, with the total and the mark only |

A part that could not be computed is `null` and is named in `notComputed`, an object of part to reason:

| Reason | When |
|---|---|
| `over_limit` | the window holds more request records than `carmona.usage.numbers.record-limit`; `totals`, `series` and `concurrency` are then all named and nothing is computed from part of the records. `refused` has no limit of its own and still comes. The previous window has a count of its own against the same limit, which names `previousTotals` alone |
| `timeout` | a statement hit the 5 s cap, or the 20 s deadline of the read had passed before it was started (`carmona.usage.numbers.deadline`) |
| `beyond_retention` | the previous window starts before the 90 days the records are kept: both previous parts are named and no statement is asked. This is no error, as the range's own `from` may not be that old |
| `failed` | anything else; only the class of the exception is logged |

The limit is 1,500,000 request records. It was calibrated on Postgres 17 with its defaults: at that count every
statement stays under 3.5 s warm and the eight together under 14 s of the 20 s deadline, and at 2,000,000 the totals alone
take 4 s. As a steady request rate it is about 17 requests a second over 24 h, 2.5 over 7 d and 0.58 over 30 d: a window
over it comes back with its parts named `over_limit` and its Refused count still showing. The deadline starts when the
call reaches the service, before the membership check; after it no further statement is started, and the answer comes
within about 25 s. Nothing is retried. A window read never answers `read_timeout`: a cut statement is a part named
`timeout`. A name the organization does not have is a window of counts of 0, not a 404.

## Why it is like this

**Arrival time is the billing clock.** It is the only clock all parties agree on: an event carries the engine's
timestamps, but what billing can act on is when the platform learned about it. Sealing a range that can never
receive another event is what makes a window safe to bill.

**The grace period exists for the relay, not for the engine.** A window is sealed a minute after it ends, so a
batch already in flight when the window closes still lands inside it.

**Ninety days of events, and totals forever.** Raw events exist to explain a charge and to reconcile the
engines' counters. Once a window is sealed, the totals are the record.

**Request records live in the usage event's table, and a refusal never becomes a row there.** One row per request
keeps the bill and the request's story in the same place, written by the same relay with the same idempotence, with no
second pipeline to drift. A refusal is the case that breaks it: it would be counted as a billed request by the seal and
by the reconciliation, so it lives apart, best effort and capped, and is never counted in a deployment's error rate (the
[decisions page](../reference/decisions.md) has the entry).

**Errors are counted, not summed.** A request that failed inside the platform cost tokens and earned nothing,
so it appears in `errors` and stays out of the token columns. Keeping it in the table at all is what makes the
failure rate readable.

## What would change it

- **The summary prices per UTC day, not per billing window.** That is a shortcut with a known ceiling: a price
  that changed inside a day misprices that day's earlier tokens, and per-day rounding can differ from the
  per-window charge by under one micro-BRL. The ledger itself stays exact. Pricing per window, with a cursor,
  is the upgrade.
- **The relay is a Valkey stream, not Kafka**, which carries one consumer comfortably. A second consumer of
  usage events is the trigger to move.
- **The window read has a ceiling in records, not in time.** Above 1,500,000 records the totals, the series and the
  concurrency are not computed (`over_limit`); raising the limit means faster statements first: the totals, 2.6 s at the limit, set it, and the peak
  concurrency sweep sorts twice the rows (2.3 s; one scan with a lateral `VALUES` is the upgrade the code names).
- **Retention is a constant, 90 days**, and the summary's range is capped at 31 days with 100 groups.
- **Reconciliation is a comparison, not a repair.** `Reconciler` in inference-service compares the engines' own
  token counters with what was stored and warns past a threshold; nothing is corrected automatically.

## Where to look

- [UsageController.java](https://github.com/carmonaai/back/blob/main/api/usage/src/main/java/ai/carmona/usage/UsageController.java) — the four endpoints, internal and customer-facing.
- [UsageService.java](https://github.com/carmonaai/back/blob/main/api/usage-service/src/main/java/ai/carmona/usage/UsageService.java) — validation, the summary and its pricing.
- [SealJob.java](https://github.com/carmonaai/back/blob/main/api/usage-service/src/main/java/ai/carmona/usage/SealJob.java) — the window, the grace and the cursor lock.
- [PartitionJob.java](https://github.com/carmonaai/back/blob/main/api/usage-service/src/main/java/ai/carmona/usage/PartitionJob.java) — partition creation, retention and the advisory lock.
- [create_tables.sql](https://github.com/carmonaai/back/blob/main/api/usage-service/src/main/resources/db/migration/V2026.10.03.001__create_tables.sql) — the partitioned table and the seal cursor.
