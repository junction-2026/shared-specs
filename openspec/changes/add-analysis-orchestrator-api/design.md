# Design: analysis orchestrator API, events and analyzer-service protocol

Based on backend @ f7d36425060767d1069efd3e086ac60d388c159f, project @
441ecbf96961128099af004da50a063f18b3345c, shared-specs @
6126b2cac9b4a9f79bdd77e5c03d488ac611bcb3. All three are empty scaffolds.

## Context

The orchestrator accepts a piece of content, runs a configured set of analyzers
against it as a dependency DAG, streams each analyzer result as it settles, and once
every applicable analyzer has settled runs a single synthesis analyzer (the
finalizer) whose methodology lives in an external service. Two kinds of parties
build against the orchestrator: API clients (a future frontend, scripts) and
analyzer services (including the finalizer service at `FINALIZER_URL`).

## Goals / Non-Goals

Goals: a contract precise enough that backend, a frontend and analyzer services can
be built at the same time; consistent REST and WebSocket state; exactly-once
finalization; individual results never overwritten by finalization.

Non-goals: the scoring methodology; the registry file format, scheduler and storage
internals (backend-local); authentication (see Open Questions); frontend work.

## Decisions

### D1. Status models
- Job `status` includes `queued`, `running`, `finalizing`, `completed`, `cancelled`,
  `failed`. `done` is `true` exactly when status is terminal (`completed`,
  `cancelled`, `failed`), which answers "has the whole job including finalization
  finished". `completed` means every applicable analyzer settled AND finalization
  ended (`completed`, `failed` or `skipped`). A failed analyzer or a failed
  finalization does not make the job `failed`; job `failed` is reserved for
  orchestrator-internal errors.
- AnalyzerRun `status`: `pending`, `running`, `succeeded`, `failed`, `skipped`.
  Settled = `succeeded | failed | skipped`.
- Finalization `status`: `pending`, `running`, `completed`, `failed`, `skipped`
  (the five values the parent issue requires).

### D2. Every registry analyzer appears on every job
Disabled, unselected and inapplicable analyzers are listed as `skipped` with a
machine-readable `reason` (`disabled`, `not_selected`, `not_applicable`). This gives
clients and the finalizer full coverage information without a second call, while the
barrier simply treats them as already settled ("do not wait for them"). The
finalizer itself is not an AnalyzerRun; it is the job's `finalization` object.

### D3. Selection pulls in dependencies
`analyzers` in the create request selects analyzers; their transitive dependencies
are included automatically. Rejecting the request instead would force every client to
know the DAG. A dependency that is disabled or inapplicable makes its dependents
`skipped` with `dependency_skipped`.

### D4. Dependency semantics
A regular analyzer runs once all its dependencies `succeeded`. A failed dependency
makes it `skipped` / `dependency_failed`, a skipped one `skipped` /
`dependency_skipped` (failure propagation). The finalizer (`after_all_analyzers_settled`)
runs regardless of success.

### D5. Snapshot-on-connect instead of event replay
Each WebSocket connection starts with a `job.snapshot` event containing the full Job
object and the job's current `seq`; later events have a strictly greater `seq`. A
reconnecting client therefore never needs replay, and REST and WS use the same
objects so they cannot disagree. Per-job `seq` lets a client discard duplicates.

### D6. Finalizer short-circuit without fabrication
When finalization is enabled and no analyzer `succeeded`, the orchestrator does not
call the finalizer and records a FinalAssessment with `verdict:
insufficient_evidence`, `overall_score: null` and `produced_by: orchestrator`. This
is not scoring (no number is produced) and guarantees the acceptance criterion even
against a finalizer that would invent a score. Any finalizer response with `verdict:
insufficient_evidence` and a non-null score is rejected as `invalid_output`.

### D7. `overall_score` is a risk score, not a probability
0–100 inclusive, or `null`. The spec forbids presenting it as a probability; clients
display it as a score.

### D8. Finalization ends before `job.completed`
`job.completed` is emitted after `analysis.finalized` or
`analysis.finalization_failed`, or right after `analysis.ready_for_finalization`
when finalization is `skipped`. Individual `analyzer.*` events are never delayed by
the finalizer or by slow siblings.

### D9. `http_async` uses polling, not callbacks
Callbacks would require the backend to be reachable from every analyzer service.
Polling a `status_url` keeps the services stateless towards the orchestrator. A
callback mode can be added later as an additive change.

### D10. Tolerant reader
All objects are "at least these members"; enums for status/reason/event type are
"includes". One deliberate exception: the analyzer registry listing
(`GET /api/v1/analyzers`) must never include endpoint URLs, headers or other
execution settings, because those may carry credentials.

## Compatibility classification

There are no canonical specs on shared-specs main
(`openspec/specs/` contains only `.gitkeep` at 6126b2c), and no client exists.
Every requirement is **shared-additive** (new capability, new endpoints, new
objects, new event types, new error codes). Nothing is shared-breaking; no client
migration is needed. Objects reused across places, with their single definition:

| Object | Defined in | Reused by |
|---|---|---|
| Error envelope | api-conventions | every endpoint |
| Job | analysis-jobs-api | `POST/GET /jobs/{id}`, cancel response, `job.snapshot`, `job.completed`, `job.cancelled`, `job.failed` |
| AnalyzerRun | analysis-jobs-api | Job.analyzers, `analyzer.*` events, `$job.analyzers` binding |
| Coverage | analysis-jobs-api | Job.coverage, `analysis.ready_for_finalization`, `$job.coverage` binding |
| Finalization | analysis-jobs-api | Job.finalization, `analysis.finaliz*` events |
| FinalAssessment | analysis-jobs-api | Finalization.result; finalizer response in analyzer-service-protocol |
| Input | analysis-jobs-api | create request, Job.input, `$input` binding |

## Risks / Trade-offs

- Listing every registry analyzer on every job makes Job objects larger; acceptable
  at the expected registry size (tens of analyzers).
- In-memory job storage (backend-local decision) means jobs vanish on restart; the
  API does not promise durability in this revision.
- No authentication: anyone who can reach the API can create jobs and read results.

## Open Questions (for the approver)

1. Authentication is not defined. Deployment must keep the API on a trusted network
   until a later change adds it (adding auth later is a breaking change for clients).
2. The parent issue says the original core requirements were not attached; this
   contract defines the core scope listed in the issue only. Further core
   requirements would arrive as a shared amendment.
