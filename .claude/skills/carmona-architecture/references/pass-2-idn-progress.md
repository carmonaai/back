# Pass 2, identity chain (idn) progress

Owned modules: account, account-service, auth, auth-service, organization, organization-service. Plan: `work/pass-2/PLAN.md`; brief: `work/tasks/P2-idn.md`.

## N0 - key cache eviction after commit (D14), 2026-10-08

`ApiKeyService.rotate` is one transaction (revoke, then create) and `revoke` used to delete the gateway's `apikey:{sha256}` Valkey entry in-process, before the commit. A gateway lookup that still read the old key as live (the revoke not yet committed, READ COMMITTED) could cache it right after that early delete, and the entry then stayed until the gateway TTL while the key was already revoked. `revoke` is now `@Transactional` and registers a `TransactionSynchronization.afterCommit` that deletes the entry: inside `rotate` it joins rotate's transaction, called alone it has its own. A rollback never reaches `afterCommit`, so the still-live key stays cached.

- Test: `AuthServiceIT.aLookupBetweenTheRevokeAndTheCommitDoesNotLeaveTheOldKeyCached`. The organization stub (which `create()` calls inside the transaction, after the revoke) runs a hook that performs a real `findApiKey` (200, the revoke is uncommitted) and caches the entry; after the rotate the entry must be gone. Fails on the old code, passes on the new (outcomes in the report).
- Residual window, unchanged and bounded: a lookup that read before the commit and writes its cache entry after the `afterCommit` delete survives until the gateway's cache TTL. Closing it fully needs the gateway to write the entry only if the key is still live (compare-and-set), which is a gateway change outside this chain.
- Valkey failure (review fix): `revoke` deletes the entry twice. The first delete runs before the commit and is not guarded: a Valkey failure (1 s timeout) rolls the whole transaction back, so rotate/revoke fail closed (500, old key still live, no new key, no orphan). The second delete runs in `afterCommit`; its `RuntimeException` is caught and logged as a warning with the key id and exception class only (no hash, no message), because by then the revoke and the new key are committed and the new secret exists only in the response; a stale entry is then bounded by the gateway's 60 s TTL. Tests: `aValkeyFailureAfterTheCommitStillHandsOverTheNewKey`, `aValkeyFailureBeforeTheCommitRollsTheRotationBack`.

### New stores of personal data

None. The cache entry is keyed by the key's SHA-256 and holds ids only; it already expires by TTL and is deleted on revoke.

### Deviations

None.

### Architecture paragraph (draft, for `inference-plan.md`)

**Pass 2 N0 built 2026-10-08** (log: [pass-2-idn-progress.md](pass-2-idn-progress.md)): API-key revocation evicts the gateway's Valkey cache entry after the database commit (`afterCommit`), so a key rotation can no longer leave the old key cached by a lookup that raced the transaction. Valkey is deleted before the commit as well (fail closed) and a failure after the commit is logged, not thrown. Not deviations: the residual window of a lookup that read before the commit and caches after the eviction is still bounded by the gateway's cache TTL.

## N1a - Role enum and specific exceptions, 2026-10-08

Roles stay `owner`, `admin`, `member` (`member` is read-only). `Role` is an enum in the `organization` library, a value type with two predicates and nothing else; `MemberOut`, `OrganizationOut`, the organization-service domain (`Member`, `Organization`) and its model (`MembershipModel`, `@Enumerated(STRING)`) use it, and auth-service asks it. `ApiKeyService.MANAGERS` and `OrganizationService.OWNER` are gone; `grep -rn -E 'MANAGERS|OWNER\b|"owner"|"admin"|"member"'` over the main sources of the six modules finds nothing. No migration: the `membership.role` CHECK already holds exactly these three words.

### The authorization table (every row that exists today)

