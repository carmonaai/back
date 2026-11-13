# Inference

## What it is

`inference-service` is the OpenAI-compatible surface and the only service that talks to a model. It owns no
database: it receives a request the gateway has already authenticated, reduces it to a shape the engine can be
trusted with, relays the answer, and reports what was consumed.

<figure class="cmn-figure">
<div class="cmn-flow" markdown="0">
<svg viewBox="0 0 760 280" role="img" aria-labelledby="inf-title" aria-describedby="inf-desc"
     xmlns="http://www.w3.org/2000/svg">
  <title id="inf-title">A chat request narrowed to an allowlist, sent to the engine, and metered</title>
  <desc id="inf-desc">A client posts an OpenAI-shaped body; only ten fields survive the allowlist, and the
  service sets the fields that decide cost and engine behaviour itself. The engine returns tokens as they
  are generated, and when the request ends a usage event carrying counts but no text is written.</desc>
  <defs>
    <marker id="inf-arrow-flow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse"><path class="cmn-arrow" d="M0 0 L10 5 L0 10 z"/></marker>
    <marker id="inf-arrow-accent" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse"><path class="cmn-arrow" d="M0 0 L10 5 L0 10 z"/></marker>
    <marker id="inf-arrow-quiet" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse"><path class="cmn-arrow" d="M0 0 L10 5 L0 10 z"/></marker>
  </defs>
  <!-- Hops in reading order: the body in, the allowlist, the call, the tokens back, then the event. -->
  <g id="inf-hops">
    <path id="inf-hop1" class="cmn-link cmn-link--flow cmn-dash" d="M130 130 H180" marker-end="url(#inf-arrow-flow)"/>
    <path id="inf-hop2" class="cmn-link cmn-link--flow cmn-dash" d="M320 130 H370" marker-end="url(#inf-arrow-flow)"/>
    <path id="inf-hop3" class="cmn-link cmn-link--flow cmn-dash" d="M520 130 H570" marker-end="url(#inf-arrow-flow)"/>
    <path id="inf-hop4" class="cmn-link cmn-link--accent cmn-dash" d="M640 102 V74 H75 V102" marker-end="url(#inf-arrow-accent)"/>
    <path id="inf-hop5" class="cmn-link cmn-link--quiet" d="M445 158 V200" marker-end="url(#inf-arrow-quiet)"/>
  </g>
  <g class="cmn-node cmn-node--entry cmn-node--soft" id="inf-client" aria-labelledby="inf-client-label"><rect x="20" y="102" width="110" height="56" rx="10"/><text id="inf-client-label" x="75" y="122">Client</text><text class="cmn-sub" x="75" y="140">OpenAI SDK</text></g>
  <g class="cmn-node cmn-node--flow" id="inf-allowlist" aria-labelledby="inf-allowlist-label"><rect x="180" y="102" width="140" height="56" rx="10"/><text id="inf-allowlist-label" x="250" y="122">Allowlist</text><text class="cmn-sub" x="250" y="140">ten fields survive</text></g>
  <g class="cmn-node cmn-node--flow" id="inf-service" aria-labelledby="inf-service-label"><rect x="370" y="102" width="150" height="56" rx="10"/><text id="inf-service-label" x="445" y="122">Inference</text><text class="cmn-sub" x="445" y="140">sets cost and priority</text></g>
  <g class="cmn-node cmn-node--accent" id="inf-engine" aria-labelledby="inf-engine-label"><rect x="570" y="102" width="140" height="56" rx="10"/><text id="inf-engine-label" x="640" y="122">Engine</text><text class="cmn-sub" x="640" y="140">one URL per model</text></g>
  <g class="cmn-node cmn-node--soft" id="inf-usage" aria-labelledby="inf-usage-label"><rect x="370" y="200" width="150" height="52" rx="10"/><text id="inf-usage-label" x="445" y="219">Usage event</text><text class="cmn-sub" x="445" y="237">counts, never text</text></g>
  <circle class="cmn-packet cmn-travel" r="5" style="offset-path: path('M130 130 H180'); --cmn-travel: 0.9s; --cmn-delay: 0s;"></circle>
  <circle class="cmn-packet cmn-travel" r="5" style="offset-path: path('M320 130 H370'); --cmn-travel: 0.9s; --cmn-delay: 0.2s;"></circle>
  <circle class="cmn-packet cmn-travel" r="5" style="offset-path: path('M520 130 H570'); --cmn-travel: 0.9s; --cmn-delay: 0.4s;"></circle>
  <circle class="cmn-packet cmn-packet--accent cmn-travel" r="4.5" style="offset-path: path('M640 102 V74 H75 V102'); --cmn-travel: 1.4s; --cmn-delay: 0.7s;"></circle>
  <circle class="cmn-packet cmn-travel" r="4.5" style="offset-path: path('M445 158 V200'); --cmn-travel: 0.9s; --cmn-delay: 1.6s;"></circle>
  <rect class="cmn-label-plate" x="133" y="110" width="44" height="16" rx="4"/><text class="cmn-label" x="155" y="122">body</text>
  <rect class="cmn-label-plate" x="324" y="110" width="42" height="16" rx="4"/><text class="cmn-label" x="345" y="122">only</text>
  <rect class="cmn-label-plate" x="524" y="110" width="42" height="16" rx="4"/><text class="cmn-label" x="545" y="122">call</text>
  <rect class="cmn-label-plate" x="280" y="52" width="140" height="16" rx="4"/><text class="cmn-label" x="350" y="64">tokens, as generated</text>
  <rect class="cmn-label-plate" x="451" y="172" width="82" height="16" rx="4"/><text class="cmn-label" x="492" y="184">when it ends</text>
