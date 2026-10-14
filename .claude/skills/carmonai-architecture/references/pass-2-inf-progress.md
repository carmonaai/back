# Pass 2, inference chain (`inf`): progress

Module: `api/inference-service` (workspace `work/p2-inf`, branch `ai/p2-inf`). I1-I4 (CPU engine removed, replicas per model,
slot leases in Valkey, scaling signals) are approved at `9404b17`; this section is I5.

## I5: lease hardening (2026-10-08)

What changed, from the independent review of `lease-take.lua`, `lease-renew.lua`, `lease-release.lua`, `lease-load.lua`, `Leases.java`,
`Admission.java`:

1. **Whole-key expiry.** Take and renew set the key's own expiry after every `ZADD`, on the replica set and on the organization set:
   the lease ttl plus one second, and never shorter than the expiry the key already has (a replica with a shorter `lease-ttl`, during a
   rolling change of configuration, cannot make a set vanish under a longer lease). An organization that never returns no longer leaves
   expired members behind: the set is gone one ttl plus one second after its newest lease, with no call from anyone. Order inside the
   script: `ZREMRANGEBYSCORE`, `ZADD`, `PEXPIRE`. A set the prune emptied is deleted by Valkey, and the next `ZADD` recreates it without
   an expiry, which is why the expiry is set after every `ZADD` and not once.
2. **False refusals.** When neither of the two sampled replicas has room for the token weight, the script looks at the other
   candidates (those with a free slot, or with a free queue place when no slot is free) and takes the best that fits before it answers
   `{3}` (`model_busy`). One replica of eight with room admits every time; before, three in four tries were refused.
3. **Config validation, at startup.** `InferenceProperties` and `Model` refuse to be built when: there is no model, a model id is blank or
   repeated (lease keys are named after it), a replica url is repeated within a model (its slots would count twice), a replica has fewer
   than 1 slot, a negative queue, or a `kv-tokens` below 1 (0 means "unknown, not checked" to the script, so a configured budget is positive),
   a tier has `max-in-flight` below 1, `lease-ttl` is missing or under 3 ms (a third of it is the renewal interval), `expected-replicas` is
   below 1 (`Leases` no longer clamps it silently).
4. **Parallel-take fuzz** (`InferenceServiceIT.parallelTakesBreakNoGuardAndLeaveNoKeysBehind`).

### Tests (all in the module)

| Test | What it proves | Fails on the old code |
| --- | --- | --- |
| `InferenceServiceIT.everySetOfLeasesExpiresOnItsOwnAndRenewalKeepsThatTrue` | five organizations that never return leave no key after ttl + 1 s; every key has an expiry in (0, ttl + 1 s]; renewal keeps it; renewal that re-adds a lost lease gives the set its expiry | yes (keys stay) |
| `InferenceServiceIT.aShorterTtlNeverShortensASetsExpiry` | a 400 ms-ttl replica does not shorten a set holding a 5 s lease | yes (no expiry at all); a plain `PEXPIRE` fails it too |
| `InferenceServiceIT.aFleetWhereOnlyOneOfEightReplicasHasRoomStillAdmits` | 30 of 30 admitted on the only replica with room; refused (`model_busy`) when that one is full too; a short request still gets in | yes (about 3 in 4 refused) |
| `InferenceServiceIT.parallelTakesBreakNoGuardAndLeaveNoKeysBehind` | the invariants below, for tiers standard and enterprise | yes (keys left) |
| `InferencePropertiesTest` (6 new tests) | each validation rule above, with the message | yes (nothing was validated) |

Fuzz setup: a model of its own with 4 engine replicas (3 slots, 1 queue place, 3,000-token budget each), two `Admission` instances (two
`Leases`) on one Valkey, 6 organizations, 32 threads x 150 asks with random `max_tokens` of 20 to 1,819, each lease held 0 to 2 ms and then
given back, one ask in twenty dropped without release (a holder that died). A sampler thread reads the state of Valkey in one atomic
script call, continuously. Invariants at every sample: fleet total <= the tier's cap (standard 10 of 12 slots, enterprise 16 places),
each replica <= slots + queue (4), each replica with two or more leases <= its token budget (a single lease may exceed it: an empty replica
takes any request), each organization <= its cap (standard 2, enterprise 3); at the end no key of the model remains after the ttl.