| Action | owner | admin | member | not a member | Decided by | Enforced in | Test |
|---|---|---|---|---|---|---|---|
| create, rotate, revoke an API key | yes | yes | 403 `manager_required` | 404 | `Role.managesKeys()` | `ApiKeyService.requireManager` (auth-service) | `AuthServiceIT.theKeyRowsOfTheAuthorizationTable` (4 rows), `aMemberWhoIsRefusedGetsTheManagerRequiredCode`, `RoleTest.theAuthorizationTable` |
| read (list) API keys | yes | yes | yes | 404 | membership only | `ApiKeyService.findAll` | same matrix, column `list` |
| read usage, read balance | yes | yes | yes | 404 | membership only | usage-service and billing-service call `GET /organizations/{id}/members/{account}` and ignore the role (not owned by this chain) | `OrganizationServiceIT.everyRoleIsAMemberThatReadsAndTheLookupReportsItsRole` covers the lookup they call, for every role |
| read the organization, list mine | yes | yes | yes | 404 | membership only | `OrganizationService.findById`, `findMine` | same test |
| close the organization | yes | 403 `owner_required` | 403 `owner_required` | 404 | `Role.closesOrganization()` | `OrganizationService.close` | `OrganizationServiceIT.closingTakesAnOwner` (3 rows), `aStrangerCannotCloseAndLearnsNothing` |
| erase an account that is the only owner of an open organization | - | - | - | - | last-owner rule | `OrganizationService.removeMember` | `erasureNeverLeavesAnOpenOrganizationWithoutAnOwner` (409 `last_owner`) |

Member management and role change (the first two rows of the original N1 list) do not exist yet; they arrive with N1b and add their own predicates to `Role`. A role is read from organization-service on every call (membership lookup, no cache), never from the request.

### Decisions

- The constants of `Role` are lowercase (`owner`, not `OWNER`). `name()` is then the JSON word, the column value and the word the console already sees, so the library needs no Jackson dependency (module rule: openfeign and lombok only), the column needs no converter, and the wire does not change for services not rebuilt yet. `RoleTest.theWireStaysLowercaseAndRefusesUnknownWords` pins it (and refuses `god` and `OWNER`).
- An unknown role word coming from organization-service fails to decode in the caller; auth-service answers 503 and writes nothing (`anUnknownRoleGetsNothing`). Fail closed.
- `OrganizationOut.role` is a `Role` too, so one concept has one type; the account export keeps its own `String` (`role().name()`), so the export's wire is unchanged and the `account` library does not depend on `organization`.
- Specific exceptions are nested in the service that throws them (the house pattern of `AccountService.EmailNotVerifiedException`), with a fixed message and no stack trace. The Resource maps each to one status and a stable `code` property in the `ProblemDetail`; the generic `SecurityException` -> 403 and `IllegalStateException` -> 409 handlers are deleted, so a stray `IllegalStateException` is a 500 now, not a 409 with a borrowed text.

| Exception | Service | Status | `code` |
|---|---|---|---|
| `OwnerRequiredException` | organization | 403 | `owner_required` |
| `LastOwnerException` | organization | 409 | `last_owner` |
| `ManagerRequiredException` | auth | 403 | `manager_required` |
| `OrganizationNotActiveException` | auth | 409 | `organization_not_active` |
| `KeyLimitException` | auth | 409 | `key_limit_reached` |

auth-service and account-service pass a downstream 4xx body through unchanged (`AuthResource.downstream`, `AccountResource.downstream`), so a client of the gateway should see the same `code`, for example account erasure answering 409 `last_owner`; read in the code, no test here crosses the two services with a body.

### Checks

Mutation checks (the code was changed, the tests run, the tree restored with `git checkout -- .`): `managesKeys()` returning true kills `RoleTest` (member) and the auth matrix (member creates); `closesOrganization()` returning true for admin kills `RoleTest` (admin) and `closingTakesAnOwner` (admin); the key cap raised to 1000 kills `theFiftiethLiveKeyIsTheLastOne`; the `last_owner` code renamed kills the erasure IT; `findAll` without the membership lookup kills `anUnknownRoleGetsNothing`; `revoke` without `requireManager` kills the matrix (member and not-a-member revoke); `close` without the role check kills `closingTakesAnOwner` (admin and member).

### New stores of personal data

None. A role is an organization attribute of an account id; erasure (`DELETE /accounts/{id}` -> `removeMember`) and export (`GET /accounts/{id}/export`, `role` per organization) behave as before.

### Deviations

None.

### Architecture paragraph (draft, for `inference-plan.md`)

**Pass 2 N1a built 2026-10-08** (log: [pass-2-idn-progress.md](pass-2-idn-progress.md)): the roles of an organization are one closed set, `owner`/`admin`/`member`, as the `Role` enum in the `organization` library (a value type whose predicates `managesKeys()` and `closesOrganization()` are the authorization table; its lowercase constants are the wire and column words, so nothing on the wire changed). auth-service and organization-service ask the role instead of keeping role names, and the generic exception-to-status mappings are replaced by specific exceptions with a stable `code` in the problem body (`owner_required`, `last_owner`, `manager_required`, `organization_not_active`, `key_limit_reached`). Not deviations: usage and balance stay readable by any member through the membership lookup of usage-service and billing-service, which ignore the role; member management and role changes come with N1b.

