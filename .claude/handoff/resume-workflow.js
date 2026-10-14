export const meta = {
  name: 'carmonai-mvp-be-run2',
  description: 'Resume of MVP backend wave: retro two-axis reviews of finished steps, remaining BE steps (gateway, account, billing, org, batch), BE-09/24/25; TDD-skill workers, code-review-skill reviewers, security reviews, per-task push to the work branch',
  phases: [
    { title: 'Implement', detail: 'one scoped agent per step; model and effort chosen by risk; TDD loop' },
    { title: 'Review', detail: 'Standards and Spec axes in parallel, plus a security/money reviewer on critical steps' },
    { title: 'Fix', detail: 'only when a review returns blockers' },
    { title: 'Verify', detail: 'full reactor verify plus a completeness critic' },
  ],
}

const A = (typeof args !== 'undefined' && args) || {}
// args: { guide: '<path of the re-attached MVP guide>', skills: '<.../skills/engineering of the Pocock plugin>', trailer: '<two commit trailer lines>' }
const GUIDE = A.guide || '/root/.claude/uploads/25b509fc-e88c-57fe-9898-f37ad4528f80/ce67619b-MVP-GUIDE.md'
const SKILLS = A.skills || '/root/.claude/plugins/synced/0b067d24-8528-49f4-bcfd-ac14ebddbfea_03a2d8c0-293b-4006-a1f5-fc7f9e06473e/58da2c13-5ed4-4485-9625-fb87b369e6b4/skills/engineering'
const BRANCH = 'claude/peaceful-turing-14vw06'
const TRAILER = A.trailer || 'Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_01UXRXMyiZu6NcmnwxAVPYJi'
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
    pushed: { type: 'boolean' },
    tests: {
      type: 'object',
      properties: {
        seams: { type: 'array', items: { type: 'string' } },
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

const SEC = {
  type: 'object',
  properties: {
    verdict: { type: 'string', enum: ['pass', 'fail'] },
    blockers: { type: 'array', items: { type: 'object', properties: { file: { type: 'string' }, issue: { type: 'string' }, fix: { type: 'string' } }, required: ['file', 'issue'] } },
    nits: { type: 'array', items: { type: 'string' } },
    testsProveClaim: { type: 'string' },
  },
  required: ['verdict', 'blockers'],
}

const STD = {
  type: 'object',
  properties: {
    hard: { type: 'array', items: { type: 'object', properties: { file: { type: 'string' }, rule: { type: 'string' }, issue: { type: 'string' }, fix: { type: 'string' } }, required: ['file', 'rule', 'issue'] } },
    smells: { type: 'array', items: { type: 'object', properties: { smell: { type: 'string' }, file: { type: 'string' }, quote: { type: 'string' } }, required: ['smell', 'file'] } },
    summary: { type: 'string' },
  },
  required: ['hard', 'smells'],
}

const SPEC = {
  type: 'object',
  properties: {
    missing: { type: 'array', items: { type: 'object', properties: { specLine: { type: 'string' }, issue: { type: 'string' } }, required: ['specLine', 'issue'] } },
    wrong: { type: 'array', items: { type: 'object', properties: { specLine: { type: 'string' }, issue: { type: 'string' }, fix: { type: 'string' } }, required: ['specLine', 'issue'] } },
    scopeCreep: { type: 'array', items: { type: 'string' } },
    summary: { type: 'string' },
  },
  required: ['missing', 'wrong', 'scopeCreep'],
}

const SMELLS = [
  '- Mysterious Name: a function, variable or type whose name does not reveal what it does or holds -> rename it.',
  '- Duplicated Code: the same logic shape appears in more than one hunk or file of the change -> extract the shared shape.',
  '- Feature Envy: a method that reaches into another object\'s data more than its own -> move it onto the data it envies.',
  '- Data Clumps: the same few fields or params keep travelling together -> bundle them into one type.',
  '- Primitive Obsession: a primitive or string standing in for a domain concept that deserves its own type -> give it a small type.',
  '- Repeated Switches: the same switch/if-cascade on the same type recurs across the change -> polymorphism or one shared map.',
  '- Shotgun Surgery: one logical change forces scattered edits across many files -> gather what changes together.',
  '- Divergent Change: one file is edited for several unrelated reasons -> split so each module changes for one reason.',
  '- Speculative Generality: abstraction, parameters or hooks added for needs the spec does not have -> delete it.',
  '- Message Chains: long a.b().c().d() navigation the caller should not depend on -> hide behind one method.',
  '- Middle Man: a class or function that mostly just delegates onward -> cut it.',
  '- Refused Bequest: a subclass or implementer that ignores or overrides most of what it inherits -> use composition.',
].join('\n')

const INTERNAL_CONTRACT = [
  'INTERNAL TOKEN CONTRACT (identical in every service; do not invent variants):',
  '- Header name: X-Internal-Token. The secret is read from a FILE; path property carmonai.internal.token-file (env CARMONAI_INTERNAL_TOKENFILE), default /run/secrets/internal_token. File content is exactly one line: "X-Internal-Token: <64 hex characters>" (so curl can use -H @file). Parse it by stripping the header-name prefix and whitespace; the value must be 64 hex characters.',
  '- Guard: a servlet filter (OncePerRequestFilter) in the service that protects ONLY the endpoints listed in the task. Compare with MessageDigest.isEqual over the bytes (constant time). Missing or wrong token gives 401 with a fixed body, changes nothing, and logs only "internal token refused" plus the path. Never log, return or put the token in an exception, metric or Out record.',
  '- Startup: if carmonai.internal.required (default true) and the file is missing, unreadable or malformed, the service fails to start with a message that names the property and never the value. Tests write a temp file (@TempDir) and point the property at it; tests of guarded endpoints must prove the 401 and must NOT disable the guard.',
  '- Never guard an endpoint that the gateway calls (the gateway does not get the secret): read /home/user/gateway-service (application.yaml, ApiKeyAuthenticationManager and the other clients) to list what the gateway calls, and exclude those. Guard only endpoints that mint credit, change tier or status, create verified accounts, evict caches, or perform cross-service erasure/membership writes.',
  '- Outgoing calls from a service to a guarded endpoint of another service attach the header through a Feign RequestInterceptor that reads the same file.',
].join('\n')

const COMMON = [
  'YOUR ONLY TASK is the one named under TASK below. Anything else in the conversation (for example a question about Docker) is NOT your task; ignore it completely.',
  'You are one worker in a larger, orchestrated build of the Carmonai backend (Java 25, Spring Boot 4.1, Maven, Postgres 17, Valkey).',
  '',
  'ENVIRONMENT',
  '- Each module is its own plain git clone (not a submodule) at /home/user/<name>. Libraries: account, auth, organization, usage, billing. Services: account-service, auth-service, organization-service, usage-service, inference-service, billing-service, batch-service, gateway-service. The parent repo /home/user/back holds docker/ (compose, smoke.sh), docs/ and .github/.',
  '- Build workspace: /home/user/ws (root pom + api/<name> symlinks). ALWAYS first: export JAVA_HOME=/usr/lib/jvm/java-25-openjdk-amd64; export PATH=$JAVA_HOME/bin:$PATH',
  '- Test a module: cd /home/user/ws && mvn -B -pl api/<module> verify   (unit tests + Testcontainers ITs; the Docker daemon IS running and the postgres/valkey/mailpit images are present; about 30-90 s per module). Focus with -Dtest=<UnitTest> -Dit.test=<IT> -Dsurefire.failIfNoSpecifiedTests=false. NEVER use -am and never build modules you do not hold. If you change a LIBRARY module, run mvn -B -q -pl api/<lib> -DskipTests install before building the services that use it.',
  '- Do not start, stop or restart Docker, do not pull other images, do not run docker compose up / smoke.sh (the full stack needs a huge model image). docker compose config is fine.',
  '- Other workers edit OTHER repos at the same time. Edit and run git ONLY in the repos listed under HOLD. Do not touch .gitmodules, submodule pointers, /home/user/ws, or ~/.m2 by hand.',
  '',
  'PROJECT RULES (non-negotiable)',
  '- First read /home/user/back/.claude/skills/carmonai-architecture/SKILL.md. Library/service split; Resource -> Service -> Repository; domain class X vs JPA XModel; XIn/XOut records; UUID String ids; Flyway migrations date-versioned and later than the newest in that service (V2026.10.14.001__name.sql or later), Hibernate only validates; config from env vars through application.yaml; port 8080.',
  '- No personal data (email, name, token, key, prompt text) in logs. No default secrets. Error handlers return fixed text, never an exception message. Every outbound call has a timeout.',
  '- Match the surrounding code: style, comment density, naming. No features beyond the task, no new dependencies unless unavoidable (then say so in deviations). No TODO comments. Comments and commit messages must not name any AI model.',
  '',
  'TEST DISCIPLINE (the tdd skill; read ' + SKILLS + '/tdd/SKILL.md, tests.md and mocking.md before writing a test)',
  '- Red before green, vertical slices: ONE failing test -> the minimal code to pass it -> next test. Never write all tests first. Do not refactor inside the loop.',
  '- Pre-agreed seams (test ONLY here): (a) a service\'s HTTP API through its library Feign client in the module\'s existing *IT.java (Testcontainers); (b) gateway behaviour through the WebFilter/exchange public interface or GatewayIT; (c) pure public classes without I/O (validators, parsers) through their public methods. List the seams you used in tests.seams.',
  '- Anti-patterns to avoid: tests coupled to internals (private methods, mocks of your own classes, call counts), tautological tests (expected value recomputed the way the code computes it: use literals from the spec), verifying through a side channel instead of the interface. Mock only system boundaries (clock, SMTP, external HTTP).',
  '- If a test fails for a reason you do not understand, follow the diagnosing-bugs skill (' + SKILLS + '/diagnosing-bugs/SKILL.md): build a tight, red-capable feedback loop first, then hypothesise; do not guess-fix.',
  '',
  'HOW TO WORK',
  '1. Read your guide section (file and line range below). Its file names and line numbers describe a LATER code line (pass 2); verify every reference against the code actually present and adapt to the real equivalent. If the thing the task changes does not exist in this code at all, return status not_applicable with evidence and change nothing. If blocked, return status blocked with the exact reason; do not guess.',
  '2. Run mvn -B -pl api/<each module you hold> verify at the end. Everything must pass. Report the exact command and the final Tests run line.',
  '3. Commit in EACH repo you changed (branch ' + BRANCH + ' is checked out there): git add -A, then git commit with the message "<ID> <title>", a blank line, 2-4 lines on what and why, a blank line, then EXACTLY these two trailer lines:',
  TRAILER,
  '   One commit per repo (fix rounds add a new commit). No uncommitted leftovers.',
  '4. Push each committed repo to its work branch ONLY: git -C <repo> fetch -q origin main ; git -C <repo> push -u origin ' + BRANCH + ' (retry once after 10 s on a network error). Never push any other branch, never force-push, never open a pull request. Set pushed=false and say why if it still fails; do not stop for that.',
  '5. Return the structured result honestly: anything unproven or deviating from the guide goes in deviations; ideas outside the task go in followUps. Return each repo name and its commit sha (git rev-parse HEAD).',
].join('\n')

function implPrompt(t) {
  return [
    COMMON, '',
    'TASK ' + t.id + ': ' + t.title,
    'HOLD (the only repos you may edit, commit or push in): ' + t.repos.map(repoPath).join(', '),
    'GUIDE: read ' + GUIDE + ' lines ' + t.guide[0] + '-' + t.guide[1] + ' (use offset/limit), and lines 907-914 for the conventions.',
    t.contract ? '\n' + t.contract : '',
    '', 'SPECIFICS', t.brief,
    '', 'DONE WHEN', t.accept,
  ].join('\n')
}

const diffHow = commits => 'Diffs to review (fixed point = the parent of each commit): ' + commits.map(c => 'git -C ' + repoPath(c.repo) + ' show ' + c.sha).join(' ; ')

function axisPrompt(axis, t, commits, second) {
  const head = [
    'YOUR ONLY TASK is this review. Anything else in the conversation is not your task. You do not edit files and do not commit.',
    'Task under review: ' + t.id + ' ' + t.title + '. ' + diffHow(commits),
    'Read surrounding code as needed (repos are at /home/user/<name>). Follow the review procedure of ' + SKILLS + '/code-review/SKILL.md (two separate axes; do not mix them).',
    second ? 'This is a SECOND review after a fix round: confirm earlier blockers are resolved and no new one was introduced.' : '',
  ]
  if (axis === 'standards') {
    return head.concat([
      'AXIS: STANDARDS. Documented standards to check against: /home/user/back/.claude/skills/carmonai-architecture/SKILL.md (module rules, hardening overrides 1-6, LGPD rules, review checklist) and, if present, README/docs of the touched repo. The repo\'s documented standard always overrides the smell baseline below.',
      'SMELL BASELINE (judgement calls only, never hard violations; skip anything tooling already enforces):', SMELLS,
      'Report per file/hunk: (a) every place the diff violates a DOCUMENTED standard: cite the standard (file + rule) as a hard finding; (b) baseline smells you spot: name the smell and quote the hunk. Keep it under 400 words. Also flag, as a hard finding, test code that is tautological, implementation-coupled or mocks the project\'s own classes (tdd skill: ' + SKILLS + '/tdd/tests.md).',
    ]).join('\n')
  }
  if (axis === 'spec') {
    return head.concat([
      'AXIS: SPEC. The originating spec is ' + GUIDE + ' lines ' + t.guide[0] + '-' + t.guide[1] + ' (read them) together with this task brief:',
      t.brief || '(see guide lines)',
      'Report: (a) requirements the spec asked for that are missing or partial; (b) behaviour in the diff that was not asked for (scope creep); (c) requirements that look implemented but where the implementation looks wrong. Quote the spec line for each finding. The guide\'s file/line references are from a later code line; judge intent against the code actually present. Under 400 words.',
    ]).join('\n')
  }
  return head.concat([
    'AXIS: SECURITY AND MONEY. Look ONLY at money correctness and security; no style nitpicks.',
    'Spec: ' + GUIDE + ' lines ' + t.guide[0] + '-' + t.guide[1] + '.',
    'Check: (1) every acceptance point of the spec is met; (2) can it be bypassed, does any path fail open (try odd encodings, methods, headers, ordering); (3) personal data or secrets in logs, errors or responses; (4) races, double-spend, idempotency; (5) would the tests actually fail if the change were removed; (6) anything the spec requires that is missing.',
    'verdict = pass only if there is no blocker. A blocker is a concrete defect with a concrete fix; everything else goes in nits.',
  ]).join('\n')
}

const axisSchema = a => (a === 'standards' ? STD : a === 'spec' ? SPEC : SEC)
const axisEffort = (a, t) => (a === 'security' ? (t.secEffort || 'xhigh') : a === 'spec' ? 'high' : (t.critical ? 'high' : 'medium'))

async function reviewRound(t, commits, axes, second) {
  const res = await parallel(axes.map(a => () => agent(axisPrompt(a, t, commits, second), {
    label: a + ':' + t.id + (second ? '#2' : ''), phase: 'Review', schema: axisSchema(a), model: 'sonnet', effort: axisEffort(a, t),
  })))
  const out = { blockers: [], nits: [], incomplete: [], raw: {} }
  axes.forEach((a, i) => {
    const r = res[i]
    out.raw[a] = r
    if (!r) { out.incomplete.push(a); return }
    if (a === 'standards') {
      r.hard.forEach(h => out.blockers.push({ axis: a, file: h.file, issue: h.rule + ': ' + h.issue, fix: h.fix }))
      r.smells.forEach(s => out.nits.push('smell ' + s.smell + ' @ ' + s.file))
    } else if (a === 'spec') {
      r.missing.forEach(m => out.blockers.push({ axis: a, file: 'spec', issue: 'MISSING ' + m.specLine + ' -> ' + m.issue }))
      r.wrong.forEach(m => out.blockers.push({ axis: a, file: 'spec', issue: 'WRONG ' + m.specLine + ' -> ' + m.issue, fix: m.fix }))
      r.scopeCreep.forEach(s => out.nits.push('scope creep: ' + s))
    } else {
      if (r.verdict !== 'pass') r.blockers.forEach(b => out.blockers.push({ axis: a, file: b.file, issue: b.issue, fix: b.fix }))
      ;(r.nits || []).forEach(n => out.nits.push('sec: ' + n))
    }
  })
  return out
}

function fixPrompt(t, blockers) {
  return [
    COMMON, '',
    'TASK ' + t.id + ' FIX ROUND: independent reviewers found blockers in the earlier commit(s). Fix exactly these and nothing else, test-first for each (red then green), then commit as a NEW commit per repo with the message "' + t.id + ' review fixes", and push as described.',
    'HOLD: ' + t.repos.map(repoPath).join(', '),
    'GUIDE: ' + GUIDE + ' lines ' + t.guide[0] + '-' + t.guide[1],
    t.contract ? '\n' + t.contract : '',
    'BLOCKERS (JSON): ' + JSON.stringify(blockers),
  ].join('\n')
}

const T = (o) => o

const TASKS = [
  // ---- finished work: curated review findings are fixed first, then re-reviewed ----
  T({ id: 'BE-03R', title: 'Close public registration (SEC-01): fix review findings, then confirm', repos: ['gateway-service', 'back'], retro: [
      { repo: 'gateway-service', sha: '44e6a9db2a0a01a99e57a7794a8dc012650ff156' }, { repo: 'gateway-service', sha: '44bc86983551cfdbea90192e72e34446ef666ba4' }, { repo: 'back', sha: 'f5a4beefb3db336eb5b88939b3f8338495201390' }],
    axes: ['standards', 'spec', 'security'], alwaysReview: ['security'], critical: true, model: 'sonnet', effort: 'xhigh', guide: [998, 1008], why: 'security fix whose independent security review was cut off; standards/spec findings to fix',
    brief: 'carmonai.gateway.registration-open defaults false; POST /auth/register answered 403 registration_closed by the gateway before routing in every written form of the path (encoded, matrix); login/refresh/logout unchanged; harness compose sets the property true.',
    prior: [
      { axis: 'standards', file: 'back/docs (running.md near line 178, fact-sheet.md near lines 54-56)', issue: 'Docs still say POST /auth/register always answers 202 and the gateway filter tables do not list RegistrationFilter; the docs are now false for the default configuration.', fix: 'Find the lines with grep in /home/user/back/docs; state that registration is closed by default (403 registration_closed), that the harness compose sets CARMONAI_GATEWAY_REGISTRATIONOPEN=true, and add RegistrationFilter to the filter tables.' },
      { axis: 'standards', file: 'GatewayIT.java (trailingSlashFormsNeverReachTheAuthService)', issue: 'assertThat(status).isIn(401, 403, 404) accepts three outcomes so it passes whichever way the gateway refuses.', fix: 'Observe the real status for the trailing-slash form and pin it exactly.' },
      { axis: 'standards', file: 'RegistrationFilterTest.java (closedRegistrationIsRefusedBeforeTheChainRuns)', issue: 'startsWith on the serialized JSON prefix pins the serialization owned by OpenAiErrors.', fix: 'Parse the body as JSON and assert error.code equals registration_closed (and the status is 403).' },
    ] }),
  T({ id: 'BE-05R', title: 'Reject silently ignored parameters (API-02): fix review findings', repos: ['inference-service'], retro: [{ repo: 'inference-service', sha: '77e9d73ca1c050372a5be94644506d9441f94749' }],
    axes: ['standards', 'spec'], model: 'sonnet', effort: 'high', guide: [1022, 1031], why: 'standards/spec findings to fix; an interrupted attempt exists as a patch',
    brief: 'response_format json_object/json_schema, logprobs true, top_logprobs, logit_bias give 400 unsupported_parameter naming the field; text format and logprobs false accepted; user/metadata/store ignored. An interrupted earlier attempt at the fixes is saved as /home/user/back/.claude/handoff/wip/inference-service-BE-05R-interrupted-fix.patch (git apply it from /home/user/inference-service if it applies cleanly, then verify and finish; it was never run).',
    prior: [
      { axis: 'standards', file: 'ChatRequest.java, ChatRequestTest.java', issue: 'The literal word store appears in a main-code comment and in the test JSON, so the project checklist grep -ri store over the module hits.', fix: 'Reword the comment without that word and drop the store literal from the test; the field simply stays out of ALLOWED.' },
      { axis: 'standards', file: 'ChatRequestTest.java', issue: 'refusesParametersThatChangeTheAnswerAndWouldBeDropped bundles six cases in one test (first failure hides the rest) and another test asserts on the internal upstream().propertyNames().', fix: 'One parameterized case per rejected field, asserting the public outcome (ApiError code unsupported_parameter and the field named); assert the accepted case through the public result, not the internal map.' },
    ] }),
  T({ id: 'BE-18R', title: 'Production mail (ID-02, ID-04, ID-05): fix review findings', repos: ['account-service'], retro: [{ repo: 'account-service', sha: '95a279147e5e204db837d76101ed1f50ea2ae16e' }],
    axes: ['standards', 'spec'], model: 'sonnet', effort: 'high', guide: [1189, 1202], why: 'standards/spec findings to fix',
    brief: 'SMTP from env; prod startup guard refusing localhost/.local console URL or sender and missing SMTP user; Portuguese templates with accents plus one English line; at most 3 reset tokens per account per hour, 4th answers 202 with no mail.',
    prior: [
      { axis: 'standards', file: 'MailGuard / application-prod.yaml', issue: 'Prod requires STARTTLS but a blank SPRING_MAIL_PASSWORD starts fine and nothing sets mail.smtp.auth=true.', fix: 'The prod guard also fails startup on a blank spring.mail.password (message names the property, never a value); application-prod.yaml sets spring.mail.properties.mail.smtp.auth=true; tests for both.' },
      { axis: 'spec', file: 'AccountService.requestPasswordReset', issue: 'The throttle comment says issued since then, spent or not, but AccountTokens.use() deletes spent tokens so only unspent tokens count; and count-then-issue is not atomic so concurrent requests can exceed 3.', fix: 'Make the comment true; take a per-account lock (pg_advisory_xact_lock on the account id) around count and issue; add a concurrency test (N parallel requests give at most 3 tokens and the rest answer 202 without mail).' },
      { axis: 'spec', file: 'MailGuard', issue: 'The localhost/.local check is a broad substring match (a legitimate host such as localhost-free.example is refused).', fix: 'Compare the HOST part of the console URL and the sender domain: equals localhost, or ends with .local or .localhost; tests for both a refused and an accepted host.' },
      { axis: 'standards', file: 'AccountServiceIT.mailIsPortugueseWithAnEnglishLine', issue: 'Asserts the verbatim copy so any wording tweak fails it, and does not prove UTF-8 on the wire.', fix: 'Assert stable markers (Portuguese marker word, the link, the English tail marker) and that the accented subject is transmitted as UTF-8 (RFC 2047 encoded header).' },
    ] }),
  T({ id: 'BE-20aR', title: 'Cap organizations per account (ORG-03): fix review findings', repos: ['organization-service'], retro: [{ repo: 'organization-service', sha: 'b73d708a148ba279845fe6e7de05ebfd2459c02d' }],
    axes: ['standards', 'spec'], model: 'sonnet', effort: 'high', guide: [1217, 1227], why: 'spec findings to fix',
    brief: 'max-organizations-per-account default 3; 4th create is 409 organization_limit; closing one frees a slot.',
    prior: [
      { axis: 'spec', file: 'OrganizationServiceIT', issue: 'Every test runs at the default of 3, so a hard-coded 3 would pass; nothing proves the cap follows the property.', fix: 'Tests with the property set to 1 and to 5 (a second application context or a focused service-level seam).' },
      { axis: 'spec', file: 'OrganizationService / properties', issue: 'A zero or negative max-organizations-per-account is accepted silently.', fix: 'Fail startup with a message naming the property when the value is below 1; test it. Add a code comment recording that only owned, non-closed organizations count and members do not use a slot.' },
    ] }),
  T({ id: 'BE-06R', title: 'Typed and referenced credit (BIL-01): fix standards/spec findings', repos: ['billing', 'billing-service'], retro: [
      { repo: 'billing', sha: 'ab6d99a5c70e6712099c8bcd1c7aeadb9668f58f' }, { repo: 'billing-service', sha: '5f0f5167f6b1c137d8f926f118b99cf397ea7eb8' }],
    axes: ['standards', 'spec'], critical: true, model: 'sonnet', effort: 'xhigh', guide: [1033, 1043], why: 'security axis already passed; standards/spec findings to fix',
    brief: 'GrantIn gains type (grant default or top_up) and reference (at most 256 chars); ledger row carries them; idempotency key format grant:{org}:{key}; same key twice = one row; reconcile balanced; top-up clears no_credit within 1 s.',
    prior: [
      { axis: 'standards', file: 'BillingServiceIT', issue: 'Several tests verify through raw SQL on ledger_entry and through the Redis CreditFlags key scheme instead of a public interface.', fix: 'Assert through the billing HTTP API / Feign client (balance, flags) wherever an interface exists; keep SQL only for ledger-row facts the API does not expose; no assertions on the Redis key scheme.' },
      { axis: 'spec', file: 'BillingServiceIT / docs', issue: 'No test calls the reconcile entry point after a top-up (only repository.mismatches()), and the rule that the idempotency key is the Pix end-to-end id and reference holds the id plus an operator tag exists only in Java comments.', fix: 'Add a test that calls reconcile after a top-up and shows it balanced; document the idempotency-key and reference rule in the billing docs page under /home/user/back/docs (find the closest existing page; do not add nav entries).' },
    ] }),

  // ---- independent small tasks ----
  T({ id: 'BE-20c', title: 'Batch file retention property (BAT-01): reviews of the finished implementation', repos: ['batch-service'], partial: [{ repo: 'batch-service', sha: '02badfc93dc697ea823ae5fa1aa72673e2e75595' }], model: 'haiku', effort: 'high', guide: [1217, 1227], axes: ['standards', 'spec'], why: 'implemented and pushed by run 2; only the two reviews are missing',
    brief: 'Property carmonai.batch.file-retention (Duration, default 7 days) replaces the hard-coded file retention in the file expiry INSERTs and sweep; the value is bound into the SQL; log text uses it; with retention 1 minute the sweep deletes the file and its stored object.' }),

  // ---- gateway lane ----
  T({ id: 'BE-04a', title: 'Production key prefix (SEC-02), code', repos: ['auth-service', 'gateway-service'], needs: ['BE-03R'], model: 'sonnet', effort: 'high', critical: true, axes: ['standards', 'spec', 'security'], guide: [1010, 1020], why: 'security change spanning two services',
    brief: [
      '- auth-service: new property carmonai.keys.prefix (env CARMONAI_KEYS_PREFIX), default cmn_test_. The constant ApiKeys.PREFIX becomes the configured value; newly minted keys use it. The production value cmn_live_ goes in application-prod.yaml (activated by SPRING_PROFILES_ACTIVE=prod); create it if missing.',
      '- gateway-service: new property carmonai.gateway.key-prefixes (env CARMONAI_GATEWAY_KEYPREFIXES, comma list), default both cmn_test_ and cmn_live_; application-prod.yaml lists only cmn_live_. A well-formed key whose prefix is not allowed gets 401 invalid_api_key BEFORE any lookup: prove with a test that the auth-service client/stub is called 0 times.',
      '- Verify the key checksum covers the key body only, not the prefix. If it covers the prefix, STOP and report in deviations instead of changing the format.',
      '- Update tests asserting the old prefix so they pass; default stays cmn_test_. Add: a key minted under prefix cmn_live_ starts with cmn_live_, and the gateway refuses cmn_test_ when only cmn_live_ is allowed.',
    ].join('\n'),
    accept: 'New tests fail before and pass after; mvn -B -pl api/auth-service verify and api/gateway-service verify green.' }),
  T({ id: 'BE-04b', title: 'Document the cmn_live_ prefix and its two properties', repos: ['back'], needs: ['BE-04a'], model: 'haiku', effort: 'medium', axes: ['spec'], guide: [1010, 1020], why: 'docs-only, mechanical: smallest model',
    brief: [
      '- Docs only. In /home/user/back/docs (and docker/*.md if any) find places that describe the API key format cmn_test_... Add one short note each: production keys start cmn_live_; the test stack mints cmn_test_ unless CARMONAI_KEYS_PREFIX (auth-service) and CARMONAI_GATEWAY_KEYPREFIXES (gateway-service) are set. Check exact names and defaults in the BE-04a commits: git -C /home/user/auth-service log -1 -p ; git -C /home/user/gateway-service log -1 -p.',
      '- Do NOT edit docker/smoke.sh or any code. If docs have no such place, return not_applicable.',
    ].join('\n'),
    accept: 'git -C /home/user/back diff shows only small doc additions; committed and pushed.' }),
  T({ id: 'BE-23', title: 'Hide batch for launch (BAT-02)', repos: ['gateway-service', 'back'], after: ['BE-04b'], model: 'sonnet', effort: 'medium', axes: ['standards', 'spec'], guide: [1258, 1268], why: 'small config + filter + doc; routine',
    brief: [
      '- gateway-service: property carmonai.gateway.batch-enabled (env CARMONAI_GATEWAY_BATCHENABLED), default true. application-prod.yaml (create or extend) sets it false. When false, every request to /v1/files, /v1/files/** , /v1/batches, /v1/batches/** is answered with an OpenAI-shaped 404 with code not_found, before routing, after the API-key checks (an invalid key still gets 401, a valid key gets 404). Match paths with the same PathPattern semantics the registration filter uses so encoded forms cannot bypass it. Do not restate the route list in the prod profile.',
      '- harness: /home/user/back/docker/compose.yaml sets CARMONAI_GATEWAY_BATCHENABLED=true on the gateway with a one-line comment (smoke.sh batch section must keep passing on the harness).',
      '- docs: add /home/user/back/docs/operations/batch-reenable.md (check docs layout first; add to mkdocs.yml nav only if that nav lists the other operations pages) with the re-enable checklist from guide item 3.',
    ].join('\n'),
    accept: 'New tests fail before, pass after; mvn -B -pl api/gateway-service verify green.' }),
  T({ id: 'BE-11', title: 'Real client IP behind the proxy (SEC-03), plus Origin path-match hardening', repos: ['gateway-service'], after: ['BE-23'], model: 'sonnet', effort: 'high', critical: true, axes: ['standards', 'spec', 'security'], guide: [1094, 1105], why: 'security: trust model of a forwarded header needs judgement',
    brief: [
      '- Make rate limiting (RateLimitFilter) and the access log (AccessLogFilter client_ip) use the real client address from X-Forwarded-For when the request comes through the trusted proxy, via server.forward-headers-strategy: framework or Reactor Netty forwarded handling; the test decides which works. Record in the test which entry of a two-entry header is used.',
      '- Test (red first): 25 POST /auth/login from the same peer with X-Forwarded-For 203.0.113.9 hit 429 from about the 21st (burst 20, refill 1/s); right after, X-Forwarded-For 203.0.113.10 is not throttled; each access-log line carries its own client_ip.',
      '- Short code comment and a note in docs/operations (or closest page): the header is trusted from anyone who can reach the gateway, so the gateway must be reachable only from the reverse proxy and the proxy must overwrite X-Forwarded-For.',
      '- Also fix a finding from the BE-03 review: OriginFilter decides on the raw path string (Set.contains), so /auth/%6Cogin skips the Origin check. Use the same PathPattern/pathWithinApplication semantics as RegistrationFilter, with a red test first.',
      '- Optional source port: only if trivial, property carmonai.gateway.client-port-header (default empty = off) copied into a new access-log field client_port. Otherwise list in followUps.',
    ].join('\n'),
    accept: 'New tests fail before, pass after; mvn -B -pl api/gateway-service verify green.' }),
  T({ id: 'BE-12', title: 'OpenAI compatibility polish (API-03, API-04, API-05)', repos: ['inference-service', 'gateway-service'], needs: ['BE-05R'], after: ['BE-11'], model: 'sonnet', effort: 'high', axes: ['standards', 'spec'], guide: [1107, 1118], why: 'streaming usage semantics are subtle; two services',
    brief: [
      '- GET /v1/models/{id}: add the route in inference-service and in the gateway route list. 200 with the same object shape as an entry of GET /v1/models; unknown id gives 404 model_not_found. The created field comes from a catalog field in the model entry configuration (add it, non-zero and stable).',
      '- Streaming usage: keep asking the engine for continuous usage (billing needs it). When the CLIENT set stream_options.include_usage=true, forward exactly one final chunk with choices: [] and the usage object, and usage: null on all other chunks. Without the option forward no usage at all. Test: the single non-null usage equals the usage event written for that request.',
      '- max_tokens above the cap stays 400 invalid_max_tokens and the message states the cap value.',
      '- Reasoning: if the engine returns a reasoning field, return it as reasoning and also as reasoning_content, in the message and in stream deltas; its tokens stay billed as completion tokens.',
    ].join('\n'),
    accept: 'New tests fail before (models.retrieve is 404; every stream chunk carries usage) and pass after; mvn -B -pl api/inference-service verify and api/gateway-service verify green.' }),

  // ---- account lane ----
  T({ id: 'BE-08', title: 'Record terms and privacy acceptance (ID-01)', repos: ['account', 'account-service'], after: ['BE-18R'], model: 'sonnet', effort: 'high', axes: ['standards', 'spec'], guide: [1058, 1068], why: 'new append-only table plus library DTO; run 1 was blocked only because the library was not in HOLD',
    brief: [
      '- New Flyway migration creating accounts.terms_acceptance(account_id, document, version, accepted_at, channel): document is terms or privacy (CHECK), append-only with the same trigger pattern as the billing ledger (see /home/user/billing-service/src/main/resources/db/migration/V2026.10.03.001__create_tables.sql, refuse_change). COMMENT ON TABLE states purpose (evidence of acceptance), retention, and what erasure does. Default: the row holds only the account id, no name or email, and stays after erasure as evidence (assumption to confirm with the lawyer; say so in the comment).',
      '- Service method to record acceptance (both documents; missing/blank versions give 400), repository support. The export (GET /accounts/{id}/export; in this code the export method is near AccountService lines 130-147) must include the rows: add a termsAcceptances list to AccountExportOut in the account LIBRARY (you hold it; keep JSON backwards compatible; run mvn -B -q -pl api/account -DskipTests install after changing it).',
      '- UPDATE and DELETE on the table are refused (assert in an IT through the service seam). Erasure behaves exactly as the table comment says (assert it).',
      '- The provisioning endpoint is a LATER task (BE-10): deliver storage, service method, export and tests only.',
    ].join('\n'),
    accept: 'New tests fail before, pass after; mvn -B -pl api/account verify and api/account-service verify green.' }),
  T({ id: 'BE-10', title: 'Provision endpoint (ORG-02, server side)', repos: ['account', 'account-service'], needs: ['BE-08'], model: 'sonnet', effort: 'high', axes: ['standards', 'spec'], guide: [1083, 1092], why: 'new internal endpoint with identity and idempotency rules',
    brief: [
      '- POST /accounts/provision {name, email, termsVersion, privacyVersion, acceptedAt, channel} returns the account id. The account is created verified (email_verified_at set); NO mail is sent; terms and privacy acceptance rows are written via the BE-08 method; calling twice with the same email returns the same id and creates no second account.',
      '- No password in the request: the account gets an unusable random password hash (the customer sets a password later through the reset-password link). Never log the email. Add the Feign method and records to the account library.',
      '- Internal only: confirm by READING /home/user/gateway-service/src/main/resources/application.yaml (do not edit it) that no gateway route matches /accounts/provision, and say so. The shared-secret guard is a later task (BE-24c); do not add one.',
    ].join('\n'),
    accept: 'New tests fail before, pass after (incl. no mail in Mailpit and idempotent second call); mvn -B -pl api/account verify and api/account-service verify green.' }),
  T({ id: 'BE-20b', title: 'Delete stale unverified accounts and expired tokens (RET-01)', repos: ['account-service'], needs: ['BE-10'], model: 'sonnet', effort: 'medium', axes: ['standards', 'spec'], guide: [1217, 1227], why: 'scheduled job with a clock-injection test; routine',
    brief: [
      '- Daily job: delete accounts never verified after 7 days (property for the days, default 7) and expired account_token rows. Provisioned accounts are verified at creation, so they are safe. Use the time source the code already uses, or inject a Clock so the test controls time.',
      '- Test (red first): an 8-day-old unverified account disappears together with its tokens; a verified account of the same age stays; a fresh unverified account stays.',
    ].join('\n'),
    accept: 'New test fails before, passes after; mvn -B -pl api/account-service verify green.' }),

  // ---- billing / org lane ----
  T({ id: 'BE-06b', title: 'Billing hardening from the BE-06 review', repos: ['billing', 'billing-service'], needs: ['BE-06R'], model: 'sonnet', effort: 'xhigh', critical: true, axes: ['standards', 'spec', 'security'], guide: [1033, 1043], why: 'money path follow-ups found by the independent reviewer',
    brief: [
      '- type top_up REQUIRES a non-blank reference (400 otherwise, fixed text); type grant keeps reference optional. Reason: otherwise free-text reason, which may hold a payer name, lands in the append-only ledger.',
      '- A replay of an idempotency key whose amount, type or reference DIFFERS from the stored row returns 409 with code idempotency_conflict and writes nothing; an identical replay still returns 200 with the same balance.',
      '- organizationId must match [A-Za-z0-9-]{1,36} (no colon) so the key grant:{org}:{key} cannot collide across organizations; 400 otherwise.',
      '- BillingResource exception handler must return fixed text per exception type, never getMessage().',
      '- Scope the order-dependent IT billsEachSealedWindowOnceAndFlagsOrganizationsOutOfCredit so its global mismatches() assertion only covers its own organizations.',
      '- reference must match ^[A-Za-z0-9._:|-]{1,256}$ for every type (no spaces or accents, so a person\'s name cannot be written into the append-only ledger); 400 otherwise. reason becomes optional (max 200 characters) when a reference is present.',
      '- Each rule: red test first through the billing-service HTTP API (Feign client) seam.',
    ].join('\n'),
    accept: 'New tests fail before, pass after; mvn -B -pl api/billing verify and api/billing-service verify green.' }),
  T({ id: 'BE-07', title: 'Tier and suspend with immediate cache eviction (ORG-01)', repos: ['organization-service', 'organization', 'auth-service', 'auth', 'gateway-service'], needs: ['BE-04a'], after: ['BE-20aR', 'BE-12'], model: 'sonnet', effort: 'max', critical: true, secEffort: 'max', axes: ['standards', 'spec', 'security'], guide: [1045, 1056], why: 'cross-service control, five repos, cache layers: biggest model and effort',
    brief: [
      '- organization-service (+ organization library): internal-only PUT /organizations/{id}/admin with body {tier?, status?}. tier in trial|standard|enterprise; status only active or suspended (never closed); unknown organization 404; closed organization 409. Add NO gateway route for it.',
      '- After the change, organization-service calls a NEW internal auth-service endpoint (Feign method in the auth library, implemented in auth-service) that deletes the cached apikey:{hash} entry of EVERY key of that organization. Evict before and after the commit (same pattern the existing key revoke uses; read it). If the eviction call fails, return an error and log only the organization id.',
      '- Effect within 1 s: after tier=standard the next /v1 request shows the standard rate-limit headers; after status=suspended the next /v1 request is 403 organization_not_active; active restores it. Find every cache layer holding tier/status (auth-service Valkey entry, any gateway in-memory cache) and make the eviction cover each; say how.',
      '- Gateway test (read its test style): with a valid customer JWT, PUT /organizations/{id}/admin through the public route returns 404 (the public route list allows only GET, POST, DELETE for /organizations); without a token the gateway answers 401 first. Write both numbers into the test.',
      '- Tests first (red): ITs in OrganizationServiceIT/AuthServiceIT for the behaviour above, the gateway test, unit tests for validation.',
    ].join('\n'),
    accept: 'New tests fail before, pass after; mvn -B -pl api/organization, api/organization-service, api/auth, api/auth-service, api/gateway-service all green.' }),
  T({ id: 'BE-09', title: 'Block unfunded organizations (BIL-02)', repos: ['billing-service', 'billing', 'organization-service', 'organization'], needs: ['BE-06b', 'BE-07'], model: 'sonnet', effort: 'max', critical: true, secEffort: 'max', axes: ['standards', 'spec', 'security'], guide: [1070, 1081], why: 'money: default-deny for unfunded organizations across two services',
    brief: [
      '- billing-service: new internal, idempotent POST /billing/organizations/{id}/open (Feign method in the billing library): insert a zero balance row (ON CONFLICT DO NOTHING) and sync the credit flag so a zero balance sets no_credit; calling it twice leaves one row. Then the first /v1 request of an organization with no grant returns 402 insufficient_balance (verify the flag path the gateway already uses, read ApiKeyAuthenticationManager/CreditFlags; the gateway needs no change unless it does not treat the flag as designed). After a grant the same key works.',
      '- organization-service: call open on organization creation (best effort with a short retry, never failing the creation; log only the organization id).',
      '- Reconcile: extend billing-service reconcile so it also opens every organization it can list. Add a PAGED, internal-only list call in organization-service (+ organization library) with a maximum page size and use it from billing-service; keep the dependency direction acyclic at module level (libraries carry only Feign interfaces and records).',
      '- The provisioning flow call from the guide belongs to the operator scripts (SELL-02) and is out of scope. The shared-secret guard comes later (BE-24); do not add it.',
      '- Red-first tests at the seams: billing-service IT (open twice = one row; zero balance sets the flag; grant clears it), organization-service IT (creation calls open through its Feign client against a stub HTTP server; creation still succeeds when open fails), reconcile test.',
    ].join('\n'),
    accept: 'New tests fail before, pass after; mvn -B -pl api/billing, api/billing-service, api/organization, api/organization-service all green.' }),

  // ---- BE-24: internal shared secret, split per service ----
  T({ id: 'BE-24a', title: 'Internal token guard: billing-service', repos: ['billing-service', 'billing'], needs: ['BE-09'], model: 'sonnet', effort: 'xhigh', axes: ['standards', 'spec'], guide: [1270, 1281], contract: INTERNAL_CONTRACT, why: 'security change with a fixed contract; per-service slice',
    brief: [
      '- Guard in billing-service: POST /billing/grants and POST /billing/organizations/{id}/open, plus every other internal WRITE endpoint of this service you find (list them in the result). POST /billing/adjustments will be guarded by BE-25 using the same filter: build the guard so adding a path is one line.',
      '- Red-first tests per protected call: no token and a wrong token give 401 and change nothing (balance, flag); the right token works. Existing ITs now send the token (temp file).',
    ].join('\n'),
    accept: 'New tests fail before, pass after; mvn -B -pl api/billing-service verify green.' }),
  T({ id: 'BE-24b', title: 'Internal token guard: organization-service', repos: ['organization-service', 'organization'], needs: ['BE-09'], after: ['BE-24a'], model: 'sonnet', effort: 'xhigh', axes: ['standards', 'spec'], guide: [1270, 1281], contract: INTERNAL_CONTRACT, why: 'security change with a fixed contract; per-service slice',
    brief: [
      '- Guard in organization-service: PUT /organizations/{id}/admin, the new internal organization list call (BE-09), and the internal cross-service writes the guide names (removeMember, closeSessions-like erasure/membership writes) that no gateway route reaches. Verify each against the gateway route list before guarding.',
      '- Outgoing: add the Feign interceptor so organization-service attaches the token on its calls to billing (open) and auth (key-cache eviction).',
      '- Red-first tests: 401 without or with a wrong token and nothing changes (tier, status); right token works; the outgoing calls carry the header (assert at the HTTP boundary with a stub server).',
    ].join('\n'),
    accept: 'New tests fail before, pass after; mvn -B -pl api/organization-service verify green.' }),
  T({ id: 'BE-24c', title: 'Internal token guard: account-service', repos: ['account-service', 'account'], needs: ['BE-10', 'BE-20b'], after: ['BE-24b'], model: 'sonnet', effort: 'xhigh', axes: ['standards', 'spec'], guide: [1270, 1281], contract: INTERNAL_CONTRACT, why: 'security change with a fixed contract; per-service slice',
    brief: [
      '- Guard in account-service: POST /accounts/provision and GET /accounts/lookup (verify it exists and that no gateway route or gateway call uses it), plus other internal-only account writes you find. Do not guard anything the gateway or auth-service login path calls without the secret: read how auth-service calls account-service and, if it needs one of these, make auth-service the second holder of the secret (list it in followUps for BE-24d).',
      '- Outgoing: Feign interceptor on account-service calls to guarded endpoints of other services (erasure paths).',
      '- Red-first tests: 401 without or with a wrong token and no account is created; the right token works; outgoing header asserted at the HTTP boundary.',
    ].join('\n'),
    accept: 'New tests fail before, pass after; mvn -B -pl api/account-service verify green.' }),
  T({ id: 'BE-24d', title: 'Internal token guard: auth-service', repos: ['auth-service', 'auth'], needs: ['BE-07'], after: ['BE-24c'], model: 'sonnet', effort: 'xhigh', axes: ['standards', 'spec'], guide: [1270, 1281], contract: INTERNAL_CONTRACT, why: 'security change with a fixed contract; per-service slice',
    brief: [
      '- Guard in auth-service: the key-cache eviction endpoint added in BE-07, closeSessions and any other internal-only write you find. NOT the endpoints the gateway calls (key lookup / whoami / login path): verify against the gateway code.',
      '- Outgoing: Feign interceptor for calls auth-service makes to guarded endpoints (for example to account-service lookup, if guarded in BE-24c: read its commit).',
      '- Red-first tests: 401 without or with a wrong token and the cache entry is NOT evicted; right token evicts; existing ITs send the token.',
    ].join('\n'),
    accept: 'New tests fail before, pass after; mvn -B -pl api/auth-service verify green.' }),
  T({ id: 'BE-24e', title: 'Internal token: compose secret, dev generator, CI, scripts', repos: ['back'], needs: ['BE-24a', 'BE-24b', 'BE-24c', 'BE-24d'], model: 'sonnet', effort: 'high', axes: ['standards', 'spec'], guide: [1270, 1281], contract: INTERNAL_CONTRACT, why: 'compose/CI/scripts wiring; cannot run the full stack here',
    brief: [
      '- /home/user/back/docker/compose.yaml: a top-level secret internal_token (file ./secrets/internal_token), mounted at /run/secrets/internal_token ONLY into billing-service, organization-service, account-service and auth-service; the gateway service must NOT mount it. Add docker/secrets/ to .gitignore (no secret ever committed).',
      '- docker/gen-dev-secrets.sh: creates docker/secrets/internal_token with one line "X-Internal-Token: <openssl rand -hex 32>" (mode 400), refuses to overwrite an existing file; LF line endings, set -euo pipefail. Call it from .github/workflows/ci.yaml before compose up, and mention it in the docker docs.',
      '- smoke.sh, bench.sh, batch-bench.sh (and any script that calls billing grants or other guarded endpoints directly): send the token with curl -H @docker/secrets/internal_token (value never on a command line).',
      '- Verify only what can be verified here: bash -n on each script, docker compose -f docker/compose.yaml config (no pull), and a grep proving the gateway has no secret mount. The full stack cannot run here; say so in notRun.',
    ].join('\n'),
    accept: 'bash -n clean, compose config valid, gateway has no secret mount, committed and pushed.' }),
  T({ id: 'BE-24R', title: 'Internal shared secret (SEC-04): cross-service security review', repos: ['billing-service', 'billing', 'organization-service', 'organization', 'account-service', 'account', 'auth-service', 'auth', 'back'], needsAll: ['BE-24a', 'BE-24b', 'BE-24c', 'BE-24d', 'BE-24e'], aggregate: ['BE-24a', 'BE-24b', 'BE-24c', 'BE-24d', 'BE-24e'], axes: ['security'], critical: true, secEffort: 'max', maxFix: 2, model: 'sonnet', effort: 'xhigh', guide: [1270, 1281], contract: INTERNAL_CONTRACT, why: 'one reviewer over all five slices: the contract must hold end to end',
    brief: 'The five slices together: every listed internal call refuses a missing or wrong token; the gateway can never reach a guarded endpoint with the secret; constant-time compare; no secret in logs/errors; startup fails closed; callers attach the token; nothing the gateway calls was guarded by mistake; compose mounts the secret only where needed.' }),
  T({ id: 'BE-25', title: 'Adjustments and refunds endpoint (BIL-05)', repos: ['billing', 'billing-service', 'back'], needs: ['BE-24R'], model: 'sonnet', effort: 'xhigh', critical: true, secEffort: 'xhigh', axes: ['standards', 'spec', 'security'], guide: [1283, 1293], contract: INTERNAL_CONTRACT, why: 'money correction path, signed ledger entries',
    brief: [
      '- POST /billing/adjustments {organizationId, amountMicroBrl (signed, not 0), type (adjustment or refund), reference, idempotencyKey}, guarded by the BE-24a internal-token filter (add the path), writes ONE ledger row of that type and changes the balance once in the same transaction; reconcile stays balanced; the same idempotency key returns the same balance with no second row (a replay with different content is 409 idempotency_conflict, like BE-06b); an entry that would make the balance negative is refused with 409 unless the request carries allowNegative: true; reference at most 256 characters and never a payer name. Feign method in the billing library.',
      '- Write /home/user/back/docs/runbooks/refund.md: ledger entry first (curl against the guarded endpoint using -H @token file, no value on a command line), then the Pix return from the PJ bank app, then the NFS-e cancellation or credit as the accountant says, then a line in the receipt log. Keep it short and operator-friendly; do not add it to the public mkdocs nav.',
      '- Red-first tests through the billing-service HTTP API seam.',
    ].join('\n'),
    accept: 'New tests fail before, pass after; mvn -B -pl api/billing and api/billing-service verify green; runbook committed in back.' }),
]

const jobs = {}
for (const t of TASKS) {
  jobs[t.id] = (async () => {
    try {
      const needs = await Promise.all([...(t.needs || []), ...(t.needsAll || [])].map(i => jobs[i]))
      await Promise.all((t.after || []).map(i => jobs[i]))
      const bad = needs.find(r => !r || r.status !== 'done')
      if (bad) return { id: t.id, status: 'skipped', summary: 'needs ' + (bad ? bad.id : '?') + ' which did not finish done' }
      const names = [...t.repos].sort()
      const releases = []
      for (const n of names) releases.push(await mu(n).acquire())
      try {
        log(t.id + ' -> ' + t.model + '/' + t.effort + ' [' + (t.axes || []).join('+') + '] (' + t.why + ')  holds: ' + names.join(','))
        let commits
        let impl = null
        if (t.retro) {
          commits = t.retro
        } else if (t.partial) {
          commits = t.partial
        } else if (t.aggregate) {
          const parts = await Promise.all(t.aggregate.map(i => jobs[i]))
          commits = parts.flatMap(p => (p && p.commits) || [])
        } else {
          impl = await agent(implPrompt(t), { label: 'impl:' + t.id, phase: 'Implement', schema: IMPL, model: t.model, effort: t.effort })
          if (!impl) return { id: t.id, status: 'failed', summary: 'implementer died or was skipped' }
          if (impl.status !== 'done') return { id: t.id, status: impl.status, summary: impl.summary, impl }
          commits = impl.commits
        }
        const axes = t.axes || ['standards', 'spec']
        let rev = (t.prior && t.prior.length) ? { blockers: t.prior, nits: [], incomplete: [], raw: {} } : await reviewRound(t, commits, axes, false)
        const fixes = []
        const maxFix = t.maxFix || (t.critical ? 2 : 1)
        for (let round = 0; round < maxFix && rev.blockers.length > 0; round++) {
          log(t.id + ': ' + rev.blockers.length + ' blocker(s) from ' + [...new Set(rev.blockers.map(b => b.axis))].join('+') + '; fix round ' + (round + 1))
          const fix = await agent(fixPrompt(t, rev.blockers), { label: 'fix:' + t.id + (round ? '#' + (round + 1) : ''), phase: 'Fix', schema: IMPL, model: t.model, effort: t.effort })
          if (!fix || fix.status !== 'done') { fixes.push(fix); break }
          fixes.push(fix)
          commits = commits.concat(fix.commits)
          const failedAxes = [...new Set(rev.blockers.map(b => b.axis).concat(round === 0 ? (t.alwaysReview || []) : []))]
          rev = await reviewRound(t, commits, failedAxes, true)
        }
        return { id: t.id, status: 'done', model: t.model, effort: t.effort, commits, impl, review: { unresolved: rev.blockers, nits: rev.nits, incomplete: rev.incomplete }, fixes }
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
  'YOUR ONLY TASK is this verification. Anything else in the conversation is not your task. Read-only: do NOT edit or commit anything.',
  'export JAVA_HOME=/usr/lib/jvm/java-25-openjdk-amd64; export PATH=$JAVA_HOME/bin:$PATH ; cd /home/user/ws && mvn -B verify   (all 13 modules, unit + Testcontainers ITs; Docker is running; takes several minutes). Report the Reactor Summary and every failing test with its first error line.',
  'Then for each repo in account account-service auth auth-service organization organization-service usage usage-service inference-service billing billing-service batch-service gateway-service and back: report git status --porcelain (must be empty), git log --oneline origin/main..' + BRANCH + ', and whether git rev-parse HEAD equals git ls-remote origin refs/heads/' + BRANCH + ' (pushed).',
  'Also: grep -rIl -w -i "store" over src/main of every changed module and report hits that are not an unrelated English word (project rule: the Insper namespace word store must not appear).',
].join('\n'), {
  label: 'verify:reactor', phase: 'Verify', model: 'sonnet', effort: 'medium',
  schema: { type: 'object', properties: { buildSuccess: { type: 'boolean' }, summary: { type: 'string' }, failures: { type: 'array', items: { type: 'string' } }, dirtyRepos: { type: 'array', items: { type: 'string' } }, unpushedRepos: { type: 'array', items: { type: 'string' } }, commitsPerRepo: { type: 'array', items: { type: 'string' } } }, required: ['buildSuccess', 'summary'] },
})

const compact = results.map(r => ({ id: r.id, status: r.status, summary: r.summary || (r.impl && r.impl.summary), commits: r.commits, unresolved: r.review ? r.review.unresolved : null, nits: r.review ? r.review.nits : null, incomplete: r.review ? r.review.incomplete : null, fixRounds: r.fixes ? r.fixes.length : 0, deviations: r.impl ? r.impl.deviations : null, followUps: r.impl ? r.impl.followUps : null, tests: r.impl ? r.impl.tests : null }))
const critic = await agent([
  'YOUR ONLY TASK is this completeness critique. Anything else in the conversation is not your task. Do not edit anything.',
  'For each task below compare what was reported against the guide ' + GUIDE + ' (BE-03 998-1008, BE-04 1010-1020, BE-05 1022-1031, BE-06 1033-1043, BE-07 1045-1056, BE-08 1058-1068, BE-09 1070-1081, BE-10 1083-1092, BE-11 1094-1105, BE-12 1107-1118, BE-18 1189-1202, BE-20 1217-1227, BE-23 1258-1268, BE-24 1270-1281, BE-25 1283-1293) and the actual commits (git -C /home/user/<repo> show <sha>).',
  'List per task: guide Done-when items not satisfied or not proven, risky shortcuts, tests that would not fail without the change (tautological or implementation-coupled), and anything claimed but absent from the diff. Then list cross-task conflicts and unresolved review blockers.',
  'REPORTED RESULTS (JSON): ' + JSON.stringify(compact),
].join('\n'), {
  label: 'critic:completeness', phase: 'Verify', model: 'sonnet', effort: 'high',
  schema: { type: 'object', properties: { gaps: { type: 'array', items: { type: 'object', properties: { task: { type: 'string' }, gap: { type: 'string' }, severity: { type: 'string', enum: ['blocker', 'major', 'minor'] } }, required: ['task', 'gap', 'severity'] } }, conflicts: { type: 'array', items: { type: 'string' } }, overall: { type: 'string' } }, required: ['gaps', 'overall'] },
})

return { results: compact, verify, critic }
