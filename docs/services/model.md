# Model

## What it is

`model-service` owns the `models` schema and holds the list of models that are registered while everything runs: for each one its
name, the organization that rented the machine (if there is one), the address and sizes of its engines, and the engine's key, sealed.
A deploy tool or an operator registers a model it has just started; [inference-service](inference.md) reads the list on a timer and
serves what it finds. All four calls are internal: they need the shared secret, no gateway route reaches them and no port is published.

<figure class="cmn-figure">
<div class="cmn-flow" markdown="0">
<svg viewBox="0 0 760 280" role="img" aria-labelledby="mod-title" aria-describedby="mod-desc"
     xmlns="http://www.w3.org/2000/svg">
  <title id="mod-title">A model registered while the stack runs, and the list inference-service reads</title>
  <desc id="mod-desc">A deploy tool posts a model to model-service with the shared secret. The service checks it, seals the engine key and
  writes a row in Postgres. On a timer inference-service asks model-service for the list of active models, receives it with the keys, and
  from then on calls the engine with that key.</desc>
  <defs>
    <marker id="mod-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse"><path class="cmn-arrow" d="M0 0 L10 5 L0 10 z"/></marker>
  </defs>
  <!-- Hops in reading order: the registration, the row, the timer's question, the list, the engine call. -->
  <g id="mod-hops">
    <path id="mod-hop1" class="cmn-link cmn-link--flow cmn-dash" d="M140 68 H224" marker-end="url(#mod-arrow)"/>
    <path id="mod-hop2" class="cmn-link cmn-link--flow cmn-dash" d="M299 96 V170" marker-end="url(#mod-arrow)"/>
    <path id="mod-hop3" class="cmn-link cmn-link--flow cmn-dash" d="M514 56 H374" marker-end="url(#mod-arrow)"/>
    <path id="mod-hop4" class="cmn-link cmn-link--accent cmn-dash" d="M374 82 H514" marker-end="url(#mod-arrow)"/>
    <path id="mod-hop5" class="cmn-link cmn-link--flow cmn-dash" d="M599 96 V170" marker-end="url(#mod-arrow)"/>
  </g>
  <g class="cmn-node cmn-node--entry cmn-node--soft" id="mod-tool" aria-labelledby="mod-tool-label"><rect x="20" y="40" width="120" height="56" rx="10"/><text id="mod-tool-label" x="80" y="60">Deploy tool</text><text class="cmn-sub" x="80" y="78">curl and the secret</text></g>
  <g class="cmn-node cmn-node--flow" id="mod-service" aria-labelledby="mod-service-label"><rect x="224" y="40" width="150" height="56" rx="10"/><text id="mod-service-label" x="299" y="60">model-service</text><text class="cmn-sub" x="299" y="78">checks, seals the key</text></g>
  <g class="cmn-node cmn-node--flow" id="mod-db" aria-labelledby="mod-db-label"><rect x="224" y="170" width="150" height="56" rx="10"/><text id="mod-db-label" x="299" y="190">Postgres</text><text class="cmn-sub" x="299" y="208">schema models</text></g>
  <g class="cmn-node cmn-node--flow" id="mod-inference" aria-labelledby="mod-inference-label"><rect x="514" y="40" width="170" height="56" rx="10"/><text id="mod-inference-label" x="599" y="60">inference-service</text><text class="cmn-sub" x="599" y="78">applies the list whole</text></g>
  <g class="cmn-node cmn-node--soft" id="mod-engine" aria-labelledby="mod-engine-label"><rect x="514" y="170" width="170" height="56" rx="10"/><text id="mod-engine-label" x="599" y="190">Engine</text><text class="cmn-sub" x="599" y="208">on a rented GPU</text></g>
  <circle class="cmn-packet cmn-travel" r="5" style="offset-path: path('M140 68 H224'); --cmn-travel: 1.1s; --cmn-delay: 0s;"></circle>
  <circle class="cmn-packet cmn-travel" r="5" style="offset-path: path('M299 96 V170'); --cmn-travel: 1.1s; --cmn-delay: 0.4s;"></circle>
  <circle class="cmn-packet cmn-travel" r="4.5" style="offset-path: path('M514 56 H374'); --cmn-travel: 1.2s; --cmn-delay: 0.9s;"></circle>
  <circle class="cmn-packet cmn-packet--accent cmn-travel" r="4.5" style="offset-path: path('M374 82 H514'); --cmn-travel: 1.2s; --cmn-delay: 1.3s;"></circle>
  <circle class="cmn-packet cmn-travel" r="4.5" style="offset-path: path('M599 96 V170'); --cmn-travel: 1.1s; --cmn-delay: 1.8s;"></circle>
  <rect class="cmn-label-plate" x="143" y="44" width="78" height="16" rx="4"/><text class="cmn-label" x="182" y="56">POST /models</text>
  <rect class="cmn-label-plate" x="307" y="125" width="68" height="16" rx="4"/><text class="cmn-label" x="341" y="137">sealed key</text>
  <rect class="cmn-label-plate" x="388" y="30" width="112" height="16" rx="4"/><text class="cmn-label" x="444" y="42">GET /models/active</text>
  <rect class="cmn-label-plate" x="386" y="88" width="124" height="16" rx="4"/><text class="cmn-label" x="448" y="100">the list, keys included</text>
  <rect class="cmn-label-plate" x="607" y="125" width="84" height="16" rx="4"/><text class="cmn-label" x="649" y="137">key as bearer</text>