## N1b - member management in organization-service, 2026-10-08

organization-service gets the member API: list, add an existing account by email, change a role, remove or leave. Resource -> Service -> Repository as everywhere else: `OrganizationResource` implements the new methods of the `OrganizationController` Feign interface (library `organization`), `OrganizationService` decides, `MembershipRepository`/`MembershipModel` store. The roles stay `owner`/`admin`/`member`; the library `Role` gained two predicates, `managesMembers()` (owner, admin) and `managesOwners()` (owner), and `RoleTest` pins them. No migration: `membership(organization_id, account_id)` is already the primary key (it serves the paged list) and its `role` CHECK already holds the closed set, so `V2026.10.08.001` is left for N2.

### The endpoints (all on `OrganizationController`; `id-account` is the caller, set by the gateway)

| Call | Who | Result |
|---|---|---|
| `GET /organizations/{id}/members?page&size` | any member | 200 `MemberOut` list (account id and role, never an email), ordered by account id, `size` capped at 100, `page < 0` or `size < 1` is 400; non-member 404 |
| `POST /organizations/{id}/members` `{email, role}` | owner, admin | 201 `MemberOut` + `Location`; role left out = `member`; `owner` only from an owner (403 `owner_required`); plain member 403 `manager_required`; non-member 404; an email nobody has verified: plain 404; already a member 409 `already_member`; organization not `active` 409 `organization_not_active`; blank or longer than 256: 400; account-service failing: 503 |
| `PUT /organizations/{id}/members/{idMember}` `{role}` | owner, admin | 200 `MemberOut` (the same role again is a 200 that changes nothing); granting `owner` or touching an owner needs an owner (403 `owner_required`); demoting the only owner 409 `last_owner`; closed organization 409 `organization_not_active`; member caller 403 `manager_required`; non-member caller or target 404 |
| `DELETE /organizations/{id}/members/{idMember}` | owner, admin; anyone for themselves | 204; removing an owner needs an owner (403 `owner_required`); the only owner of an organization that is not closed cannot go (409 `last_owner`), leaving included; a plain member removing someone else 403 `manager_required` before anything about the target is looked up; non-member caller or target 404 |

`GET /organizations/{id}/members/{idAccount}` (the internal role lookup of auth, usage and billing) is unchanged. The erasure `DELETE /organizations/members/{idAccount}` is unchanged except that its 409 now shares one `LastOwnerException` text with the new paths.

### How the rules are enforced

- One place: `OrganizationService`. `requireManager` (role from the membership, 404 if none, 403 `manager_required`), `requireOwner` (`Role.managesOwners()`), `requireAnotherOwner` (owners counted after the lock). The caller is the `id-account` header; the body carries no caller and no role of the caller.
- No self-promotion needs no rule of its own, it falls out of the two predicates: a plain member cannot manage, an admin cannot grant `owner`. `noOneRaisesTheirOwnRole` pins it (admin to owner 403, member to admin 403).
- Last owner: every path takes `OrganizationRepository.lockById` (`SELECT ... FOR UPDATE`, the lock the erasure already used) before it counts owners and reads the caller role, so two owners leaving or demoting each other at once cannot both pass; the second reads the committed state. Closing keeps every membership (it is an owner-only status change); once the organization is `closed` the last owner may leave or be erased, as before. A suspended organization still protects its last owner.
- The email lookup (`POST /accounts/lookup`, a new internal endpoint in account-service and its library, answering the id of a VERIFIED email, or 404 for any other case, byte for byte) is a network call, so `addMember` runs it outside the transaction: the rights of the caller are checked first (a caller who may not add never reaches the lookup and cannot learn which emails have accounts), then the lookup, then a `TransactionTemplate` transaction that takes the lock and checks the rights again. No row lock and no pool connection is held while account-service answers (a slow account-service could otherwise drain the 10-connection pool that the membership lookups of other services also use).
- organization-service now calls account-service through `AccountController` (Feign, 1 s connect, 3 s read, Resilience4j breaker 50 % over 20 calls, 30 s open, 3 half-open probes, 4xx ignored by the breaker, a bulkhead of 25). No retry: the lookup is a POST and an admin simply repeats the call. A Feign 404 becomes the plain 404 of the Resource; everything else is a 503 and only the exception class is logged.
- `/accounts/lookup` is a POST so the email travels in a body, not in a URL that access logs keep; the gateway route for accounts is `GET,DELETE` on `/accounts/{id}`, so the endpoint is unreachable from outside.

