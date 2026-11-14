## MODIFIED Requirements

### Requirement: Create job
`POST /api/v1/jobs` SHALL accept the body `{"input": Input, "analyzers": [<analyzer id>] (optional), "options": {"finalize": <boolean, default true>} (optional)}`, or the same body with `"scrape": ScrapeRequest` instead of `input`, and respond 201 with the created Job and the header `Location: /api/v1/jobs/{id}`. Scraping and analysis SHALL start asynchronously; the response MUST NOT wait for the scraper or any analyzer.

#### Scenario: Job created
- **WHEN** a client posts `{"input": {"content": "Some article text"}}`
- **THEN** the status is 201, the body is a Job with `status` `queued` or `running` and `done: false`, and every non-finalizer registry analyzer appears in `analyzers`

### Requirement: Create job validation
`POST /api/v1/jobs` SHALL reject a body larger than 1 MiB (1 048 576 bytes) with 413 `payload_too_large`, and SHALL respond 422 `validation_failed` for a missing or blank `input.content`, wrong member types, an unsupported `content_type`, an invalid `source.url` or `source.published_at`, duplicate ids in `analyzers`, or an invalid ScrapeRequest (Scrape request validation).

#### Scenario: Blank content
- **WHEN** a client posts `{"input": {"content": "   "}}`
- **THEN** the status is 422 with `error.code` `validation_failed`

### Requirement: Job object
The Job object SHALL have at least: `id`; `status`; `done` (boolean); `created_at`; `started_at` and `finished_at` (timestamp or null, `finished_at` set when `done` becomes true); `input` (Input with defaults applied; see Input of scrape jobs); `scrape` (Scrape object, or null for a job created with `input`); `options` with at least `finalize` (boolean); `analyzers` (array of AnalyzerRun); `coverage` (Coverage); `finalization` (Finalization).

#### Scenario: Fresh job
- **WHEN** a job has just been created
- **THEN** it has `done: false`, `finished_at: null` and `finalization.status` `pending` or `skipped`

#### Scenario: Text job has no scrape
- **WHEN** a job is created with `{"input": {"content": "hello"}}`
- **THEN** the job has `scrape: null`

### Requirement: Job status
Job `status` values SHALL include `queued` (nothing started), `scraping` (scrape running), `running`, `finalizing` (all AnalyzerRuns settled, finalization not yet ended), `completed` (all settled and finalization ended as `completed`, `failed` or `skipped`), `cancelled` and `failed` (orchestrator-internal error, or failed scrape). `done` SHALL be `true` if and only if status is `completed`, `cancelled` or `failed`. Analyzer or finalization failures SHALL NOT make the job `failed`.

#### Scenario: Analyzer failure does not fail the job
- **WHEN** one analyzer fails, the others succeed and finalization completes
- **THEN** the job ends with `status: completed` and `done: true`

#### Scenario: Scrape failure fails the job
- **WHEN** the scrape of a job ends `failed` with `error.code` `account_private`
- **THEN** the job ends with `status: failed` and `done: true`

### Requirement: Job analyzer list
`Job.analyzers` SHALL contain one AnalyzerRun per registry analyzer at job creation, excluding analyzers with trigger `after_all_analyzers_settled`, ordered by analyzer id. Disabled analyzers SHALL be `skipped` with reason `disabled`, analyzers whose applicability rules reject the input `skipped` with `not_applicable`, and unselected analyzers `skipped` with `not_selected`.

#### Scenario: Disabled analyzer listed
- **WHEN** the registry contains a disabled analyzer `legacy`
- **THEN** every new job lists `legacy` with `status: skipped` and `reason: disabled`