Observed (the full module verify, this host, real Valkey 9.0.6 in Testcontainers):

```
I5 fuzz standard:   32 threads x 150 asks over 2 replicas, 6 organizations (cap 2): admitted 425 (dropped 20), refused fleet 3898, refused organization 477; 269 snapshots, peak fleet 10 of 10, peak replica 3 of 4, peak organization 2 of 2, peak token budget used 99% (replicas with 2+ leases); violations 0; 6 keys left at the end, gone after 2537 ms
I5 fuzz enterprise: 32 threads x 150 asks over 2 replicas, 6 organizations (cap 3): admitted 523 (dropped 30), refused fleet 2358, refused organization 1919; 269 snapshots, peak fleet 16 of 16, peak replica 4 of 4, peak organization 3 of 3, peak token budget used 100% (replicas with 2+ leases); violations 0; 6 keys left at the end, gone after 2537 ms
```

(ttl 1.5 s + the 1 s margin = 2.5 s: the keys were gone after 2,537 ms in both runs. The snapshot count is low because each sample is one script call that competes with the 32 threads; every one of them was checked. Other runs of the same test: peaks identical, 0 violations each time.)

### Decisions the brief left open

- **Queue may be 0.** The brief says "slots/queue > 0"; a queue of 0 is a documented setting (`replicas[].queue: 0`, tested since I2: a request then
  needs a free slot). Validated: slots >= 1, queue >= 0. See Deviations.
