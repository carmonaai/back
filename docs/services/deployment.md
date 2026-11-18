# Deployment

## What it is

`deployment-service` owns the `deployments` schema and keeps an organization's serving units: a name, a state, the machines the
operator rented for it and, one line for each connect, what its engines loaded. The operator connects an engine to a deployment
through it; any member of the organization reads the deployments through the gateway. The engine's address and key are never kept
here: [model-service](model.md) is the only place that holds them, and this service passes them on.

<figure class="cmn-figure">
<div class="cmn-flow" markdown="0">
<svg viewBox="0 0 760 310" role="img" aria-labelledby="dep-title" aria-describedby="dep-desc"
     xmlns="http://www.w3.org/2000/svg">
  <title id="dep-title">An engine connected to a deployment, and a member reading it</title>
  <desc id="dep-desc">The operator connects an engine with a call to deployment-service. The service registers the model id with
  model-service, then writes its own row: the state serving and a line for what was loaded. A member of the organization reads the
  deployment through the gateway, and the service first asks organization-service whether the caller is a member.</desc>
  <defs>
    <marker id="dep-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse"><path class="cmn-arrow" d="M0 0 L10 5 L0 10 z"/></marker>
  </defs>
  <!-- Hops in reading order: the connect, the registration, the row, the member's read, the membership check. -->
  <g id="dep-hops">
    <path id="dep-hop1" class="cmn-link cmn-link--flow cmn-dash" d="M140 68 H224" marker-end="url(#dep-arrow)"/>
    <path id="dep-hop2" class="cmn-link cmn-link--flow cmn-dash" d="M374 68 H514" marker-end="url(#dep-arrow)"/>
    <path id="dep-hop3" class="cmn-link cmn-link--flow cmn-dash" d="M299 200 V236" marker-end="url(#dep-arrow)"/>
    <path id="dep-hop4" class="cmn-link cmn-link--accent cmn-dash" d="M140 178 H224" marker-end="url(#dep-arrow)"/>
    <path id="dep-hop5" class="cmn-link cmn-link--accent cmn-dash" d="M374 178 H514" marker-end="url(#dep-arrow)"/>
  </g>
  <g class="cmn-node cmn-node--entry cmn-node--soft" id="dep-operator" aria-labelledby="dep-operator-label"><rect x="20" y="40" width="120" height="56" rx="10"/><text id="dep-operator-label" x="80" y="60">Operator</text><text class="cmn-sub" x="80" y="78">curl and the secret</text></g>
  <g class="cmn-node cmn-node--flow" id="dep-service" aria-labelledby="dep-service-label"><rect x="224" y="40" width="150" height="160" rx="10"/><text id="dep-service-label" x="299" y="110">deployment-service</text><text class="cmn-sub" x="299" y="130">one name, one state,</text><text class="cmn-sub" x="299" y="146">one open line</text></g>
  <g class="cmn-node cmn-node--flow" id="dep-model" aria-labelledby="dep-model-label"><rect x="514" y="40" width="170" height="56" rx="10"/><text id="dep-model-label" x="599" y="60">model-service</text><text class="cmn-sub" x="599" y="78">the registry: address, key</text></g>
  <g class="cmn-node cmn-node--flow" id="dep-db" aria-labelledby="dep-db-label"><rect x="224" y="236" width="150" height="56" rx="10"/><text id="dep-db-label" x="299" y="256">Postgres</text><text class="cmn-sub" x="299" y="274">schema deployments</text></g>
  <g class="cmn-node cmn-node--soft" id="dep-gateway" aria-labelledby="dep-gateway-label"><rect x="20" y="150" width="120" height="56" rx="10"/><text id="dep-gateway-label" x="80" y="170">Gateway</text><text class="cmn-sub" x="80" y="188">a member's GET</text></g>
  <g class="cmn-node cmn-node--soft" id="dep-organization" aria-labelledby="dep-organization-label"><rect x="514" y="150" width="170" height="56" rx="10"/><text id="dep-organization-label" x="599" y="170">organization-service</text><text class="cmn-sub" x="599" y="188">is the caller a member?</text></g>
  <circle class="cmn-packet cmn-travel" r="5" style="offset-path: path('M140 68 H224'); --cmn-travel: 1.0s; --cmn-delay: 0s;"></circle>
  <circle class="cmn-packet cmn-travel" r="5" style="offset-path: path('M374 68 H514'); --cmn-travel: 1.1s; --cmn-delay: 0.4s;"></circle>
  <circle class="cmn-packet cmn-travel" r="4.5" style="offset-path: path('M299 200 V236'); --cmn-travel: 1.0s; --cmn-delay: 0.9s;"></circle>
  <circle class="cmn-packet cmn-packet--accent cmn-travel" r="4.5" style="offset-path: path('M140 178 H224'); --cmn-travel: 1.0s; --cmn-delay: 1.3s;"></circle>
  <circle class="cmn-packet cmn-packet--accent cmn-travel" r="4.5" style="offset-path: path('M374 178 H514'); --cmn-travel: 1.1s; --cmn-delay: 1.7s;"></circle>
  <rect class="cmn-label-plate" x="136" y="44" width="92" height="16" rx="4"/><text class="cmn-label" x="182" y="56">PUT .../engine</text>
  <rect class="cmn-label-plate" x="418" y="44" width="52" height="16" rx="4"/><text class="cmn-label" x="444" y="56">register</text>
  <rect class="cmn-label-plate" x="307" y="210" width="52" height="16" rx="4"/><text class="cmn-label" x="333" y="222">the row</text>
  <rect class="cmn-label-plate" x="148" y="156" width="72" height="16" rx="4"/><text class="cmn-label" x="184" y="168">any member</text>
  <rect class="cmn-label-plate" x="418" y="156" width="52" height="16" rx="4"/><text class="cmn-label" x="444" y="168">member</text>
