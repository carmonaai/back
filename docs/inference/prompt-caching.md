# Prompt caching

How to lay out a long prompt so the engine reads most of it back instead of computing it, and what the
platform measures, prices and does not promise about that.

## What it is

When a request starts with the same tokens as an earlier one, the engine reuses the work it already did on
them instead of computing them again. That is the prompt cache. For a customer who sends 30,000 tokens of which
most never change, it decides what a request costs and how long its first token takes. The **prompt layout
contract** is the six rules below that keep a prompt in a shape the cache can use. It is a rule for the
customer's prompt, because only the customer knows which parts of it change.

<figure class="cmn-figure">
<div class="cmn-flow" markdown="0">
<svg viewBox="0 0 760 280" role="img" aria-labelledby="pc-title" aria-describedby="pc-desc"
     xmlns="http://www.w3.org/2000/svg">
  <title id="pc-title">How the engine matches a prompt against its cache</title>
  <desc id="pc-desc">A client sends a prompt with its stable part first. inference-service sets cache_salt to
  the organization id and passes the prompt on. The engine hashes the prompt block by block from the start. The
  blocks that match are read back from the cache and the blocks after the first difference are computed in
  prefill. The final usage reports how many prompt tokens came from the cache, and it returns to the client.</desc>

  <defs>
    <marker id="pc-arrow" viewBox="0 0 10 10" refX="9" refY="5"
            markerWidth="6" markerHeight="6" orient="auto-start-reverse">
      <path class="cmn-arrow" d="M0 0 L10 5 L0 10 z"/>
    </marker>
  </defs>

  <!-- Reading order: the prompt in, the salt, the split, then the usage home. -->
  <g id="pc-hops">
    <path id="pc-hop1" class="cmn-link cmn-link--flow cmn-dash" d="M146 100 H196"
          marker-end="url(#pc-arrow)"/>
    <path id="pc-hop2" class="cmn-link cmn-link--flow cmn-dash" d="M336 100 H370"
          marker-end="url(#pc-arrow)"/>
    <path id="pc-hop3" class="cmn-link cmn-link--flow cmn-dash" d="M410 130 V190"
          marker-end="url(#pc-arrow)"/>
    <path id="pc-hop4" class="cmn-link cmn-link--flow cmn-dash" d="M500 130 V190"
          marker-end="url(#pc-arrow)"/>
    <path id="pc-usage" class="cmn-link cmn-link--accent cmn-dash" d="M455 70 V40 H81 V70"
          marker-end="url(#pc-arrow)"/>
  </g>

  <g class="cmn-node cmn-node--entry cmn-node--soft" id="pc-client" aria-labelledby="pc-client-label">
    <rect x="16" y="70" width="130" height="60" rx="10"/>
    <text id="pc-client-label" x="81" y="90">Client</text>
    <text class="cmn-sub" x="81" y="108">stable part first</text>
  </g>

  <g class="cmn-node cmn-node--flow" id="pc-inference" aria-labelledby="pc-inference-label">
    <rect x="196" y="70" width="140" height="60" rx="10"/>
    <text id="pc-inference-label" x="266" y="90">Inference</text>
    <text class="cmn-sub" x="266" y="108">sets cache_salt</text>
  </g>

  <g class="cmn-node cmn-node--accent" id="pc-engine" aria-labelledby="pc-engine-label">
    <rect x="370" y="70" width="170" height="60" rx="10"/>
    <text id="pc-engine-label" x="455" y="90">Engine</text>
    <text class="cmn-sub" x="455" y="108">hashes blocks in order</text>
  </g>

  <g class="cmn-node cmn-node--soft" id="pc-cached" aria-labelledby="pc-cached-label">
    <rect x="300" y="190" width="160" height="56" rx="10"/>
    <text id="pc-cached-label" x="380" y="210">Cached prefix</text>
    <text class="cmn-sub" x="380" y="228">read back, not computed</text>
  </g>

  <g class="cmn-node cmn-node--flow" id="pc-rest" aria-labelledby="pc-rest-label">
    <rect x="480" y="190" width="160" height="56" rx="10"/>
    <text id="pc-rest-label" x="560" y="210">Everything after</text>
    <text class="cmn-sub" x="560" y="228">computed in prefill</text>
  </g>

  <circle class="cmn-packet cmn-travel" r="5"
          style="offset-path: path('M146 100 H196'); --cmn-travel: 0.5s; --cmn-delay: 0.1s;"></circle>
  <circle class="cmn-packet cmn-travel" r="5"
          style="offset-path: path('M336 100 H370'); --cmn-travel: 0.4s; --cmn-delay: 0.6s;"></circle>
  <circle class="cmn-packet cmn-travel" r="4.5"
          style="offset-path: path('M410 130 V190'); --cmn-travel: 0.5s; --cmn-delay: 1.1s;"></circle>
  <circle class="cmn-packet cmn-travel" r="4.5"
          style="offset-path: path('M500 130 V190'); --cmn-travel: 0.5s; --cmn-delay: 1.1s;"></circle>
  <circle class="cmn-packet cmn-packet--accent cmn-travel" r="5"
          style="offset-path: path('M455 70 V40 H81 V70'); --cmn-travel: 1.2s; --cmn-delay: 1.7s;"></circle>

  <!-- Labels last, each on its own plate. -->
  <rect class="cmn-label-plate" x="137" y="12" width="262" height="16" rx="4"/>
  <text class="cmn-label" x="268" y="24">usage.prompt_tokens_details.cached_tokens</text>
  <rect class="cmn-label-plate" x="372" y="152" width="32" height="16" rx="4"/>
  <text class="cmn-label" x="388" y="164">hit</text>
  <rect class="cmn-label-plate" x="508" y="152" width="36" height="16" rx="4"/>
  <text class="cmn-label" x="526" y="164">miss</text>
  <rect class="cmn-label-plate" x="270" y="256" width="420" height="16" rx="4"/>
  <text class="cmn-label" x="480" y="268">matched from the start; the first change ends the match</text>
