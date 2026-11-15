## MODIFIED Requirements

### Requirement: List jobs
`GET /api/v1/jobs` SHALL return only jobs with `public: true` (Listing excludes non-public jobs), newest first (by `created_at`, ties by `id`), with cursor pagination and the optional filters `status` (unknown value: 400 `invalid_request`), `q` and `language`. Each item SHALL be a JobSummary with at least `id`, `status`, `done`, `created_at`, `finished_at`, `coverage`, `excerpt`, `language` and `finalization` as `{"status", "verdict"}`, `verdict` being the FinalAssessment verdict or null.

#### Scenario: Filter by status
- **WHEN** a client calls `GET /api/v1/jobs?status=running`
- **THEN** every item has `status: running`

#### Scenario: Summary carries an excerpt
- **WHEN** a client calls `GET /api/v1/jobs` and a listed job was created with `{"input": {"content": "Some article text"}}`
- **THEN** its item has `excerpt: "Some article text"` besides the other JobSummary members

## ADDED Requirements

### Requirement: Job list language filter
`GET /api/v1/jobs` SHALL accept the optional query parameter `language`. After trimming leading and trailing white space, an empty `language` (or none) SHALL NOT filter. A code SHALL list only jobs whose job language (JobSummary language) equals that code; `unknown` SHALL list only jobs whose job language is null. A well-formed code that no job has SHALL give 200 with `items: []`.

#### Scenario: Filter by a language
- **WHEN** public jobs A (succeeded `translation` with `source_language: "de"`) and B (`source_language: "en"`) exist and a client calls `GET /api/v1/jobs?language=de`
- **THEN** the items hold A and not B, and A's item has `language: "de"`

#### Scenario: Unknown language
- **WHEN** public jobs exist with no `translation` run, with a failed or skipped one, with a succeeded one whose `source_language` is null or `"german"`, and with `source_language: "fr"`, and a client calls `GET /api/v1/jobs?language=unknown`
- **THEN** the items hold every job except the French one, each with `language: null`

#### Scenario: Job whose translation has not settled
- **WHEN** a public job's `translation` run is `pending` or `running`
- **THEN** its item has `language: null` and it is listed for `language=unknown`, not for any code

#### Scenario: Blank language
- **WHEN** a client calls `GET /api/v1/jobs?language=%20`
- **THEN** the response equals that of `GET /api/v1/jobs`

#### Scenario: Code with no jobs
- **WHEN** no job has language `zz` and a client calls `GET /api/v1/jobs?language=zz`
- **THEN** the status is 200 with `items: []` and `next_cursor: null`

### Requirement: Job list language values
A non-empty trimmed `language` SHALL be compared case-insensitively and SHALL be either a two-letter ISO 639-1 code (`^[a-z]{2}$` after lower-casing) or `unknown`; any other value SHALL yield 400 `invalid_request`. The server SHALL NOT require the code to be an assigned ISO 639-1 code.

#### Scenario: Case and white space ignored
- **WHEN** a client calls `GET /api/v1/jobs?language=%20DE%20`
- **THEN** the response equals that of `GET /api/v1/jobs?language=de`

#### Scenario: Malformed language
- **WHEN** a client calls `GET /api/v1/jobs` with `language` `deu`, `de-AT`, `german`, `d` or `null`
- **THEN** the status is 400 with `error.code` `invalid_request`

### Requirement: Job list language paging
`language` SHALL combine with `status`, `q` and the exclusion of non-public jobs (all must hold) and, like them, SHALL be applied before paging: `limit` and `next_cursor` count matching jobs only, a page holds `limit` items whenever at least that many matching jobs follow the cursor, and `next_cursor` is null when none follows. Ordering stays newest first. A client following `next_cursor` SHALL send the same `language`, `q` and `status`.

#### Scenario: Paging through a language
- **WHEN** 3 of 30 public jobs have language `de`, the oldest of them created first, and a client calls `GET /api/v1/jobs?language=de&limit=2`
- **THEN** the first page holds the two newest German jobs with a non-null `next_cursor`, and following it with `language=de` returns the third with `next_cursor: null`

#### Scenario: Language with search and status
- **WHEN** public jobs all containing "needle" exist: German completed, German failed and French failed, and a client calls `GET /api/v1/jobs?language=de&q=needle&status=failed`
- **THEN** the items hold only the German failed job

#### Scenario: Non-public job not listed by language
- **WHEN** a job with `public: false` has language `de` and a client calls `GET /api/v1/jobs?language=de`
- **THEN** that job is in no page

### Requirement: Job list language scope
The `language` filter SHALL cover the whole listed history, like `q` (Job list search scope): live jobs and, with persistent history, every persisted public job not yet removed by History retention, including jobs stored before the `language` filter existed, whose language SHALL be derived from their stored `translation` run in the same way.

#### Scenario: Job stored before the filter existed
- **WHEN** a deployment with persistent history upgrades and holds a public job stored earlier whose `translation` run succeeded with `source_language: "ru"`
- **THEN** `GET /api/v1/jobs?language=ru` lists it with `language: "ru"`, and a stored job without a succeeded `translation` run is listed for `language=unknown`

### Requirement: JobSummary language
JobSummary `language` SHALL be the job language: the value `$job.source_language` resolves to for the job (analyzer-service-protocol "Source language binding source"), a lower-case two-letter code or null. It SHALL be null while the job's `translation` run is not settled and SHALL NOT change once that run has succeeded. `GET /api/v1/jobs/{id}` and the Job object are unchanged.

#### Scenario: Normalized code
- **WHEN** a listed job's `translation` run succeeded with `{"source_language": "RU", "translated_text": "..."}`
- **THEN** its item has `language: "ru"`

#### Scenario: Interrupted translation
- **WHEN** the server stops while a job's `translation` run is running and, after the restart, the run is `failed` with `error.code: interrupted`
- **THEN** its item has `language: null`

### Requirement: JobSummary language for clients
Clients SHALL treat a missing JobSummary `language` member like `language: null` (unknown) and SHALL accept any string value, showing a code they have no name for as the code itself. A client SHALL send `language` only as a two-letter code or `unknown`.

#### Scenario: Server without languages
- **WHEN** an item has no `language` member
- **THEN** a client handles it like `language: null`