</svg>
</div>
<figcaption>The top path writes and is the operator's: the engine is registered with model-service first, and only then does the service write
its own row, so a call that failed between the two is finished by the same call again. The lower path reads and is the member's: the
caller's membership is asked of organization-service before anything of the organization is read.</figcaption>
</figure>

<div class="cmn-legend">
  <span><i class="is-flow"></i> the operator's calls (solid)</span>
  <span><i class="is-accent"></i> a member's read (dashed)</span>
</div>

1. **The operator creates a deployment** with `POST /organizations/{organization}/deployments`: a name and the machines it declares.
   The organization must exist and must not be closed.
2. **The operator connects an engine** with `PUT /organizations/{organization}/deployments/{name}/engine`, the loaded model (a Hugging Face
   repository at a revision), the engine's key and its spec.
3. **The service registers the model id with model-service**, `org-<organization id>/<name>`, for that organization.
4. **Then it writes its row**: the state is `serving`, and one line records what was loaded.
5. **A member reads** `GET /organizations/{organization}/deployments` or `.../{name}` through the gateway; the service asks
   organization-service whether the caller is a member and answers only then.

## The calls

The operator's four calls are the service's own: each needs the `X-Internal-Token` header (the secret file, read at start; the service
does not start without a valid one), and no gateway route reaches them. The two reads are the library's `DeploymentController`, behind the
gateway's `deployments` route ([Gateway](gateway.md#the-route-table)).

| Call | Answers |
|---|---|
| `POST /organizations/{organization}/deployments` creates | `201` with the deployment; `400 invalid_request`; `409 deployment_name_taken`, `409 organization_closed` |
| `PUT /organizations/{organization}/deployments/{name}/engine` connects, or replaces | `200` with the deployment; `400`; `404 deployment_not_found`; `409 deployment_ended`; the registry's own 4xx, passed on as it wrote it |
| `DELETE /organizations/{organization}/deployments/{name}/engine` stops | `204`: the registry's entry is retired, and the deployment keeps its machines and its name |
| `DELETE /organizations/{organization}/deployments/{name}` ends | `204`: for good, its name stays taken and its history stays |
| `GET /organizations/{organization}/deployments?page=&size=` lists | `200`, every deployment of the organization, ended ones included, newest first; `size` is 20 when left out and cut to 100; a bad page or size is a `400` |
| `GET /organizations/{organization}/deployments/{name}` reads one | `200`, the same shape as an item of the list; `404 deployment_not_found` |

A read with no `id-account` is a bare 401; a caller that is not a member, or an organization nobody knows, gets organization-service's own 404, so
a stranger never learns what the organization has. Any member reads, whatever the role and whatever the organization's state. Errors carry a fixed text and a
`code`: no handler reads a message from an exception, so nothing from the database, the JSON mapper or the registry's address can reach a
response. A field the records do not have is a 400, not read with a default.

A deployment answers `id`, `organizationId`, `name`, `modelId`, `state` (`serving`, `stopped` or `ended`) and `stateSince`, `createdAt`,
the `machines` in the order declared (provider, GPU name, count, memory and place) and `loadedModels`, newest first, at most 100 (repository, revision,
`connectedAt`, and `stoppedAt` while it serves). Never in it: the engine's address or key, the provider's own id of a machine, the registry's id of the entry.

