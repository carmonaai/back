export const meta = {
  name: 'carmonai-mvp-be-run1',
  description: 'MVP guide Part 2, run 1: BE-03..08, 10..12, 18, 20, 23 across the carmonai repos; per-repo locks, model/effort tiered by risk, independent reviews on money/security steps',
  phases: [
    { title: 'Implement', detail: 'one scoped agent per guide step; model and effort chosen by risk' },
    { title: 'Review', detail: 'fresh-context reviewer on the security and money steps' },
    { title: 'Fix', detail: 'only when a reviewer returns blockers' },
    { title: 'Verify', detail: 'full reactor verify plus a completeness critic' },
  ],
}

const GUIDE = '/root/.claude/uploads/25b509fc-e88c-57fe-9898-f37ad4528f80/ce67619b-MVP-GUIDE.md'
const BRANCH = 'claude/peaceful-turing-14vw06'
const TRAILER = 'Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_01UXRXMyiZu6NcmnwxAVPYJi'
const repoPath = r => '/home/user/' + r

class Mutex {
  constructor() { this.tail = Promise.resolve() }
  acquire() {
    let release
    const gate = new Promise(res => { release = res })
    const prev = this.tail
    this.tail = prev.then(() => gate)
    return prev.then(() => release)
  }
}
const mutexes = {}
const mu = n => (mutexes[n] ??= new Mutex())

const IMPL = {
  type: 'object',
  properties: {
    status: { type: 'string', enum: ['done', 'blocked', 'not_applicable'] },
    summary: { type: 'string' },
    commits: { type: 'array', items: { type: 'object', properties: { repo: { type: 'string' }, sha: { type: 'string' } }, required: ['repo', 'sha'] } },
    tests: {
      type: 'object',
      properties: {
        added: { type: 'array', items: { type: 'string' } },
        failedBeforeChange: { type: 'string' },
        command: { type: 'string' },
        result: { type: 'string' },
        notRun: { type: 'string' },
      },
      required: ['result'],
    },
    deviations: { type: 'array', items: { type: 'string' } },
    followUps: { type: 'array', items: { type: 'string' } },
  },
  required: ['status', 'summary', 'commits', 'tests'],
}

const REVIEW = {
  type: 'object',
  properties: {
    verdict: { type: 'string', enum: ['pass', 'fail'] },
    blockers: { type: 'array', items: { type: 'object', properties: { file: { type: 'string' }, issue: { type: 'string' }, fix: { type: 'string' } }, required: ['file', 'issue'] } },
    nits: { type: 'array', items: { type: 'string' } },
    testsProveClaim: { type: 'string' },
  },
  required: ['verdict', 'blockers'],
}

