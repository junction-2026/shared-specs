# Job visibility: unlisted analysis jobs (junction-2026/project#53)

Based on backend @ d03c1cc4ce1f941ef37a4b715c2de081ac65f379, frontend @ 16b0a127095cb2c5815b67ea9f3ac1cadea76ffd,
project @ 441ecbf96961128099af004da50a063f18b3345c, shared-specs @ 5981c9fdec37dc8664689f5ff2595ae797da618a.

## Why
Every analysis job appears in `GET /api/v1/jobs` and therefore in the frontend History for everyone
(analysis-jobs-api "List jobs", "Persisted jobs in listing and cancel"). Users want to submit a job without it
being listed, while still being able to share it by its URL.

## What changes
- `POST /api/v1/jobs` accepts an optional top-level boolean `public` (default `true`) next to `input` or `scrape`.
  A value that is not `true` or `false` (including `null`) yields 422 `validation_failed` with `details.fields`
  key `public`.
- The Job object gains the member `public` (boolean). Jobs created without the member, and jobs stored before this
  change, have `public: true`. The value is fixed at creation; no endpoint changes it.
- `GET /api/v1/jobs` lists only jobs with `public: true`, with and without the `status` filter and across cursor
  pagination; page sizes and `next_cursor` are computed over public jobs only.
- `GET /api/v1/jobs/{id}`, `POST /api/v1/jobs/{id}/cancel` and `GET /api/v1/jobs/{id}/events` behave the same for
  non-public ("unlisted") jobs as for public ones. Unlisted means not listed, not secret: no authentication or
  access control is added.
- Not shared (common rule 13): storage column, schema migration, defaulting of old stored rows and the listing query
  (backend local change); the switch in the Home composer, its copy in every locale and tests (frontend local change).

## Impact
- Shared capability: `analysis-jobs-api` (requirements "Create job", "Create job validation", "Job object",
  "List jobs", "Persisted jobs in listing and cancel" modified; "Job visibility", "Listing excludes non-public jobs" and "Unlisted jobs by id" added).
  All changes are shared-additive for clients (see design.md). `analysis-job-events` is unchanged: its events carry
  the Job object and so carry `public` without a spec change.
- backend: request parsing, Job member, store column with migration (existing rows public), listing filter in the
  SQLite and in-memory stores.
- frontend: a "Public" switch (on by default) in the Home composer with explanatory text; sends `"public": false`
  only when switched off. History needs no code change (the server filters) beyond tolerant types.
- Overlapping active changes (planned around, not modified; `base_changes` is empty):
  - `wikipedia-cross-language` (junction-2026/project#47, implementing) changes `wikipedia-lookup-result` only; its
    frontend task also edits `frontend/backend-api-client` (`src/api/types.ts`) and `frontend/i18n` locale files.
    This change adds disjoint members there (`public` on `CreateJobBody`/`Job`, new `compose.visibility.*` keys), so
    the two merge textually without contradiction.
  - `term-context` (junction-2026/project#49, proposed) modifies only the `analysis-jobs-api` requirement
    "Wikipedia quotes for clients"; this change modifies "Create job", "Create job validation", "Job object",
    "List jobs" and "Persisted jobs in listing and cancel" and adds three new requirements. No requirement is
    modified by both, so both deltas apply in either order.