- **Margin of one second** over the ttl, and the key's expiry never shortens (Valkey `PTTL` read in the script). The margin has no effect on
  correctness (admission reads the scores, never the key's expiry); it only makes sure a key does not vanish while its newest member is
  still live, whatever the rounding of the two clocks (the script computes both from the same frozen `TIME`).
- **Which candidate when the two sampled do not fit.** The best of the others by the same order (lower used fraction of the token budget,
  then fewer leases, then the lower place), not the first: the extra cost (the sum over each replica's members) only exists near
  saturation, where a request would otherwise be refused.
- **Minimum `lease-ttl` of 3 ms** is a mechanical bound (the renewal interval is a third of it and `Flux.interval` rejects 0), not a
  recommendation; the default is 30 s.
- **Leases from a build before I5** have no expiry on their sets. Nothing is deployed yet; a set that old is given one by the next take or
  renewal that writes to it, and the rest is a one-off `lease:*` cleanup if it ever mattered.

### Architecture alignment

New stores of personal data: none. Lease members are `<token weight>:<uuid>`; the keys carry the model id and, for the per-organization
sets, the organization id (an id, not personal data). They expire on their own one ttl + 1 s after their newest lease, which is also how
they are erased when an organization closes (nothing outlives its ttl), and there is nothing to export (no personal data). No prompt,
answer, key, email or token is in a key, a member, a log line or a metric. The `grep -rniw store` hits are ordinary English ("the lease
store is unavailable") and the metric name `carmonai_inference_lease_store_unavailable` of the I3 brief.

## Deviations

1. **Rule:** brief I5 item 3, "slots/queue > 0". **Done:** slots >= 1, queue >= 0. **Reason:** `queue: 0` is a shipped, tested setting
   (I2 replicas with no queue place; `share()` in `Leases` and the script handle it), and requiring more would force a queue place on a
   replica that is meant to have none. **Alternative:** queue >= 1 everywhere; rejected because it changes the behaviour I2-I4 were approved
   with.
2. **Ceiling, not a deviation:** a request that fits only a replica that has a queue place but no free slot, while another replica has a free
   slot without token room, is still refused (queue places are candidates only when no replica has a free slot, as before). It waits one
   poll if its tier pays. Noted in the script; left alone because the brief lists the candidate rule among what is not to change.

## Drafted paragraphs for `inference-plan.md`

For section 2, the Valkey line of the diagram: `Valkey: api-key cache · org flags (suspended / no credit) · rate buckets · slot leases
(lease:{model}:<replica>, lease:{model}:org:<id>)`.

For section 7, replacing the "in-memory caps" statements (the first bullets of "Now"):

> **Slot leases built 2026-10-08** (ADR 0001; I3 and I5 of pass 2, log: [pass-2-inf-progress.md](pass-2-inf-progress.md)): the in-flight caps are
> no longer counted in each inference-service JVM. A request takes a lease from one Lua script in Valkey (`lease-take.lua`, the pattern of
> the rate buckets: Valkey `TIME`, one hash slot per model through the `{model}` tag). A lease is the member `<token weight>:<uuid>` of
> the sorted set of its engine replica (`lease:{model}:<n>`) and of its organization's (`lease:{model}:org:<id>`), scored by its expiry in
> milliseconds. The script drops expired members, refuses when the fleet is at the tier's share of the sum of the replicas' slots (enterprise:
> slots plus queue places), when the organization is at its `max-in-flight`, or when no replica has a free slot (a free queue place only when
> none has a slot); it then takes the better of two random replicas by the lower used fraction of the token budget (the sum of its leases'
> weights, `estimated input + max_tokens`, against the KV cache in tokens read from `vllm:cache_config_info` `kv_cache_size_tokens` at startup,
> or the configured `kv-tokens`, and the log says which; an empty replica takes any request), looks at the other candidates before it
> refuses for want of token room, and writes the lease with the key's expiry set (ttl plus one second) on both sets. The holder renews it
> every third of `lease-ttl` (30 s) while the request runs; release deletes that member only, so a double release and a release by a holder
> whose lease expired change nothing; a holder that dies frees its slots within one ttl; a set nobody asks about again expires by itself.
> With Valkey down each inference-service replica admits against `slots / expected-replicas` from the leases it holds, raises
> `carmonai_inference_lease_store_unavailable`, logs once per outage, and puts its leases back by renewal when Valkey answers. Tier shares,
> `max-in-flight`, the bounded wait and VTC ordering are as before, now over fleet totals. Deviations, on purpose: (1) a queue of 0 is valid
> (slots >= 1, queue >= 0); (2) the VTC counters stay per inference-service replica (ADR 0001 keeps leases to capacity, not ordering);
> (3) the token budget is read once per start, so an engine restarted with another cache size needs a restart of the service. The
> configuration is validated at startup (no model, repeated model or replica, no slot, `max-in-flight` or `expected-replicas` below 1,
> `lease-ttl` missing or under 3 ms). Proven by a parallel-take fuzz over two `Admission` instances and one Valkey (fleet cap, replica places,
> token budget, organization cap, no key left after the ttl). Semantics checked against the Valkey 9.0 source: `PEXPIRE` on a set that
> `ZREMRANGEBYSCORE` emptied returns 0 (the key is gone) and a later `ZADD` recreates it without an expiry, so the expiry follows every
> `ZADD`; scripts replicate as effects (`PEXPIRE` becomes `PEXPIREAT`), so reading `TIME` is safe; every key of a script must share a slot.

ADR 0001's TODO stands: run `/improve-codebase-architecture` on admission when the Kubernetes work starts, or when a second component needs
slot state. Until then the lease code stays in `Leases` and the four scripts.

## Mutation checks run on I5 (each guard broken alone, the new tests run, restored; `git status` shows only the intended diff)

| Mutation | Failing tests |
| --- | --- |
| `lease-take.lua`: no expiry set on the sets | `everySetOfLeases...`, `aShorterTtl...`, `parallelTakes...` (keys left) |
| `lease-renew.lua`: no expiry set | `everySetOfLeases...` (the re-added lease's sets) |
| expiry may shorten (`PTTL` check removed) | `aShorterTtl...` |
| scan of the other candidates removed | `aFleetWhereOnlyOneOfEight...` (refused with `model_busy`) |
| fleet cap check removed | `parallelTakes...` (fleet over its cap) |
| organization cap check removed (+100) | `parallelTakes...` |
| token budget check removed | `aFleetWhereOnlyOneOfEight...`, `parallelTakes...` |
| replica places check relaxed (+10) | `parallelTakes...` |
| `InferenceProperties` validation removed (the file at `9404b17`) | the 6 new `InferencePropertiesTest` tests |

## Verification of I5

- `mvn -B verify -pl api/inference-service -am` after the last edit: 22 unit tests and 57 integration tests (`InferenceServiceIT`), BUILD SUCCESS
  (baseline before the step: 16 and 53, BUILD SUCCESS). `mvn -B -q verify -DskipTests` over the reactor: exit 0.