const COMMON = [
  'You are one worker in a larger, orchestrated build of the Carmonai backend (Java 25, Spring Boot 4.1, Maven, Postgres 17, Valkey). Do ONLY the task below, nothing adjacent.',
  '',
  'ENVIRONMENT',
  '- Each module is its own plain git clone (not a submodule) at /home/user/<name>. Libraries: account, auth, organization, usage, billing. Services: account-service, auth-service, organization-service, usage-service, inference-service, billing-service, batch-service, gateway-service. The parent repo /home/user/back holds docker/ (compose, smoke.sh), docs/ and .github/.',
  '- Build workspace: /home/user/ws (root pom + api/<name> symlinks). ALWAYS first: export JAVA_HOME=/usr/lib/jvm/java-25-openjdk-amd64; export PATH=$JAVA_HOME/bin:$PATH',
  '- Test a module: cd /home/user/ws && mvn -B -pl api/<module> verify   (runs unit tests and the Testcontainers ITs; Docker daemon IS running and the postgres/valkey/mailpit images are pre-pulled; about 30-90 s per module). Focus with -Dtest=<UnitTest> -Dit.test=<IT> -Dsurefire.failIfNoSpecifiedTests=false. NEVER use -am, never build modules you do not hold. If you change a LIBRARY module, run mvn -B -q -pl api/<lib> -DskipTests install before building the services that use it.',
  '- Do not start, stop or restart Docker, do not docker pull other images, do not run docker compose / smoke.sh (the full stack needs a huge model image). Do not run docker system prune.',
  '- Other workers are editing OTHER repos at the same time. Edit and run git ONLY in the repos listed under HOLD. Do not touch .gitmodules, submodule pointers, /home/user/ws, or ~/.m2 by hand.',
  '',
  'PROJECT RULES (non-negotiable)',
  '- First read /home/user/back/.claude/skills/carmonai-architecture/SKILL.md. Library/service split; Resource -> Service -> Repository; domain class X vs JPA XModel; XIn/XOut records; UUID String ids; Flyway migrations date-versioned and later than the newest in that service (e.g. V2026.10.13.001__name.sql), Hibernate only validates; config from env vars through application.yaml; port 8080.',
  '- No personal data (email, name, token, key, prompt text) in logs. No default secrets. Error handlers return fixed text, never an exception message. Every outbound call has a timeout.',
  '- Match the surrounding code: style, comment density, naming. No features beyond the task, no new dependencies unless unavoidable (then say so in deviations). No TODO comments. Comments and commit messages must not name any AI model.',
  '',
  'HOW TO WORK',
  '1. Read your guide section (file and line range below). Its file names and line numbers describe a LATER code line (called pass 2); verify every reference against the code that is actually present and adapt to the real equivalent. If the thing the task changes does not exist in this code at all, return status not_applicable with evidence and change nothing. If you are blocked, return status blocked with the exact reason; do not guess.',
  '2. Write the acceptance test(s) FIRST. Run them against the unchanged code and see them fail; put the failing line in tests.failedBeforeChange. Then implement until green.',
  '3. Run mvn -B -pl api/<each module you hold> verify. Everything must pass. Report the exact command and the final Tests run line.',
  '4. Commit in EACH repo you changed (branch ' + BRANCH + ' is already checked out there): git add -A, then git commit with the message "<ID> <title>", a blank line, 2-4 lines on what and why, a blank line, then EXACTLY these two trailer lines:',
  TRAILER,
  '   One commit per repo. Do NOT push. Do not leave uncommitted changes. Return each repo name and the commit sha (git rev-parse HEAD).',
  '5. Return the structured result honestly: anything unproven or deviating from the guide goes in deviations; ideas outside the task go in followUps.',
].join('\n')

function implPrompt(t) {
  return [
    COMMON, '',
    'TASK ' + t.id + ': ' + t.title,
    'HOLD (the only repos you may edit or commit in): ' + t.repos.map(repoPath).join(', '),
    'GUIDE: read ' + GUIDE + ' lines ' + t.guide[0] + '-' + t.guide[1] + ' (use offset/limit), and lines 907-914 for the conventions.',
    '', 'SPECIFICS', t.brief,
    '', 'DONE WHEN', t.accept,
  ].join('\n')
}

function reviewPrompt(t, commits, second) {
  return [
    'You are an INDEPENDENT reviewer. You did not write this code. Look ONLY at money correctness and security; do not nitpick style. Do not edit any file and do not commit.',
    'Task under review: ' + t.id + ' ' + t.title + '. Spec: ' + GUIDE + ' lines ' + t.guide[0] + '-' + t.guide[1] + '.',
    'Diffs: ' + commits.map(c => 'git -C ' + repoPath(c.repo) + ' show ' + c.sha).join(' ; '),
    'Read the surrounding code as needed (the repos are at /home/user/<name>). Project rules: /home/user/back/.claude/skills/carmonai-architecture/SKILL.md.',
    'Check: (1) every acceptance point of the spec is met; (2) can it be bypassed, does any path fail open; (3) personal data or secrets in logs, errors or responses; (4) races, double-spend, idempotency; (5) do the tests actually prove the claim (would they fail if the change were removed?); (6) anything the spec requires that is missing.',
    second ? 'This is the SECOND review after a fix round: confirm the earlier blockers are resolved and no new blocker was introduced.' : '',
    'verdict = pass only if there is no blocker. A blocker is a concrete defect with a concrete fix; put anything else in nits.',
  ].join('\n')
}

