# Proposal: analysis orchestrator API, events and analyzer-service protocol

## Why

Parent feature junction-2026/project#2 asks for a backend orchestrator that runs
declaratively configured content analyzers as a DAG, streams individual results as
they complete, and runs a final synthesis analyzer (the finalizer) once every
applicable analyzer has settled. Frontends and external analyzer/finalizer
services must be able to build against the orchestrator concurrently with the
backend, so the interfaces between them need a canonical contract.

Based on: backend @ f7d36425060767d1069efd3e086ac60d388c159f (empty Go-service
scaffold), project @ 441ecbf96961128099af004da50a063f18b3345c (integration harness
placeholder only), shared-specs @ 6126b2cac9b4a9f79bdd77e5c03d488ac611bcb3 (no
canonical specs yet). Everything here is new; there is no current canonical
behaviour to stay compatible with.

## What Changes

- **api-conventions** (new): base path `/api/v1`, JSON, timestamps, the error
  envelope, pagination and the tolerant-reader rule for every endpoint and event.
- **analysis-jobs-api** (new): `POST /api/v1/jobs`, `GET /api/v1/jobs`,
  `GET /api/v1/jobs/{id}`, `POST /api/v1/jobs/{id}/cancel`, `GET /api/v1/analyzers`;
  the Job, AnalyzerRun, Coverage, Finalization and FinalAssessment objects; analyzer
  and finalization status models.
- **analysis-job-events** (new): WebSocket `GET /api/v1/jobs/{id}/events`, the event
  envelope, the snapshot-on-connect rule, event types (analyzer results streamed as
  they settle, `analysis.ready_for_finalization`, `analysis.finalizing`,
  `analysis.finalized`, `analysis.finalization_failed`, `job.completed`,
  `job.cancelled`) and their ordering and exactly-once guarantees.
- **analyzer-service-protocol** (new): the HTTP contract between the orchestrator and
  external analyzer services (`http_sync`, `http_async` polling), the binding
  sources a service receives (`$input`, `$job.analyzers`, `$job.coverage`,
  `$analyzers.<id>`), the analyzer result conventions (evidence ids) and the
  finalizer response (FinalAssessment, `insufficient_evidence` rule).

Not in this change (backend-local, per common rule 13): the analyzer registry file
format and binding grammar, adapter internals (`custom` adapters), scheduler,
storage, concurrency limits, configuration variables and test coverage.

## Capabilities

### New Capabilities
- `api-conventions`
- `analysis-jobs-api`
- `analysis-job-events`
- `analyzer-service-protocol`

### Modified Capabilities
- none

## Impact

- backend: implements all four capabilities (children `backend-engine`,
  `backend-api`, `backend-finalizer`).
- External analyzer services and the finalizer service at `FINALIZER_URL` implement
  the service side of `analyzer-service-protocol` (out of scope for this feature).
- Future frontend work consumes `analysis-jobs-api` and `analysis-job-events`.
- No authentication is defined in this revision (see design.md, Open Questions).