</svg>
</div>
<figcaption>Steps 1 and 2 write: a registration is checked, its engine key is sealed, and one row is written. Steps 3 and 4 read, on
inference-service's own timer, never on a request's path. Step 5 is what a customer's request then does: it is sent to the engine at
the address the entry names, with the key the entry holds.</figcaption>
</figure>

<div class="cmn-legend">
  <span><i class="is-flow"></i> a call (solid)</span>
  <span><i class="is-accent"></i> the list coming back (dashed)</span>
</div>

1. **A deploy tool posts the model** to `POST /models` with the shared secret: its name, its owner organization if it has one, the
   engine's key and the engine's addresses and sizes.
2. **model-service checks it, seals the key and writes one row.** A refusal writes nothing.
3. **inference-service asks for the list** with `GET /models/active`, every 5 s by default, naming the version it last applied.
4. **The answer is the whole list of active models, keys included**, or "unchanged". inference-service applies a list whole, in one swap.
5. **The model now answers.** It is in `GET /v1/models` for the owner's keys and a chat request to it goes to the engine with the
   entry's key. A `DELETE /models/{id}` ends it the same way round: within one read the model is a 404.

## The four calls

Every call carries the header `X-Internal-Token` (the file `/run/secrets/internal_token`, read at start): missing, wrong or doubled is
a 401 before the body is read. `{id}` is the entry's UUID, never the model id, which has a slash. JSON is camelCase, times are Unix seconds.

| Call | Answers |
|---|---|
| `POST /models` registers a model | `201` with the entry, when the model id is new or was retired; `200` when the same content is registered again; `400 invalid_request`; `409 too_many_models`; `422 idempotency_conflict` |
| `DELETE /models/{id}` retires it | `204`, also when it was retired already; `404 model_not_found` |
| `GET /models/{id}` reads one entry | `200`, never the key (a retired entry has no `spec`); `404 model_not_found` |
| `GET /models/active?page=0&size=100&known=41` lists the active models | `200`: `version`, `unchanged`, `last` and the entries with their keys; a `size` above 100 is cut to 100, a negative page or a size under 1 is `400` |

Errors are a fixed text and a `code`; nothing the caller sent and no exception's message comes back. A body with a field the records
do not have is a 400, not read with a default.

## What a registration says

