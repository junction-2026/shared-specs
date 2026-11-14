## ADDED Requirements

### Requirement: Job history persistence
A deployment MAY keep job history persistently. When it does, every job SHALL survive a server restart: `GET /api/v1/jobs/{id}` SHALL then return the same Job as before the restart, every member included and each AnalyzerRun `result` and `finalization.result` verbatim with unknown members preserved, except for the changes made by "Jobs interrupted by a restart". Without persistent history, jobs are lost on restart as before.

#### Scenario: Finished job after a restart
- **WHEN** a job completed with results from `techniques`, `fact_check` and `news_search` and a finalization, and the server is restarted
- **THEN** `GET /api/v1/jobs/{id}` returns the Job with the same `status`, timestamps, `analyzers` (each `result` equivalent JSON, unknown members included) and `finalization.result`

### Requirement: Persisted jobs in listing and cancel
With persistent history, `GET /api/v1/jobs` SHALL include persisted jobs with the same JobSummary, ordering (newest first by `created_at`, ties by `id`), `status` filter and cursor pagination as live jobs. `POST /api/v1/jobs/{id}/cancel` on a persisted done job SHALL yield 409 `job_finished`.

#### Scenario: Listing after a restart
- **WHEN** three jobs exist and the server is restarted
- **THEN** `GET /api/v1/jobs?limit=2` returns the two newest with a non-null `next_cursor`, and following it returns the third

#### Scenario: Cancel a persisted finished job
- **WHEN** a client cancels a job that completed before the restart
- **THEN** the status is 409 with `error.code: job_finished`

### Requirement: History retention
With persistent history, a done job SHALL stay readable through `GET /api/v1/jobs`, `GET /api/v1/jobs/{id}` and its event stream until the deployment's history retention removes it. By default history SHALL be kept; the server's in-memory job retention SHALL NOT remove persisted jobs from these endpoints. A removed job yields 404 `not_found`.

#### Scenario: Beyond the working-set retention
- **WHEN** a job finished longer ago than the server's in-memory job retention and no history retention is configured
- **THEN** `GET /api/v1/jobs/{id}` still returns it

### Requirement: Jobs interrupted by a restart
When a deployment with persistent history starts and finds a persisted job whose `done` is false, it SHALL end that job before serving requests with `status` `failed`, `done: true` and `finished_at` the server start time. The job SHALL NOT be resumed or re-run. Settled AnalyzerRuns, a settled Scrape and an ended finalization SHALL keep every member, including `result`. `coverage` SHALL be recomputed.

#### Scenario: Interrupted job ends failed
- **WHEN** the server stops while a job has `status: running` and starts again
- **THEN** the job has `status: failed`, `done: true` and a non-null `finished_at`, and `GET /api/v1/jobs?status=running` does not list it

### Requirement: Interrupted parts
When a job is ended by "Jobs interrupted by a restart", every `pending` AnalyzerRun SHALL become `skipped` with reason `interrupted`, every `running` AnalyzerRun `failed` with `error.code` `interrupted`, a `pending` or `running` Scrape `failed` with `error.code` `interrupted`, a `pending` finalization `skipped` with reason `interrupted` and a `running` one `failed` with `error.code` `interrupted`, `result` null.

#### Scenario: Restart while analyzers run
- **WHEN** the server stops while a job has `techniques` succeeded, `fact_check` running and `news_search` pending, and then starts again
- **THEN** `techniques` is unchanged with its `result`, `fact_check` is `failed` with `error.code: interrupted`, `news_search` is `skipped` with `reason: interrupted` and `availability: unavailable`, and `finalization` is `skipped` with `reason: interrupted`

#### Scenario: Restart while scraping
- **WHEN** the server stops while a job has `status: scraping`
- **THEN** after the restart the job is `failed` with `scrape.error.code: interrupted`, `input: null` and every pending AnalyzerRun `skipped` with `reason: interrupted`

#### Scenario: Restart while finalizing
- **WHEN** the server stops while a job has `status: finalizing` with finalization `running`
- **THEN** after the restart `finalization.status` is `failed` with `error.code: interrupted`, `finalization.result` is null and every AnalyzerRun keeps its result

### Requirement: Interrupted part timing
An AnalyzerRun, Scrape or finalization changed by "Interrupted parts" SHALL get `finished_at` the server start time and `duration_ms` measured from its `started_at`, or null when `started_at` is null. Its `availability` and `note` SHALL follow "Unavailable runs" and SHALL then never change.

#### Scenario: Pending run timing
- **WHEN** a `pending` AnalyzerRun becomes `skipped` with `interrupted`
- **THEN** it has `started_at: null`, `duration_ms: null`, a non-null `finished_at` and `availability: unavailable`