### Requirement: AnalyzerRun outcomes
`succeeded`, `failed` and `skipped` are settled states; a settled AnalyzerRun SHALL never change. For `skipped`, `reason` values include `disabled`, `not_selected`, `not_applicable`, `dependency_failed`, `dependency_skipped`, `cancelled`, `input_unavailable` (the job's scrape failed). For `failed`, `error` is `{"code", "message"}` with codes including `timeout`, `adapter_error`, `invalid_output`, `cancelled`. Otherwise `reason` and `error` are null.

#### Scenario: Settled run is immutable
- **WHEN** an analyzer has settled as `failed` and finalization later runs
- **THEN** the AnalyzerRun still has the same `status`, `error` and `finished_at`

## ADDED Requirements

### Requirement: ScrapeRequest object
A ScrapeRequest SHALL be `{"url": <absolute http(s) URL, at most 2048 characters, required>, "max_posts": <integer 1–100, default 20>, "max_comments": <integer 0–200, default 50>}`; the orchestrator passes it to the scraper (social-scraper-api) and does not check at creation whether the URL names a supported platform.

#### Scenario: Job created from a URL
- **WHEN** a client posts `{"scrape": {"url": "https://bsky.app/profile/alice.bsky.social/post/3kxyz"}}`
- **THEN** the status is 201 and the body is a Job with `status` `queued` or `scraping`, `done: false`, `input: null` and `scrape` `{"status": "pending" or "running", "url": "https://bsky.app/profile/alice.bsky.social/post/3kxyz", "max_posts": 20, "max_comments": 50, ...}`

### Requirement: Scrape request validation
`POST /api/v1/jobs` SHALL respond 422 `validation_failed` when both or neither of `input` and `scrape` are present (`details.fields` key `input`) or when `scrape.url`, `scrape.max_posts` or `scrape.max_comments` is missing where required, of the wrong type or out of range. It SHALL respond 503 `scrape_unavailable`, creating no job, for a body with `scrape` when the server has no scraper configured.

#### Scenario: Both input forms
- **WHEN** a client posts `{"input": {"content": "x"}, "scrape": {"url": "https://x.com/alice"}}`
- **THEN** the status is 422 with `error.code` `validation_failed` and `error.details.fields` has the key `input`

#### Scenario: Invalid scrape URL
- **WHEN** a client posts `{"scrape": {"url": "ftp://example.com/a"}}`
- **THEN** the status is 422 with `error.code` `validation_failed` and `error.details.fields` has the key `scrape.url`

#### Scenario: Scraper not configured
- **WHEN** the server has no scraper configured and a client posts `{"scrape": {"url": "https://x.com/alice"}}`
- **THEN** the status is 503 with `error.code` `scrape_unavailable` and no job is created

### Requirement: Input of scrape jobs
For a job created with `scrape`, `input` SHALL be null until the scrape has `succeeded` (Scraped input content) and SHALL stay null if the scrape fails or is cancelled.

#### Scenario: Input while scraping
- **WHEN** a job created with `scrape` has `status: scraping`
- **THEN** its `input` is null and its `scrape.url` is the requested URL

### Requirement: Analyzer list of scrape jobs
For a job created with `scrape`, `disabled` and `not_selected` skips SHALL be applied at creation and `not_applicable` only once the scrape has succeeded; every other AnalyzerRun SHALL stay `pending` while the job is `scraping`.

#### Scenario: Analyzers wait for the scrape
- **WHEN** a job created with `scrape` is `scraping`
- **THEN** every selected, enabled AnalyzerRun has `status: pending`

### Requirement: Scrape object
The Scrape object SHALL have at least: `status` (values include `pending`, `running`, `succeeded`, `failed`); `url`, `max_posts`, `max_comments` (the ScrapeRequest with defaults applied); `platform` and `url_kind` (strings as in social-scraper-api, null until the scrape succeeded); `error`; `warnings`; `started_at`, `finished_at` (timestamp or null); `duration_ms` (integer or null).

#### Scenario: Succeeded scrape
- **WHEN** the scraper returned a Bluesky post with its comments
- **THEN** the job's `scrape` has `status: succeeded`, `platform: bluesky`, `url_kind: post`, `error: null` and non-null `finished_at`

### Requirement: Scrape outcome members
`succeeded` and `failed` are settled Scrape states; a settled Scrape SHALL never change. `error` SHALL be `{"code", "message", "details" (optional)}` when `failed` and null otherwise. `warnings` SHALL be the ScrapeResult `warnings` when `succeeded` and `[]` otherwise.

#### Scenario: Warnings kept
- **WHEN** the scraper returned a post with the warning `comments_unavailable`
- **THEN** the job's `scrape.warnings` contains that warning and `scrape.error` is null

### Requirement: Scraped input content
When a job's scrape succeeds, the orchestrator SHALL set `Job.input` from the ScrapeResult (social-scraper-api) before any analyzer starts, with `content_type` `text/plain` and `content` the `post.text` for `url_kind: post`, or for `url_kind: profile` the non-empty `text` of `posts`, newest first, joined with `\n\n`. If that `content` is blank after trimming, the scrape SHALL fail with `error.code` `no_text_content` instead.

#### Scenario: Profile history as content
- **WHEN** a profile scrape returns posts with texts `B` (newest), `` and `A`
- **THEN** the job's `input.content` is `B\n\nA`

#### Scenario: Post without text
- **WHEN** the scraped post is an image with an empty caption
- **THEN** the scrape is `failed` with `error.code` `no_text_content` and the job ends `failed`

### Requirement: Scraped input source
For a scraped input, `source.url` SHALL be the requested URL, `source.platform` the ScrapeResult `platform`, `source.author` its `username`, `source.title` its `display_name` when not null, `source.published_at` the `post.created_at` when `url_kind` is `post` and it is not null, and `source.metadata` `{"scrape": <the ScrapeResult verbatim>}`. Analyzers that bind `$input` or `$input.source` (analyzer-service-protocol) thereby receive the profile, posting history and comments.

#### Scenario: Post URL mapped to input
- **WHEN** the scraper returns `url_kind: post`, `platform: mastodon`, `username: alice@mastodon.social` and `post.text` `Vote no!`
- **THEN** the job's `input` has `content: "Vote no!"`, `source.platform: mastodon`, `source.author: alice@mastodon.social` and `source.metadata.scrape` equal to the ScrapeResult

### Requirement: Scrape failure causes
A scrape SHALL fail when the scraper answers with an error, cannot be reached, answers with an invalid body, or does not answer within the server's scrape timeout. `Scrape.error.code` values include the scraper's error codes other than `unauthorized`, `invalid_request` and `validation_failed`, passed through with their `details`, and `no_text_content`, `scraper_unavailable`, `timeout` and `cancelled`. `error.message` MUST NOT contain the scraper's URL, its token or platform credentials.

#### Scenario: Scraper error passed through
- **WHEN** the scraper answers 403 `account_private` with `details.platform` `instagram`
- **THEN** the job's `scrape.error` has `code: account_private` and `details.platform: instagram`

### Requirement: Scraper unavailable
`Scrape.error.code` SHALL be `scraper_unavailable` when the scraper is unreachable, rejects the orchestrator's credentials (401), answers `invalid_request` or `validation_failed`, answers 500 `internal_error`, or answers with a body that is neither a valid ScrapeResult nor an error envelope.

#### Scenario: Scraper down
- **WHEN** the scraper service refuses connections
- **THEN** the job's `scrape.error.code` is `scraper_unavailable` and the job ends `failed`

### Requirement: Scrape failure outcomes
When a scrape fails other than by cancellation, every `pending` AnalyzerRun SHALL be `skipped` with reason `input_unavailable`, `finalization` SHALL be `skipped` with reason `input_unavailable`, the finalizer SHALL NOT be called (no insufficient-evidence assessment is produced), `input` SHALL stay null and the job SHALL end `failed`.

#### Scenario: Unsupported platform
- **WHEN** a job is created with `{"scrape": {"url": "https://example.com/article"}}`
- **THEN** the job ends `failed` with `scrape.error.code: unsupported_url`, every selected AnalyzerRun `skipped` with `input_unavailable` and `finalization` `skipped` with `input_unavailable`

### Requirement: Cancellation during scraping
Cancelling a job whose scrape is `pending` or `running` SHALL abort the scrape, set `scrape` to `failed` with `error.code` `cancelled`, make every `pending` AnalyzerRun `skipped` with `cancelled`, make `finalization` `skipped` with `cancelled`, and end the job `cancelled`.

#### Scenario: Cancel while scraping
- **WHEN** a client cancels a job with `status: scraping`
- **THEN** the response is 202 and the job reaches `status: cancelled` with `scrape.error.code: cancelled` and `input: null`
