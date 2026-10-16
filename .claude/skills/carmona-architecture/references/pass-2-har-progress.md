# Pass 2, chain har (docker/**, scripts): progress

Brief: `work/tasks/P2-har.md` (restart addendum wins). Branch `ai/p2-har`. Compose project `carmona-p2-har`. One section per
step, written when the step lands.

## H1a Simulator as the default engine, pinned tools image, fleet profile, smoke adopted

### What exists now

| Piece | Where | Notes |
| --- | --- | --- |
| The engine | `docker/compose.yaml` service `engine` | `llm-d-inference-sim:v0.11.4@sha256:d60f0fb0...`, non-root (65532), `read_only`, `cap_drop: ALL`, `mem_limit 256m`. Flags from `work/prototype-sim/FINDINGS-contract.md`: model `carmona/qwen3-4b`, 4 running + 8 waiting, 4096 window, TTFT 600 ms +/-100, 24 ms/token +/-4, seed 42, **echo mode** (output as long as the prompt). `llama`, its model volume and every llama.cpp name are gone (compose, smoke, benches, `revenue-check.sh`, Prometheus, dashboard text). |
| Tools image | `docker/tools/Dockerfile`, service `tools` | `python:3.13-slim-bookworm@sha256:a1165e27...` + curl, uid 10001, `read_only`, tmpfs `/tmp`. Takes over the role the llama container played (curl on the network); python3 is for the load generator (H2, standard library only). |
| Fleet | profile `fleet`, `docker/fleet.env`, `docker/engine-lb/nginx.conf` | `ENGINE_REPLICAS` simulators (`deploy.replicas`) behind `engine-lb` (nginx, least_conn, **only between inference-service and the simulators**). `INFERENCE_REPLICAS` and `GATEWAY_REPLICAS` scale the other two; the gateway reaches the inference replicas directly (its own balancing runs). `ENGINE_URL`, `ENGINE_SLOTS`, `ENGINE_QUEUE` carry the fleet sums into inference-service. |
| Real engine | `docker/compose.gpu.yaml` | stays: vLLM replaces the simulator (`engine` is profiled out), same model id, `ENGINE=vllm bash smoke.sh` runs the two assertions the simulator cannot. |
| Prometheus | `prometheus.yml`, `rules.yml`, `slo-golden-signals.json` | job `llama` -> `engine` (the simulator; DNS service discovery, one target per replica) and `vllm` (real engine; no targets, so no series and no alert, on the simulator stack). Rules read the `vllm:*` series (the simulator reports the same names); `EngineUnreachable` fires on `max by (job) (up{job=~"engine\|vllm"}) == 0` **or** when neither job has an `up` series (DNS service discovery drops a container that stops resolving, so `== 0` alone is silent exactly when the engine is gone; Deviation 7); `EngineQueueSustained` is waiting >= 8 (the engine's backstop: it refuses past 8, so `> 8` could never fire; Deviation 8). Both are unit-tested in `rules.test.yml` (`docker/check-prometheus.sh`). |
| Smoke | `docker/smoke.sh` | the prototype's `smoke-sim.sh`, adopted: continue-on-fail with a count, exit status 1 on any failure, `skip-sim` helper, `ENGINE=sim` (default) or `vllm`. |
| Scripts | `bench.sh`, `batch-bench.sh`, `revenue-check.sh` | script host is `tools` instead of `llama`. |
| Checks | `docker/check-prometheus.sh` (+ `prometheus/rules.test.yml`), `docker/check-valkey-upgrade.sh` | promtool in the pinned image: config, rules and the alert unit tests; and the valkey-data upgrade/restart check (below). Neither needs the stack. |
| `docker/.gitattributes` | | `*.sh`, `*.conf`, `Dockerfile` stay LF. This Windows checkout (`core.autocrlf=true`) had given `smoke.sh`, `bench.sh` and `batch-bench.sh` CRLF, which breaks `bash x.sh`. |

Non-root, measured on the running default stack (`docker top`, uid of the container's processes): every service uid 10001; engine
and mailpit 65532; tools 10001; valkey 999; db 999; minio 10001; grafana 472; prometheus nobody. Valkey and mailpit ran as **root**
before this step (valkey because `sh -c` as the command skips the image entrypoint's step down to the valkey user); both have a
`user:` now.

**Upgrading an existing checkout (valkey-data).** Valkey used to run as root, so a `valkey-data` volume from before this step holds a
root-owned, mode 0700 `appendonlydir`; uid 999 cannot write it and Valkey exits 1 (`Error moving temp append only file on the final
destination: Permission denied`), which keeps inference, gateway and usage down. `valkey-volume` (a one-shot like `minio-volume`: root for one
`chown -R 999:999 /data`, capabilities `CHOWN` and `DAC_READ_SEARCH` only (see the review fixes), read-only filesystem, no network; valkey waits for it) fixes the owner in place, so the
append-only file and the usage events waiting in it are kept and nobody has to delete the volume. `docker/check-valkey-upgrade.sh`
builds that old volume, starts valkey through compose and asserts the key survived; with `NO_DEPS=1` it skips the init and must fail.

### Evidence (run on this machine, 2026-10-09, `run-exclusive`, project `carmona-p2-har`)

Default stack plus the MinIO overlay (batch-service stores its files in S3 since B1), built fresh, then `smoke.sh`:

```
UP rc=0 06:22:11  (16 containers; minio-volume and minio-init exited 0 as designed)
SMOKE rc=0 06:24:51
skip-sim  engine idle again after the client hung up (NOT RUN: the simulator does not notice a hang-up and generates to the end, G1)
skip-sim  the cancelled stream is billed for its generated tokens (NOT RUN: the simulator reports usage only in the last chunk, so a cancelled stream has none, G3)
smoke finished: 0 failed, 2 skip-sim
smoke passed            (130 lines starting "ok")
```

That run includes the canary check: `ok   the canary, bearer headers, the API key and query strings are in no log (access log
included), nowhere in the database and nowhere in Valkey's file`. The stack was torn down by the script (`down -v`); afterwards
`docker ps -a`, `docker volume ls` and `docker network ls` filtered on the project label return nothing.

What the two skipped assertions would see on this simulator (probe after the smoke run, same stack): the hang-up leaves
`vllm:num_requests_running=1` for about 12 s and 0 at 17 s (the 700-token echo stream runs to its end; smoke now uses 900 words, about 22 s; a prompt that does not fit under max_tokens is a 400 in echo mode), and the cancelled usage
row is `cancelled|877|0` (input estimate, no output). Both are the gaps named in the skip text, not new findings.

Memory (default stack + MinIO, idle after startup, `docker stats` and the VM's `/proc/meminfo`): containers 4.3 GiB in total
(the JVM services 340-490 MiB each, Grafana 300 of 384 MiB, MinIO 220 MiB, engine 13 MiB, Prometheus 39 MiB); VM `MemTotal` 7.6 GiB,
`MemAvailable` 2.0 GiB, swap used 0.1 GiB. A fleet adds 340-490 MiB per extra gateway or inference replica and ~15 MiB per simulator,
so the prototype's 3 gateways + 3 inference + 8 simulators (measured there without Prometheus and Grafana) leaves about 0.6 GiB
here: **the largest size that fits is H3's to find**; `fleet.env` is a starting point, not a measured ceiling. Disk: `C:` free
7.8 -> 7.4 GB over the step (9 locally built images).

Fleet, small (3 simulators, 2 inference, 2 gateways, `ENGINE_SLOTS=12`): up and healthy (`engine-lb` healthy); 18 concurrent streams
-> 18x 200, simulators 6/6/6 requests, inference replicas 9/9 (the gateway balances them directly); one simulator killed under load ->
8 of 12 requests 200 and 4 `503` (the stand-in kept a dead peer for its `fail_timeout`; that is the behaviour H3's degraded-mode
matrix has to record); the container recreated with `docker compose up -d engine` got a new address and served 7 of the next 24
requests without restarting the stand-in (`server engine:8000 resolve`, nginx 1.28 resolves it again every 5 s) and Prometheus
listed three `engine` targets. Not run: the full-size fleet, any load beyond bursts of 24, smoke on the fleet.

`promtool` (the pinned `prom/prometheus` image, files mounted read-only): `check config prometheus.yml` -> `SUCCESS: 1 rule files
found ... valid prometheus config file syntax` (with a dummy `/tmp/engine-key`, which compose writes at start), `check rules rules.yml`
-> `SUCCESS: 13 rules found`. Live: 10 targets up (`vllm` has none, as designed), every rule `health=ok`, `engine:requests_running`
returns a sample.

Baseline before the change: `docker compose config -q` passed for the default and GPU files only with `GRAFANA_ADMIN_PASSWORD` in the
environment; the workspace `.env` does not define it (nor `MINIO_*` / `STORAGE_*`), so the stack could not be composed as the tree
stood. Not run: the old llama stack (it needs a 640 MB model download and the engine is removed by this step).

### Decisions the brief left open

| Decision | Source |
| --- | --- |
| Echo mode is the default, not the random-length profile. | `FINDINGS-contract.md` G2 and the prototype's `compose.sim.yaml`: smoke's hang-up and tier-share steps need a deterministic long stream, and the fairness drill is specified in echo mode. |
| `least_conn` (with a shared `zone`) in the stand-in, not round-robin. | Prototype: nginx without a zone makes each worker count alone and all pick the first peer. The brief says "round-robin"; least_conn is what was measured. |
| The stand-in resolves its upstream with `resolve` instead of at start. | nginx 1.27.3+ (open source) re-resolves a server name; a killed and recreated simulator is found without restarting the stand-in. Tested above. |
| The model is stated field by field in `environment`. | Spring replaces a whole list from the first source that defines an element of it: a partial `CARMONA_INFERENCE_MODELS_0_*` set made `url` vanish and the service exited (seen on the first start). `compose.gpu.yaml` states the same fields for vLLM. |
| No `kv-tokens` configured. | The simulator exposes `vllm:cache_config_info`, and inference-service logs `token budget of replica 0 of carmona/qwen3-4b: 16384 tokens, from the engine's vllm:cache_config_info` (4 slots x 4096). The engine's value wins over `kv-tokens` (`Leases`), so there is nothing to set; see Deviation 4 for what that means behind the stand-in. |
| The gateway publishes `127.0.0.1:8080` only (was `0.0.0.0:8080`), exactly that port by default. | A host-only dev port; an exact port fails loudly if 8080 is busy, a range silently takes another one (seen: Docker picked 8084/8085 from 8080-8089 for two replicas, so scripts must not assume the lowest). The fleet uses a range and the drivers use `http://gateway:8080` inside the network. |
| The smoke run includes `compose.minio.yaml` (`DC` in `smoke.sh`). | batch-service (B1, integrated) answers `503 storage_unavailable` without object storage; the plan's H1b (fleet) comes later, but "0 failed" needs the batch section. The `MINIO_*` / `STORAGE_*` names are added to `.env.example`, values are generated per run and never stored. |
| `skip-sim` is used twice, with different reasons. | See Deviations 3. |

### Deviations

1. **Hardening override 5, liveness/readiness probes (engine).** The simulator image is distroless: no shell, no curl, no
   in-container healthcheck (G4). `engine` has none; `depends_on: service_started`; the stand-in has a `wget` healthcheck on
   `/health` (which crosses to an engine); Prometheus `up{job="engine"}` and the smoke test are the probes. Alternatives: a derived
   image with a static busybox (H5 builds the simulator from source anyway, and can add a `--healthcheck` mode there), a sidecar.
2. **Hardening override 5, non-root, where it still is not.** `minio-volume` (not this step's file content) runs one `chown` as uid 0
   with only `CAP_CHOWN`; recorded by the bat chain already. `valkey-volume` (this step) is the same shape with `CHOWN` and `DAC_READ_SEARCH` (root without the second cannot list the valkey-owned 0700 directory on any run after the first). Everything else this step touches is non-root.
3. **Brief, "only the two named disconnect assertions may be skip-sim".** Two are skipped, but the second is not a disconnect gap: it
   is G3 (usage only in the last chunk). inference-service bills a cancelled stream what the last chunk it saw said (`Tracker`), which
   needs the engine to send usage on every chunk (vLLM's `continuous_usage_stats`); the simulator does not, so the row is
   `cancelled|877|0`. **H5's disconnect patch does not re-enable it**: the patch must also make the simulator emit usage per chunk when
   `stream_options.continuous_usage_stats` is set, or it stays `skip-sim`. The rows check (`cancelled=1 ok=2`) does run on the
   simulator and passes. The flags that re-enable them are `SIM_NOTICES_DISCONNECT=1` and `SIM_CONTINUOUS_USAGE=1`.
   **Closed in H5:** the patch does both, the assertions run by default, and `SIM_STOCK=1` (upstream's engine) replaces those two flags.
4. **Addendum vs. architecture, replicas.** The addendum puts the nginx stand-in between inference and the simulators; the
   architecture's mechanism is the model's `replicas` list (I2, integrated). With one url and fleet sums, per-replica leases are not
   exercised against the engines, and the **token budget is one simulator's, not the fleet's**: inference-service reads
   `vllm:cache_config_info` through the stand-in, which answers from one simulator (16384 tokens), while the model has 32 slots. In
   flight, the sum of (input estimate + `max_tokens`) is capped at 16384 for the whole fleet, so a load whose requests weigh more
   than about 500 tokens each hits `model_busy` on tokens before it fills the slots (smoke and bursts of short requests do not). This is
   read from `Leases` and the startup log of the single-simulator stack; it was not measured on the fleet.
   Closest conforming version implemented as instructed, labelled as a stand-in in compose and in `nginx.conf`. Alternative,
   recommended for H2/H3 if the drills should size capacity truthfully: `CARMONA_INFERENCE_MODELS_0_REPLICAS=http://carmona-p2-har-engine-1:8000,...`
   (one url per simulator, generated by the driver from the replica count; the container names are stable), which gives every
   simulator its own slots and its own budget, and drops the stand-in. Decision for the orchestrator.

   **The same single url also breaks the engine scrape and the reconcile (review finding; read from `Reconciler`, not run on a
   fleet).** inference-service scrapes `/metrics` for each entry of the model's `replicas` list, and here there is one entry (the
   stand-in), so every 5 s scrape and every `/actuator/reconcile` reads one arbitrary simulator. Behind the stand-in: (a) the
   reconcile compares one simulator's `prompt_tokens_total` / `generation_tokens_total` growth with the whole fleet's stored usage, so it
   raises false "usage and engine disagree" WARNs and sets the `metrics.reconcile` gauge behind `ReconciliationMismatch`; (b)
   `Reconciler.restarted()` treats a counter that goes back (consecutive scrapes landing on different simulators) as a replica
   restart and resets the window, so the check is also silently skipped; (c) the `carmona_engine_*` running/waiting/cache gauges
   describe one simulator (at most 4 running), not the fleet's 32 slots. **Consequence: on the fleet profile as built, the reconcile
   and the `carmona_engine_*` gauges are invalid, and the stand-in is only good for load shape (balance, failover, goodput).** The
   accounting check (H2) and the reconciliation-drift drill (H3) need the generated `replicas` list (one url per simulator, no
   stand-in); treat that alternative as **required** for them, not optional. Prometheus is unaffected (it scrapes every simulator
   itself through DNS service discovery).
5. **CI.** `.github/workflows/ci.yaml` generates a `.env` without `GRAFANA_ADMIN_PASSWORD` (pre-existing: compose refuses to start
   without it) and without `MINIO_*` / `STORAGE_*`, and starts the stack with `compose.yaml` only. After this step CI's `smoke.sh`
   needs the overlay and those variables. Not changed here (outside `docker/**`); cross-chain request below.
7. **Observability.md alert contract, `EngineUnreachable` (review finding, fixed).** Moving the engine scrape from `static_configs` to DNS
   service discovery means a removed container (and, observed in one run, a stopped one) no longer resolves, discovery yields zero targets and Prometheus writes no
   `up` series, so `max by (job) (up{...}) == 0` is an empty vector and the alert could not fire when the engine was actually down (the
   static `llama:8080` target gave `up == 0`). Fixed in `rules.yml`: the expression adds `absent(up{job="engine"}) and on() absent(up{job="vllm"})`
   (both jobs absent, since one of the two is legitimately empty on each stack). `rules.test.yml` covers: no target at all fires,
   every target failing fires, one replica of a fleet down stays quiet, and it fails against the earlier expression (mutation run). Not
   covered: a live fire-when-stopped check on the stack (H4's negative test); only the rule is unit-tested here.
8. **`EngineQueueSustained` threshold (review finding, fixed).** The engine refuses past `--max-waiting-queue-length=8` (simulator,
   `simulator.go`: `waitingQueue.Len() >= queueCapacity`) and vLLM's `--max-num-queued-reqs` behaves the same, so the waiting gauge
   never exceeds 8 and `> 8` (and the dashboard's red step at 9) could never trigger. Both now trigger at 8, the queue-full point.
   `rules.test.yml` fires at 8 and stays quiet at 7. H4 owns the final rules and should revisit the number against per-replica
   admission (q = 2 behind C = 4).
9. **Unpinned packages in the tools image.** The base image is pinned by digest; `apt-get install curl` takes whatever bookworm
   has at build time. A pinned version would break on the next security update of that repository.

### Review fixes (commit "H1a: review fixes")

| Finding | Fix | Test that would have caught it |
| --- | --- | --- |
| valkey off root breaks an existing `valkey-data` volume | `valkey-volume` one-shot (see "Upgrading an existing checkout"). A first version with `CAP_CHOWN` only passed on a fresh upgrade and **failed on the second `up`** (root without `CAP_DAC_READ_SEARCH` cannot list the now valkey-owned 0700 directory, `chown: cannot read directory '/data/appendonlydir'`), which smoke's valkey restart hit (49 failures); `DAC_READ_SEARCH` is added. | `check-valkey-upgrade.sh`: `NO_DEPS=1` (no init) fails with the reviewer's error; `CAP_CHOWN`-only fails the restart step; the fixed file passes both. |
| Deviation 4 missed the scrape and reconcile | Deviation 4 extended: reconcile and `carmona_engine_*` invalid behind the stand-in; the generated `replicas` list is required for H2/H3 accounting and drift checks. | Documentation only (read from `Reconciler`); no fleet run. |
| `EngineQueueSustained` can never fire | `>= 8`, dashboard red step 8 (Deviation 8). | `rules.test.yml` (fires at 8, quiet at 7); fails against the earlier rule. |
| `EngineUnreachable` silent when the engine is down (DNS SD) | absence branch (Deviation 7); rules.yml comment and the drafted observability paragraph corrected. | `rules.test.yml` (no target at all fires); fails against the earlier rule. |
| Idle-after-hang-up assertion could not detect G1 | wall-clock 10 s deadline, and a 900-word prompt so the ghost stream runs about 20 s after the hang-up. The reviewer's "at least 1000 words" does not work: in echo mode the whole prompt must fit under `max_tokens` (1000), the engine answers 400 for 1005 prompt tokens, inference records it as `error` and smoke failed twice (usage rows, tier share) before this was found. | Mutation run: `SIM_NOTICES_DISCONNECT=1` on the unpatched simulator now prints `FAIL engine still busy (1)`. |

Evidence (run-exclusive, project `carmona-p2-har`, fresh stack each time, after the last edit to compose.yaml and smoke.sh):
`smoke.sh` default: rc 0, `smoke finished: 0 failed, 2 skip-sim`, 130 ok lines; a second `up -d --wait` on the same stack (re-runs
`valkey-volume`, `minio-volume`, `minio-init`) exits 0 with all three `Exited (0)`. Mutation on a fresh stack: `SIM_NOTICES_DISCONNECT=1 bash smoke.sh`
-> rc 1, `FAIL engine still busy (1)`, `smoke finished: 1 failed, 1 skip-sim`. (A second smoke on the same stack is not a valid mutation run:
the register rate limit answers 429.) Both stacks were removed afterwards: 0 containers and 0 volumes carry the project label.

### New stores of personal data

None. `tools` is stateless (`read_only`, tmpfs); the stand-in logs no access lines (`access_log off`) and no bodies; the simulator's
logs and metrics were covered by the canary check above (the canary is in no log). Nothing here changes erasure or export.

### For the orchestrator

- **Cross-chain requests.** (a) `ci.yaml`: add `GRAFANA_ADMIN_PASSWORD`, the `MINIO_*` and `STORAGE_*` values to the generated `.env`
  and start the stack with `-f compose.yaml -f compose.minio.yaml`. (b) The gateway needs `stop_grace_period: 720s` for H2's rolling
  restart (`pass-2-gw-progress.md`, G1); it is not set yet, because compose restarts are first used there. (c) H5 also needs per-chunk
  usage (Deviation 3).
- **Lines a reviewer should read twice:** none are money paths. `docker/smoke.sh` lines around `skip_sim` (a skip must name its gap and
  stay off on vLLM), and `compose.yaml` `inference.environment` (a wrong model url or key is a silent engine mix-up).

### Drafted "built" paragraphs (the orchestrator moves them)

For `inference-plan.md` (top blocks, and sections 2, 6 and 11 where they say llama.cpp or the CPU engine):

> **Simulated engine as the default built 2026-10-09** (log: [pass-2-har-progress.md](pass-2-har-progress.md), step H1a; ADR 0002 made
> real): `docker/compose.yaml` runs `llm-d-inference-sim` v0.11.4 (digest-pinned) as `carmona/qwen3-4b` with the measured vLLM GPU
> profile (4 running, 8 waiting, 4096 window, TTFT 0.6 s, 24 ms per token, echo mode); the llama.cpp service, its model volume and
> every llama.cpp rule and panel are gone, and `compose.gpu.yaml` is the real-engine overlay. `smoke.sh` passes against it: 130
> assertions, 0 failed, 2 `skip-sim`. A `fleet` profile adds N simulators behind an nginx stand-in for the replica picker (between
> inference-service and the simulators only; the gateway reaches the inference replicas directly) and scales the gateway and
> inference replicas from `docker/fleet.env`. Deviations, on purpose:
> - Two smoke assertions are `skip-sim`: the engine going idle after a hang-up (the simulator generates to the end, G1; H5 patches it)
>   and the cancelled stream's billed output tokens (the simulator sends usage only in the last chunk, G3: needs the per-chunk usage
>   that vLLM sends). They run under `ENGINE=vllm`.
> - The simulator has no in-container healthcheck (distroless); Prometheus `up` and the smoke test stand in. Its token counts come
>   from a regex tokenizer, so absolute numbers (and prices computed from them) mean nothing; reconciliation compares like with like.
> - The stand-in is one model url with the fleet's summed slots, so per-replica leases are not exercised against the engines and the
>   token budget is one simulator's (16384 tokens) for the whole fleet, until the model's `replicas` list is generated for the fleet.
>   Its engine scrape and the reconcile read one arbitrary simulator too, so on this profile the reconcile and the
>   `carmona_engine_*` gauges are invalid: the accounting and reconciliation-drift checks need the generated `replicas` list.

For `platform.md` (compose section):

> **Compose stack, 2026-10-09 (har H1a).** The default engine is the simulator; `tools` (curl, bash, python3, non-root, pinned base)
> is the script host on the network; profile `fleet` (+ `fleet.env`) scales engine, inference and gateway replicas; every container
> a step touches is non-root with dropped capabilities where it does not need them (valkey and mailpit moved off root). The gateway
> publishes `127.0.0.1:8080` only. Batch needs `compose.minio.yaml` (object storage) for its smoke section. Secrets stay out of the
> repo: `.env.example` lists every name, and a run supplies the values it needs (Grafana, MinIO) from its own environment.
> **Engine image (har H5).** The engine is `carmona/llm-d-inference-sim:v0.11.4-disconnect.1`, a one-time local build (`bash docker/sim/build.sh`,
> which needs a copy of the v0.11.4 source): compose does not build it and `pull_policy` is `never`, so on a fresh machine `up` stops with
> "image not found" until the script has run once. `ENGINE_IMAGE` swaps in upstream's pinned image (then run `smoke.sh` with `SIM_STOCK=1`).

For `observability.md` (jobs, alerts, Gaps; H4 owns the Gaps 3 text, these are the H1a changes): scrape job `llama` is now `engine`
(DNS service discovery: one target per simulator replica) plus `vllm` for the GPU overlay (no targets on the simulator stack, so no
`up` series and no alert); `engine:requests_running|waiting|cache_usage` read the `vllm:*` series only; `EngineUnreachable` fires when
every target of an engine job fails its scrape or when neither engine job has any target (DNS service discovery drops a container
that stops resolving, so the `up` series disappears instead of reading 0; both jobs absent is the outage, one of them is always legitimately empty);
`EngineQueueSustained` is waiting >= 8 (queue full: the engine refuses past 8, so its gauge never exceeds it) on either engine; Gap 6 (llama.cpp exposes no KV ratio)
is obsolete, the simulator reports `vllm:kv_cache_usage_perc` at 0 unless it runs with `--enable-kvcache`.

### Review fixes, round 2 (commit "H1a: review fixes", second)

| Finding | Fix | Test that would have caught it |
| --- | --- | --- |
| Prometheus saw ONE `inference` and ONE `gateway` target whatever the replica count | `inference` and `gateway` use `dns_sd_configs` (A records of the compose service name, port 8081, 15 s), as `engine` does. The six services with no replica knob stay static on purpose: a static target of a container that is gone still reads `up == 0`, so ServiceDown keeps seeing it (a DNS target would vanish). | `check-prometheus.sh` fails if `inference`, `gateway`, `engine` or `vllm` is not on `dns_sd_configs` (mutation run: `inference` back to `static_configs` -> `FAIL: job inference is not scraped through dns_sd_configs`); `check-fleet-targets.sh` is the live check; `rules.test.yml` "ServiceDown names the one replica that is down". |
| A replica that leaves discovery leaves no series, so ServiceDown is silent | New `ReplicaMissing` (count of targets below its 30 m maximum, warning) and `ReplicatedServiceAbsent` (no `up` at all for `inference` or `gateway`, critical); `ServiceDown`'s text now names the instance. | `rules.test.yml`: "ReplicaMissing fires when one of two replicas leaves discovery" (and ServiceDown stays quiet in the same case), "ReplicatedServiceAbsent fires when a replicated service has no target at all". |
| Small leftovers | Progress document: valkey-volume capabilities (`CHOWN` + `DAC_READ_SEARCH`) and what a stopped container does to discovery. `smoke.sh` header lists the real prerequisites. `engine-lb`: `proxy_connect_timeout 2s`, `max_fails=2 fail_timeout=5s`. `inference` waits for `engine-lb` on the fleet profile (`required: false` elsewhere). Left as is: the `tools` healthcheck (`CMD true`), as the review suggested. | Live run below. |

**Live run (run-exclusive, project `carmona-p2-har`, fresh stack, `ENGINE_REPLICAS=2 INFERENCE_REPLICAS=2 GATEWAY_REPLICAS=2`, fleet profile + MinIO overlay, with the final `compose.yaml`, `nginx.conf` and `prometheus.yml`; `rules.yml` gained `ReplicaMissing` after it and is covered by promtool only):**

```
up rc=0   (inference x2, gateway x2, engine x2, engine-lb healthy; inference started after engine-lb)
inference: 2 running, 2 targets up
gateway: 2 running, 2 targets up
engine: 2 running, 2 targets up            (check-fleet-targets.sh rc=0)
{job="engine"} => 2   {job="inference"} => 2   {job="gateway"} => 2        (count by (job) (up); the failing run had engine 2, gateway 1, inference 1)
up{instance="172.20.0.16:8081", job="inference"} => 1 ... .17 inference, .20 and .21 gateway
```

Observed behaviour when a replica goes away (`docker stop` of one `inference` replica, then `docker rm -f`; probes every 15 s):

- t+15 s: `count by (job) (up{job="inference"})` is still 2. t+30 s and every sample to t+120 s: **1**. No `up == 0` series at any sample
  (`count by (job) (up{job="inference"} == 0)` returned nothing), and `ALERTS{alertname=~"ServiceDown|ReplicatedServiceAbsent"}` was empty.
  A lookup of `inference` from the `tools` container while it was stopped returned only the surviving replica, in 0.0 s: **in this run
  a stopped container left Docker's DNS at once and its target was dropped on the next discovery refresh.**
- The review reported the opposite on its machine: the name kept resolving, the lookup timed out, Prometheus kept the stale target and
  wrote `up == 0`. It did not reproduce here (Docker Engine 28.3.3 on Docker Desktop, one run). Both are recorded because the rules must not
  depend on either: a stale target is named by `ServiceDown` (per instance), a dropped one by `ReplicaMissing`, and `docker rm -f` of the
  stopped replica changed nothing further (still 1 target). Not run: `ReplicaMissing` live (its 30 m baseline needs a run longer than this
  one; it is unit-tested only), so H3's drill should include "stop one replica, wait for the alert".
- `docker compose up -d --wait inference` recreated the replica (`inference-3`), and 40 s later both jobs showed 2 targets again.
- Stand-in with one simulator killed (`docker kill`), 16 sequential requests to `engine-lb:8000` from `tools`: `504 400 504 400 400 ... 400`.
  The two 504s are the connect timeout (2 s) of the first two attempts at the dead peer; after `max_fails=2` it was out of rotation and the
  other 14 reached the live simulator (the 400s are the simulator rejecting `max_tokens: 4` below the echo prompt, which proves they got
  there). Before this change (default `max_fails=1`, `fail_timeout=10s`, no connect timeout) the same kill had turned 4 of 12 into 503s.
  Not repeated with the old config in this run.
- Torn down with `down -v`; 0 containers carry the project label afterwards.

- Verification after the last edit (through the slot semaphore): `bash docker/check-prometheus.sh` -> config valid, 15 rules, `promtool test rules` SUCCESS, `SUCCESS: inference, gateway, engine and vllm use dns_sd_configs`. Mutation runs on a copy: `ReplicaMissing` made never-true -> `FAILED: alertname: ReplicaMissing, time: 20m`; `ReplicatedServiceAbsent` made never-true -> `FAILED: alertname: ReplicatedServiceAbsent, time: 3m`; `inference` back to `static_configs` -> `FAIL: job inference is not scraped through dns_sd_configs`. `docker compose config` is valid with and without `--profile fleet --env-file fleet.env` (the `engine-lb` dependency of `inference` is `required: false`, so the default stack has no such service and still resolves). `ReplicaMissing` and the rule file as a whole were not exercised on a live stack (see above).

## H5 Simulator disconnect patch, built from the pinned source

Closes G1 (the simulator does not notice a client that hangs up) and G3 (usage only in the last chunk) of
`work/prototype-sim/FINDINGS-contract.md`, and with them Deviation 3 of H1a: the two `skip-sim` assertions run on the default stack again.

### What exists now

| Piece | Where | Notes |
| --- | --- | --- |
| The patch | `docker/sim/disconnect.patch` | Unified diff against llm-d-inference-sim **v0.11.4** (commit `db3e12bdf8ccf500d93309dc73015fb811296404`), 13 files, 391 lines of code and 862 of tests; its header says what it does. The tree it applies to is the one the prototype kept, `work/prototype-sim/_sim-src-v0.11.4`, which I checked to be identical to `git archive v0.11.4` of the prototype's clone (`diff -r`, no difference; the clone's tag resolves to the commit above). |
| The build | `docker/sim/build.sh`, `docker/sim/Dockerfile` | `bash docker/sim/build.sh` copies the source (default `../../../prototype-sim/_sim-src-v0.11.4`, or `SIM_SRC`), turns the `.go`/`go.mod`/`go.sum` files to LF (the checkout is CRLF), **refuses any tree that is not v0.11.4** (`SRC_PIN`: sha256 over the sha256 of every file `go build` reads; the same value from the LF `git archive` and from the CRLF checkout), applies the patch and builds. Multi-stage: `golang:1.26.6@sha256:0d1d3a79...` builds the pure-Go binary exactly as upstream's Dockerfile does (`CGO_ENABLED=0`); the runtime stage is **upstream's own pinned image** (`ghcr.io/llm-d/llm-d-inference-sim:v0.11.4@sha256:d60f0fb0...`: distroless static, uid 65532, same entrypoint) with only `/app/llm-d-inference-sim` replaced. `SIM_TEST=1` runs the simulator's Go tests (the patch's included) as a build stage first, with `--output type=cacheonly` so that no 5.7 GB test image is stored per run; `docker image prune -f` after a build session leaves `docker images -f dangling=true` empty. The script does not clone anything (rule: no GitHub). |
| The image | `carmona/llm-d-inference-sim:v0.11.4-disconnect.1` | Local tag, never `latest`; `docker image inspect` on this machine: `id=sha256:836172a01d7b831d4ba38474f7938fed35f0762c58a619d135e43919bf2b2b5a user=65532:65532 entrypoint=[/app/llm-d-inference-sim] size=85660945`. |
| Compose | `docker/compose.yaml` | `engine` uses `${ENGINE_IMAGE:-carmona/llm-d-inference-sim:v0.11.4-disconnect.1}` with `pull_policy: never` (a missing image is an error that names it, not a pull attempt from Docker Hub). `ENGINE_IMAGE=ghcr.io/llm-d/llm-d-inference-sim:v0.11.4@sha256:d60f0fb0...` swaps upstream's engine back in. `docker compose config` is valid for the default, the MinIO overlay and the `fleet` profile, and shows both images. |
| Smoke | `docker/smoke.sh` | It first waits (at most 60 s) until the console login route answers something other than 503, and the cancelled stream is cut by hanging up after 12 lines (`head -n 12`), not by a 2 s timer; the failing cancelled row is printed. The two H1a `skip-sim` assertions run by default. `SIM_STOCK=1` (instead of H1a's `SIM_NOTICES_DISCONNECT` / `SIM_CONTINUOUS_USAGE`, which are gone) skips them for upstream's engine. |
| Live check | `docker/check-sim-disconnect.sh [image]` | No compose stack: starts the image on a private network with 1 slot, drives it with python raw sockets from the tools base image, and asserts E19 (below) plus the per-chunk usage; also the negative control against upstream's image. |
| `docker/.gitattributes` | | `*.patch` stays LF (a CRLF patch does not apply to the LF-normalised tree). |

What the patch changes in the simulator (all in `pkg/communication` and `pkg/simulator`):

1. Every HTTP generation request gets a context (`HandleRequestCtx`, `clientLink` in `client_link.go`) that is cancelled when the client hangs up or the response is complete. A stream that is being written finds out at its next write (fasthttp closes the body pipe). A request that has written nothing yet (waiting in the queue, in the first-token delay) is found by `watchClient`, which every 25 ms peeks at the socket (`MSG_PEEK` through `RawConn.Read`, `conncheck_linux.go`; it consumes no byte, so keep-alive reuse is not disturbed; cmux's `MuxConn` is unwrapped; a connection without a socket falls back to the write).
2. The worker's two sleeps (first token, between tokens; the omni image delay stays uninterruptible, as in stock) wait on that context (`sleepCtx`), so the slot is freed at the next token, not at the end of the generation. A request still in the waiting queue leaves it at once (`dropWaiting`, `context.AfterFunc`), so ghosts do not hold the queue's 8 places.
3. An aborted request is counted by the simulator: `vllm:request_success_total{finish_reason="abort"}` +1, the prompt tokens if the first-token delay had elapsed, the tokens produced so far in the token counters. A hang-up before the first token counts nothing. **The `abort` series is simulator-only**: vLLM v0.30.0 was measured (phase-6-progress.md line 39) to leave `request_success_total{finished_reason="abort"}` at 0 for a cancelled request, and its label is `finished_reason` (docs.vllm.ai, design/metrics). Only the token counters (`prompt_tokens_total`, `generation_tokens_total`) are comparable between the two engines, and even those are unverified for a streamed, cancelled request on vLLM (Deviation 13).
4. `stream_options.continuous_usage_stats` (with `include_usage`, as vLLM requires) puts `usage` on every chat chunk: the role chunk has the prompt tokens and 0 completion tokens, each token chunk the count so far, the finish chunk the total; the usage chunk at the end is unchanged. This is what `Tracker` reads (`prompt_tokens`, `completion_tokens` of the last chunk it saw) when it bills a cancelled stream.
5. A failed write to a client that has gone is no longer answered with `sendError` on the fasthttp context. **Upstream bug found on the way** (the negative control hit it): by then the context belongs to the next request of that worker, so after a hang-up mid-stream a `/metrics` scrape answered `500` (`3 failed scrapes` in the control run, with the log line `Sending stream chunk failed, io: read/write on closed pipe`). Prometheus scrapes of the engine would have failed at random under any drill that kills a client mid-stream.

### Analysis before the last fix-up (2026-10-09, asked for by the owner; what worked, what did not, the plan)

Worked:
- Building from the pinned source (`SRC_PIN`, upstream's runtime image with only the binary replaced) and testing the patch through a real server on cmux, a real socket and a raw client. The live check against the built image, with upstream's image as negative control (5 assertions fail on it), is what found the upstream `sendError` bug.
- Mutating one guard at a time found real gaps every time it was tried (watcher leak, refused-stream branch, 499 branch, the `sendStream` guard).
- The H1a smoke assertions (E34, E35) check the thing the patch is for, end to end.

Did not work:
- Guards were tested one at a time, each time a reviewer found the next untested one (four rounds). There was no inventory, so the class was never closed.
- Guards were added for cleanliness, not need: `Stop()` on a ticker and a timer, an `ok` on a type assertion of a queue that holds one type, a `break` the list implementation made redundant. None can fail a spec.
- Smoke E35 cancelled the stream with a 2 s timer: on a slow start the cut came before the first byte (a cancelled row with 0 tokens, 1 run of 4). The first request after `up --wait` once got a 503 from login.
- Every `docker build --target test` stored a 5.7 GB image (12 of them filled the disk by 24 GB in two hours).

Plan, in this order (the review checklist of round 4): (1) list every guard, branch, cleanup call and goroutine exit the patch adds (grep of the patch) with its own single-guard mutation and a named failing spec; delete what protects nothing a drill measures, add a spec where the guard is needed; (2) `--output type=cacheonly` for the test stage and the mutation builds, `docker image prune -f` at the end; (3) smoke: wait for the condition (login route answers) and hang up after 12 lines, three consecutive full runs; (4) re-run the live check on the final image and against upstream; (5) the ponytail comments and the doc leftovers; (6) one commit, clean tree.

### Evidence (this machine, 2026-10-09)

Go tests, in `golang:1.26.6@sha256:0d1d3a79...` (pinned, through the slot semaphore), after the last edit (the patch as `build.sh` applies it to the CRLF tree):

```
$ SIM_TEST=1 bash docker/sim/build.sh        (test stage with --output type=cacheonly, then the image)
#13 57.84 ok  	github.com/llm-d/llm-d-inference-sim/pkg/api	0.014s
#13 60.04 ok  	github.com/llm-d/llm-d-inference-sim/pkg/simulator	0.326s
#13 80.77 ok  	github.com/llm-d/llm-d-inference-sim/pkg/communication	21.026s
[carmona/llm-d-inference-sim:v0.11.4-disconnect.1] sha256:836172a01d7b831d4ba38474f7938fed35f0762c58a619d135e43919bf2b2b5a
go test -race (baseline of the mutation runs):  ok pkg/api 1.130s, ok pkg/simulator 7.687s, ok pkg/communication 23.179s
gofmt -l pkg cmd   (no output)     go vet ./pkg/...  ok     GOOS=darwin go build ./pkg/... && go vet ./pkg/communication/   ok  (the non-Linux stub compiles)
```

47 specs in `pkg/communication` (the patch's plus the stock ones), 107 in `pkg/simulator`.

Guard inventory and mutation runs (review round 4). **The class is closed here, not one guard at a time.** Inventory: the patch was grepped for every added
`return`, `stop(`, `gone(`, `signalDone`, `go `, `defer`, `AfterFunc`, `if `, `case `, `break`, `cancel` outside the test files (91 added lines of code; the
499 branch and `sendOrFail` are in it). Every hit is a row below, on the "deleted" list, or a plain accessor or return value (`cancelCtx`, `setCancelCtx`, `stop()`/`gone()` bodies, the `true` a sleep returns when its timer fires). Method: `bash`-driven loop over a scratch copy of the patched
tree, one guard removed (or inverted) per run, `go test ./pkg/api/... ./pkg/simulator/... ./pkg/communication/...` as a `docker build --target test
--output type=cacheonly` through the slot semaphore (two at a time; a scratch Dockerfile with a Go build-cache mount, otherwise the test stage of
`docker/sim/Dockerfile`, same base image by digest), baseline green first. Result: **62 mutations, 62 killed, none survives.** "run crashed" rows are
mutations that panic in a goroutine the test does not own, so the whole test binary dies and Ginkgo cannot print a summary; the spec named is the one that was
running (rerun with `-ginkgo.v`). CC4 (a read that waits for the socket) hangs the suite for go test's 10 minutes without `-ginkgo.fail-fast`; it was run with it. SM22 needs
`go test -race` (a lock is invisible to a plain run): the baseline is clean under `-race`, the mutation is not.

| # | Guard removed (one at a time, on a scratch copy) | Result: named spec(s) that fail |
| --- | --- | --- |
| CL1 | client_link.go `newClientLink`: `cu != nil &&` (request type without stream_options) | 1 failed: newClientLink: asks for no continuous usage of a request that cannot carry stream_options |
| CL4 | client_link.go `watchClient`: exit on `ctx.Done()` (goroutine exit) | 2 failed: hang-up: leaves no watcher behind once a response is complete, stream or not, on a connection that stays open; hang-up: leaves no watcher behind when the engine refuses a stream request (429, queue full), on a connection that stays open |
| CL5 | client_link.go `watchClient`: `link.cancel()` when `peerGone` | 5 failed: hang-up: stops a request that is still waiting for its first token, and counts nothing for it; hang-up: stops a tool-call stream at its next token and counts the tool tokens produced (+3 more) |
| CL6 | client_link.go `stamp`: return unchanged when not asked | 3 failed: continuous: leaves the chunks without usage when only include_usage is asked; continuous: ignores it without include_usage, as vLLM does (+1 more) |
| CL7 | client_link.go `stamp`: return unchanged when not a `jsonDataChunk` | run crashed, continuous: puts the usage so far on every chunk of a tool-call stream, counting the tool tokens (process panic: runtime error: invalid memory address or nil pointer dereferenc) |
| CL8 | client_link.go `stamp`: data boxed once | 2 failed: continuous: puts the usage so far on the image chunk of an omni answer; stamp: stamps a chat chunk whether the data is boxed once or twice |
| CL9 | client_link.go `stamp`: data boxed twice (the real shape) | 5 failed: continuous: puts the usage so far on every chunk, the role chunk first; continuous: puts the usage so far on every chunk of a tool-call stream, counting the tool tokens (+3 more) |
| CL10 | client_link.go `stamp`: `cc != nil` | 1 failed: stamp: leaves alone what is not a chat chunk: nothing, the [DONE] marker, other data |
| HT1 | http.go `handleHTTP`: `go c.watchClient(...)` (the goroutine) | 5 failed: hang-up: stops a request that is still waiting for its first token, and counts nothing for it; hang-up: stops a tool-call stream at its next token and counts the tool tokens produced (+3 more) |
| HT2 | http.go `handleHTTP`: the watcher starts only after the engine accepted the request | 1 failed: hang-up: leaves no watcher behind when the engine refuses a request before it is queued (404, unknown model), on a connection that stays open |
| HT3 | http.go `handleHTTP`: `HandleRequestCtx(link.ctx, ...)` (the request lives as long as its client) | 7 failed: hang-up: stops a running stream at its next token and counts only the tokens produced; hang-up: stops a request that is still waiting for its first token, and counts nothing for it (+5 more) |
| HT4 | http.go `handleHTTP`: `defer link.stop()` on the non-stream branch | 1 failed: hang-up: leaves no watcher behind once a response is complete, stream or not, on a connection that stays open |
| HT5 | http.go `handleStream`: the whole closed-channel (499) branch | 1 failed: gone: is answered 499 and nothing else when the request ended before its first token (stream) |
| HT6 | http.go `handleStream` 499 branch: `link.stop()` | 1 failed: gone: is answered 499 and nothing else when the request ended before its first token (stream) |
| HT7 | http.go `handleStream` 499 branch: status 499 | 1 failed: gone: is answered 499 and nothing else when the request ended before its first token (stream) |
| HT8 | http.go `handleStream` 499 branch: `return` | 1 failed: gone: is answered 499 and nothing else when the request ended before its first token (stream) |
| HT9 | http.go `handleStream` refused (`first.Err`, 429) branch: `link.stop()` | 2 failed: hang-up: leaves no watcher behind when the engine refuses a stream request (429, queue full), on a connection that stays open; hang-up: lets the handler of a queued request return when its client leaves |
| HT10 | http.go `sendNonStream`: `if link.gone() { return }` | 1 failed: gone: is not built: no error body for a request nobody waits for |
| HT12 | http.go `sendStream`: `defer link.stop()` | 1 failed: hang-up: leaves no watcher behind once a response is complete, stream or not, on a connection that stays open |
| HT13 | http.go `sendStream`: `if link.gone() { return }` | 1 failed: gone: is not answered with the missing-choice 500 when the client left before one of two choices started |
| HT14 | http.go `sendStream`: `state.prompt = respCtx.UsageData()` | run crashed, continuous: puts the usage so far on every chunk, the role chunk first (process panic: runtime error: invalid memory address or nil pointer dereferenc) |
| HT15 | http.go `sendOrFail`: a closed pipe is not reported on the fasthttp context | 1 failed: gone: is not written to the fasthttp context when the pipe is closed |
| HT16 | http.go stamp site: image chunk | 1 failed: continuous: puts the usage so far on the image chunk of an omni answer |
| HT17 | http.go stamp site: role (first) chunk | 3 failed: continuous: puts the usage so far on every chunk, the role chunk first; continuous: puts the usage so far on every chunk of a tool-call stream, counting the tool tokens (+1 more) |
| HT18 | http.go stamp site: token chunk | 2 failed: continuous: puts the usage so far on every chunk, the role chunk first; continuous: puts the usage so far on the image chunk of an omni answer |
| HT19 | http.go stamp site: cache_threshold finish chunk | 1 failed: continuous: puts the usage so far on the finish chunk of a cache_threshold answer, which has no tokens |
| HT20 | http.go stamp site: last (finish) chunk | 2 failed: continuous: puts the usage so far on every chunk, the role chunk first; continuous: puts the usage so far on the image chunk of an omni answer |
| HT21 | http.go stamp site: tool-call chunk | 1 failed: continuous: puts the usage so far on every chunk of a tool-call stream, counting the tool tokens |
| HT22 | http.go `emitResponseChunks`: `state.completion++` | 2 failed: continuous: puts the usage so far on every chunk, the role chunk first; continuous: puts the usage so far on every chunk of a tool-call stream, counting the tool tokens |
| CC1 | conncheck_linux.go `peerGone`: unwrap cmux's `MuxConn` | 6 failed: peerGone: looks inside cmux's connection; hang-up: stops a request that is still waiting for its first token, and counts nothing for it (+4 more) |
| CC2 | conncheck_linux.go `peerGone`: connection without a socket (`!ok`) is not gone | 1 failed: peerGone: is false for a connection it cannot look at: TLS or a pipe (no socket), a socket that will not open |
| CC3 | conncheck_linux.go `peerGone`: `SyscallConn()` error is not gone | 1 failed: peerGone: is false for a connection it cannot look at: TLS or a pipe (no socket), a socket that will not open |
| CC4 | conncheck_linux.go `peerGone`: the `RawConn.Read` callback returns true (never waits for readability) | 1 failed: hang-up: stops a request that is still waiting for its first token, and counts nothing for it |
| CC5 | conncheck_linux.go `peerGone`: `ErrDeadlineExceeded` is not a hang-up | 1 failed: peerGone: is false while a read deadline has passed: cmux sets one while it sniffs a new connection |
| CC6 | conncheck_linux.go `peerGone`: any other `Read` error (closed here) is gone | 1 failed: peerGone: is true for a connection this side has closed |
| CC7 | conncheck_linux.go `peerGone`: zero bytes read is gone | 7 failed: hang-up: stops a request that is still waiting for its first token, and counts nothing for it; hang-up: stops a tool-call stream at its next token and counts the tool tokens produced (+5 more) |
| CC8 | conncheck_linux.go `peerGone`: `EAGAIN` is not gone | 13 failed: continuous: puts the usage so far on every chunk, the role chunk first; continuous: leaves the chunks without usage when only include_usage is asked (+11 more) |
| CC9 | conncheck_linux.go `peerGone`: any other errno (ECONNRESET) is gone | 1 failed: peerGone: is true once the client has reset the connection |
| CC10 | conncheck_linux.go `peerGone`: `MSG_PEEK` (the look consumes no byte) | 1 failed: peerGone: is false while the client has sent something, and does not consume it |
| SM2 | context.go `sleepCtx`: `case <-ctx.Done()` | 5 failed: sleepCtx: is false at once for a context that is done, whatever the delay; sleepCtx: is false as soon as the context is done while it waits (+3 more) |
| SM3 | context.go `simulateTTFT`: stop when `sleepCtx` says cancelled | 1 failed: hang-up: stops a request that is still waiting for its first token, and counts nothing for it |
| SM4 | context.go `simulateInterTokenLatency`: stop when `sleepCtx` says cancelled | 2 failed: hang-up: stops a running stream at its next token and counts only the tokens produced; hang-up: stops a tool-call stream at its next token and counts the tool tokens produced |
| SM5 | simulator.go `simulateResponseProcessing`: `out.prefilled = true` | 2 failed: hang-up: stops a running stream at its next token and counts only the tokens produced; hang-up: stops a tool-call stream at its next token and counts the tool tokens produced |
| SM6 | simulator.go `simulateResponseProcessing`: text, `out.cancelled = true` | 1 failed: hang-up: stops a running stream at its next token and counts only the tokens produced |
| SM7 | simulator.go `simulateResponseProcessing`: tool call, `out.cancelled = true` | 1 failed: hang-up: stops a tool-call stream at its next token and counts the tool tokens produced |
| SM8 | simulator.go `simulateResponseProcessing`: text, `out.generated++` | 1 failed: hang-up: stops a running stream at its next token and counts only the tokens produced |
| SM9 | simulator.go `simulateResponseProcessing`: tool call, `out.generated++` | 1 failed: hang-up: stops a tool-call stream at its next token and counts the tool tokens produced |
| SM10 | simulator.go `simulateResponseProcessing`: before the first token, `out.cancelled = true` | 1 failed: hang-up: stops a request that is still waiting for its first token, and counts nothing for it |
| SM11 | worker.go `processRequest`: the prompt is counted only `if out.prefilled` | 1 failed: hang-up: stops a request that is still waiting for its first token, and counts nothing for it |
| SM12 | worker.go `processRequest`: `return` after the abort accounting | 3 failed: hang-up: stops a running stream at its next token and counts only the tokens produced; hang-up: stops a request that is still waiting for its first token, and counts nothing for it (+1 more) |
| SM13 | simulator.go `dropWaiting`: `if !found { return }` | run crashed, hang-up: takes its own place out of the queue, not the one in front of it (process panic: sync: negative WaitGroup counter) |
| SM14 | simulator.go `dropWaiting`: `reqCtx.signalDone()` | 2 failed: lora-wait: leaves waiting_lora_adapters, and running_lora_adapters is not touched; hang-up: lets the handler of a queued request return when its client leaves |
| SM15 | simulator.go `dropWaiting`: the LoRA branch | 1 failed: lora-wait: leaves waiting_lora_adapters, and running_lora_adapters is not touched |
| SM16 | simulator.go `dropWaiting`: match its own item (not the front one) | run crashed, hang-up: takes its own place out of the queue, not the one in front of it (process panic: sync: negative WaitGroup counter) |
| SM17 | simulator.go `dropWaiting`: the waiting gauge -1 | 3 failed: hang-up: leaves the queue at once, without touching the request that is running; hang-up: takes its own place out of the queue, not the one in front of it (+1 more) |
| SM18 | simulator.go `addRequestToQueue`: `context.AfterFunc(..., dropWaiting)` | 4 failed: lora-wait: leaves waiting_lora_adapters, and running_lora_adapters is not touched; hang-up: leaves the queue at once, without touching the request that is running (+2 more) |
| SM19 | simulator.go `HandleRequest`: passes a context (not nil) to `HandleRequestCtx` | 1 failed: HandleRequest enqueue failure does not affect sibling choices that already made it into newRequests and are being processed |
| SM20 | simulator.go `HandleRequestCtx`: `reqCtx.setCancelCtx(ctx)` | 2 failed: lora-wait: leaves waiting_lora_adapters, and running_lora_adapters is not touched; HandleRequest enqueue failure does not affect sibling choices that already made it into newRequests and are being processed |
| SM21 | metrics.go `lorasUpdater`: `case droppedUsageState` | 1 failed: lora-wait: leaves waiting_lora_adapters, and running_lora_adapters is not touched |
| API1 | request.go `ContinuousUsageStats`: `StreamOptions != nil` | 1 failed: ContinuousUsageStats: needs stream_options with both include_usage and continuous_usage_stats, as vLLM does |
| API2 | request.go `ContinuousUsageStats`: needs `include_usage` | 1 failed: continuous: ignores it without include_usage, as vLLM does |
| SM22 | simulator.go `dropWaiting`: `queueLock` Lock and Unlock (run under `go test -race`) | 1 failed: data race reported by go test -race (19 reports) |

Deleted because no spec can fail them or they protect nothing a drill measures (the rest of the class):

| Deleted | Why |
| --- | --- |
| `defer t.Stop()` on the ticker of `watchClient` and on the timer of `sleepCtx` | Unobservable: `go.mod` says go 1.26, which collects an unreferenced timer or ticker. A comment says so. |
| `ok &&` on the `waitingQueueItem` assertion in `dropWaiting` | The queue holds nothing else; the mutation was equivalent. A plain assertion now (it panics loudly if that ever changes). |
| `break` after `list.Remove` in `dropWaiting` | `Remove` clears the element's links, so the loop ends anyway (equivalent mutation); a comment says so. |
| `return` after `link.cancel()` in `watchClient` | Equivalent: the next turn of the loop sees `ctx.Done()`. |
| `if l != nil` in `gone()` and `stop()`, `link != nil &&` in `sendStream` (nil `*clientLink`) | Production never passes nil. Their mutations (CL2, CL3, HT11) crashed the run instead of failing a named spec. The two stock specs that passed `nil` now get `testLink(false)`. |
| `if d <= 0 { return ctx.Err() == nil }` in `sleepCtx` | Mutation SM1 survived: a zero delay is not a profile any drill runs, and with a zero delay and a done context either answer is fine. |
| `MSG_DONTWAIT` in `peerGone` | Mutation CC11 survived: Go makes every socket it opens non-blocking, so the recv never waits. `MSG_PEEK` stays (CC10 fails the spec that checks no byte is consumed). |

Kept on purpose: the `link.gone()` guard in `sendStream` (HT13) matters for `n > 1` only (inference-service sends `n = 1`): when the client leaves, a choice that never
started has no entry, and the missing-choice check would call `sendError` on a fasthttp context that by then serves another request. The spec builds exactly that with two choices.
Not a guard, not mutated: `conncheck_other.go` (the non-Linux stub, `return false`); it is compile-checked with `GOOS=darwin go build ./pkg/... && go vet ./pkg/communication/`
(ok), and `gofmt -l pkg cmd` and `go vet ./pkg/...` are clean.

New specs of this round: the 499 closed-channel branch (both ways the channel can be closed), the `sendStream` guard (two choices), the refused-before-queue watcher (404), the queue place of
the one that leaves (not the one in front), `ContinuousUsageStats` of a request, and `peerGone`'s goroutine now recovers a panic into a failing spec.

The specs that count goroutines do it through a `pprof` dump (`inGoroutines`), against the count before the spec, so a leak of an earlier spec cannot hide behind them.

Live check of the built image `sha256:836172a0...` (`docker/check-sim-disconnect.sh`, 1 slot, TTFT 600 ms, 24 ms per token, 300-token prompts; a stream of 300 tokens is 7 s), run after the last edit through the slot semaphore:

```
$ bash docker/check-sim-disconnect.sh                      (our image)
ok   engine idle at the start
ok   engine idle within 1 s of a hang-up mid-stream (idle after 0.05 s)
ok   the cut stream is counted once as finish_reason=abort (abort 0 -> 1)
ok   only the tokens produced before the hang-up are counted (1 tokens after the hang-up, 300 in the prompt)
ok   no token is generated after that
ok   engine idle again
ok   engine idle within 1 s of a hang-up during prefill (idle after 0.05 s)
ok   nothing is counted for a prompt that was never processed
ok   engine idle again
ok   the second request waits in the queue
ok   the queue is empty within 1 s of the waiting client's hang-up (empty after 0.05 s)
ok   the request in front of it is still running
ok   and it is answered to the end
ok   engine idle again
ok   every chunk carries usage (10 of 10 chunks have it)
ok   the role chunk has the prompt tokens and no completion tokens ({"prompt_tokens": 13, "completion_tokens": 0, "total_tokens": 13, "prompt_tokens_details": {"cached_tokens": 0}})
ok   completion tokens count up with the chunks (10 chunks, last says 8)
ok   the usage chunk is still the last one
ok   the engine's /metrics answered every scrape (0 failed scrapes)
check-sim-disconnect: 0 failed
rc=0
```

The same script against upstream's image (`ghcr.io/llm-d/llm-d-inference-sim:v0.11.4@sha256:d60f0fb0...`), the negative control: 5 of the assertions fail, the ones about the hang-up, the usage and the scrape; the ones that do not depend on the patch pass.

```
$ bash docker/check-sim-disconnect.sh ghcr.io/llm-d/llm-d-inference-sim:v0.11.4@sha256:d60f0fb0...
ok   engine idle at the start
FAIL engine idle within 1 s of a hang-up mid-stream (idle after more than 3 s)
ok   engine idle again
FAIL engine idle within 1 s of a hang-up during prefill (idle after more than 3 s)
ok   nothing is counted for a prompt that was never processed
ok   engine idle again
ok   the second request waits in the queue
FAIL the queue is empty within 1 s of the waiting client's hang-up (empty after 2.07 s)
ok   the request in front of it is still running
ok   and it is answered to the end
ok   engine idle again
FAIL every chunk carries usage (0 of 10 chunks have it)
ok   the usage chunk is still the last one
FAIL the engine's /metrics answered every scrape (3 failed scrapes)
check-sim-disconnect: 5 failed
rc=1
```
(The script also prints the engine's log tail after a failure; it shows `Sending stream chunk failed, io: read/write on closed pipe`, the line behind the scrape failures.)

Full stack, **three consecutive full runs** on the final image `sha256:836172a0...` (each through `work/docker-slots.sh run-exclusive`, project `carmona-p2-har`, default stack + MinIO overlay,
`up -d --build --wait`, then `smoke.sh` (no `SIM_STOCK`), then `down -v`; the secrets generated per run in the process environment only, about 25 s between runs for the login bucket).
Lines of each run that matter (every run had 133 `ok` lines and no `FAIL`):

```
== run 1 UP 21:48:34 ==
UP rc=0 21:50:04
== run 1 SMOKE 21:50:05 ==
SMOKE rc=0 21:52:27
ok   the console login route answers (401)
ok   engine idle within 10 s of the client hanging up
ok   usage recorded once each: cancelled=1 ok=2 
ok   the cancelled stream is billed for its 6 generated tokens
smoke finished: 0 failed, 0 skip-sim
smoke passed
ok lines: 133
== run 1 DOWN ==
containers left: 0, volumes left: 0, networks left: 0

== run 2 UP 21:53:51 ==
UP rc=0 21:54:52
== run 2 SMOKE 21:54:52 ==
SMOKE rc=0 21:57:10
ok   the console login route answers (401)
ok   engine idle within 10 s of the client hanging up
ok   usage recorded once each: cancelled=1 ok=2 
ok   the cancelled stream is billed for its 6 generated tokens
smoke finished: 0 failed, 0 skip-sim
smoke passed
ok lines: 133
== run 2 DOWN ==
containers left: 0, volumes left: 0, networks left: 0

== run 3 UP 21:57:53 ==
UP rc=0 21:58:45
== run 3 SMOKE 21:58:46 ==
SMOKE rc=0 22:00:58
ok   the console login route answers (401)
ok   engine idle within 10 s of the client hanging up
ok   usage recorded once each: cancelled=1 ok=2 
ok   the cancelled stream is billed for its 6 generated tokens
smoke finished: 0 failed, 0 skip-sim
smoke passed
ok lines: 133
== run 3 DOWN ==
containers left: 0, volumes left: 0, networks left: 0
```

The readiness wait ended with `401` (a wrong password reaches auth-service) in all three runs, so the 503 that once came right after `up --wait` did not recur; the cancelled
stream is billed 6 tokens in each run (it is cut after the role chunk and five token chunks), where the 2 s timer once saw 0. Contract points **E19** (live check: 0.05 s to idle against 7 s stock), **E34** (smoke: engine idle within 10 s of the hang-up) and **E35**
(smoke: rows `cancelled=1 ok=2`, the cancelled row's output tokens > 0) pass. The canary check ran in each of the three (`ok   the canary, bearer headers, the API key and query strings are in no log (access log included), nowhere in the database and nowhere in Valkey's file`).

Mutation at the stack level (run once, on an earlier build of the patch; the result depends on the stock engine, not on the patch, and was not repeated): the same stack started with upstream's engine (`ENGINE_IMAGE=ghcr.io/llm-d/llm-d-inference-sim:v0.11.4@sha256:d60f0fb0...`,
engine image id `sha256:d60f0fb0...`), `smoke.sh` without `SIM_STOCK`:

```
[stock] SMOKE rc=1 14:41:24
FAIL engine still busy (1)
ok   usage recorded once each: cancelled=1 ok=2
FAIL the cancelled stream recorded no output tokens
smoke finished: 2 failed, 0 skip-sim           (130 other lines ok)
[stock] DOWN rc=0; project containers left: 0, volumes left: 0
```

With `SIM_STOCK=1` the same two print as `skip-sim` and the run is H1a's (0 failed, 2 skip-sim); that mode was not run again in this step.

Not run in this step: the fleet profile with the patched engine (`docker compose config` only: valid), the GPU overlay, the rolling restart or
any kill drill (H2/H3), `check-prometheus.sh` (no Prometheus file changed), `go test` of the packages the patch does not touch (`./pkg/...` builds and
vets clean; only `./pkg/api`, `./pkg/simulator` and `./pkg/communication` were tested).

### Review fixes, round 4 (commit "H5: review fixes", fourth)

What the review asked for, in its order, and where it is shown:

1. **The class of guards without a test is closed**: the inventory, the 62 single-guard mutations (all killed, each by a named spec) and the list of what was deleted are under Evidence. Two real gaps were found by it that earlier rounds missed:
   the 499 closed-channel branch had no failing spec (HT5 to HT8 now do), and `dropWaiting` removed the *front* item of the queue instead of its own (SM16 was not covered; a request that stayed behind was dropped). The `sendStream` gone-guard
   was not deleted: it has an effect for `n > 1` (spec HT13), none for `n = 1`; the reviewer's condition ("delete it unless a spec shows otherwise") is met by that spec. The guards on the "deleted" list (Evidence) were removed instead of tested.
2. **No test image is stored**: `docker/sim/build.sh` builds the test stage with `--output type=cacheonly` (so do the mutation builds); after the session `docker image prune -f` reclaimed 0 B and `docker images -f dangling=true` is empty (header only).
   Free disk on `C:` stayed at 13 GB or more.
3. **Smoke determinism**: the readiness wait and the hang-up-after-12-lines cancel of the uncommitted work held; **three consecutive full runs, 0 failed each** (Evidence).
4. **Live check on the final image**: 19 ok, 0 failed; against upstream's digest 5 failed (Evidence). The image id recorded above is that of these runs.
5. **Leftovers**: `ponytail:` comments with ceiling and upgrade path on the 25 ms poll (`clientPollEvery`), the Linux-only peek (`conncheck_linux.go`, `conncheck_other.go`), continuous usage on chat streams only (`continuousUsageRequester`) and the goroutine per request (`watchClient`);
   the `processRequest` comment now says only that the repo's own measurement (phase-6-progress.md:39) left `request_success_total{finished_reason="abort"}` at 0 on vLLM v0.30.0; the drafted `platform.md` paragraph says that the engine image is a one-time local build (`bash docker/sim/build.sh`) because `pull_policy` is `never`.

### Decisions the brief left open

| Decision | Source |
| --- | --- |
| The runtime stage of the image is upstream's pinned image, only the binary replaced. | Same user, entrypoint, port and distroless base as the pinned simulator by construction, and no second base image to pin. Cost: the old binary's layer stays underneath (85 MB image). |
| The source is verified by a content hash, not by a tag. | The prototype's tree is a CRLF checkout without `.git`; the commit cannot be read from it. `SRC_PIN` is computed from the LF `git archive` of tag v0.11.4 and equals the CRLF tree after normalising. The build stops on any other tree, and `patch` would also fail on a different context. |
| Detect the hang-up with a socket peek, not with a read or an SSE keepalive. | A read would steal the next request's first bytes on a reused connection; a keepalive write would commit the 200 status before the queue-full 429 that `handleStream` deliberately waits for. |
| The wire label stays `finish_reason`. | It is the simulator's own label for every finish reason; renaming it for one value would break its other dashboards. The rules and drills read `request_success_total` by `finish_reason`. |
| Usage on every chunk only for `/v1/chat/completions` streams. | The only endpoint inference-service uses; `/v1/completions`, `/v1/responses` and `/v1/messages` stay as upstream (patch header says so). |
| `SIM_STOCK=1` replaces the two opt-in flags of H1a. | The patched engine is the default now, so the exception is the stock engine. |

### Deviations

10. **Hardening override 5, pinned images, for the engine.** The image compose runs is built locally and referenced by a version tag
    (`carmona/llm-d-inference-sim:v0.11.4-disconnect.1`), not by `tag@sha256`: a locally built image has no registry digest until it is pushed,
    and pushing is not allowed here. What is pinned: both inputs of the build (the golang image and the upstream runtime image by digest,
    the source by `SRC_PIN`) and `pull_policy: never`. Alternative: a private registry, then `image@sha256:`.
11. **Build is not part of `docker compose up`.** The source lives outside the repo (`work/prototype-sim/_sim-src-v0.11.4`), so compose cannot
    `build:` it. A fresh checkout needs `bash docker/sim/build.sh` once (and a copy of the v0.11.4 source) before the first `up`. CI is the
    first place that fails (cross-chain request below). Alternative: vendor the source under `docker/sim/` (about 1 MB of Go), which makes the build
    self-contained.
12. **`finish_reason`, not `finished_reason`, and the abort series is not vLLM's.** The simulator names the label `finish_reason`, patched or not; vLLM's is
    `finished_reason` (docs.vllm.ai/en/latest/design/metrics.html). Worse for fidelity: the repo's own measurement on vLLM v0.30.0 (phase-6-progress.md line 39)
    is that an aborted request appears in none of vLLM's finish counters (`finished_reason="abort"` stays 0). The review read the same in v0.30.0's
    `output_processor.py` (`abort_requests` drops the request state without recording a finish); I could not fetch the source here to confirm it. So the simulator's `finish_reason="abort"` count has no counterpart on vLLM.
    A rule, dashboard or drill that must also run with `ENGINE=vllm` must not read it; use it only as simulator evidence (the live check and smoke do).
13. **Simulator fidelity left open.** The abort counters count the work done (tokens produced, the prompt once processed). That is the simulator's own
    reading, not a copy of vLLM: how vLLM v0.30.0 counts the tokens of a streamed, cancelled request, and of one aborted while it waits, is not
    verified (the simulator counts nothing for a hang-up before the first token). To verify on the GPU (owner-driven): cancel a stream mid-way and
    diff `prompt_tokens_total` and `generation_tokens_total` against the tokens the client saw. Token counts are
    still the simulator's regex tokenizer (G9). `cache_salt` and `priority` stay ignored (G6, G7).
14. **Linux-only socket peek.** On a non-Linux build, or behind TLS, a hang-up is found by the next write only (the stream case); a request still
    waiting in the queue would run as before. The image is Linux.

### New stores of personal data

None. The patch adds no logging of request content: the one new log line is at debug level and carries the request id and a token count; the
engine's logs were covered by the canary check (`CANARY-<uuid>` in no log, no database dump) in the smoke run below.

### For the orchestrator

- **Cross-chain requests.** (a) `.github/workflows/ci.yaml`: before `docker compose up`, run `bash docker/sim/build.sh` (needs the v0.11.4 source in `SIM_SRC`, or vendor it, Deviation 11) and run `smoke.sh` without `SIM_STOCK`; the H1a request about `GRAFANA_ADMIN_PASSWORD` / `MINIO_*` still stands. (b) H2/H3 must not read the abort series (`request_success_total{finish_reason="abort"}`) in any check that must also run with `ENGINE=vllm` (Deviation 12). H2/H3 can now count on the engine token counters: a cancelled stream adds at most the tokens produced before the next 25 ms poll (a few) to `generation_tokens_total` beyond the last chunk inference-service saw, so the accounting tolerance for cancelled streams is a few tokens per cancel, not the rest of the generation.
- **Lines a reviewer should read twice.** None is a money path. `client_link.go` `stamp` and `http.go` `emitResponseChunks` (`state.completion++` sits between the role chunk and the token chunk: it decides what a cancelled stream is billed); `conncheck_linux.go` (a wrong "gone" cancels a healthy request: the `ErrDeadlineExceeded` case); `build.sh` `SRC_PIN` check.

### Drafted "built" paragraph (the orchestrator moves it)

For `inference-plan.md` (top blocks and the paragraph on the simulated engine written for H1a):

> **Simulator disconnect patch built 2026-10-09** (log: [pass-2-har-progress.md](pass-2-har-progress.md), step H5; closes G1 and G3 of the
> prototype's findings): the default engine is llm-d-inference-sim v0.11.4 plus `docker/sim/disconnect.patch`, built by `docker/sim/build.sh`
> from the verified v0.11.4 source into the local image `carmona/llm-d-inference-sim:v0.11.4-disconnect.1` (upstream's runtime image with
> the binary replaced). A client that hangs up now stops the generation at its next token, in the queue, before the first token and
> mid-stream (a waiting request leaves the queue at once); an aborted request is counted by the simulator (`finish_reason="abort"`, the
> tokens produced, the prompt if it was processed; that series is simulator-only, vLLM v0.30.0 leaves `finished_reason="abort"` at 0); `continuous_usage_stats` puts the usage so far on every chat chunk, so a cancelled stream is billed
> what it had produced. The two H1a `skip-sim` assertions run again (`smoke.sh`: 0 failed, 0 skip-sim); `SIM_STOCK=1` skips them for upstream's
> engine. Deviations, on purpose: the image is a local tag, not `tag@sha256` (no registry); it is a one-time local build (`bash docker/sim/build.sh`, `pull_policy: never`), not built by `compose up`; continuous usage covers chat
> streams only; and the socket peek is Linux-only.
