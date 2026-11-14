# Design: persistent job history

## Context
backend @ 2ee817e: `internal/store/store.go` defines `Store` (`Put`, `Get`, `All`, `EvictFinished`) with only
`Memory`; `internal/engine/engine.go` defaults `Config.Store` to memory, evicts done jobs after `JOB_RETENTION`
(default 24h) and resolves `Subscribe`/`Cancel` through its in-process `runs` map, so after a restart a job would be
unknown to the event stream. No active shared change exists (`openspec/changes/` holds only `archive`), so there is
no overlap and `base_changes` is empty.

## Decisions
1. **Persistence is a deployment property, not an API switch.** The shared contract states what clients see when a
   deployment keeps history; it does not name SQLite, paths or env variables (backend-local).
2. **Interrupted jobs end `failed`.** `failed` already means "orchestrator-internal error"
   (analysis-jobs-api/spec.md:56); a crash is one. No new job status, so `done` semantics and the `status` filter
   are unchanged. Unsettled parts get `interrupted`:
   - `pending` AnalyzerRun -> `skipped`, reason `interrupted`;
   - `running` AnalyzerRun -> `failed`, `error.code` `interrupted`;
   - Scrape `pending`/`running` -> `failed`, `error.code` `interrupted`;
   - Finalization `pending` -> `skipped`, reason `interrupted`; `running` -> `failed`, `error.code` `interrupted`.
   Settled runs keep everything (settled-immutability, spec.md:81). Availability follows the existing "Unavailable
   runs" rule (spec.md:386: any failed code and any unlisted skip reason -> `unavailable`), so no new note text.
3. **No events for the interruption.** No subscriber survives a restart; reconnecting clients get a `job.snapshot`
   showing the final state, which the existing snapshot rule (analysis-job-events/spec.md:23) already allows.
   `seq` of that snapshot is the last seq emitted before the stop, so it never goes backwards for a client.
4. **History retention.** With persistent history, done jobs stay readable until the deployment's history
   retention removes them (default: kept); the in-memory working-set retention no longer makes them 404.
   With the default in-memory store behaviour is unchanged.

## Compatibility classification (every touched object/endpoint)
| Item | Where used (canonical) | Change | Class |
|---|---|---|---|
| AnalyzerRun `reason` values | analysis-jobs-api/spec.md:81 ("values include") | + `interrupted` on a new condition | shared-additive |
| AnalyzerRun `error.code` | analysis-jobs-api/spec.md:81 ("codes including") | + `interrupted` on a new condition | shared-additive |
| Finalization `reason`/`error.code` | analysis-jobs-api/spec.md:106 | + `interrupted` on a new condition | shared-additive |
| Scrape `error.code` | analysis-jobs-api/spec.md:299 ("values include") | + `interrupted` on a new condition | shared-additive |
| Job `status` `failed` | analysis-jobs-api/spec.md:56 | reused for the existing meaning (internal error) | unchanged |
| AnalyzerRun `availability`/`note` | analysis-jobs-api/spec.md:386 | covered by existing unknown-reason rule | unchanged |
| `GET /api/v1/jobs`, `GET /api/v1/jobs/{id}`, cancel | analysis-jobs-api/spec.md:160,167 | same shapes, order, pagination; more jobs survive | shared-additive |
| `GET /api/v1/jobs/{id}/events` | analysis-job-events/spec.md:9,23 | persisted job is an "existing job" | shared-additive |
| Unknown values for clients | api-conventions/spec.md:63 | clients already must tolerate | unchanged |

No shared-breaking change; no client migration needed. Frontend verified tolerant at 6a5eda5.

## Risks
- Event-stream state (plan, progress, previews, activities, last seq) must be persisted for the snapshot of a
  reloaded job; backend task owns that.
- Write volume: the backend writes at least on creation and on every settle/terminal transition; progress-only
  updates may be coalesced (backend-local).