function fixPrompt(t, review) {
  return [
    COMMON, '',
    'TASK ' + t.id + ' FIX ROUND: an independent reviewer found blockers in your earlier commit(s). Fix exactly these and nothing else, with a test for each, then commit as a NEW commit per repo (message "' + t.id + ' review fixes").',
    'HOLD: ' + t.repos.map(repoPath).join(', '),
    'GUIDE: ' + GUIDE + ' lines ' + t.guide[0] + '-' + t.guide[1],
    'BLOCKERS (JSON): ' + JSON.stringify(review.blockers),
  ].join('\n')
}

const TASKS = [
  {
    id: 'BE-03', title: 'Close public registration (SEC-01)', repos: ['gateway-service', 'back'],
    model: 'sonnet', effort: 'high', review: true, guide: [998, 1008],
    why: 'security-critical but small and well specified',
    brief: [
      '- gateway-service: new property carmonai.gateway.registration-open (env CARMONAI_GATEWAY_REGISTRATIONOPEN), default false.',
      '- When false, POST /auth/register is answered by the gateway itself with HTTP 403 and an OpenAI-shaped error body with code registration_closed, BEFORE any routing/proxying: account-service receives no call, no mail is sent. Reuse the helper the existing filters (OriginFilter, V1RequestFilter) use to build OpenAI-shaped errors. /auth/login, /auth/refresh, /auth/logout are unchanged. When true: previous behaviour.',
      '- Harness: in /home/user/back/docker/compose.yaml set CARMONAI_GATEWAY_REGISTRATIONOPEN=true on the gateway service (smoke.sh and bench.sh register through the gateway) with a one-line comment that production must not set it.',
      '- Tests: unit/slim tests for the new filter or handler, in the style of OriginFilterTest: default false gives 403 + code and the downstream chain is never invoked; true passes through.',
    ].join('\n'),
    accept: 'New tests fail on unchanged code and pass after; mvn -B -pl api/gateway-service verify green; the compose diff is only the one env line plus its comment.',
  },
  {
    id: 'BE-04a', title: 'Production key prefix (SEC-02), code', repos: ['auth-service', 'gateway-service'], needs: ['BE-03'],
    model: 'sonnet', effort: 'high', review: true, guide: [1010, 1020],
    why: 'security change spanning two services, needs care but not deep design',
    brief: [
      '- auth-service: new property carmonai.keys.prefix (env CARMONAI_KEYS_PREFIX), default cmn_test_. The constant ApiKeys.PREFIX becomes the configured value; newly minted keys use it. The production value cmn_live_ goes in a new application-prod.yaml (activated by SPRING_PROFILES_ACTIVE=prod); create the file if missing.',
      '- gateway-service: new property carmonai.gateway.key-prefixes (env CARMONAI_GATEWAY_KEYPREFIXES, comma list), default both cmn_test_ and cmn_live_; application-prod.yaml lists only cmn_live_. A well-formed key whose prefix is not allowed gets 401 invalid_api_key BEFORE any lookup: prove with a test that the auth-service client/stub is called 0 times.',
      '- Verify the key checksum covers the key body only, not the prefix, so the format stays compatible. If it covers the prefix, STOP and report it in deviations instead of changing the format.',
      '- Update the existing tests that assert the old prefix in these two modules so they pass; the default stays cmn_test_ so unrelated ITs keep working. Add: a test that a key minted under prefix cmn_live_ starts with cmn_live_ (AuthServiceIT or ApiKeysTest) and that the gateway refuses cmn_test_ when only cmn_live_ is allowed.',
    ].join('\n'),
    accept: 'New tests fail before and pass after; mvn -B -pl api/auth-service verify and mvn -B -pl api/gateway-service verify green.',
  },
  {
    id: 'BE-04b', title: 'Document the cmn_live_ prefix and its two properties', repos: ['back'], needs: ['BE-04a'],
    model: 'haiku', effort: 'medium', review: false, guide: [1010, 1020],
    why: 'docs-only, mechanical: smallest model',
    brief: [
      '- Docs only. In /home/user/back/docs (and docker/*.md if any) find places that describe the API key format cmn_test_... Add one short note each: production keys start cmn_live_; the test stack mints cmn_test_ unless CARMONAI_KEYS_PREFIX (auth-service) and CARMONAI_GATEWAY_KEYPREFIXES (gateway-service) are set. Check the exact names and defaults in the BE-04a commits: git -C /home/user/auth-service log -1 -p ; git -C /home/user/gateway-service log -1 -p.',
      '- Do NOT edit docker/smoke.sh or any code. Do not rewrite unrelated docs text. If docs have no such place, return not_applicable.',
    ].join('\n'),
    accept: 'git -C /home/user/back diff shows only small doc additions; grep -rn cmn_live_ /home/user/back/docs returns the new notes.',
  },
  {
    id: 'BE-23', title: 'Hide batch for launch (BAT-02)', repos: ['gateway-service', 'back'], after: ['BE-04b'],
    model: 'sonnet', effort: 'medium', review: false, guide: [1258, 1268],
    why: 'small config + filter + doc; routine',
    brief: [
      '- gateway-service: new property carmonai.gateway.batch-enabled (env CARMONAI_GATEWAY_BATCHENABLED), default true. application-prod.yaml (create or extend) sets it false. When false, every request to /v1/files, /v1/files/** , /v1/batches, /v1/batches/** is answered with an OpenAI-shaped 404 with code not_found, before routing. Apply it after the API-key checks (so an invalid key still gets 401, a valid key gets 404). Do not restate the route list in the prod profile.',
      '- harness: docker/compose.yaml in /home/user/back sets CARMONAI_GATEWAY_BATCHENABLED=true on the gateway with a one-line comment (smoke.sh batch section must keep passing on the harness).',
      '- docs: add /home/user/back/docs/operations/batch-reenable.md (check the docs layout first; add it to mkdocs.yml nav only if that nav lists the other operations pages) with the re-enable checklist from guide item 3: batch-bench on the GPU, limits (4 MB file, 50,000 lines, 24h window, no list calls), retention 7 days, a half-price batch price row added as a future row.',
      '- Tests: property false gives 404 not_found for each of the listed paths and methods, property true passes through.',
    ].join('\n'),
    accept: 'New tests fail before, pass after; mvn -B -pl api/gateway-service verify green.',
  },
  {
    id: 'BE-11', title: 'Real client IP behind the proxy (SEC-03)', repos: ['gateway-service'], after: ['BE-23'],
    model: 'sonnet', effort: 'high', review: true, guide: [1094, 1105],
    why: 'security: trust model of a forwarded header needs judgement',
    brief: [
      '- Make rate limiting (RateLimitFilter) and the access log (AccessLogFilter client_ip) use the real client address from X-Forwarded-For when the request comes through the trusted proxy, via server.forward-headers-strategy: framework or the Reactor Netty forwarded handling; the test decides which works in this gateway. Record in the test which entry of a two-entry header is used.',
      '- Test (must fail on unchanged code): 25 POST /auth/login from the same peer with X-Forwarded-For 203.0.113.9 hit 429 from about the 21st (burst 20, refill 1/s); right after, a request with X-Forwarded-For 203.0.113.10 is not throttled; each access-log line carries its own client_ip.',
      '- Add a short code comment and a note in docs/operations (or the closest existing page) that the header is trusted from anyone who can reach the gateway, so the gateway must be reachable only from the reverse proxy and the proxy must overwrite X-Forwarded-For.',
      '- Optional source port: only if trivial, add property carmonai.gateway.client-port-header (default empty = off) that, when set, copies that header into a new access-log field client_port. Otherwise skip and list it in followUps.',
    ].join('\n'),
    accept: 'New tests fail before, pass after; mvn -B -pl api/gateway-service verify green.',
  },
  {
    id: 'BE-05', title: 'Reject silently ignored parameters (API-02)', repos: ['inference-service'],
    model: 'sonnet', effort: 'medium', review: false, guide: [1022, 1031],
    why: 'single-service, well specified request validation',
    brief: [
      '- In the chat request parsing (ChatRequest): response_format of type json_object or json_schema, logprobs: true, any top_logprobs, any logit_bias each return HTTP 400 with code unsupported_parameter and a message that names the field. Accept response_format type text and logprobs: false. Ignore harmlessly: user, metadata, store. top_k, min_p and reasoning_effort stay ignored. Use the same ApiError helper the other validations use (unsupported_n is the model).',
      '- Tests first, in a unit test class for ChatRequest parsing (create ChatRequestTest if none) and, if the existing InferenceServiceIT has a natural place, one end-to-end case. They must fail on unchanged code (today they return 200 and the field is dropped).',
    ].join('\n'),
    accept: 'New tests fail before, pass after; mvn -B -pl api/inference-service verify green.',
  },
  {
    id: 'BE-12', title: 'OpenAI compatibility polish (API-03, API-04, API-05)', repos: ['inference-service', 'gateway-service'], needs: ['BE-05'], after: ['BE-11'],
    model: 'sonnet', effort: 'high', review: false, guide: [1107, 1118],
    why: 'streaming usage semantics are subtle; two services',
    brief: [
      '- GET /v1/models/{id}: add the route in inference-service and in the gateway route list. 200 with the same object shape as an entry of GET /v1/models; unknown id gives 404 model_not_found. The created field comes from a catalog field in the model entry configuration (add it, non-zero, stable; not the current 0).',
      '- Streaming usage: keep asking the engine for continuous usage (billing needs it). When the CLIENT set stream_options.include_usage=true, forward exactly one final chunk with choices: [] and the usage object, and usage: null on all other chunks. Without the option forward no usage at all. Test: the single non-null usage equals the usage event written for that request.',
      '- max_tokens above the cap stays 400 invalid_max_tokens and the message states the cap value.',
      '- Reasoning: if the engine returns a reasoning field, return it as reasoning and also as reasoning_content, in the message and in stream deltas; its tokens stay billed as completion tokens (already inside usage).',
    ].join('\n'),
    accept: 'New tests fail before (models.retrieve is 404; every stream chunk carries usage) and pass after; mvn -B -pl api/inference-service verify and mvn -B -pl api/gateway-service verify green.',
  },
  {
    id: 'BE-06', title: 'Typed and referenced credit (BIL-01)', repos: ['billing', 'billing-service'],
    model: 'sonnet', effort: 'xhigh', review: true, guide: [1033, 1043],
    why: 'money path: highest care, independent review required',
    brief: [
      '- billing library: GrantIn gains type (absent/null means grant; allowed grant or top_up; any other value gives 400 with the same error style the controller uses) and reference (optional, at most 256 characters; when absent fall back to reason). Old callers that send neither field must keep working (JSON compatible).',
      '- billing-service: the ledger row gets the requested type and the reference. Idempotency key format stays grant:{org}:{idempotencyKey}; the same key twice leaves ONE ledger row and ONE balance increase. Reconcile stays balanced:true. A top-up that lifts an exhausted organization clears the no_credit flag within 1 s (verify the existing flag sync; fix only if it does not).',
      '- Code comment: the idempotency key is the Pix end-to-end id; reference holds the id plus an operator tag, never a payer name (the ledger is append-only and a name is personal data). Never log the reference.',
      '- Tests first in BillingServiceIT (they must fail on unchanged code), plus a unit test for the GrantIn validation if you extract it.',
    ].join('\n'),
    accept: 'New BillingServiceIT cases fail before and pass after; mvn -B -pl api/billing verify and mvn -B -pl api/billing-service verify green.',
  },
  {
    id: 'BE-08', title: 'Record terms and privacy acceptance (ID-01)', repos: ['account-service'],
    model: 'sonnet', effort: 'high', review: false, guide: [1058, 1068],
    why: 'new append-only table, export and erasure semantics',
    brief: [
      '- New Flyway migration creating accounts.terms_acceptance(account_id, document, version, accepted_at, channel): document is terms or privacy (CHECK), append-only with the same trigger pattern as the billing ledger (see /home/user/billing-service/src/main/resources/db/migration/V2026.10.03.001__create_tables.sql, refuse_change). COMMENT ON TABLE states purpose (evidence of acceptance), retention, and what erasure does. Default: the row holds only the account id, no name or email, and stays after erasure as evidence (assumption to confirm with the lawyer; say so in the comment).',
      '- Service method to record acceptance (both documents, versions required: missing/blank versions give 400), repository support, and GET /accounts/{id}/export includes the rows. UPDATE and DELETE on the table are refused (assert in an IT). Erasure behaves exactly as the table comment says (assert it).',
      '- The provisioning endpoint is a LATER task (BE-10): deliver storage, service method, export and tests only.',
    ].join('\n'),
    accept: 'New tests fail before, pass after; mvn -B -pl api/account-service verify green.',
  },
  {
    id: 'BE-18', title: 'Production mail (ID-02, ID-04, ID-05)', repos: ['account-service'], after: ['BE-08'],
    model: 'sonnet', effort: 'high', review: false, guide: [1189, 1202],
    why: 'config guard + templates + throttle; moderate',
    brief: [
      '- SMTP settings come from the environment (spring.mail.* via relaxed binding SPRING_MAIL_HOST/PORT/USERNAME/PASSWORD/PROPERTIES_MAIL_SMTP_AUTH/STARTTLS_ENABLE; sender CARMONAI_MAIL_FROM; console URL CONSOLE_URL). Show the variables in application.yaml defaults only where the current file already does; no secrets.',
      '- Startup guard under the prod profile: refuse to start when the console URL or the sender contains localhost or .local, or the SMTP username is missing; clear message with no URL or secret in it. The existing Mailpit IT must still pass with empty auth.',
      '- Portuguese templates (verify, already registered, reset) with UTF-8 subjects incl. accents and one English line at the end of each body (ID-04). Keep links to /verify-email?token= and /reset-password?token= as they are.',
      '- Throttle (ID-05): at most 3 reset tokens per account per hour; the 4th request sends no mail and still answers 202.',
    ].join('\n'),
    accept: 'Guard test and throttle test fail before, pass after; the existing mail IT still passes; mvn -B -pl api/account-service verify green.',
  },
  {
    id: 'BE-10', title: 'Provision endpoint (ORG-02, server side)', repos: ['account-service', 'account'], needs: ['BE-08'], after: ['BE-18'],
    model: 'sonnet', effort: 'high', review: false, guide: [1083, 1092],
    why: 'new internal endpoint with identity/idempotency rules',
    brief: [
      '- POST /accounts/provision {name, email, termsVersion, privacyVersion, acceptedAt, channel} returns the account id. The account is created verified (email_verified_at set); NO mail is sent; terms and privacy acceptance rows are written via the BE-08 method; calling twice with the same email returns the same id and creates no second account.',
      '- No password in the request: the account gets an unusable random password hash (the customer sets a password later through the reset-password link). Never log the email. Add the Feign method and records to the account library.',
      '- Internal only: confirm by READING /home/user/gateway-service/src/main/resources/application.yaml (do not edit it) that no gateway route matches /accounts/provision, and say so in the summary. The shared-secret guard is a later task; do not add one.',
    ].join('\n'),
    accept: 'New tests fail before, pass after (incl. no mail in Mailpit and idempotent second call); mvn -B -pl api/account verify and mvn -B -pl api/account-service verify green.',
  },
  {
    id: 'BE-20b', title: 'Delete stale unverified accounts and expired tokens (RET-01)', repos: ['account-service'], needs: ['BE-10'],
    model: 'sonnet', effort: 'medium', review: false, guide: [1217, 1227],
    why: 'scheduled job with clock-injection test; routine',
    brief: [
      '- Daily job: delete accounts never verified after 7 days (property for the number of days, default 7) and expired account_token rows. Provisioned accounts are verified at creation, so they are safe. Use the clock/time source the code already uses, or inject a Clock so the test controls time.',
      '- Test (fail first): an 8-day-old unverified account disappears together with its tokens; a verified account of the same age stays; a fresh unverified account stays.',
    ].join('\n'),
    accept: 'New test fails before, passes after; mvn -B -pl api/account-service verify green.',
  },
  {
    id: 'BE-20a', title: 'Cap organizations per account (ORG-03)', repos: ['organization-service'],
    model: 'sonnet', effort: 'medium', review: false, guide: [1217, 1227],
    why: 'small, well specified rule',
    brief: [
      '- Property max-organizations-per-account (under the existing carmonai.* config prefix of this service), default 3. Creating a 4th organization for the same account returns 409 with code organization_limit; closing one frees a slot. Count only non-closed organizations the account owns/belongs to as owner; read the service to choose the right count and say what you chose.',
      '- Tests first in OrganizationServiceIT (must fail on unchanged code).',
    ].join('\n'),
    accept: 'New IT cases fail before, pass after; mvn -B -pl api/organization-service verify green.',
  },
  {
    id: 'BE-20c', title: 'Batch file retention property (BAT-01)', repos: ['batch-service'],
    model: 'haiku', effort: 'high', review: false, guide: [1217, 1227],
    why: 'one property bound into an existing query; mechanical, haiku with high effort',
    brief: [
      '- Property carmonai.batch.file-retention (Duration, default 7 days) replaces the hard-coded retention in the file expiry INSERT/sweep (see BatchRepository, BatchFinisher). Bind the value into the SQL instead of a literal interval; the log text must use the configured value.',
      '- Test: with retention 1 minute the sweep deletes the file and its stored object (extend BatchServiceIT or add a focused test following its pattern).',
    ].join('\n'),
    accept: 'New test fails before, passes after; mvn -B -pl api/batch-service verify green.',
  },
  {
    id: 'BE-07', title: 'Tier and suspend with immediate cache eviction (ORG-01)', repos: ['organization-service', 'organization', 'auth-service', 'auth', 'gateway-service'], needs: ['BE-04a'], after: ['BE-20a', 'BE-12'],
    model: 'sonnet', effort: 'xhigh', review: true, guide: [1045, 1056],
    why: 'cross-service security/money-adjacent control; five repos; independent review required',
    brief: [
      '- organization-service (+ organization library): internal-only PUT /organizations/{id}/admin with body {tier?, status?}. tier in trial|standard|enterprise; status only active or suspended (never closed); unknown organization 404; closed organization 409. Add NO gateway route for it.',
      '- After the change, organization-service calls a NEW internal auth-service endpoint (add Feign method in the auth library, implement in auth-service) that deletes the cached apikey:{hash} entry of EVERY key of that organization. Evict before and after the commit (the same pattern the existing key revoke uses; read it). If the eviction call fails, return an error and log only the organization id: the old value then lives at most as long as the key cache TTL.',
      '- Effect within 1 s: after tier=standard the next /v1 request shows the standard rate-limit headers; after status=suspended the next /v1 request is 403 organization_not_active; active restores it. Find where the gateway and auth-service cache a key lookup and make sure the eviction covers every cache layer that holds the tier/status (if the gateway holds an in-memory cache, handle it and say how).',
      '- Gateway test (gateway-service, read its test style): with a valid customer JWT, PUT /organizations/{id}/admin through the public route returns 404 (the public route list allows only GET, POST, DELETE for /organizations); without a token the gateway answers 401 first. Write both numbers into the test.',
      '- Tests first: ITs in OrganizationServiceIT/AuthServiceIT for the behaviour above (they must fail on unchanged code), the gateway test, and unit tests for validation.',
    ].join('\n'),
    accept: 'New tests fail before, pass after; mvn -B -pl api/organization verify, api/organization-service, api/auth, api/auth-service, api/gateway-service all green.',
  },
]

