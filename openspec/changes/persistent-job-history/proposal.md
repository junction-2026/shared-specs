# Persistent job history (junction-2026/project#43)

## Why
Jobs, including every AnalyzerRun result and the final assessment, live only in backend memory: they are lost on
restart and evicted after the job retention period. Users want to restart the backend and still list and read past
analyses of every analyzer type.

## What changes
- The backend gains an optional persistent job store (SQLite); the in-memory store stays the default. Store
  selection, database path, schema migration and serialization are backend-local (common rule 13).
- Interface part only, all additive (see design.md):
  - analysis-jobs-api: ADDED "Job history persistence", "Persisted jobs in listing and cancel" and "History retention" (a job read from persistent history is the same Job/JobSummary
    as before the restart, same ordering and pagination, cancel of it answers 409 `job_finished`) and ADDED
    "Jobs interrupted by a restart", "Interrupted parts" and "Interrupted part timing" (a job not `done` when the server stopped ends `failed` at the next start; its
    unsettled parts get the new skip reason / error code `interrupted`).
  - analysis-job-events: ADDED "Event stream of a persisted job" and "No events for an interruption" (after a restart a persisted job still has an
    event stream: one `job.snapshot` with the last emitted `seq`, then close 1000).
- No new endpoint, no new or changed member, no changed status for an existing case.

## Impact
- Shared capabilities modified: `analysis-jobs-api`, `analysis-job-events` (additive only).
- backend: `Store` persistence boundary, SQLite implementation (pure Go), config, startup recovery, docs, tests.
- frontend: no change required. It treats `failed` jobs and unknown reasons / error codes generically
  (`src/job/useJob.ts` TERMINAL list, `src/job/Verdict.tsx`, unknown reasons are `availability: unavailable`).
- project: no new integration suite; backend repo-ci covers persistence and restart tests.

Based on backend @ 2ee817ed318928e5ecb2d6ce9aab822a7cc99f16, frontend @ 6a5eda5b3ffa6e3f3e3d875768bc6e2810999f73,
project @ 441ecbf96961128099af004da50a063f18b3345c, shared-specs @ 2463f0290862b5267cd298c35eb73d35b45e8f2c.
