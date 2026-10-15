---
name: carmonai-architecture
description: Carmonai architecture rules — module split, layering, security, resilience, LGPD, stack. Load before designing, reviewing, or changing any service, API, auth, or data code.
---

# Carmonai architecture

Source: the Insper "Platforms, Microservices, DevOps and APIs" course (2026.2 Classes + Hands-on; code in `repo-classes/pma.261*`). Its structure binds us; the **hardening overrides** below win where they conflict. Before inventing a pattern, find the matching page in [references/insper-map.md](references/insper-map.md) and follow it.

Scope today: all thirteen modules. Five libraries (`account`, `auth`, `organization`, `usage`, `billing`), each with its `-service`, and three services without a library because no Java caller needs one: `gateway-service`, `inference-service` and `batch-service`. Inference, money, batch and the gateway for several replicas follow [references/inference-plan.md](references/inference-plan.md) (approved 2026-10-03; the dated blocks at its top say what was built and which deviations were made on purpose, up to pass 2 and the MVP backend steps of 2026-10-15; the numbered sections are the design as it stands; the `batch-inference-design` skill is behind it). The vocabulary is `CONTEXT.md` at the project root.

## Shape

`client → gateway-service (WebFlux, the only published port) → auth-service / business services → Postgres`

- One schema per service, no shared tables. Services reach each other through the library's Feign client.
- Services are stateless, so replicas scale horizontally.
- The gateway validates the JWT, then sets `id-account` itself, stripping any inbound copy (for an API key it sets `id-organization`, `id-api-key` and `tier`; it also strips `x-internal-token`). Services trust those headers from the gateway only.
- "Stateless" holds for the gateway hops (it balances each request across the replicas of an upstream itself) and for any service behind a balancing Service; the Feign clients between services keep a fixed `url=` and can pin a replica for the JVM's DNS-cache window, so check that before scaling a service behind one.

## Module rules

- Two modules per service: `<name>` library + `<name>-service`.
  - Library: `XController` Feign interface (`@FeignClient(name="<name>", url="http://<name>:8080")`) and `XIn`/`XOut` records with `@Builder`. Dependencies: openfeign + lombok. No business logic, with one exception: a **value type** that two modules must read the same way, with no logic beyond predicates and arithmetic on its own values. The `organization` library holds the `Role` enum (`owner`, `admin`, `member`; its predicates `managesKeys()`, `closesOrganization()`, `managesMembers()` and `managesOwners()` are the authorization table, and its lowercase constants are the wire and column words); `billing` holds `Price` (one rounding and one "row in effect" rule for the debit job and the customer summary) and `Overshoot` (the quotable duration). A service never keeps its own list of role names.
  - Service: depends on the library at `${project.version}`.
- Request flow in the service: `XResource` (`@RestController implements XController`) → `XService` → `XRepository` (Spring Data) → DB.
  - Domain class `X` and JPA class `XModel` stay separate (`new XModel(domain)`, `model.to()`).
  - Parse at each boundary: Resource turns `XIn` into `X` and `X` into `XOut`; Service turns `X` into `XModel` and back. `XService` never sees DTOs or HTTP types.
- IDs are UUID `String`. Each service owns a schema named after its aggregate plural (`accounts`). Flyway migrations are date-versioned (`V2026.10.02.001__create_table.sql`); Hibernate only validates.
- Configuration comes from env vars through `application.yaml`; port 8080; `spring.application.name=<name>`.

## Hardening overrides

1. **Passwords**: Argon2id (`Argon2PasswordEncoder`, spring-security-crypto + Bouncy Castle). The hash lives only in account-service; no `Out` record carries a password or hash. (Reference: unsalted SHA-256.)
2. **JWT**: asymmetric (RS256/ES256), access token 5–60 min. auth-service signs and publishes a JWKS; the gateway validates locally from the cached JWKS, so no request-path call to auth-service. (Reference: HS256 + `/auth/solve` on every request.)
3. **Resilience**: every outbound call has an explicit timeout (about the downstream P99.9, per dependency). Feign runs through Resilience4j (`spring.cloud.openfeign.circuitbreaker.enabled`):
   - circuit breaker opens at 50% failures over the last 10–20 calls, waits 30–60 s, probes with 3–5 half-open calls;
   - retry with exponential backoff + jitter on idempotent calls only (GET/PUT/DELETE; POST only with an idempotency key);
   - a bulkhead per dependency; token-bucket rate limiting at the gateway.
   - Postgres: every JDBC URL carries `options=-c statement_timeout=5000` (a migration that needs longer sets `SET LOCAL statement_timeout = 0` itself); a pooler needs `ignore_startup_parameters` for it.
