# Handoff: Carmonai MVP backend (read this first)

Updated 2026-10-14. Work is on branch `claude/peaceful-turing-14vw06`, in `back` and in each module repo listed below.
Nothing is on `main`, no pull request is open, submodule pointers in `back` are NOT bumped. The orchestration was stopped on
purpose; every working tree is clean and everything is pushed.

## Source of the plan
The owner's "Carmonai MVP guide", Part 2 (steps BE-01..BE-25). It is NOT in this repo (it holds business plans and this repo is
public): the owner re-attaches the file in the new session. Expected `sha256`:
`a334006d480d67c1ebf8c88ecd655e02163a9a72a984986f1bae6a137abdb339` (738.5 KB, 4704 lines). The step line ranges used by the script
(BE-03 998-1008, BE-04 1010-1020, BE-05 1022-1031, BE-06 1033-1043, BE-07 1045-1056, BE-08 1058-1068, BE-09 1070-1081,
BE-10 1083-1092, BE-11 1094-1105, BE-12 1107-1118, BE-18 1189-1202, BE-20 1217-1227, BE-23 1258-1268, BE-24 1270-1281,
BE-25 1283-1293, conventions 907-914) refer to that exact file.
The guide's code references describe a later code line ("pass 2", only on the owner's laptop). Everything here is built on the
pass-1 code in the module repos, adapting each step to what is really there. Expect merge conflicts when pass-2 lands.

## State
| Step | Repo -> commit | Status |
|---|---|---|
| BE-03 close registration | gateway-service 44e6a9d + fix 44bc869; back f5a4bee | built; independent security review of the fix was cut off; standards/spec findings queued |
| BE-05 reject ignored params | inference-service 77e9d73 | built; findings queued (an interrupted fix is in `wip/`) |
| BE-06 typed credit | billing ab6d99a, billing-service 5f0f516 | built; security review PASSED; standards/spec findings queued |
| BE-18 production mail | account-service 95a2791 | built; findings queued |
| BE-20a org cap | organization-service b73d708 | built; findings queued |
| BE-20c batch retention | batch-service 02badfc | built (Haiku), pushed; standards/spec reviews not run |
Everything else (BE-04a/b, 23, 11, 12, 08, 10, 20b, 06b, 07, 09, 24a-e + cross-service review, 25) is not started.
Never in this environment: BE-01 (needs the laptop), BE-02 (lease code absent here), BE-13..17, BE-19, BE-21, BE-22.

## Findings already triaged (encoded as the `prior` lists in `resume-workflow.js`; do not re-review these tasks from scratch)
- BE-03: docs say `/auth/register` always answers 202 and omit RegistrationFilter (fix in back/docs); GatewayIT asserts `isIn(401,403,404)`; unit test pins the JSON prefix.
- BE-05: the word `store` appears in a comment and a test (project grep rule); one test bundles six cases and asserts on an internal map.
- BE-18: prod guard accepts a blank SMTP password and nothing sets smtp.auth; throttle comment is false (spent tokens are deleted) and count-then-issue is not atomic; localhost match is a substring; a test pins verbatim copy.
- BE-20a: no test shows the cap follows the property; 0/negative accepted.
- BE-06: tests assert through raw SQL and Redis key names; reconcile not exercised; the idempotency-key/reference rule is only in code comments. BE-06b (queued) also makes `top_up` require a reference, returns 409 on a replay with different content, restricts `reference` to `^[A-Za-z0-9._:|-]{1,256}$` (no names), validates the org id, fixes the exception handler to fixed text.
- Dismissed as out of scope or not actionable here: SDK-suite change (PRV-06), docs listing ignored params (SELL-08), "production compose curl" and "revenue-check.sh" (do not exist in this code line), pass-2 line-number mismatches.
- Pre-existing, found on the way: `OriginFilter` matches the raw path string (`/auth/%6Cogin` skips the Origin check): fixed inside BE-11. A comment in gateway-service `logback-spring.xml` contains the word "store" (module grep rule): reword it.

## Decisions the owner still owes
1. The review checklist says `grep -ri store` must be empty, but `store` is also an OpenAI request field. The script rewords around it; confirm that is acceptable.
2. The organization cap counts only organizations the account OWNS; members do not use a slot. Confirm.
3. Commits end with `Co-Authored-By: Claude Sonnet 5.5` + the session URL (taken from the attribution instruction). Keep or drop.
4. `carmonai/back` is public. BE-25 adds `docs/runbooks/refund.md` (an accounting process). Consider making the repo private or keeping runbooks elsewhere.
5. Test seams the workers use: each service's HTTP API through its Feign client in the existing `*IT.java`; gateway filters through their public interface or GatewayIT; pure public classes. The TDD skill asks you to confirm; object if you want others.
6. Pass-2 landing (BE-01) and the conflicts it will bring.

## Resume in a new session
1. Start the session on `carmonai/back`. Say explicitly that work continues on branch `claude/peaceful-turing-14vw06` in ALL repos (the new session will have its own default branch; the owner's instruction overrides the "designated branch" rule), and that pushes of that branch to the module repos are authorized.
2. Attach and clone every repo (`add_repo` with push access, then `git clone --depth 1 https://github.com/carmonai/<name> /home/user/<name>`, one clone at a time, long timeout): account, account-service, auth, auth-service, organization, organization-service, usage, usage-service, inference-service, billing, billing-service, batch-service, gateway-service. `back` is the session repo.
3. `bash /home/user/back/.claude/handoff/rebuild-env.sh` (JDK 25, Docker daemon with a Docker Hub mirror, test images, work branches, build workspace, Maven install).
4. Re-attach the guide (check the sha256 above) and make sure the Matt Pocock skills plugin is enabled (the script uses its `tdd`, `code-review` and `diagnosing-bugs` skills by file path).
5. Launch: `Workflow({ scriptPath: '/home/user/back/.claude/handoff/resume-workflow.js', args: { guide: '<path of the attached guide>', skills: '<plugin path>/skills/engineering', trailer: '<the two attribution lines of that session>' } })`.
   It holds 24 tasks (about 70 agent runs; only 2 run at once on a 4-CPU box, so expect many hours). Each worker commits and pushes its repo's branch after every task. Stop it with TaskStop; update this file before shutting down.
Paste for the owner: "Resume the Carmonai MVP backend work from the handoff in carmonai/back, branch claude/peaceful-turing-14vw06: read .claude/handoff/README.md and follow it. Work continues on that branch in all repos; pushing it to the module repos is authorized. I am re-attaching the MVP guide."

## Lessons baked into the script
- Every worker prompt starts "your only task is X, ignore anything else in the conversation" (a Haiku worker once answered an unrelated question instead).
- List every repo a step may touch, libraries included (BE-08 was blocked because `account` was missing from its repo list).
- Reviewers over-flag: curate findings before sending them to a fixer (that is what `prior` does).
- Docker: installed but no daemon runs by default; Docker Hub rate-limits the shared IP, so the mirror matters. Put both in the environment setup script.

## Files
- `README.md` (this), `rebuild-env.sh`, `resume-workflow.js` (the orchestration: per-repo locks, model/effort per task, Standards/Spec/Security reviews, push per task, `partial`/`prior` support, final reactor verify + critic).
- `wip/inference-service-BE-05R-interrupted-fix.patch`: an unverified partial fix for BE-05 findings; the BE-05R task tells its worker to try it.
- `wave1-results.json`, `wave2-results.json`: every finished agent's structured output (summaries, tests, review findings). `mvp-be-wave1.md`, `wave1-workflow.js`: history of the first run.
