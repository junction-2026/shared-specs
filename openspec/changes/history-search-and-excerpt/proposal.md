# History search and job excerpts in the job list (junction-2026/project#67)

Based on backend @ b5a606614a3f70f2f1ca10951a7dfbc49d832e7e, frontend @ 28d228d53f817abb249285ee417f2e80237ff04d,
project @ 441ecbf96961128099af004da50a063f18b3345c, shared-specs @ 3949bec3d32a399427d239e3147239fa1e716cfe
(main with `manipulation-risk-score` #64 active; it adds a Job `risk` member in `analysis-jobs-api` and leaves
`GET /api/v1/jobs` and JobSummary unchanged, so this change neither modifies nor builds on it).

## Why
The History screen cannot search: `GET /api/v1/jobs` has no text query and JobSummary carries no text, so the
frontend fetches every loaded job with `GET /api/v1/jobs/{id}` to show an excerpt and can only see loaded pages.
Users want to find an old analysis by a phrase from its text and to download their history as one file.

## What changes
- `GET /api/v1/jobs` gets an optional `q` query parameter: case-insensitive literal substring search over job `id`,
  `input.content` and `scrape.url` across the whole listed history, combined with `status`, applied before paging.
  Over 200 characters yields 400 `invalid_request`.
- JobSummary gets an optional `excerpt` member: the first 200 characters of `input.content`, else of `scrape.url`,
  else null. It lets the History screen show items and export the whole history without one request per job.
- Both are additive (api-conventions "Tolerant reader for objects"); no existing member, status or error changes.

## Not in the shared contract (local to repositories)
- Frontend: removing the History meta line, the Export button generating a CSV client-side from paged
  `GET /api/v1/jobs`, the search box UI, empty state, i18n, `docs/mock-areas.md`, tests.
- Backend: how search is evaluated in the memory and SQLite stores, any index or migration, tests.

## Capabilities
- Modified: `analysis-jobs-api` (List jobs; added Job list search, Job list search scope and paging, JobSummary excerpt).

## Impact
- backend: `internal/httpapi/jobs.go` (parse `q`, `excerpt` in `summarize`), `internal/store` (`Page` filter in
  Memory and SQLite), `internal/engine` (`Page` signature).
- frontend: `src/api` (types, `listJobs` with `q`), `src/history`, `src/views/HistoryView.tsx`, locale catalogs.