</svg>
</div>
<figcaption>The client's body is not trusted: step 1 carries it to the allowlist, and step 2 forwards only the
ten fields that survived, with the service's own values for everything that decides cost or engine behaviour.
Step 3 asks the engine, step 4 streams the tokens back along a path of their own, and step 5 reports counts
once the request has ended.</figcaption>
</figure>

<div class="cmn-legend">
  <span><i class="is-flow"></i> a request travelling (solid)</span>
  <span><i class="is-accent"></i> tokens coming back (dashed)</span>
  <span><i class="is-async"></i> the usage event, after the answer (dotted)</span>
</div>

1. **The client posts an OpenAI-shaped body** to `POST /v1/chat/completions`, with the API key the gateway has
   already resolved.
2. **`ChatRequest.parse` narrows it to an allowlist** and rejects anything else, so ten client fields reach the
   engine and no more.
3. **The service fills in what it decides**: the model, `n = 1`, `max_tokens`, the stream options, and — for a
   vLLM engine — the scheduling `priority` and the cache salt.
4. **The engine's tokens travel back as they are generated**, on a path of their own, because a streaming
   answer is not a reply that arrives at the end.
5. **When the request ends, an event reports what it cost**, carrying ids and counts and never the prompt or
   the answer.

## The two endpoints

`InferenceApplication` declares two routes and nothing else:

```java
RouterFunctions.route()
    .GET("/v1/models", chat::models)
    .POST("/v1/chat/completions", chat::chat)
```

