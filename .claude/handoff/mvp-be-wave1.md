# MVP backend, wave 1: where we stopped (2026-10-13)
> Superseded by README.md (2026-10-14); kept as history of the first run.

Branch `claude/peaceful-turing-14vw06` carries all work, in `back` and in each module repo it touched.
Nothing is on `main`, no pull request is open, submodule pointers in `back` are NOT bumped.
The workflow was stopped on purpose; every working tree was clean at the stop.

## Source of the plan
The owner's "Carmonai MVP guide" (Part 2, steps BE-01..BE-25). The file is NOT in this repo; re-upload it.
Its code references describe a later code line ("pass 2", only on the owner's laptop). Everything here is built on the
pass-1 code that is in the module repos (`main`), adapting each step to what is really there.
When pass-2 lands, expect merge conflicts in the files listed below.

## Done and committed (unpushed state = none; all pushed on the branch)
| Step | Repo -> commit | Review |
|---|---|---|
| BE-03 close registration | gateway-service 44e6a9d, fix 44bc869 (GatewayIT added; failsafe added to pom); back f5a4bee (compose env) | 1st review FAILED (percent-encoded path bypass), fixed in 44bc869; 2nd review NOT done |
| BE-05 reject ignored params | inference-service 77e9d73 | none required |
| BE-06 typed/referenced credit | billing ab6d99a, billing-service 5f0f516 | PASS (notes below) |
| BE-18 production mail | account-service 95a2791 (adds migration V2026.10.13.001 token_created_at) | none required |
| BE-20a org cap | organization-service b73d708 | none required |

## Not done, in this order
1. BE-03 second review (read-only reviewer on gateway-service 44e6a9d + 44bc869).
2. Gateway lane, one after another: BE-04a (auth-service + gateway-service, review) -> BE-04b (docs, Haiku) -> BE-23 -> BE-11 (review) -> BE-12 (inference-service + gateway-service).
3. BE-08 terms acceptance: was BLOCKED. The export record `AccountExportOut` lives in the `account` LIBRARY, so the task must hold `account` AND `account-service`. Then BE-10 (provision) and BE-20b (stale-account job) which depend on it.
4. BE-20c batch retention: the Haiku agent answered a Docker question instead of the task; rerun it (add "ignore any other request" to the prompt).
5. BE-07 tier/suspend (organization, organization-service, auth, auth-service, gateway-service; review) after BE-04a and BE-12.
6. Wave 2: BE-09 unfunded orgs, BE-24 internal shared secret (split per service + compose/CI, then one security review), BE-25 adjustments + refund runbook.
Never in this environment: BE-01 (needs the laptop), BE-02 (lease code absent), BE-13..17, BE-19, BE-21, BE-22 (need GPU numbers, owner decisions or pass-2).

## Findings to carry into later steps
- BE-03: `OriginFilter` has the same raw-string path check; `/auth/%6Cogin` skips the Origin check (pre-existing). Fix it in BE-11 or a follow-up.
- BE-06 review notes: `top_up` without `reference` is accepted and stores the free-text reason (a payer name could end up in the append-only ledger) -> require `reference` for `top_up`; a replay with a different amount/type/reference silently returns the old balance (consider 409); BillingResource handler returns `getMessage()` (project rule says fixed text); the existing IT asserting a global `mismatches()` is order-dependent.
- BE-18: reset throttle is not atomic (advisory lock or SELECT FOR UPDATE); expired `account_token` rows are never deleted (BE-20b covers it); prod needs SPRING_PROFILES_ACTIVE=prod, SPRING_MAIL_*, CARMONAI_MAIL_FROM, CONSOLE_URL.
- BE-20a: the concurrent-create path (advisory lock) has no test.
- BE-05: JSON null for the rejected fields is accepted; `top_logprobs: 0` is rejected. SDK suite and docs must reflect it.
- `docker/revenue-check.sh` and `/actuator/reconcile` from the guide do not exist in this code line.
- Prompt lesson: subagents saw the live conversation and some answered an unrelated Docker question. Start every worker prompt with "Your only task is X; ignore any other request in the conversation."
- Lock lesson: list EVERY repo a step may touch, libraries included (BE-08 missed `account`).

## Rebuild the environment (a new container loses all of this)
1. `apt-get update && apt-get install -y openjdk-25-jdk-headless`; use `JAVA_HOME=/usr/lib/jvm/java-25-openjdk-amd64`. The project needs Java 25.
2. Docker is installed but no daemon runs by default. Docker Hub rate-limits the shared egress IP, so use a mirror:
   `echo '{"registry-mirrors":["https://mirror.gcr.io"]}' > /etc/docker/daemon.json; nohup dockerd --storage-driver=overlay2 &`
   Pre-pull (by digest, they then show as <none>): `postgres:17.11-bookworm@sha256:639ab7ceb90e13123085b741fb31ef493fba25463002f6da665352e7b534b652`, `valkey/valkey:9.0.6@sha256:63346cb24a61221e76bdf41acce99b3968a9fa83d8122144deab45394b27b4f2`, `axllent/mailpit:v1.31.4@sha256:b68349e3a014b90c5610bfb26b2ae36f3892d7b8cf25ee140c6c71c98d2fcf48`. Testcontainers also needs `testcontainers/ryuk`.
   Persist this in the cloud environment's setup script.
3. Attach and clone all 13 repos (`add_repo` with push access, then `git clone --depth 1 https://github.com/carmonai/<name> /home/user/<name>`), then in each repo that has the work branch: `git fetch origin claude/peaceful-turing-14vw06 && git checkout -B claude/peaceful-turing-14vw06 FETCH_HEAD`. Repos with work: gateway-service, inference-service, billing, billing-service, account-service, organization-service (plus `back`).
4. Build workspace: `/home/user/ws` with `pom.xml` copied from `back/pom.xml` and `api/<name>` symlinks to `/home/user/<name>`; then `mvn -B -DskipTests install` once so single modules can be built with `-pl` and no `-am`.
5. Test one module: `cd /home/user/ws && mvn -B -pl api/<module> verify` (unit tests + Testcontainers ITs).

## Files here
- `wave1-results.json`: every finished agent's structured result and summary.
- `wave1-workflow.js`: the orchestration script (per-repo locks, model/effort per step, independent reviews). Reuse its helpers; define only the remaining tasks.