### Tests

organization-service `OrganizationServiceIT` (62 tests, through the library Feign client), `RoleTest` (4); account-service `AccountServiceIT.lookupFindsOnlyAVerifiedEmailAndTheMissesLookAlike`.

An IT per rule, every expected outcome written out, not derived from `Role`: `addingByEmailMakesAMemberAndNothingElse` (9 rows: only `member` is accepted, admin and owner are 400, a plain member 403 first), `addingByEmailReturnsTheMemberAndDefaultsToTheLeastPrivilege`, `anUnknownEmailIs404AndACallerWhoMayNotAddNeverReachesTheLookup` (counts the calls of the stub), `addingAnExistingMemberOrToAClosedOrganizationIs409`, `badInputAndAFailingAccountServiceAreRefusedWithoutWriting` (incl. raw JSON with the role `god`), `membersArePagedInAStableOrderWithAMaximumAndOnlyMembersSeeThem` (105 members, pages of 40, size 100000 capped), `changingARoleTakesAManagerAndOnlyAnOwnerTouchesOwners` (15 rows), `noOneRaisesTheirOwnRole` (5), `changingARoleOfANonMemberOrAsANonMemberIs404AndOnAClosedOrganization409`, `removingTakesAManagerAndOnlyAnOwnerRemovesAnOwner` (9), `removingNeverRevealsWhoIsAMemberToSomeoneWhoManagesNothing`, `everyRoleCanLeave` (3). Last-owner tests for every path: `theLastOwnerOfAnOpenOrganizationCannotLeaveBeDemotedOrBeErased` (leave, demote to admin, demote to member, erasure, the same again after ownership moved, then close and leave), `erasureNeverLeavesAnOpenOrganizationWithoutAnOwner` (existing), and two concurrent tests, `twoOwnersLeavingAtOnceLeaveOne` and `twoOwnersDemotingEachOtherAtOnceLeaveOne` (8 rounds each, released together by a barrier). The existing tests now unwrap `NoFallbackAvailableException` (the test client runs through the breaker like every Feign client of the house) with `outcome`/`refusal`.

Mutation checks (code changed, tests run, tree restored and compared with the saved file): an admin may touch owners in `changeRole` (4 rows of the change matrix and `noOneRaisesTheirOwnRole` fail); no rights check before the lookup (`anUnknownEmailIs404...` fails); `requireAnotherOwner` never firing (`theLastOwnerOfAnOpenOrganization...` and `twoOwnersLeavingAtOnceLeaveOne` fail); default role `admin` (the default test fails); an admin removes an owner, and a member may remove others (run together: 4 rows of the remove matrix and `removingNeverRevealsWhoIsAMemberToSomeoneWhoManagesNothing` fail); the closed exception removed (the close-then-leave step of the last-owner test fails); no row lock in `changeRole` and `remove` (both concurrent tests fail, so the race tests do detect a missing lock).

### Decisions

- An account added by email is always a `member`: a body role of `admin` or `owner` is a 400, a role left out is `member`. Review fix: a unilateral add as owner let a stranger make a victim the sole owner of an open organization and block the victim's erasure (see the residual in the threat model).
- Only a verified email resolves (account-service side): anyone can register an address they do not own, and an unverified account must not pass for the person.
- Adding is allowed only while the organization is `active` (as for keys); a role change only while it is not `closed`; a removal always (so the last owner of a closed organization can leave).
- Listing members is open to every member (account ids and roles, no emails), the same "membership only" row as reading keys and usage.

### Threat model for N1 (five lines)