`GET /v1/models` (and `GET /v1/models/{id}`) is built from `carmona.inference.models` in configuration and from the
models registered while the service runs — the model list is configuration, not code, so adding a model is adding a YAML entry
([Adding a model](#adding-a-model)) or registering one ([below](#models-registered-while-the-service-runs)); a model that
belongs to an organization is listed for that organization's keys only. Each model object has OpenAI's `id`, `object`, `created` and `owned_by`,
then `context_window` and `max_output_tokens`, the model's own sizes, which a client needs to fit its requests
to it, and `reasoning_efforts`, only for a model that lists levels of reasoning. `POST /v1/chat/completions` is
the one that matters. There is no `GET /v1/embeddings`: it is not hidden or unimplemented behind a flag, it does
not exist, and an OpenAI SDK that calls it gets a 404.

## The allowlist

Exactly these fields are copied through: `messages`, `temperature`, `top_p`, `stop`, `presence_penalty`,
`frequency_penalty`, `seed`, `tools`, `tool_choice`, `parallel_tool_calls`.

Everything else is either refused or replaced. The service sets `model`, `n = 1`, `max_tokens`, `stream`,
`stream_options` when streaming, and for a vLLM engine `priority` and `cache_salt`. That list is the point: a
client cannot choose its own scheduling priority, cannot ask for multiple completions, cannot claim a larger
output budget than the model allows, and cannot pass a vLLM extension, a `chat_template_kwargs` or a user id
through to the engine. The one engine setting a client does steer is the reasoning level, and only among the
levels the model's entry lists ([Reasoning level](#reasoning-level)).

| Condition | Status | `code` |
|---|---|---|
| the declared length is over the largest body any model takes | 413 | `request_too_large` |
| the body is not a JSON object | 400 | `invalid_json` |
| `messages` missing, not an array, or empty | 400 | `invalid_messages` |
| a content part that is not text | 400 | `unsupported_content` |
| `n` present and not 1 | 400 | `unsupported_n` |
| `service_tier` not `auto`, `default` or `flex` | 400 | `unsupported_service_tier` |
| `max_tokens` outside 1…`max-output` | 400 | `invalid_max_tokens` |
| `reasoning_effort` is not one of the levels the model lists (only for a model that lists some) | 400 | `invalid_reasoning_effort` |
| the body is larger than `context-window × 16` bytes | 413 | `context_length_exceeded` |
| `model` is not one the caller may see: not configured, not registered, or registered for another organization | 404 | `model_not_found` |
| the bytes of request bodies the service holds at once would pass its budget | 503, with `Retry-After: 5` | `server_busy` |

The request-size limit follows the configured models; it is not a constant. The most the service accepts of any
request is the biggest `context-window` of its models times 16 bytes (`BodyLimit`, from `maxBodyBytes`; with the registry on, the larger of that and `carmona.inference.registry.max-context-window` times 16 bytes, read at start), and the
codecs that read bodies, a non-streamed answer of an engine among them, are given that figure too, never less than
Spring's own 256 KiB, which is what the engines' `/metrics` page and usage-service are read with. A model with a
window of 1,048,576 tokens takes bodies of up to 1,048,576 × 16 = 16,777,216 bytes (16 MiB), and a smaller model
in the same service is still held to its own bound. The declared `Content-Length` is checked against the largest
bound first, on the head of the request and before the model is known (`BodyDrain`), so a request over it answers
`request_too_large`, ahead of `context_length_exceeded`, which needs the model and so comes after the parse. A
body with no declared length is cut by the codecs as it is read, with the same `request_too_large`, and the rest of it is not read first (no caller
sends one, the gateway requires a length: [gaps](../reference/gaps.md)). A non-streamed
answer of an engine that is longer than the limit is the engine's failure (a 502), no longer a 413.

The answer to a refused length waits for the body. The service reads what is left of it and throws it away, every buffer released as it arrives and nothing
kept, parsed or reserved, and sends the 413 when the last byte is in, so that no sender is still writing when the answer goes out, whatever a platform does with a
connection that is closed on bytes nobody read. The reading is
bounded by `carmona.inference.body.drain-up-to`, 64MB unless set, which should be at least the gateway's `chat-max-size` (32MB as shipped) so that every body the
gateway lets through is read to its end; a declared length above it is answered at once with `Connection: close`, and its body is never read. The cost is
bandwidth spent on a body that is thrown away, and the service has no timeout of its own on it: the gateway's body timeouts cut a slow sender. At 64 MiB the
default leaves something to read only while the biggest window is under 4,194,304 tokens (4,194,304 × 16 = 67,108,864 bytes = 64 MiB); for a model with that window
or more every refused length is already above the setting, nothing is read and the early answer with the close is what comes back, so raise `drain-up-to` together
with `chat-max-size`. A refused body reserves nothing from the budget and is not counted by `carmona_inference_body_refused_total`, which is the `503 server_busy`
count: it is one more 413 in `http_server_requests_seconds_count` ([Observability](../operations/observability.md)).

The bound says how big one body may be, not how many may be in flight. A body is on the heap as text, as a parsed
tree and as the text sent to the engine, so a burst of large ones could exhaust the heap and take every running
stream with it. Before the body of a chat request is read it reserves the length it declares (the largest bound,
when it declares none) from a budget of `carmona.inference.body.budget`, a tenth of the JVM's maximum heap unless
the setting says otherwise, and gives it back when its exchange ends, however it ends. One that does not fit is
`503 server_busy`, its body unread and the engine not called; the budget has to be at least the largest bound, or
the service does not start. A body longer than `carmona.inference.body.offload-above` (256 KB, measured on the
body's text, so a body of multi-byte characters is offloaded at a larger size in bytes) is parsed and guarded on a
worker of the service's own, so that megabytes of JSON do not stall every stream the event-loop thread serves; a
guard must not rely on which thread it runs on. A refusal is logged as a WARN, as every 5xx of the service is.
The meters are `carmona_inference_body_reserved_bytes` and `carmona_inference_body_refused_total`
([Observability](../operations/observability.md)). Everything the budget says about the heap is an estimate
derived from the copies the code makes, not a measurement; the comment in `application.yaml` says so too.

Content is text only — no `image_url`, no audio, no file parts — so the engine never fetches anything on a
request's behalf. `max_completion_tokens` wins over the older `max_tokens`, and neither present means the
model's own output cap.

Two settings are always the platform's, whatever the client asked:

- **Usage is always requested from the engine.** `stream_options` is set to
  `{"include_usage": true, "continuous_usage_stats": true}` on every streaming request. The client's own
  `include_usage` flag decides only whether *the client* sees the usage block; billing's copy is not optional.
- **`cache_salt` is the organization id.** Each tenant gets its own prefix cache, so one organization cannot
  time another's cached prompts — and since the field is not in the allowlist, a client cannot set it either.
  How a customer lays out a prompt to hit its own cache is on [Prompt caching](../inference/prompt-caching.md).

`priority` follows the tier: `enterprise` 0, `standard` 10, `trial` 20, and 30 for a batch line or a flex
request. vLLM runs lower values first and preempts them last, so this is the whole of the tier's scheduling
effect — the rest of it is [admission](../requests/admission.md).

## Reasoning level

`reasoning_effort` is OpenAI's field for how long a model that thinks may think. What becomes of it is decided by
the model's entry, never by the client:

- **A model whose entry lists no `reasoning.efforts` takes no level.** The field is ignored and nothing of it
  reaches the engine, exactly as before the levels were configurable: the upstream body of such a model is
  byte-identical to what it was (`GoldenUpstreamBodyTest` pins it).
- **A model that lists levels takes one of them.** A listed string is the level. An unlisted one, or a value that is
  not a string, is `400 invalid_reasoning_effort` with the text `reasoning_effort must be one of low, high, max.`
  (the levels of the entry; the text is built from configuration and never from what the client sent). A JSON
  `null` is no level.
- **The level reaches the engine as the field `reasoning_effort`**, or, when the entry sets `reasoning.template-kwarg`,
  as `chat_template_kwargs.<that name>`, for a chat template that reads its level from a keyword argument. A client's
  own `chat_template_kwargs` never gets through, either way.
- **A client that names no level gets the entry's `reasoning.default`,** if it has one. None is shipped: the right
  default is found by measuring the model. Without a default nothing is sent and the engine's own default applies.

The levels are words, so each is 1 to 32 characters of `a-z`, `0-9` and `_`, none twice, because they reach an error
text and the engine's body. `GET /v1/models` shows a model's levels as `reasoning_efforts`, in the order its entry
writes them; the default and the keyword stay the operator's. Reasoning tokens are part of the output tokens: they
are inside `completion_tokens`, so they are billed at the output price and nothing prices them separately (see
[the usage event](#the-usage-event-it-produces)).

## `flex`

`service_tier: "flex"` is OpenAI's spare-capacity lane, and it is honest about what it buys: batch prices at
batch priority, on the model's spare capacity only. A flex request keeps its organization's rate buckets and
its in-flight cap, but takes the share of the model's slots that batch traffic takes — which means it is
admitted only when there is room, and refused at once rather than waiting, with a 429 saying there is no spare
capacity right now. Nothing is billed for a refused request.

`auto` and `default` mean the standard lane, and any other value is a 400. A batch line is already running in
the half-price lane, so `flex` is ignored for it rather than applied twice.

## The identity it reads

`Caller.from(headers)` reads three headers and nothing else: `id-organization`, `id-api-key` and `tier`. The
gateway sets them and strips any inbound copy, so a request that arrives without them did not come through the
gateway and is answered 401 `invalid_api_key`. A `tier` outside `trial`, `standard`, `enterprise` fails the
same way.

The fourth is `batch-line`, of the form `{batchId} {line} {batchCreatedAt}`, which marks a request
batch-service is running for a batch. The gateway strips that header too, or a client could buy answers at
batch prices.

## The usage event it produces

`UsageEvent` is usage-service's `UsageEventIn` shape: `eventId`, `requestId`, `organizationId`, `apiKeyId`,
`model`, `mode`, `tier`, `inputTokens`, `cachedInputTokens`, `outputTokens`, `status`, `startedAt`, `ttftMs`,
`durationMs`, `reasoningTokens`, `firstOutputMs`. Ids and counts — never the prompt, the answer, or the caller's
address.

The last two describe the request and are no part of the bill. `reasoningTokens` is what the engine reported in
`completion_tokens_details.reasoning_tokens`, the last value it reported, never more than `outputTokens`; it is
a part of `outputTokens` and is never added to it, to a price or to the engine reconciliation. `firstOutputMs` is
the time from the start to the first content, tool call or reasoning of a stream, so for a model that thinks first
it is the end of the prefill, where `ttftMs` (first content or tool call) waits for the answer. Each is null when
the engine or the service could not know it (an engine without a reasoning parser, a non-streamed answer, a stream
that produced nothing), never 0.

Four details are decisions rather than plumbing:

- **The outcome is the event's status.** How a request ends — ok, an error of ours, or cancelled by a client
  that hung up — sets `status`, and `Tracker` follows the request without keeping its text to be able to say
  which happened.
- **`mode` is `sync` unless the request came from batch-service, or asked for `flex`.** Both of those run in
  the half-price lane, so both are recorded as `batch`.
- **A batch line's event id is a name-based UUID of `(batch, line)`, and its `startedAt` is the batch's
  creation time.** So however many times a line is retried or a worker is killed, the event's identity is the
  same and it is stored, and billed, once.
- **An engine's answer that is no answer is an error of ours.** A non-streamed answer with status 200 whose body is empty, is not JSON or is not an
  object with a `choices` array is the engine's failure: the caller gets 502 `engine_error`, the event is an `error` one, the slot is given back and
  the failure is counted as any engine failure is. Nobody is billed for it, because usage-service leaves `error` events out of the window sums that
  billing charges and out of the customer's summary ([Metering](metering.md)). The check reads the answer the tracker already parses for its usage, so
  there is no second parse, and nothing the engine sent reaches the caller's answer, the event or a log. An object with an empty `choices` array still
  passes: the rule is the shape, and the usage says what was spent. Before it, an engine that answered 200 with nothing was passed on as an empty 200 and
  billed as `ok` on the input estimate, which is what the live check of 2026-11-13 met. A streamed request is not covered: an engine that answers 200 and
  ends with no data line still gives the caller a 200 with an empty event stream and an `ok` event on the input estimate ([gaps](../reference/gaps.md)).

The event goes to the Valkey stream `usage:events`; a relay delivers batches to usage-service every second and
deletes them once they are stored. A killed instance loses nothing: the stream is append-only on disk, and an
entry that was never confirmed is claimed again after `carmona.inference.usage-claim-after` (60 s).
[Metering](metering.md) takes it from there.

## Adding a model

A model is an entry of `carmona.inference.models`: settings alone, no code, and nothing in the backend is named
after or sized for one model. The backend reads no architecture, no weights and no `config.json`; it holds numbers
and names. Which models an engine can load is the engine's question (the engine is vLLM, ADR 0002), and the
backend adds no limit of its own to it. Kimi K3.1-Pro on a rented node, `carmona/kimi-k3.1-pro`, is the first worked
example (entry 4 of `docker/models.example.yaml`), not a special case. Every key is described where it lives, in
[application.yaml](https://github.com/carmonaai/back/blob/main/api/inference-service/src/main/resources/application.yaml);
this is what they mean together.

**The entry.** The first group is required and has no default, because each value depends on the model and on its
hardware. A model that leaves one out does not start: the service stops, and the message names the model and the
rule, never an address.

| Key | Rule | What it is |
|---|---|---|
| `id` | required | What clients send, what billing prices and what goes to the engine as `model`: it equals the engine's served model name. It may contain a slash (`carmona/example`). |
| `created` | required, not in the future | When the model became available, an ISO instant; `GET /v1/models` shows it as Unix seconds. |
| `url` or `replicas` | one of the two | The engine's address, or a list of engine replicas, each with its own `slots`, `queue` and `kv-tokens` if it differs. |
| `api-key` | needed in practice | The key the engine was started with (`--api-key`). The service does not check it at start. |
| `context-window` | required, at least 1 | Tokens per request. The engine's `--max-model-len` must be at least this: the contract check warns when it is below. |
| `max-output` | required, 1 to the window | The cap on `max_tokens`, and what a request that names none is given. Your choice, not a measurement. |
| `slots` | required, at least 1 | Requests the engine runs at once, per replica: on the model, or on every replica. |
| `queue` | required, 0 or more | Places that may wait at the engine, per replica: on the model, or on every replica. 0 is legal: a request then needs a free slot. |
| `kv-tokens` | optional | The engine's KV cache in tokens, for an engine that exposes none. The engine's own reading, taken at start, wins. |

Everything else is optional and falls back to the global key of the same name, so a model that sets none of it
behaves exactly as before these keys existed:

| Key | What it sets for this model alone |
|---|---|
| `reasoning.efforts`, `.default`, `.template-kwarg` | The levels a client may ask for, the level sent when it names none, and the chat-template keyword that carries the level ([Reasoning level](#reasoning-level)). |
| `tiers.<tier>` | The limits of one tier (requests per minute, input and output tokens per minute, `max-in-flight`), replacing the global ones for that tier on this model. An entry is a whole set, so it states all four keys; a tier left out keeps the global limits. The limits that admit a request are the ones that settle it ([admission](../requests/admission.md)). |
| `ttft-timeout`, `idle-timeout`, `response-timeout` | The model's own timeouts, each at least 1s with its unit (a bare `30` is 30 ms). `response-timeout` is at most the global one, from which the shutdown phase, the container's grace period and the gateway's route wait are sized. |
| `prefill.ms-per-token`, `prefill.ceiling` | The model's own prefill allowance: the first-event wait grows from `ttft-timeout` by `ms-per-token` for each estimated input token (the body's bytes ÷ 4), up to `ceiling`. A rate of 0 turns the allowance off for this model. The ceiling is 1s to 600s and at least the model's `ttft-timeout` once the rate is above 0, or the service does not start, naming the model. |
| `carmona.inference.control-tokens.models[].roles` | The message roles the model accepts, replacing the global list for it alone, next to that list's per-model patterns. Another model still refuses `developer`. |

Two things join the entry to the rest of the service. The slots plus the queue of each replica must be at most
`max-connections` (64): the engine pool is per engine address, so a replica that admission lets hold more requests
than the pool has connections would be answered 503 for requests admission let in, and the service does not start.
And the levels of a reasoning model are words, which YAML can read as something else: write a level such as `"off"`,
`"on"`, `"yes"` or `"no"` in quotes, because unquoted they bind as booleans.

**Where the entry lives.** In compose, in a file: copy `docker/models.example.yaml` to `docker/models.yaml` (git
ignores it), keep the entries you serve, set what their comments ask for, and start the stack with
`docker compose -f compose.yaml -f compose.minio.yaml -f compose.models.yaml up -d --build --wait`. The overlay
mounts the file read-only into inference-service as an additional configuration location, takes the model keys of the
environment away and starts no simulator. Engine keys stay in `docker/.env`, which the file reads as `${NAME}`
placeholders. The environment form still works (`CARMONA_INFERENCE_MODELS_<n>_ID`, `_URL`, `_SLOTS` and so on, a list as
one comma-separated value), but an environment that defines any element of the list replaces the whole YAML list, so
every model must be restated; the file is the way to serve more than one. The configured list is read once, at start. Adding,
changing or removing a configured model is an edit of the file and a restart of inference-service
(`up -d --force-recreate inference` with the same `-f` flags): only that container is recreated, and it lets the streams
it holds finish, because its `stop_grace_period` is 720 s. A model that is added while the service runs is registered,
not configured ([below](#models-registered-while-the-service-runs)).

**Keeping the simulator with a large window.** The engine of the default stack is a simulator (`llm-d-inference-sim`, ADR 0002), and it takes request bodies
of up to 4 MB unless told otherwise: `--max-request-body-size-mb`, its own default, in MB of 1,048,576 bytes, which it accepts from 1 to 512 and refuses to
start outside. The service takes `context-window` × 16 bytes of body, so any window over 262,144 tokens (262,144 × 16 = 4,194,304) lets through a body that the
simulator closes the connection on before it answers; the service retries once, and the caller gets 503 `engine_unavailable`. The live check of 2026-11-13
([progress](https://github.com/carmonaai/back/blob/main/.claude/skills/carmona-architecture/references/any-model-progress.md)) saw this with a body of 5 MiB on an
entry of 1,048,576 tokens, whether or not the simulator's own window and KV cache were raised to the entry's, and saw the same body answered 200 in 2.07 s with
the cap at 64. `docker/compose.yaml` therefore takes the cap from a variable: set `ENGINE_MAX_REQUEST_BODY_MB`, in `docker/.env` or in the shell, to at least the
largest body you will send (16 for a window of 1,048,576 tokens) and recreate the engine. Unset, it is the simulator's own 4 and the stack does not change. The
variable is in the engine's command in `compose.yaml` and not in the models overlay, which starts no engine and whose override of `command` would replace the
whole list and so restate every flag of the simulator; it works under the overlay all the same, whose `--profile simulator-off` brings the simulator back.
`compose.fleet.yaml` restates the other flags and not this one, and its simulators keep the 4.

The simulator is no model of a real engine's limits, and the live check ran no other engine. It answers with its prompt (echo mode), so a body within about 230
bytes of the bound gets an answer longer than the service reads from an engine (5,243,110 bytes came back for 5,242,880 sent), which is a 502 `engine_error`: a
body of exactly the bound got one, the cause was not shown, and this is the likely one. In that mode it also refuses a prompt of more than half its
`--max-model-len` in its own tokens (about one per word), and one longer than `max_tokens`, with a 400. To test the plumbing of a large body, send one unbroken run
of a single character, as the live check did, and not prose.

**What the engine must be started with.** The backend's contract with a vLLM engine is a launch recipe as much as a
set of keys. Each line below was read in vLLM's documents on 2026-11-12 (the OpenAI-compatible server and serving pages,
and the source of its chat serving) and has not yet been checked by us on a real engine. Nothing stops at start when
one is left out: the service starts, and the failure shows later, as a 404 from the engine, as an error on every chat
request, as refusals of every tier but enterprise, or as an input bill without the cached discount.

| Start the engine with | Because |
|---|---|
| `--served-model-name` equal to the entry's `id` | The service sends the id to the engine as `model`. With another name every request is a 404 from the engine, while the contract check only warns. |
| `--scheduling-policy priority` | The service sends `priority` 0, 10, 20 or 30 by tier. vLLM raises an error for a priority other than 0 when the model is not served with priority scheduling, so without it only enterprise requests pass. A test with an enterprise key proves nothing about the other tiers. |
| `--enable-prompt-tokens-details` | Without it the usage chunks carry no cached token count, which reads as 0: all input is billed at the full input price and none at the cached price. |
| a chat template | Without one the engine cannot process chat and every chat request errors. A model whose repository ships none needs `--chat-template`. |
| `--reasoning-parser`, for a model that thinks | The engine reports `completion_tokens_details.reasoning_tokens` only when a reasoning parser is configured; without it `reasoningTokens` stays null and the response carries no separate `reasoning` field (the page we read does not say where the thinking text goes then). |

The engine's `--max-num-seqs` is the entry's `slots`, and its `--max-num-queued-reqs` is the slots plus the queue,
as `docker/compose.gpu.yaml` starts vLLM. `contract.fail-fast` stays false for a model nobody has measured: it ends the
whole JVM, for every model, when one engine is still loading after the startup grace.

**What must be measured before a model serves customers.** Nothing in the backend refuses an unmeasured model, and
nothing here is invented for one. A value that only a run on the model's own hardware gives is left to that run:

- `slots` and `queue` are the saturation concurrency C and the queue q from the bench (see
  [capacity](../inference/capacity.md)), the numbers the engine is started with too. For a test, the safe settings are
  `slots: 1` and `queue: 0`, no `kv-tokens`, no reasoning levels and none of the optional keys; the cost is that a
  second request at the same moment is refused with a 429 `model_busy`.
- `ttft-timeout` and `prefill.ms-per-token` come from the cold curve: the time to the first event of cold prompts of two
  or three sizes. Without them every prompt gets the global 30 s, and a long cold prompt on a large model can be cut
  with a 503 `engine_timeout` and its work thrown away. A placeholder in the models file whose variable is set but
  blank reaches the container empty: the required numbers (`slots`, `queue`, `max-output`) are still refused then, but
  these two are optional and bind as null, so they fall back to the global 30 s and to no allowance, and the service
  starts. Give them a value; do not leave them blank.
- `reasoning.default` is left unset until a run shows which level suits the model.
- `tiers` are sized from C and q. The global ones are prototype values: the trial tier's input bucket is 20,000
  tokens a minute, so one prompt of 1,048,576 tokens takes about 52 minutes of it (1,048,576 ÷ 20,000), and a bucket
  that may go negative then keeps that organization waiting for the refill. Admission does not refuse a request for its size: it asks that each bucket holds at
  least 1, charges the whole input estimate, and corrects it to the engine's own prompt count when the request ends ([admission](../requests/admission.md)). So
  the first request near the window passes for every tier: in the live check of 2026-11-13 a body of 5 MiB (1,310,720 estimated tokens) was admitted for a
  trial organization, and its `x-ratelimit-remaining-tokens` read 0 of 20,000, a header that never shows below 0.
- A price row in billing, in the future (the price trigger refuses past dates). Without one the usage is metered, billing
  sets the charge aside, and the first price that appears bills the back log at that price, so the usage of a test can be
  billed after the fact: give a test model an id of its own. A model registered for an organization needs no row: its id
  starts with `org-` and it is priced zero by rule ([Money](../data/money.md)).
- Prometheus finds its engine jobs by DNS name, so a remote engine is not scraped there; the service's own
  `carmona_engine_*` gauges still show it.

**The roll order is usage-service before inference-service.** The new usage event fields need the columns that
usage-service's migration `V2026.11.12.001__reasoning_and_first_output.sql` adds. A usage-service that is still the
old one ignores fields it does not know, so nothing breaks the other way round, but the `reasoningTokens` and
`firstOutputMs` of every event that arrives before it is rolled are lost. A new usage-service takes events without the
two fields and stores them as null. gateway-service has no order to keep: its caps are settings with defaults.

## Models registered while the service runs

A model need not be in the configuration. [model-service](model.md) keeps a list of registered models in its database and
inference-service follows it while it runs. Nothing on a request's path calls model-service or waits for it, and the models of the
configuration stay as they are: always there, and first. The feature is on when `carmona.inference.registry.url` is set (compose:
`http://model:8080`); blank, it is off, none of the meters below exists and the service is as it was.

| Key | Rule |
|---|---|
| `carmona.inference.registry.url` | model-service's address: an http or https url with a host and no user name or password. A refusal names the property and never quotes the url |
| `carmona.inference.registry.refresh-every` | `5s`: how often the list is read; at least 1s, with its unit |
| `carmona.inference.registry.max-context-window` | required when `url` is set, no default: the largest `context-window`, in tokens, a registered model may have. It also sizes the request-size limit ([above](#the-allowlist)), so a higher one takes a restart |
| `carmona.inference.registry.max-models` | `32`, at least 1: the most registered models at once. Each adds a scrape of its replicas and its series to the meters, so this bounds that fan-out; it is no measured limit |

The ceiling is one number with two readers that must agree: model-service refuses a registration above its own
(`carmona.model.max-context-window`), and inference-service neither follows a model above this one nor reads a body bigger than it
allows. Compose feeds both from one variable. A configured model may not have an id that starts with `org-`: that namespace
belongs to the models an organization registers for itself, which are metered and never charged per token.

**How the list is read.** One loop on a timer of its own (`ModelRosterSync`) asks `GET /models/active`, with the secret of
`carmona.internal.token-file` in the header of this one client and no other, in pages of 100. On its first page it names the version
it last applied whole, and an answer that nothing changed applies nothing. A list is applied only whole and only of one version: pages
whose versions differ (the list moved while it was read) drop that pass and count it `inconsistent`, and so do a page that fails, an
answer that is no page and one that does not come in time, counted `failed`. A dropped pass changes nothing, so **a model-service that
is down leaves every model that runs as it is**: inference-service keeps the last list it read, and what grows is the age of the list. After a failure the pause doubles up to a
minute, with a quarter of jitter either way; the loop has no circuit breaker, because this service has no Resilience4j.

**What is applied.** Each entry is read by the rules of a configured model and never taken on trust: an id that breaks the model id
rule, a namespace that is not its owner's (`org-<owner id>`, and no `org-` for a model without one), an id that is a configured
model's (the configuration wins), a missing key, more than 16 replicas, a slot count that is absent (none is invented here) and a
window above the ceiling are all refused. The first `max-models` entries by id are read, and a running model beyond them goes like one
that left the list. An entry that breaks a rule is skipped alone, with its id and the rule in the log, and counted in
`carmona_inference_models_skipped`; a model that is running keeps its last good version, because failing closed would stop a
customer's model for a typo. **A model that changed is retired and then appeared again**, a changed replica list included, in one
swap: there is no rule that the replicas of a registered model cannot change. The cost is a transient: leases are keyed by a replica's
place in the list, so after the list changes the leases of the old model's running requests count against the engine now at that
place until they end, an over-count for as long as the longest of them and never a lost lease.

**Who sees what.** A configured model, and a registered one with no owner, is public. A registered model with an owner is listed by
`GET /v1/models` and found by a chat request for that organization's keys only. For every other caller, a model of another
organization, a retired one and an unknown one alike, it is the same `404 model_not_found`, so no request can learn that a model
exists. The operator's tools (drain, the replica states, the scrape) see every model. The gateway's credit rule is unchanged and
knows no model: an organization with no credit is refused before any model is looked at, so it cannot call its own model either.

**Retire.** A new request no longer finds the model (404) and the listing drops it within one read. A request that is running holds
the model it found: its lease is renewed and given back through that model, its stream ends, and its usage event names the model and
is metered like any other. What goes: the readers of the model's leases, the contract check of its replicas, the health gate's
opinion of them and the gauges of the model. **What stays until a restart**, a few numbers for each id that was ever registered: the
lease budgets and the count of what this JVM holds, one engine-timeouts object, the counters and timers of the model, and, in Valkey,
the replica-state hash, which has no expiry. A model registered again under the same id takes these over.

**Start, and a model-service that is not there.** The first read is part of the start, cut at two seconds, after the replica states
and before the web server takes a connection. With model-service down the service still starts and serves the configured models, a
registered model is a 404 until the first read succeeds, and the loop brings it in within a refresh. There is no local copy of the
list, so a restart while model-service is down forgets every registered model until it is back.

**Meters.** Four exist only while the registry is on, and carry ids and counts, never an organization, a key or an address:
`carmona_inference_models_age_seconds` (seconds since the last good read, an "unchanged" answer included; from the start of the
process until the first one, so a model-service that never answered shows as growing and not as missing),
`carmona_inference_models{source}` (`configured` or `registered`), `carmona_inference_models_skipped` (the entries the last pass
refused: a registered model that is not being served) and `carmona_inference_models_refresh_total{outcome}` (`ok`, `failed`,
`inconsistent`, at 0 from the start). The alerts are `ModelListStale` and `ModelEntrySkipped`
([Observability](../operations/observability.md)).

## Why it is like this

**An allowlist, not a denylist.** A denylist has to enumerate everything a future engine version might accept,
and it is wrong the moment the engine adds a field. Ten names that are known to be safe stay correct.

**Nothing that decides cost comes from the client.** `model`, `max_tokens` and `n` are the three fields that
determine what a request costs, and all three are set here. A client that could set `n` could multiply its own
bill, and a client that could set `priority` would be scheduling itself ahead of other tenants.

**The tokens come back on their own hop.** A streaming answer is not a reply that exists at the end, so the
diagram separates it: the client may be reading the first token while the last one has not been decided. That
is also why the timeouts are what they are — a first token within 30 s, silence between tokens never longer
than 30 s, and a whole non-streamed answer within 600 s.

**The usage event is written after the request ends, deliberately.** Settlement of the rate buckets happens
before it, so a client cannot be billed twice by a retry of the accounting, and the event describes a request
that is over rather than one in flight.

## What would change it

- **Flex usage is recorded in mode `batch`.** That is what the half-price lane prices, so it is correct today
  and wrong the moment flex needs a price or a report of its own — a `flex` mode, with the migrations that go
  with it.
- **One engine endpoint per model.** `carmona.inference.models` maps a model id to a single URL. Routing
  across replicas needs more GPUs and a different model of capacity.
- **In-flight caps live in one JVM's memory.** Admission's per-tier and per-organization caps are a single
  replica's view, so a second replica would double them.
- **There is no `GET /v1/embeddings`**, and the model list is the configuration plus what is registered, not a catalogue of every model an engine could serve.
- **Tracing is not wired**, so a request id is the only thing joining these logs to the gateway's.

## Where to look

- [InferenceApplication.java](https://github.com/carmonaai/back/blob/main/api/inference-service/src/main/java/ai/carmona/inference/InferenceApplication.java) — the two routes, in full.
- [ChatRequest.java](https://github.com/carmonaai/back/blob/main/api/inference-service/src/main/java/ai/carmona/inference/ChatRequest.java) — the allowlist, the refusals and the flex lane.
- [Caller.java](https://github.com/carmonaai/back/blob/main/api/inference-service/src/main/java/ai/carmona/inference/Caller.java) — the identity headers and the batch line.
- [UsageEvent.java](https://github.com/carmonaai/back/blob/main/api/inference-service/src/main/java/ai/carmona/inference/UsageEvent.java) — what a finished request reports.
- [application.yaml](https://github.com/carmonaai/back/blob/main/api/inference-service/src/main/resources/application.yaml) — the tiers, the timeouts and the model list.