const done = {}
const jobs = {}
const logs = []
for (const t of TASKS) {
  jobs[t.id] = (async () => {
    try {
      const needs = await Promise.all((t.needs || []).map(i => jobs[i]))
      await Promise.all((t.after || []).map(i => jobs[i]))
      const bad = needs.find(r => !r || r.status !== 'done')
      if (bad) return { id: t.id, status: 'skipped', summary: 'needs ' + (bad ? bad.id : '?') + ' which did not finish done' }
      const names = [...t.repos].sort()
      const releases = []
      for (const n of names) releases.push(await mu(n).acquire())
      try {
        log(t.id + ' -> ' + t.model + '/' + t.effort + ' (' + t.why + ')  holds: ' + names.join(','))
        const impl = await agent(implPrompt(t), { label: 'impl:' + t.id, phase: 'Implement', schema: IMPL, model: t.model, effort: t.effort })
        if (!impl) return { id: t.id, status: 'failed', summary: 'implementer died or was skipped' }
        if (impl.status !== 'done') return { id: t.id, status: impl.status, summary: impl.summary, impl }
        let commits = impl.commits
        let review = null
        let fix = null
        if (t.review) {
          review = await agent(reviewPrompt(t, commits, false), { label: 'review:' + t.id, phase: 'Review', schema: REVIEW, model: 'sonnet', effort: 'xhigh' })
          if (review && review.verdict !== 'pass' && review.blockers.length) {
            log(t.id + ' review returned ' + review.blockers.length + ' blocker(s); fix round')
            fix = await agent(fixPrompt(t, review), { label: 'fix:' + t.id, phase: 'Fix', schema: IMPL, model: t.model, effort: t.effort })
            if (fix && fix.status === 'done') {
              commits = commits.concat(fix.commits)
              review = await agent(reviewPrompt(t, commits, true), { label: 'review2:' + t.id, phase: 'Review', schema: REVIEW, model: 'sonnet', effort: 'xhigh' })
            }
          }
        }
        return { id: t.id, status: 'done', model: t.model, effort: t.effort, commits, impl, review, fix }
      } finally {
        releases.forEach(r => r())
      }
    } catch (e) {
      return { id: t.id, status: 'failed', summary: 'orchestration error: ' + String(e && e.message ? e.message : e) }
    }
  })()
}