## A name is the model id

A deployment's `modelId` is `org-<organization id>/<name>`, written in one place (`Deployment.modelId`), and it never changes. The name follows the
registry's rule for the name part of a model id (1 to 64 characters of `a-z`, `0-9`, dots, hyphens and underscores, starting with a letter or a digit), is unique in the
organization for ever, and is never renamed: an ended deployment keeps it, because the table's key does not look at the state. The loaded model is the part
that changes. A connect on a deployment that already serves is a replace: the registry's entry is retired, the model is registered again under the same
id, and the row closes the line that served and opens the next in one transaction. A request records its deployment by that id, so its history does not split at a swap
([Metering](metering.md#what-a-deployments-reads-return)).

At most one line of a deployment is open at a time, which a partial unique index enforces whatever the code does. A deployment serves one loaded
model at a time. The registry allows 32 active models, so at most 32 deployments serve at once until that setting is raised.

## Two steps, and no repair job

A connect is two calls, the registry and then the row, and the service calls the registry outside any transaction, because the registry's writes take turns under a lock of its own
and a call that waits there must not hold a database connection. The registry answers a registration it already has with the same entry and a second retire with 204, so a call
that failed between the steps is finished by the operator repeating it. There is no retry in the service and no repair job. A plain repeat (the same entry, the same repository
and revision) writes nothing. A registry that is down, slow or open-circuit is a bare 503, logged by the class of what failed and nothing else, because the cause could quote
the request, and the request holds the key.

## An organization that closes ends its deployments

`DeploymentSweeper` asks organization-service, once for each organization that has a deployment not ended, every `carmona.deployment.sweep-every` (1 minute, 5 s in compose; the first
pass comes one wait after the start, and under 1 s the service does not start). It acts only on an explicit `closed`: a 404, a timeout or an open circuit ends nothing, and the next pass
does it. Each deployment is then ended the way the operator's call ends it, the registry's entry retired first. A sweep and a connect on one row end in `ended`, because a connect checks the
state again when it writes and answers 409; an entry that a late connect registered is retired by model-service's own sweep, whose owner is the closed organization.

## Why it is like this

**A service of its own, and a schema.** The owner chose it over the recommendation, a second table in model-service. It costs two more repositories (both on the CI token's list) and every connect
is two calls. It buys a registry that stays the only holder of an engine's address and key, and a place for what the registry never kept: the machines, the history of what was loaded, the state.
**The name is the model id**, so callers never change what they type when the engine behind it does. **Nothing is deleted**, so an ended deployment's history and name survive and a request's
record always finds its deployment. **Pulled, not pushed**, as model-service's sweep is: a pass that missed is done by the next one. Both decisions are in the
[decisions record](../reference/decisions.md).

## What would change it

- **Two calls on one deployment at the same moment** can read the same row and write over each other; the open-line index refuses a second serving line. A lock on the deployment's row
  (`SELECT ... FOR UPDATE`) is the upgrade when changes are made often enough to meet.
- **A deployment is read with its machines and its loaded models in separate queries**, one plus two for each deployment, at most 201 for a page of 100 and with no snapshot between
  them. One query for each table and a `REPEATABLE READ` read are the upgrade if a page gets heavy.
- **The sweep is one status call for each organization with a deployment not ended**, per pass, with those deployments held in memory; an `organization.closed` event replaces it when that grows.
- **More than one loaded model for a deployment** needs a second naming level, and `GET /v1/models` shows the name and not what is loaded.
- **The machines are declared, not checked** against any provider.

## Where to look

- [DeploymentResource.java](https://github.com/carmonaai/back/blob/main/api/deployment-service/src/main/java/ai/carmona/deployment/DeploymentResource.java) — the six calls and every refusal's fixed text.
- [DeploymentService.java](https://github.com/carmonaai/back/blob/main/api/deployment-service/src/main/java/ai/carmona/deployment/DeploymentService.java) — connect, stop, end and the two steps.
- [DeploymentSweeper.java](https://github.com/carmonaai/back/blob/main/api/deployment-service/src/main/java/ai/carmona/deployment/DeploymentSweeper.java) — ending the deployments of a closed organization.
- [DeploymentController.java](https://github.com/carmonaai/back/blob/main/api/deployment/src/main/java/ai/carmona/deployment/DeploymentController.java) — the two reads and what each answers.
- [create_tables.sql](https://github.com/carmonaai/back/blob/main/api/deployment-service/src/main/resources/db/migration/V2026.11.15.001__create_tables.sql) — the three tables and their checks.