</svg>
</div>
<figcaption>The prompt goes in whole on every request and is matched from its first token. The two arrows under
the engine are the same request split in two: the blocks before the first difference (hit) and everything from
it onward (miss). The dashed path above is the answer to "did it work": the final usage says how many prompt
tokens were read back.</figcaption>
</figure>

<div class="cmn-legend">
  <span><i class="is-flow"></i> the prompt travelling (solid)</span>
  <span><i class="is-accent"></i> the usage coming back (dashed)</span>
</div>

1. **The client sends the whole prompt every time**: system prompt, knowledge, tools, history, new turn, in
   that order. The platform stores no conversation, so the cache is the only memory of the earlier part.
2. **inference-service passes `messages` and `tools` on as they are** and sets `cache_salt` to the organization
   id. A client cannot set it.
3. **The engine cuts the prompt into blocks and hashes each one together with the hash of the block before
   it.** A block can only match if every block before it matched ([vLLM design page][vllm]).
4. **Blocks that match are read back from memory.** Matching stops at the first block that differs.
5. **Everything after that block is computed in prefill** and paid at the full input price.
6. **The final usage chunk says how many prompt tokens were read back** (`cached_tokens`). Billing prices
   those apart, and the check in rule 5 reads the same number.

## The layout contract

1. **Everything that is the same on every request comes first.** System prompt, standing knowledge and tool
   definitions, in a fixed order. The match runs from the first token, so a stable block that sits behind a
   changing one is never reused.
2. **Then the conversation history, appended in order.** Earlier turns are never edited, reordered,
   summarised in place or re-rendered. Store a turn exactly as you sent it and send it again unchanged.
3. **Everything that changes per request comes last.** The new user turn, timestamps, request or session ids,
   names, and retrieved snippets that differ per turn. Nothing per-request above the shared part.
4. **One organization, one model name, one `cache_salt` per cache.** The platform sets the salt from the
   organization, so every API key of one organization shares one cache and two organizations never share one,
   even for an identical prompt. A model name is one engine, and a second name is a second, cold cache.