4. **Collections**: `page`/`size` with a maximum size. The existing `account` library's `findAll()` becomes paged.
5. **Containers**: pinned image tags, multi-stage Dockerfile, non-root user; K8s liveness/readiness probes (`/actuator/health/liveness|readiness`) with requests and limits.
6. **Actuator and Prometheus** run on a management port (8081) that is never published and never routed by the gateway. (Reference routes `/<svc>/actuator` through the gateway.)
7. **Internal endpoints carry a shared secret** (BE-24, SEC-04). An endpoint that mints credit, changes a tier or status, creates verified accounts, drops memberships, ends sessions or evicts key caches is marked `@InternalToken.Required` and answers 401 unless the request carries exactly one `X-Internal-Token` header equal to the secret in the file named by `carmonai.internal.token-file` (`/run/secrets/internal_token`, one line `X-Internal-Token: <64 hex>`, read at start; the service does not start without it). The gateway never holds the file and strips the header from every inbound request; a Feign client adds it only toward a service that guards an endpoint. The secret is a second lock behind "no gateway route" and the network split, not a replacement. A new internal endpoint is open until marked: mark it, or list it as deliberately open (callers that hold no file), and extend the module's inventory test.

## LGPD working rules (confirm with legal/DPO)

- Collect only fields a feature needs; record the purpose of each.
- Logs, traces, metrics and events carry ids; email, name, passwords, tokens and prompt content stay out.
- Error bodies carry a fixed text chosen by the error's code, never an exception's message (CONTEXT.md, **Fixed text**); test every handler path with `CANARY-<uuid>` in the exception's message.
- `DELETE /accounts/{id}` erases or irreversibly anonymizes the data and reaches every service holding it. Each service holding personal data states how it erases and how it exports.
- TLS in transit, encrypted DB volumes at rest, secrets from env or a secret manager, never in a repo or a default value.

## Stack

Versions come from `back/api/account/pom.xml` (Java 25 LTS — Boot 4.1 supports up to 26 —, Spring Boot 4.1, Spring Cloud 2025.1, Maven, Lombok). Tests: JUnit + Testcontainers 2; every guard has a test that fails when the guard is removed; CI: `back/.github/workflows/ci.yaml` (`mvn -B verify`, compose up, `smoke.sh`; the compose stack runs a simulated engine, not a CPU model: ADR 0002, `docker/sim/build.sh`). Postgres 17 + Flyway; gateway on WebFlux (`spring-cloud-starter-gateway-server-webflux`), other services on `spring-boot-starter-webmvc`. Boot 4 renamed several starters, so confirm artifact names with `mvn verify`.

Later phases (nginx, Redis, Kafka, K8s, CI): read [references/platform.md](references/platform.md) before adding any of them. Observability is built — metrics, dashboards and alerts: read [references/observability.md](references/observability.md).

## Review checklist

A change is done when each item holds:

- Every hardening override above is met.
- `grep -rniw store` over the changed modules: every hit is ordinary English in a comment or a log text, the `no-store` cache header, or the OpenAI request field `store` (and its tests), which the API must name; never a package, class, config key, table, compose or file name. The rule exists to catch names left over from the example project (owner, 2026-10-14; RULES.md of pass 2 spells out the same test).
- No `latest` image tag, no default password, no unbounded collection endpoint.
- Every new internal endpoint is marked (override 7) or listed as open on purpose; no error handler reads an exception message.
- No personal data in logs, events or caches that outlive an erasure.