const results = await Promise.all(TASKS.map(t => jobs[t.id]))

phase('Verify')
const verify = await agent([
  'Read-only verification of the whole Carmonai reactor. Do NOT edit or commit anything.',
  'export JAVA_HOME=/usr/lib/jvm/java-25-openjdk-amd64; export PATH=$JAVA_HOME/bin:$PATH ; cd /home/user/ws && mvn -B verify   (all 13 modules, unit + Testcontainers ITs; Docker is running; takes several minutes). Report the Reactor Summary and every failing test with its first error line.',
  'Then for each repo in account account-service auth auth-service organization organization-service usage usage-service inference-service billing billing-service batch-service gateway-service and back: report git status --porcelain (must be empty) and git log --oneline origin/main..' + BRANCH + ' (for back use the branch tip vs the commit before this session: git log --oneline -15).',
  'Also run: grep -rIl -i "store" over src/main of every changed module and report any hit that is not an unrelated English word (project rule: the Insper namespace word store must not appear).',
].join('\n'), {
  label: 'verify:reactor', phase: 'Verify', model: 'sonnet', effort: 'medium',
  schema: { type: 'object', properties: { buildSuccess: { type: 'boolean' }, summary: { type: 'string' }, failures: { type: 'array', items: { type: 'string' } }, dirtyRepos: { type: 'array', items: { type: 'string' } }, commitsPerRepo: { type: 'array', items: { type: 'string' } } }, required: ['buildSuccess', 'summary'] },
})

