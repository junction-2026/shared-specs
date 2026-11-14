## MODIFIED Requirements

### Requirement: Create job
`POST /api/v1/jobs` SHALL accept the body `{"input": Input, "analyzers": [<analyzer id>] (optional), "options": {"finalize": <boolean, default true>} (optional), "public": <boolean, default true> (optional)}`, or the same body with `"scrape": ScrapeRequest` instead of `input`, and respond 201 with the created Job and the header `Location: /api/v1/jobs/{id}`. Scraping and analysis SHALL start asynchronously; the response MUST NOT wait for the scraper or any analyzer.

#### Scenario: Job created
- **WHEN** a client posts `{"input": {"content": "Some article text"}}`
- **THEN** the status is 201, the body is a Job with `status` `queued` or `running`, `done: false` and `public: true`, and every non-finalizer registry analyzer appears in `analyzers`

#### Scenario: Non-public job created
- **WHEN** a client posts `{"input": {"content": "Some article text"}, "public": false}`
- **THEN** the status is 201, the body is a Job with `public: false`, and the job is analysed like a public job

#### Scenario: Non-public scrape job created
- **WHEN** a client posts `{"scrape": {"url": "https://bsky.app/profile/alice.bsky.social/post/3kxyz"}, "public": false}`
- **THEN** the status is 201 and the body is a Job with `public: false` and `scrape.url` the requested URL

### Requirement: Create job validation
`POST /api/v1/jobs` SHALL reject a body larger than 1 MiB (1 048 576 bytes) with 413 `payload_too_large`, and SHALL respond 422 `validation_failed` for a missing or blank `input.content`, wrong member types, an unsupported `content_type`, an invalid `source.url` or `source.published_at`, duplicate ids in `analyzers`, an invalid ScrapeRequest (Scrape request validation), or a `public` member that is present and is not `true` or `false` (`null` included), with `details.fields` key `public`.

#### Scenario: Blank content
- **WHEN** a client posts `{"input": {"content": "   "}}`
- **THEN** the status is 422 with `error.code` `validation_failed`

#### Scenario: Invalid public flag
- **WHEN** a client posts `{"input": {"content": "x"}, "public": "no"}` or `{"input": {"content": "x"}, "public": null}`
- **THEN** the status is 422 with `error.code` `validation_failed`, `error.details.fields` has the key `public`, and no job is created

### Requirement: Job object
The Job object SHALL have at least: `id`; `status`; `done` (boolean); `created_at`; `started_at` and `finished_at` (timestamp or null, `finished_at` set when `done` becomes true); `input` (Input with defaults applied; see Input of scrape jobs); `scrape` (Scrape object, or null for a job created with `input`); `options` with at least `finalize` (boolean); `public` (boolean, see Job visibility); `analyzers` (array of AnalyzerRun); `coverage` (Coverage); `finalization` (Finalization).

#### Scenario: Fresh job
- **WHEN** a job has just been created
- **THEN** it has `done: false`, `finished_at: null` and `finalization.status` `pending` or `skipped`

#### Scenario: Text job has no scrape
- **WHEN** a job is created with `{"input": {"content": "hello"}}`
- **THEN** the job has `scrape: null`

### Requirement: List jobs
`GET /api/v1/jobs` SHALL return only jobs with `public: true` (Listing excludes non-public jobs), newest first (by `created_at`, ties by `id`), with cursor pagination and an optional `status` filter (an unknown value yields 400 `invalid_request`). Each item SHALL be a JobSummary with at least `id`, `status`, `done`, `created_at`, `finished_at`, `coverage` and `finalization` as `{"status", "verdict"}`, where `verdict` is the FinalAssessment verdict or null.

#### Scenario: Filter by status
- **WHEN** a client calls `GET /api/v1/jobs?status=running`
- **THEN** every item has `status: running`

### Requirement: Persisted jobs in listing and cancel
With persistent history, `GET /api/v1/jobs` SHALL include persisted jobs with `public: true` with the same JobSummary, ordering (newest first by `created_at`, ties by `id`), `status` filter, cursor pagination and exclusion of non-public jobs as live jobs. `POST /api/v1/jobs/{id}/cancel` on a persisted done job SHALL yield 409 `job_finished`.

#### Scenario: Listing after a restart
- **WHEN** three public jobs exist and the server is restarted
- **THEN** `GET /api/v1/jobs?limit=2` returns the two newest with a non-null `next_cursor`, and following it returns the third

#### Scenario: Non-public job after a restart
- **WHEN** a job created with `"public": false` exists and the server is restarted
- **THEN** `GET /api/v1/jobs/{id}` returns it with `public: false` and `GET /api/v1/jobs` does not list it

#### Scenario: Cancel a persisted finished job
- **WHEN** a client cancels a job that completed before the restart
- **THEN** the status is 409 with `error.code: job_finished`

## ADDED Requirements

### Requirement: Job visibility
A job's `public` member SHALL be the value given at creation, `true` when the create body omits it, and SHALL NOT change afterwards; no endpoint changes it. A job stored before this member existed SHALL be reported with `public: true` and listed like other public jobs. `public: false` means unlisted, not secret: it SHALL NOT add authentication or access control, and anyone who knows the job id can read it.

#### Scenario: Default is public
- **WHEN** a client creates a job without a `public` member
- **THEN** the Job has `public: true` and `GET /api/v1/jobs` lists it

#### Scenario: Job stored before the member existed
- **WHEN** a deployment with persistent history upgrades and reads a job stored without `public`
- **THEN** `GET /api/v1/jobs/{id}` returns it with `public: true` and `GET /api/v1/jobs` lists it

### Requirement: Listing excludes non-public jobs
`GET /api/v1/jobs` SHALL leave out jobs with `public: false` before paging, with and without the `status` filter: `limit` and `next_cursor` SHALL count public jobs only, so a page holds `limit` items whenever at least that many matching public jobs follow the cursor, and `next_cursor` SHALL be null when no matching public job follows.

#### Scenario: Non-public jobs not listed
- **WHEN** jobs A (public), B (`public: false`) and C (public) were created in that order and a client calls `GET /api/v1/jobs`
- **THEN** the items are C then A, and B appears in no page with or without a `status` filter

#### Scenario: Paging skips non-public jobs
- **WHEN** jobs P1, P2, P3 (public) and U1, U2 (`public: false`) were created interleaved and a client calls `GET /api/v1/jobs?limit=2`
- **THEN** the first page holds the two newest public jobs with a non-null `next_cursor`, following it returns the remaining public job with `next_cursor: null`, and no page holds U1 or U2

### Requirement: Unlisted jobs by id
`GET /api/v1/jobs/{id}`, `POST /api/v1/jobs/{id}/cancel` and `GET /api/v1/jobs/{id}/events` (analysis-job-events) SHALL behave for a job with `public: false` the same as for a public job; the Job they return or carry (including `data.job` of `job.snapshot` and the terminal events) SHALL have `public: false`.

#### Scenario: Read an unlisted job by URL
- **WHEN** a client that did not create a job with `public: false` calls `GET /api/v1/jobs/{id}` for it
- **THEN** the status is 200 and the body is the Job with `public: false`

#### Scenario: Follow an unlisted job
- **WHEN** a client connects to `GET /api/v1/jobs/{id}/events` of a running job with `public: false`
- **THEN** it receives `job.snapshot` with `data.job.public: false` and every later event of the job as for a public job

#### Scenario: Cancel an unlisted job
- **WHEN** a client cancels a running job with `public: false`
- **THEN** the status is 202 and the job reaches `status: cancelled`
