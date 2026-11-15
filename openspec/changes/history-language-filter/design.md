## Context

Canonical `analysis-jobs-api` (shared-specs @ d654f43) defines the job list at `specs/analysis-jobs-api/spec.md:171-180` ("List jobs"), the public-only rule at `:624-634`, search at `:661-719` and the JobSummary `excerpt` at `:721-745`. Pagination is `api-conventions/spec.md:40-49`; tolerant readers `api-conventions/spec.md:51-61`. The job's language is defined only as the binding source `$job.source_language` (`analyzer-service-protocol/spec.md:126-139`): the succeeded `translation` result's `source_language`, trimmed and lower-cased, when it matches `^[a-z]{2}$`, otherwise null. The backend implements that rule as `adapter.JobSourceLanguage` (backend @ 881c056, `internal/adapter/adapter.go:134`).

The active change `ai-country-association` (another feature) modifies `analysis-jobs-api` only by adding the Job member `country_association`; it does not touch "List jobs", JobSummary or the listing filters, so this change does not build on it and does not conflict with it.

## Goals / Non-Goals

Goals: a single-select `language` filter for `GET /api/v1/jobs`, matching and paging rules identical in style to `q`/`status`, and a JobSummary member showing the same value.

Non-goals: language detection changes, re-analysis, multi-select, filtering by UI language or claim languages, a languages-in-history facet endpoint.

## Decisions

1. **Job language = `$job.source_language`.** Reusing the existing normalized rule keeps one definition. A job whose `translation` run has not settled, failed, was skipped, is absent, or returned a non-code value has language null and is matched by `language=unknown`. Once the run has succeeded, the value does not change (a settled run does not change, analysis-jobs-api "AnalyzerRun outcomes"); before that the value is null. A job interrupted by a restart keeps null when its translation run becomes `failed` (`interrupted`).
2. **Parameter syntax.** After trimming, an empty value does not filter (like `q`). The rest is compared case-insensitively: `de`, `DE` and ` De ` mean `de`; `unknown`/`UNKNOWN` mean unknown. Anything else (`deu`, `de-AT`, `german`, `1x`, `null`) is 400 `invalid_request` (api-conventions "Common error codes": malformed query parameter). Any two-letter code is accepted, also one with no jobs (`zz` → 200, empty page); the server does not keep an ISO table for this.
3. **No facet endpoint.** The issue allows either "languages present in history" or "a fixed set plus unknown". A fixed set in the frontend needs no new interface; a facet endpoint can be added later additively.
4. **JobSummary `language`** is a string or null, never omitted by a server implementing this change; clients treat a missing member as null so older servers keep working. The Job object (`GET /api/v1/jobs/{id}`) is unchanged.
5. **Paging.** Like `q`, `status` and the public-only rule, `language` is applied before paging; the cursor (created_at, id) is unchanged and filter-independent, so following `next_cursor` with the same parameters continues the filtered sequence.

## Compatibility classification

| Item | Uses in canonical specs | Class |
|---|---|---|
| `GET /api/v1/jobs` query parameter `language` | `analysis-jobs-api/spec.md:172` (List jobs), `:625` (Listing excludes non-public jobs), `:707` (search paging) | shared-additive: new optional parameter; requests without it are answered as today |
| 400 `invalid_request` for a malformed `language` | `api-conventions/spec.md:32` | shared-additive: existing code on a new condition that only arises with the new parameter |
| JobSummary member `language` | JobSummary is defined only at `analysis-jobs-api/spec.md:172` and used only by `GET /api/v1/jobs`; not part of the Job object, events (`analysis-job-events`) or the map (`propaganda-map-api`) | shared-additive: new optional member (api-conventions "Tolerant reader for objects") |
| "List jobs" requirement text | `analysis-jobs-api/spec.md:171-180` | rewritten in the same at-least style; obligations for existing parameters and members unchanged |

No breaking change; no client migration is required. Existing frontend (`src/api/client.ts` `listJobs`, `src/api/types.ts` `JobSummary`) keeps working unmodified.

## Risks / Trade-offs

- A running job is listed as `unknown` until its translation succeeds; a user filtering by `de` sees it only afterwards. Accepted and stated in the spec.
- Persisted history must be backfilled so that old jobs filter correctly; this is a backend-local requirement (migration), required by "Job list language scope".
