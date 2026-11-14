# Job visibility: unlisted analysis jobs (junction-2026/project#53)

Based on backend @ 0e6833bfa5f54cab43426bf15f74a65307afdfa0, frontend @ 4aab58091e8fa5edbe79f0d6f35f0fb24cec8ad8,
project @ 441ecbf96961128099af004da50a063f18b3345c, shared-specs @ 07b1fce6c316aa2ddf926ffab423dd721fb5b9b4.

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
- No overlap with the active change `job-text-localization` (it does not touch `analysis-jobs-api`).
