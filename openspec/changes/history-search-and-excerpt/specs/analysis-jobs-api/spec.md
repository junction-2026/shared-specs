## MODIFIED Requirements

### Requirement: List jobs
`GET /api/v1/jobs` SHALL return only jobs with `public: true` (Listing excludes non-public jobs), newest first (by `created_at`, ties by `id`), with cursor pagination, an optional `status` filter (unknown value: 400 `invalid_request`) and an optional search `q`. Each item SHALL be a JobSummary with at least `id`, `status`, `done`, `created_at`, `finished_at`, `coverage`, `excerpt` and `finalization` as `{"status", "verdict"}`, `verdict` being the FinalAssessment verdict or null.

#### Scenario: Filter by status
- **WHEN** a client calls `GET /api/v1/jobs?status=running`
- **THEN** every item has `status: running`

#### Scenario: Summary carries an excerpt
- **WHEN** a client calls `GET /api/v1/jobs` and a listed job was created with `{"input": {"content": "Some article text"}}`
- **THEN** its item has `excerpt: "Some article text"` besides the other JobSummary members

## ADDED Requirements

### Requirement: Job list search
`GET /api/v1/jobs` SHALL accept the optional query parameter `q`. After trimming leading and trailing white space, an empty `q` (or none) SHALL NOT filter. A non-empty `q` SHALL list only jobs where it occurs as a substring of at least one of: `id`, `input.content` (when `input` is not null) or `scrape.url` (when `scrape` is not null).

#### Scenario: Match by text
- **WHEN** public jobs A with content "The Minister said X" and B with content "Weather today" exist and a client calls `GET /api/v1/jobs?q=minister`
- **THEN** the items hold A and not B

#### Scenario: Match by id
- **WHEN** a client calls `GET /api/v1/jobs?q=<part of a public job's id>`
- **THEN** that job is among the items

#### Scenario: Match by scrape URL
- **WHEN** a public scrape job has `scrape.url` `https://example.com/news/42` and a client calls `GET /api/v1/jobs?q=example.com/news`
- **THEN** that job is among the items

#### Scenario: Blank query
- **WHEN** a client calls `GET /api/v1/jobs?q=%20%20`
- **THEN** the response equals that of `GET /api/v1/jobs`

### Requirement: Job list search matching
`q` matching SHALL ignore case, comparing both sides after Unicode lowercase mapping, and SHALL treat every character literally: no wildcards, operators or word splitting. A `q` longer than 200 characters (Unicode code points) after trimming SHALL yield 400 `invalid_request`.

#### Scenario: Case ignored beyond ASCII
- **WHEN** a public job has content "ÄRZTE warnen" and a client calls `GET /api/v1/jobs?q=ärzte`
- **THEN** that job is among the items

#### Scenario: Literal characters
- **WHEN** a client calls `GET /api/v1/jobs?q=%25` (`q` is `%`) and no job id, content or scrape URL contains `%`
- **THEN** the response is 200 with `items: []` and `next_cursor: null`

#### Scenario: Query too long
- **WHEN** a client calls `GET /api/v1/jobs` with a `q` of 201 characters
- **THEN** the status is 400 with `error.code` `invalid_request`

### Requirement: Job list search scope
The `q` filter SHALL cover the whole listed history: live jobs and, with persistent history, every persisted public job not yet removed by History retention, not only recent jobs. Non-public jobs SHALL NOT be listed for any `q`, including their full id.

#### Scenario: Persisted job found after a restart
- **WHEN** a public job containing "needle" completed and the server is restarted
- **THEN** `GET /api/v1/jobs?q=needle` lists it

#### Scenario: Non-public job not found by search
- **WHEN** a job with `public: false` contains "needle" and a client calls `GET /api/v1/jobs?q=needle` or `GET /api/v1/jobs?q=<its id>`
- **THEN** that job is in no page

### Requirement: Job list search paging
`q` SHALL combine with `status` (both must hold) and, like `status` and the exclusion of non-public jobs, SHALL be applied before paging: `limit` and `next_cursor` count matching jobs only, a page holds `limit` items whenever at least that many matching jobs follow the cursor, and `next_cursor` is null when none follows. Ordering stays newest first. A client following `next_cursor` SHALL send the same `q` and `status`.

#### Scenario: Match beyond the first page
- **WHEN** 25 public jobs exist, only the oldest contains "needle" in `input.content`, and a client calls `GET /api/v1/jobs?q=needle&limit=20`
- **THEN** the response holds only that job and `next_cursor: null`

#### Scenario: Paging through matches
- **WHEN** 3 of 30 public jobs contain "needle" and a client calls `GET /api/v1/jobs?q=needle&limit=2`
- **THEN** the first page holds the two newest matching jobs with a non-null `next_cursor`, and following it with `q=needle` returns the third with `next_cursor: null`

#### Scenario: Search with status
- **WHEN** a completed and a failed public job both contain "needle" and a client calls `GET /api/v1/jobs?q=needle&status=failed`
- **THEN** the items hold only the failed job

### Requirement: JobSummary excerpt
JobSummary `excerpt` SHALL be the first 200 characters (Unicode code points) of the job's `input.content` when `input` is not null and its content is non-empty, otherwise the first 200 characters of `scrape.url` when `scrape` is not null, otherwise null. It SHALL be copied verbatim: no whitespace change and no ellipsis. `GET /api/v1/jobs/{id}` and the Job object are unchanged.

#### Scenario: Long content cut
- **WHEN** a listed job's `input.content` has 500 characters
- **THEN** its item's `excerpt` equals the first 200 characters of `input.content`

#### Scenario: Scrape job without input
- **WHEN** a listed scrape job is `scraping` or failed scraping, with `input: null` and `scrape.url` `https://bsky.app/profile/alice.bsky.social/post/3kxyz`
- **THEN** its item's `excerpt` is `https://bsky.app/profile/alice.bsky.social/post/3kxyz`

#### Scenario: Persisted job
- **WHEN** a public job was stored before this member existed and the server is restarted
- **THEN** its item in `GET /api/v1/jobs` has `excerpt` built from its stored `input.content` or `scrape.url`

### Requirement: JobSummary excerpt for clients
`excerpt` is untrusted content: clients SHALL render it as plain text, without HTML or Markdown interpretation and without turning it into links. Clients SHALL treat a missing `excerpt` member like `excerpt: null`. A client can tell an excerpt was cut only when it has 200 characters.

#### Scenario: Markup in an excerpt
- **WHEN** an item has `excerpt` `<b>hi</b> [x](https://example.com)`
- **THEN** a client shows those characters literally and creates no link

#### Scenario: Server without excerpts
- **WHEN** an item has no `excerpt` member
- **THEN** a client handles it like `excerpt: null`