`modelId` is `namespace/name` in lower case (`a-z`, `0-9`, `.`, `-`, `_`; 128 characters at most): it is also the name the engine is
started with (`--served-model-name`). `ownerOrganizationId` is the organization that rented the machine, or absent for a public model;
an owned model's namespace is exactly `org-<owner uuid>` and a public one never starts with `org-`, so the two cannot meet. `apiKey`
is the bearer token the engine expects: 16 to 256 printable ASCII characters, no space. `spec` carries `contextWindow` and `maxOutput`
(at most `carmona.model.max-context-window`), 1 to 16 `replicas` (`url`, `slots`, `queue`, `kvTokens`) and, all optional, `reasoning`,
`tiers`, the three timeouts and `prefill`, with the rules of the same keys in [Adding a model](inference.md#adding-a-model). A
registered model has no roles and no control-token patterns: it runs on the global ones.

A replica that names no `slots` or `queue` is stored with 1 and 0, and the answer shows it. These are placeholders so that an
unmeasured model can be tried, never measurements; inference-service refuses an entry that arrives without them and invents none. A
replica's `url` is called from inside the network with the engine's key attached, so it is `https` (plain `http` only with
`carmona.model.allow-http`), with a host, no user name, query or fragment, and a public name or address unless
`carmona.model.allow-internal-hosts` says otherwise. This registers a public model (no owner); the address and the key are placeholders:

```bash
docker compose exec -T tools curl -s -H @/run/secrets/internal_token -H 'Content-Type: application/json' \
  -X POST http://model:8080/models -d '{"modelId":"carmona/example","apiKey":"an-engine-key-of-16-or-more",
  "spec":{"contextWindow":4096,"maxOutput":1024,"replicas":[{"url":"https://gpu-1.example.net:8443"}]}}'
```

## Retire, and register again

Retiring is `DELETE /models/{id}`: the row keeps its name, owner, sizes and history, and loses its settings and its key (the addresses
of a rented machine and its credential are the personal and secret part). The next read of inference-service removes the model from
its roster; requests already running on it finish ([what stays in memory](inference.md#models-registered-while-the-service-runs)).

```bash
docker compose exec -T tools curl -s -H @/run/secrets/internal_token -X DELETE http://model:8080/models/$ID   # 204, also the second time
```

**There is no change in place.** A model that must change is retired, then registered again: the same model id becomes active again as
the same entry, with the new content, and `created` is kept. This is also how a GPU rented for part of the day comes back on another
address under the same name. Registering the same content again is a `200` with the same entry, so a retry after a lost answer is safe;
other content for an id that is active is `422 idempotency_conflict`, with the text "retire it, then register it again". Registering
past `carmona.model.max-active` (32) is `409 too_many_models`.

## The registry clock

Every write begins with one statement that raises the single row of `model_clock` and keeps it locked until the commit, so writers take
turns and the versions appear in the order they were numbered. A call that changes nothing (a replay, a second retire) rolls the number
back, so the clock rises for a change and for nothing else. `GET /models/active` reads the clock and the page in one `REPEATABLE READ`
transaction, so "version 42" holds exactly the entries of version 42. That is what makes the list a snapshot and not a feed: a reader
that missed a step is healed by its next full read, and one that sends `known` equal to the current version gets `unchanged` and no
entries. Pages of one list are separate calls: if a write comes between them the versions differ and the reader discards that read.

## The key at rest

The engine key is a customer's credential for a machine open to the internet, and inference-service needs it in clear, so it is sealed
and not hashed: AES-256-GCM with a fresh random 12-byte IV for every seal, a 128-bit tag, and the model id as associated data, so a
sealed key copied to another row does not open there. The data key is the file `model_key` (64 hex characters on one line, created by
`docker/init-secrets.sh`, mounted in this service and nowhere else, read once; no start without it).

**What the sealing does not protect:** someone who holds both the database and that file; the key in clear in the memory of this service
and of inference-service; and the key on the wire between them, which is plain `http` inside the compose network. Losing the file loses
every stored key. A row whose key does not open makes `GET /models/active` answer `500 key_unreadable` for the whole call (the ERROR line names the
entry's id only), and inference-service then keeps its last list: skipping the row would read as "retired" and stop a running model.
Retiring does not need the key, so the way out is to retire the entry and register it again.

## Who sees it, and what it costs

A model with an owner is listed and callable by that organization's API keys only; every other caller gets the `404 model_not_found`
of a model that is not there. A model with no owner is public. The gateway rule is unchanged: an organization with no credit cannot call
its own model, nor list models. A model whose id starts with `org-` is metered and never charged per token, by a rule in `Price.at` and
not by price rows ([Money](../data/money.md)).

When an organization is closed, `ModelSweeper` retires every active model it owns, so no address or key outlives the customer. It asks
organization-service once per owner every `carmona.model.sweep-every` (1 minute; 5 s in compose) and acts only on an explicit `closed`:
a 404, a timeout or an open circuit retires nothing, as in the batch sweep ([Organization](organization.md)).

## Settings

| Key | Rule |
|---|---|
| `carmona.model.key-file` (`MODEL_KEY_FILE`) | the data key file; no start without a valid one |
| `carmona.model.max-context-window` (`MODEL_MAX_CONTEXT_WINDOW`) | **required, no default**: the largest window a registration may state; it follows from the hardware, and a guess would be wrong for some model |
| `carmona.model.max-active` (`MODEL_MAX_ACTIVE`) | 32; at least 1; the most active entries |
| `carmona.model.allow-http`, `allow-internal-hosts` | false; true only for a lab network |
| `carmona.model.sweep-every` (`MODEL_SWEEP_EVERY`) | 1m; at least 1s |

## Why it is like this

**A service of its own.** inference-service holds no database on purpose and its request path never waits for anything slow, so the
list lives here and is read on a timer; model-service down changes nothing for a model that runs. **A snapshot, not a feed**, because it
heals itself after any missed step. **Retire, then register**, because there is one way to change an entry, and it is the way a GPU rented for
part of the day comes back on another address under the same name. **The UUID in the path**, because a model id has a slash and a path segment does not. **Zero price by
rule**, because an owner's own model costing nothing is an invariant: a price row can be forgotten or superseded, a rule cannot.

## What would change it

- **One lock for all writes.** A few registrations a day never wait for each other; a lock per model id is the upgrade if registration
  becomes a stream.
- **One data key, no rotation.** A rotation adds a second key under the next version byte and seals the rows again; do it when an audit
  or a leak asks.
- **No local copy of the list.** inference-service started with model-service down serves the configured models, and a registered one is
  a 404 until the first read succeeds.
- **The url check is a typo guard, not egress control.** A public name that later resolves to an internal address is not caught; the
  real control is egress filtering of inference-service, which is not in this repository.
- **The sweep is one call per owner per pass**; an `organization.closed` event replaces it when that grows.
- **The library has one implementer and no other Java caller.** inference-service reads the list with its own records and WebClient.

## Where to look

- [ModelController.java](https://github.com/carmonaai/back/blob/main/api/model/src/main/java/ai/carmona/model/ModelController.java) — the four calls and what each answers.
- [ModelService.java](https://github.com/carmonaai/back/blob/main/api/model-service/src/main/java/ai/carmona/model/ModelService.java) — register, retire, the clock and the snapshot read.
- [ModelCheck.java](https://github.com/carmonaai/back/blob/main/api/model-service/src/main/java/ai/carmona/model/ModelCheck.java) — every rule a registration meets.
- [KeyBox.java](https://github.com/carmonaai/back/blob/main/api/model-service/src/main/java/ai/carmona/model/KeyBox.java) — the sealing of the engine key.
- [ModelRosterSync.java](https://github.com/carmonaai/back/blob/main/api/inference-service/src/main/java/ai/carmona/inference/ModelRosterSync.java) — the reader on the other side.
