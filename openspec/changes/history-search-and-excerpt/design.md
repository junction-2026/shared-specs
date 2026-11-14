# Design: history-search-and-excerpt

## Context
Canonical `analysis-jobs-api` "List jobs" (openspec/specs/analysis-jobs-api/spec.md:171-176) defines
`GET /api/v1/jobs` with cursor paging (api-conventions "Cursor pagination", openspec/specs/api-conventions/spec.md:40-49),
a `status` filter and JobSummary. "Persisted jobs in listing and cancel" (spec.md:510-523) and "Listing excludes
non-public jobs" (spec.md:616-625) require filters to be applied before paging. The backend lists from
`Store.Page(status, after, limit)` (backend `internal/store/sqlite.go:311`, memory store `store.go:145`), and builds
JobSummary in `internal/httpapi/jobs.go:332`. The frontend fetches excerpts per item in `src/history/useExcerpts.ts`.

## Decisions
1. **Search parameter `q` on the existing list endpoint**, not a new endpoint: it keeps ordering, cursor paging,
   `status` and public-only rules identical, so "load more" works unchanged on search results.
2. **Fields searched: `id`, `input.content`, `scrape.url`.** These are what the History item shows (id and
   excerpt source). `input.source.*` and analyzer results are not searched (non-goal: advanced search).
3. **Literal, case-insensitive substring** via Unicode lowercase mapping on both sides; no wildcards. SQL `LIKE`
   wildcards (`%`, `_`) must therefore be escaped or not used by the backend. 200-character limit bounds the cost.
4. **Applied before paging**, like `status` and the public filter, so a match beyond the first unfiltered page is
   returned on the first search page. Cursors stay positional (`created_at`, `id`), so the existing cursor
   format works; clients resend the same `q` and `status`.
5. **JobSummary `excerpt` (200 chars, verbatim).** Without it, export of the full history would need one
   `GET /api/v1/jobs/{id}` per job. 200 leaves room for the frontend's 140-character display cut. Copied verbatim
   so the backend does no presentation work; clients render plain text (untrusted content).
6. **Export stays client-side** (frontend local requirement): the frontend pages `GET /api/v1/jobs?limit=100` and
   builds a CSV. No export endpoint is added (issue non-goal: server-side export).

## Compatibility classification
| Object / endpoint | Used in (canonical) | Change | Class |
|---|---|---|---|
| `GET /api/v1/jobs` query | analysis-jobs-api spec.md:171-176, 510-523, 616-625; api-conventions spec.md:40-49; propaganda-map-api spec.md:9, 78 (refers to the set of listed jobs, without `q`) | new optional `q` parameter; new 400 `invalid_request` only on the new condition (`q` > 200 chars) | shared-additive |
| JobSummary | analysis-jobs-api spec.md:172 (List jobs), 211 (verdict values), 511 (persisted listing); not used by events or other endpoints | new member `excerpt` (string or null) | shared-additive |
| Job, `GET /api/v1/jobs/{id}`, events, map endpoints | analysis-jobs-api, analysis-job-events, propaganda-map-api | unchanged | none |

No shared-breaking change. A server without this change ignores `q` (request tolerance) and omits `excerpt`;
clients treat a missing `excerpt` as null. The frontend and backend ship together in one feature group.
The "List jobs" requirement already reads "at least"; it is kept in that style.

## Parallel feature junction-2026/project#64 (`manipulation-risk-score`, implementing)
- Shared spec: #64 only ADDS "Job risk member" (Job `risk`) to `analysis-jobs-api` and an event requirement to
  `analysis-job-events`; it does not touch "List jobs" or JobSummary. This change MODIFIES only "List jobs" and ADDS
  requirements with new names, so both deltas archive cleanly in either order. JobSummary does not gain `risk`.
- Backend: both features touch the job store. This feature adds no schema migration (the append-only
  `migrations` list in `internal/store/sqlite.go` is where #64 may add one), so the two never claim the same
  migration index; search is evaluated in Go over the stored job (e.g. a registered SQL function or a filtered scan).
- Frontend: #64 changes the Results screen; this feature changes only the History screen, `listJobs`/JobSummary
  types and `history` catalog keys, so the edits are in different blocks of shared files (types, catalogs).

## Risks
- Search over the SQLite history decodes or scans `data` JSON per row; acceptable at current history sizes and
  bounded by the 200-character query. The backend may add a column or index locally; that is not part of the contract.
- Unicode lowercase on both sides: SQLite's built-in `lower()` is ASCII-only, so the backend must not rely on it
  alone (e.g. register a Go function or filter in Go).