const compact = results.map(r => ({ id: r.id, status: r.status, summary: r.summary || (r.impl && r.impl.summary), commits: r.commits, reviewVerdict: r.review ? r.review.verdict : null, reviewBlockers: r.review ? r.review.blockers : null, deviations: r.impl ? r.impl.deviations : null, followUps: r.impl ? r.impl.followUps : null, tests: r.impl ? r.impl.tests : null }))
const critic = await agent([
  'You are a completeness critic. Do not edit anything. For each task below, compare what was reported against the guide section ' + GUIDE + ' (line ranges: BE-03 998-1008, BE-04 1010-1020, BE-05 1022-1031, BE-06 1033-1043, BE-07 1045-1056, BE-08 1058-1068, BE-10 1083-1092, BE-11 1094-1105, BE-12 1107-1118, BE-18 1189-1202, BE-20 1217-1227, BE-23 1258-1268) and against the actual commits (git -C /home/user/<repo> show <sha>).',
  'List per task: guide Done-when items NOT satisfied or not proven, risky shortcuts, tests that would not fail without the change, and anything claimed but absent from the diff. Then list cross-task conflicts (two tasks changing the same behaviour inconsistently).',
  'REPORTED RESULTS (JSON): ' + JSON.stringify(compact),
].join('\n'), {
  label: 'critic:completeness', phase: 'Verify', model: 'sonnet', effort: 'high',
  schema: { type: 'object', properties: { gaps: { type: 'array', items: { type: 'object', properties: { task: { type: 'string' }, gap: { type: 'string' }, severity: { type: 'string', enum: ['blocker', 'major', 'minor'] } }, required: ['task', 'gap', 'severity'] } }, conflicts: { type: 'array', items: { type: 'string' } }, overall: { type: 'string' } }, required: ['gaps', 'overall'] },
})

return { results: compact, verify, critic }
