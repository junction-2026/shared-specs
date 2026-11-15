## Context

Canonical `propaganda-map-api` (shared-specs @ 92a5491) gives a job one map country, from the page outlet or the outlet table (`openspec/specs/propaganda-map-api/spec.md:34-61`). The backend derives it in `internal/store/mapvalues.go` `DeriveMap` and stores one `map_country_code` column per job (`internal/store/sqlite.go:44-49`). The frontend reads it in `src/api/mapTypes.ts` and already treats `outlet` as nullable (`readAnalyses`).

## Goals / Non-Goals

Goals: every analysis with detected propaganda gets countries from an LLM step when they can be determined; multi-country map analyses; backfill of stored jobs; the step never fails an analysis.
Non-goals: changes to technique detection, manual country editing, forcing a country.

## Decisions

1. **Job-level step, not an AnalyzerRun.** Like `risk`, the step is part of the orchestrator and is stored as `Job.country_association`. It needs the settled analyzer results as input, must be backfillable for done jobs (an AnalyzerRun is immutable once settled and the analyzer list of a done job must not grow), and must not take part in the finalization barrier or coverage. Alternative rejected: an analyzer `country_association` depending on `techniques` and `source_info` — it would block `analysis.ready_for_finalization` and could not be added to stored jobs.
2. **Runs concurrently with finalization, before `done`.** No extra latency unless the step is slower than finalization; `job.completed` carries the settled value, so "Map freshness" (`propaganda-map-api/spec.md:90-96`) holds unchanged. No new event type, so `analysis-job-events` is unchanged.
3. **Only for jobs with detected propaganda.** Other jobs can never be map analyses; skipping them (`reason: no_detected_propaganda`) limits LLM cost. Non-public jobs still run live (their job page shows it); the backfill skips non-public jobs to limit cost.
4. **Union with the outlet country.** Map countries = outlet country (existing rules, kept as fact and as fallback when the step fails or is not configured) followed by associated countries. A deployment without a model keeps today's map exactly.
5. **Country names from the orchestrator's ISO table**, codes validated against officially assigned ISO 3166-1 alpha-2 codes; at most 10. Model text never reaches clients as a country name.
6. **Backfill** replaces only missing or `failed` associations, runs in the background in bounded batches with a bounded attempt count (sizes are backend-local configuration), and re-derives the map countries of the job with the fixed map outlet and technique set.

## Compatibility classification

Every use of the changed objects in canonical specs (`grep -n "country_code\|MapAnalysis\|CountryAggregate\|map country" openspec/specs/*/spec.md`): only `propaganda-map-api` and `source-info-result` (Outlet object, unchanged) use them.

| Change | Spec evidence | Class | Clients / migration |
|---|---|---|---|
| `Job.country_association` new member | `analysis-jobs-api/spec.md:56-57` (Job object "at least") | shared-additive | none required |
| New capability `country-association` | — | shared-additive | — |
| Map analysis: at least one map country instead of one outlet country | `propaganda-map-api/spec.md:8-9` | shared-breaking (meaning: more jobs qualify, incl. pasted text) | frontend: wording of lede, tooltip, empty state (`src/i18n/locales/*/explore.ts` `pmap.*`) |
| Map country becomes a list | `propaganda-map-api/spec.md:34-43` | shared-breaking (meaning) | frontend: none for aggregates; panel may show other countries |
| Outlet table fallback gives map outlet; "No URL" scenario | `propaganda-map-api/spec.md:45-54` | shared-breaking (changed outcome for existing case) | frontend: pasted-text items |
| "No inferred country" removed | `propaganda-map-api/spec.md:56-61` | shared-breaking | frontend wording |
| Map values fixed when done: backfill exception | `propaganda-map-api/spec.md:63-68` | shared-breaking (counts of old jobs may grow) | none (clients re-request) |
| `analyses` = distinct count; sum may exceed | `propaganda-map-api/spec.md:98-104` | shared-breaking (changed relation) | frontend uses `analyses` only for the subtitle count and empty check (`src/explore/propagandaMap/PropagandaMap.tsx:78,88`) — correct as distinct count; no client may sum items to get the total |
| CountryAggregate `analyses`/`country` per code among countries | `propaganda-map-api/spec.md:112-118` | shared-additive for single-country jobs, meaning extended | none |
| Country list includes multi-country analyses | `propaganda-map-api/spec.md:133-135` | shared-additive | none |
| MapAnalysis `country_code`/`country` = list's country; new `countries` | `propaganda-map-api/spec.md:166-171` | `countries` additive; `country_code` meaning extended (equal to before for single-country) | frontend may read `countries` |
| MapAnalysis `outlet` nullable | `propaganda-map-api/spec.md:173-174` | shared-breaking (type: object → object or null) | frontend `readAnalyses` already maps a non-object outlet to null and `Panel.tsx:19` renders it conditionally; add a test |
| `source.url` may be `""` | `propaganda-map-api/spec.md:174` | shared-breaking (new value) | frontend must not show/link an empty URL (Map rendering) |
| Map rendering adds `countries[].country` | `propaganda-map-api/spec.md:202-207` | additive | frontend plain text |
| Map country meaning reworded | `propaganda-map-api/spec.md:209-214` | shared-breaking (UI wording obligation) | frontend tooltip "analyses associated with <country>" |

Affected clients: frontend only (the sole consumer of the map endpoints). The project repo has no map tests (full-e2e is a placeholder).

## Risks / Trade-offs

- LLM cost/latency: limited to jobs with propaganda; backfill bounded and retried.
- Model mistakes: names come from the table, codes validated; wording forbids presenting a country as origin/author/target.
- Prompt injection from analyzed text: the reply is parsed as structured codes only; a bad reply is `invalid_output`, never fails the job.
- Canonical `propaganda-map-api` Purpose still says "country of the analyzed page's outlet"; requirements are authoritative. A later change may reword the Purpose.
