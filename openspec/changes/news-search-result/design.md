# Design: News coverage search analyzer

## Context

Canonical shared specs (shared-specs @ 42cc024) treat an analyzer's `result` as the
service's JSON object (`openspec/specs/analysis-jobs-api/spec.md:65-66` "AnalyzerRun
object") and keep skip reasons and error codes open lists
(`analysis-jobs-api/spec.md:72-73` "AnalyzerRun outcomes": "`reason` values
include", "codes including"). `topic-extraction-result` defines the input this
analyzer searches (`openspec/specs/topic-extraction-result/spec.md`, "TopicExtraction
object", "Topic and NewsItem objects"). The backend (@ f2ee870) resolves
`$analyzers.<id>` bindings (`internal/adapter/adapter.go:69-96`), has a Mistral
client (`internal/adapter/translation.go`) and settles runs only as succeeded/failed
from an adapter, skips only by dependency (`internal/engine/run.go:111-130`). The
frontend (@ 3e51ec4) reads no job objects.

## Goals / Non-goals

Goals: a stable result shape for news coverage search that the backend produces and
any client (frontend, finalizer, later fact-check features) can read; minimal search
spending visible in the result. Non-goals: other providers, a persistent or shared
cache, frontend display, judging claims from coverage.

## Decisions

1. **New capability `news-search-result`, no modified canonical requirement.** Same
   pattern as `topic-extraction-result`; keeps this change disjoint from the active
   `social-media-scrape-input`, which modifies `analysis-jobs-api` and
   `analysis-job-events`.
2. **Skip reason `no_searchable_topics` is defined in this capability.** The
   canonical reason list is open, so adding a value on a new condition is additive;
   the requirement also tells clients to treat unknown reasons as "not run".
3. **Runtime skip after start.** The decision needs the dependency's result, so the
   run is `running` first; `analyzer.started` then `analyzer.skipped` satisfies
   "One settle event per analyzer" (`analysis-job-events/spec.md:40-41`). Coverage
   counts it as applicable (`analysis-jobs-api/spec.md:91`: only `disabled`,
   `not_selected`, `not_applicable` are excluded) — intended, because the analyzer
   did apply and found nothing to search.
4. **Partial success.** Search quota is scarce and searches are independent; one
   failed query must not discard the others. Each SearchQuery carries `status` and
   `error`; per-query codes (`search_failed`, `translation_failed`) are new values in
   a new object, not AnalyzerRun codes.
5. **Whole-run failures reuse existing codes** (`adapter_error`, `timeout`,
   `cancelled`). 401/403 fail the run immediately (a wrong key would fail every
   query and burn quota).
6. **Spending is visible.** `searches_used` (sent requests incl. retries and
   fallbacks) and `cached` let operators and tests verify the issue's budget rules
   without a provider dashboard.
7. **`date` is opaque provider text** (Serper returns relative dates). Ordering ties
   use it only where the backend can interpret it.
8. **Provider data is untrusted.** Titles/snippets come from arbitrary web pages and
   URLs may carry any scheme: the backend drops non-`http(s)` URLs and clients still
   check the scheme before linking, render all text as plain text.
9. **Dependency on `translation` uses the canonical rule.** No optional dependency is
   introduced; omitting `translation` from `depends_on` removes `source` from the
   languages.
10. **Backend-local, not shared:** Serper endpoints and request body, `gl`/`hl`
    mapping, cache key and TTL, concurrency, retry backoff, Mistral model and batch
    prompt, registry keys and defaults, finalizer `llm.description`.

## Affected uses (classification)

| Use | Evidence | Change | Class |
|---|---|---|---|
| AnalyzerRun `result` for id `news_search` | `analysis-jobs-api/spec.md:66` (result is the analyzer's object) | defines NewsSearch for a new analyzer id | shared-additive (new object) |
| AnalyzerRun skip `reason` | `analysis-jobs-api/spec.md:73` ("values include") | new value `no_searchable_topics` on a new condition | shared-additive |
| AnalyzerRun error codes | `analysis-jobs-api/spec.md:73` | none new (reuses `adapter_error`, `timeout`, `cancelled`) | unchanged |
| `analyzer.started` / `analyzer.skipped` events | `analysis-job-events/spec.md:34`, `:41` | runtime skip after start, already allowed | unchanged |
| Coverage | `analysis-jobs-api/spec.md:91` | skip counts as applicable, per existing rule | unchanged |
| Selection / dependencies | `analysis-jobs-api/spec.md:30`, `:80` | `news_search` selects `topic_extraction` (+ `translation`) as dependencies | unchanged |
| TopicExtraction object | `topic-extraction-result/spec.md` "TopicExtraction object" | read only | unchanged |
| Finalizer input (`$job.analyzers`) | `analyzer-service-protocol/spec.md:30` | carries the new result like any other | unchanged |

No shared-breaking change; no client migration. There is no current client of
`/api/v1/jobs` in the frontend. No "exactly" clause is touched.

## Risks

- Search quota: bounded by deployment limits (topics, news items, languages, the
  single fallback, the cache); defaults give at most (3 + 2) x 2 x 2 = 20 requests
  per run before retries.
- Backend file overlap with project#8 (still in implementation): see the backend
  task's file ownership; the only shared file is `internal/engine/run.go` (a narrow
  hook), not `internal/job` or `internal/httpapi`.