1. Privilege escalation: the role comes from the membership read under the row lock of the organization, never from the request; only an owner grants or touches `owner`, so an admin cannot raise anyone, themselves included (matrix and self rows).
2. Orphaned organization: all paths that remove an owner (leave, remove, demote, erasure) count owners under `SELECT ... FOR UPDATE`; concurrent leave and concurrent mutual demotion are tested.
3. Enumeration: an unverified or unknown email is a plain 404 with the same body, and a caller who may not add never reaches the lookup. Known residual: a verified account that creates its own organization is its owner and can still probe emails (201 means the account exists). The cost is a verified email of its own, and every hit enrols the victim into the attacker organization as a plain `member`; the bound has to be the per-account rate limit of the gateway when X5 routes the endpoint, and removing the oracle needs invitations (parked with SMTP).
3b. Unwanted ownership (residual, not closed): an add can no longer grant `admin` or `owner`, but an owner may still promote any member with a PUT, which is as unilateral as the add. Sequence: attacker creates an organization, adds the victim, promotes the victim to `owner`, leaves. The victim is then the sole owner of an open organization they never joined: they cannot leave (409 `last_owner`) and `DELETE /accounts/{id}` answers 409 `last_owner` until they find the organization (`GET /organizations`) and close it, which the 409 text tells them. Their organization list also shows an attacker-chosen name (up to 256 characters). This is not the "sees it and can leave" case of line 3: the victim cannot leave. Only consent closes it: invitations that the target accepts (SMTP parked), or a rule that erasure closes an organization whose sole owner is erased (changes the erasure semantics and the existing `erasureNeverLeavesAnOpenOrganizationWithoutAnOwner`, so left to the orchestrator). Bound until then: the gateway rate limit on the add and the promote.
4. Tenant probing: a non-member always gets 404 (never 403) on every member call, and a plain member who removes someone else is refused before the target is looked up.
5. Availability and leakage: the account-service call has timeouts, a breaker and a bulkhead and runs outside the transaction; logs, errors and metrics carry no email (fixed texts, the exception class only).

### New stores of personal data

None. `membership` holds an account id and a role, as before; erasure (`DELETE /accounts/{id}` -> `removeMember(accountId)`) and export (`GET /accounts/{id}/export`, the `role` per organization) are unchanged. The email sent to `/accounts/lookup` is used for one query and is not stored, cached or logged by organization-service (account-service already holds it and its logs carry ids only).

### Deviations

- Rule "XService never sees DTOs or HTTP types": `OrganizationService.addMember` calls `AccountController.lookup`, which returns `ResponseEntity<AccountRefOut>`, so the Service touches a library record and an HTTP wrapper. This is the existing pattern of the house (`AccountService` calls `OrganizationController`, `ApiKeyService` calls `organizationController.tenant(..).getBody()`), kept for a minimal diff. Alternative: a one-method `AccountDirectory` class between them; not worth a class with one implementation.
- Residual, no consent step (invitations are parked with SMTP): promoting a member to owner is unilateral, so an attacker can leave a victim as sole owner of an open organization and block the victim's erasure until the victim closes it (threat model 3b). Alternatives: invitations; erasure closes the organization of a sole owner. Needs an orchestrator decision.
- No DB-level guard for the last owner (a deferred constraint trigger): the guard is the row lock in the service, tested for concurrent calls. A trigger would also fire for the LGPD erasure and for closed organizations and needs the same exceptions; left out (ponytail).
- For N2, X5 and reviewers: the gateway must route the list (`GET /organizations/{id}/members`), `POST`, `PUT` and `DELETE` of members but never `GET /organizations/{id}/members/{x}` (the internal role lookup, no `id-account`), and must rate-limit the add per account.

### Architecture paragraph (draft, for `inference-plan.md`)

**Pass 2 N1b built 2026-10-08** (log: [pass-2-idn-progress.md](pass-2-idn-progress.md)): organization-service manages members: owners and admins add an existing account by email (a new internal `POST /accounts/lookup` in account-service resolves a verified email to an id; unknown and unverified emails answer the same plain 404 and a caller without the right never reaches the lookup), change roles and remove members; any member can leave. Only an owner grants or touches `owner`, nobody raises their own role, and an open organization always keeps one owner on remove, demote and leave, enforced under the row lock of the organization together with the LGPD erasure path (409 `last_owner`; other refusals carry `owner_required`, `manager_required`, `organization_not_active`, `already_member`). organization-service now calls account-service through the library Feign client (1 s/3 s timeouts, breaker, bulkhead, no retry), outside the database transaction. Deviations on purpose: no invitations (SMTP is parked), so adding an account is unilateral (always as a `member`; a later promotion by an owner is still unilateral, see threat model 3b, and can leave the target as sole owner of an organization they cannot leave, so erasure answers 409 until they close it) and a success reveals that the email has an account (bounded by the gateway rate limit of X5); the Service sees the Feign `ResponseEntity` of the lookup, as other services already do.