5. **Check it.** Send the same request twice and read `usage.prompt_tokens_details.cached_tokens` on the
   second. Then change one line at the start of the prompt and one at the end and compare: the start should
   lose almost everything, the end almost nothing. The cache is best effort. It is empty after an engine
   restart, old blocks are evicted under memory pressure, and the first request after the daily GPU window
   opens is cold by design (the [runbook](../operations/running.md) warms it with the customer's own prefix).
6. **A change anywhere in the prompt invalidates the cache from the first changed block to the end.** Only full
   blocks are cached, so the last partial block of a prompt is always computed ([vLLM design page][vllm]). Our
   block size is **not yet measured** `[UNVERIFIED]`: about 1,056 tokens is expected for Qwen3.6 from reading
   vLLM's source, and a Day A probe reads the real figure.

[vllm]: https://docs.vllm.ai/en/latest/design/prefix_caching/

That page describes vLLM's standard KV cache manager (read 2026-10-24). Qwen3.6 is a hybrid: 30 of its 40
layers keep a fixed-size recurrent state instead of per-token keys and values, and prefix caching on such a
model is off by default and called experimental by vLLM's own recipe. So **whether the cache works on this
model at all, and how it behaves for a change in the middle of a prompt, are not yet measured**
`[UNVERIFIED]`. The six rules hold either way: they are what any prefix cache needs. See
[What Day A settles](#what-day-a-settles).

## A worked example

The same clinic prompt twice, abbreviated. In the first, everything that repeats is on top and everything that
varies is in the last turn. The history carries its old timestamps, stored as they were sent.

```json
{
  "model": "carmona/chat-standard",
  "tools": [ { "type": "function", "function": { "name": "list_free_slots", "...": "same schema, same order" } } ],
  "messages": [
    { "role": "system", "content": "You answer for a dental clinic. Rules: ... Opening hours: ... Price list: ..." },
    { "role": "user", "content": "[14:02] Hi, do you open on Saturdays?" },
    { "role": "assistant", "content": "We open on Saturdays from 8 to 12." },
    { "role": "user", "content": "[14:09] Can I book Saturday at 9?\n(session 7f3a, patient: Ana)" }
  ]
}
```

In the second, the same facts are moved to the top. The first line of the system prompt is new on every
request, so in a real prompt the match ends in the first block and the 30,000 tokens behind it are
computed again.

```json
{
  "model": "carmona/chat-standard",
  "messages": [
    { "role": "system", "content": "Now: 2026-10-24 14:09:31. Session 7f3a. Patient: Ana.\nYou answer for a dental clinic. Rules: ..." },
    { "role": "user", "content": "Hi, do you open on Saturdays?" },
    { "role": "assistant", "content": "We open on Saturdays from 8 to 12." },
    { "role": "user", "content": "Can I book Saturday at 9?" }
  ]
}
```

## What breaks it

| What changes | Why the match ends there | Do this instead |
|---|---|---|
| A date or time in the system prompt | the first block differs on every request | put it in the last turn |
| A request, session or trace id, or a random value, near the top | same | keep ids in your own logs; the `user` field is accepted and ignored, so it is safe |
| The patient's or user's name in the system prompt | one prompt per person: the shared part is no longer shared | put it after the history |
| History edited in place: summarised, a typo fixed, another whitespace or template | everything after the edit is a new prompt | append only; if you must summarise, do it rarely and in one step, and the next request pays once |
| The oldest turns dropped to stay under a limit | the start of the history moves, so every history block changes (the stable part above it still hits) | cut in large, rare steps, not one turn per request |
| Tools reordered, keys of a tool schema reordered, or JSON serialised differently | the chat template renders tool definitions into the prompt text, so another order is other tokens (not yet checked for this model's template) `[UNVERIFIED]` | build the list once and serialise it the same way |
| `tools` or `tool_choice` toggled between requests | whether vLLM renders tools when `tool_choice` is `none` is `[UNVERIFIED]` | keep both fixed |
| Retrieved snippets that differ per turn, placed before the history | per-request text above the shared part | place them in the new turn |
| The model's reasoning replayed inside the history | the platform neutralises think tags in client text, so the engine reads other text than the model wrote | send back only `content` |
| Another model name, or an API key of another organization | another engine, or another `cache_salt` | one model name and one organization per prompt family |

What does not break it: sampling parameters (`temperature`, `seed`, `max_tokens`), `stream`, `service_tier`,
`user` and `metadata`, and using several API keys of the same organization. None of them is part of the
prompt, and vLLM's block hash covers the tokens plus extras such as LoRA ids, multimodal hashes and the cache
salt ([vLLM design page][vllm]).

## What it costs and what it saves

**Money.** Cached input is priced apart. `Price.cost` charges `(input − cached) × input price + cached × cached
input price + output × output price`, where cached tokens are a subset of the input, and rounds once per window
([Money](../data/money.md)). The only prices seeded today are placeholders for the two prototype models, where a
cached token costs half of an input token (0.25 against 0.50 BRL per million for `carmona/qwen3-4b`). They say
nothing about the commercial price card, which is set separately and which this page does not quote.

**Time.** A cold 32,000-token prompt takes seconds of prefill on the target card, at a prefill speed that is
**not yet measured** `[UNVERIFIED]`. A request that hits the cache computes only the tokens after the match.
That is an estimate for sizing, not a response-time promise: the platform promises none (see the end of this
page).
`carmona_inference_first_output_seconds{cache}` splits the time to the first output into `none`, `partial` and
`full` by the share of the prompt that came from the cache (under 10 percent, in between, over 90 percent),
which is the number that shows the operator what the layout is worth. A customer reads the same split in the
`cached_tokens` of its own responses.

## What the platform measures

| Signal | Says | Status |
|---|---|---|
| `usage.prompt_tokens_details.cached_tokens` in the response | prompt tokens read back for this request; absent or 0 when nothing was | exists; needs the engine flag `--enable-prompt-tokens-details` |
| `cachedInputTokens` in the usage event | the same number per request, summed per organization and window for billing | exists |
| `carmona_inference_first_output_seconds{cache}` | how long the first output took, by share cached | exists |
| `carmona_engine_prefix_cache_hit_ratio` | the engine's own hit ratio per scrape, from its counters | exists in `Metrics` |
| `carmona_inference_prompt_cache_tokens_total{model,mode,result}` | prompt tokens served from the cache (`hit`) and the rest (`miss`) | ships with this change |
| Alert `PromptCacheHitRatioLow` | the 30-minute hit ratio is under 0.30 with real traffic behind it; informational | ships with this change |

The counter is added once per request, and only when the engine's final usage chunk was seen and the prompt was
not empty: that chunk is the only one that carries `cached_tokens`, so a request cut before it would count as
a miss for lack of news and bias the ratio down. It does not replace `carmona_inference_tokens_total`, which
stays the billing count, estimates included. The hit ratio is `sum(rate(...{result="hit"})) /
sum(rate(...))`. The series appears with the first measured request, and the rules and the alert stay silent
while it does not exist, when traffic is below a floor, and when the engine contract check says prefix caching
is off. The 0.30 threshold and the floor are placeholders that Day A tunes. See
[Observability](../operations/observability.md) for the rule names.

Metrics carry `model` and `mode` only, never an organization, so this is a fleet number. One customer's ratio
is read from its usage events. If the engine's own ratio is high and the request-level one is near zero, check
that the engine runs with `--enable-prompt-tokens-details` `[INFER]`.

## What the platform does not promise

- **No hit ratio.** There is no minimum, no latency promise for a cached request, and a hit still waits for its
  queue and for the tokens after the match.
- **No memory across restarts.** The cache lives in the engine's GPU memory. A restart empties it, the daily
  window destroys the card, and the first request of the day is cold. Eviction is least recently used, under
  memory pressure ([vLLM design page][vllm]); we promise no minimum lifetime.
- **No rewriting of your prompt to help the cache.** `ChatRequest` passes `messages` and `tools` through in the
  order sent and adds no text. The one change we make is `ControlTokenGuard` neutralising role markers and
  control tokens in client text. It is a pure function of the text, so the same prompt gives the same bytes every
  time and the cache is not affected.
- **No sharing between organizations.** That is the purpose of `cache_salt`
  ([Tenancy](../data/tenancy.md)).
- **No view of where a prompt first differs from the last one.** A diagnostic for that is planned, behind a
  measured trigger, and not built.

## What Day A settles

Day A is the first measured day on the rented card, run from `bench/RUNBOOK-DAY-A.md`. Three probes run in the
step where prefix caching is on, and each prints a verdict.

| Probe | Verdict | What changes on this page |
|---|---|---|
| `bench/workload/probe_prefix_divergence.py`: change one place at 1, 10, 50, 90 and 99 percent of a 32k prefix | `exact_prefix` | nothing; the cost of a change is everything after its block |
| | `all_or_nothing` | rule 3 becomes absolute: per-request text inside the shared part costs all of it |
| | `early_bust` | a change loses more than the blocks after it; the measured loss replaces "from the first changed block" |
| | `no_cache` | the contract still holds for any engine, but this page's cost and capacity claims lose their premise |
| `bench/workload/probe_burst_cold.py`: 8 identical cold 32k requests at once | `computed_n_times` | add burst advice: send one request, wait for its first token, then send the rest |
| | `deduplicated` | no burst advice |
| `bench/perf/probe_decode_roofline.py`: decode speed at 1 to 32 streams | `kernel_path_suspect` and the others | nothing in the layout; it says whether the decode figures behind the capacity paragraph can be trusted |

The same probes also settle the block size of rule 6. The verdict words are those of the probe design and the
probes print them.

## What the hit ratio is worth

A card that serves long prompts spends its time on prefill, so how many such requests it can take scales as
1 / (1 − hit ratio): every token read back is a token not computed. The table is that arithmetic and nothing
else.

| Prompt cache hit ratio | Share of the prompt still computed | Prefill capacity, against hit ratio 0 |
|---|---|---|
| 0 | 100% | 1x |
| 0.4 | 60% | 1.7x |
| 0.6 | 40% | 2.5x |
| 0.9 | 10% | 10x |
| 0.97 | 3% | 33x |

**This is an upper bound from prefill alone, pending Day A.** The hit ratios are unmeasured on this engine, and
if the cache does not work on this model the ratio is 0 and the first row applies. The table also leaves out the limits that bite first in
the top rows: peak simultaneity, cold-start bursts, the time decode takes, and above all the cache's own
memory, which holds only a limited number of long prefixes at once. Past that number old prefixes are evicted,
the hit ratio falls, and the top rows are out of reach. The layout on this page decides which row a customer is
on; it does not lift those limits. Figures for a particular card are not published here.

## Why it is like this

**A rule for the customer, not a rewrite by the platform.** Sorting tools, hoisting timestamps or summarising
history inside inference-service would change what the model reads, and so the answer, and would make the
platform understand content that its logs, metrics and events are built never to hold
([Security and privacy](../architecture/security.md)).

**The contract asks for an order, not a marker.** vLLM's match is automatic and by position, so there is
nothing to mark. A request field that says "cache up to here" would be a new field for the allowlist to carry
and the tests to pin, for no gain.

**The salt is the organization, not the key.** A salt per key would give each application of one customer its
own cold cache for the same prompt `[INFER]`. A salt shared across organizations is the timing side channel
that [Tenancy](../data/tenancy.md) closes.

**The hit counter counts tokens, once, from the final usage chunk.** Counting every request would treat "the
engine did not say" as "no hit", and the ratio would read low exactly when a client hangs up early.

## What would change it

- **The Day A verdicts**, above. They are the only open facts on this page.
- **A second engine replica.** The cache belongs to one replica, so requests of one prompt family would have to
  reach the same one or each replica warms its own copy. There is no prefix-aware routing yet
  ([Routing responses](routing.md)).
- **A customer under about 80 percent in the first month** would justify the diagnostic of where a prompt first
  differs.
- **A cache that survives restarts** is not built: a cold long prefill is seconds of GPU `[UNVERIFIED]`, so
  losing the cache at each window start costs one slow answer, not money. Active prefixes that no longer fit in
  the cache's memory, or restarts that cost customers more than one slow request a day, would reopen it.

## Where to look

- [`ChatRequest.java`](https://github.com/carmonaai/back/blob/main/api/inference-service/src/main/java/ai/carmona/inference/ChatRequest.java)
  — `cache_salt`, the allowlist, no added text.
- [`Tracker.java`](https://github.com/carmonaai/back/blob/main/api/inference-service/src/main/java/ai/carmona/inference/Tracker.java)
  — reads `cached_tokens` from the final usage.
- [`Metrics.java`](https://github.com/carmonaai/back/blob/main/api/inference-service/src/main/java/ai/carmona/inference/Metrics.java)
  — first-output series and the hit counter.
- [`ControlTokenGuard.java`](https://github.com/carmonaai/back/blob/main/api/inference-service/src/main/java/ai/carmona/inference/ControlTokenGuard.java)
  — the only rewrite of client text.
- [`Price.java`](https://github.com/carmonaai/back/blob/main/api/billing/src/main/java/ai/carmona/billing/Price.java)
  — `cost`: cached input priced apart.

**Back to:** [Capacity and fairness](capacity.md) for the limits a cached request still lives under.
