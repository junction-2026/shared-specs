# analysis-jobs-api Specification

## Purpose
REST API of the analysis orchestrator for creating, listing, reading and cancelling content analysis jobs and for listing configured analyzers, including the job, analyzer-run, coverage, finalization and final-assessment objects shared with the event stream.

## Requirements

### Requirement: Input object
The Input object SHALL have at least: `content` (string, required, non-empty after trimming); `content_type` (string, default `text/plain`, values include `text/plain`, `text/markdown`, `text/html`); `source` (object, default `{}`) with optional `url` (absolute http(s) URL), `title`, `author`, `platform` (strings), `published_at` (timestamp) and `metadata` (free-form object kept verbatim).

#### Scenario: Defaults applied
- **WHEN** a job is created with `{"input": {"content": "hello"}}`
- **THEN** the job's `input` contains `"content": "hello"`, `"content_type": "text/plain"` and `"source": {}`

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

### Requirement: Analyzer selection
When `analyzers` is omitted, every analyzer is selected. When it is present (even empty), only the listed analyzers and their transitive dependencies are selected and every other analyzer SHALL be `skipped` with reason `not_selected`. Naming an unknown id SHALL yield 422 `unknown_analyzer` with `details.analyzer_ids`. Naming an analyzer with trigger `after_all_analyzers_settled` SHALL yield 422 `analyzer_not_selectable`. Naming a disabled analyzer is not an error.

#### Scenario: Selection pulls in dependencies
- **WHEN** analyzer `claims` depends on `entities` and a client posts `"analyzers": ["claims"]`
- **THEN** both `claims` and `entities` are selected and all other analyzers are `skipped` with reason `not_selected`

#### Scenario: Unknown analyzer
- **WHEN** a client posts `"analyzers": ["nope"]`
- **THEN** the status is 422 with `error.code` `unknown_analyzer` and `error.details.analyzer_ids` `["nope"]`

#### Scenario: Finalizer not selectable
- **WHEN** a client posts `"analyzers": ["final_synthesis"]`
- **THEN** the status is 422 with `error.code` `analyzer_not_selectable`

### Requirement: Job object
The Job object SHALL have at least: `id`; `status`; `done` (boolean); `created_at`; `started_at` and `finished_at` (timestamp or null, `finished_at` set when `done` becomes true); `input` (Input with defaults applied; see Input of scrape jobs); `scrape` (Scrape object, or null for a job created with `input`); `options` with at least `finalize` (boolean); `public` (boolean, see Job visibility); `analyzers` (array of AnalyzerRun); `coverage` (Coverage); `finalization` (Finalization).

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

### Requirement: AnalyzerRun object
The AnalyzerRun object SHALL have at least: `id`, `name`, `category` (strings); `depends_on` (array of ids); `status` (values include `pending`, `running`, `succeeded`, `failed`, `skipped`); `reason` and `error` (see AnalyzerRun outcomes); `started_at`, `finished_at` (timestamp or null); `duration_ms` (integer or null); `result` (the service's JSON object verbatim when `succeeded`, otherwise null).

#### Scenario: Succeeded run
- **WHEN** an analyzer service returns `{"score": 12}`
- **THEN** the AnalyzerRun has `status: succeeded`, `result: {"score": 12}`, `reason: null` and `error: null`

### Requirement: AnalyzerRun outcomes
`succeeded`, `failed` and `skipped` are settled states; a settled AnalyzerRun SHALL never change. For `skipped`, `reason` values include `disabled`, `not_selected`, `not_applicable`, `dependency_failed`, `dependency_skipped`, `cancelled`, `input_unavailable` (the job's scrape failed). For `failed`, `error` is `{"code", "message"}` with codes including `timeout`, `adapter_error`, `invalid_output`, `cancelled`. Otherwise `reason` and `error` are null.

#### Scenario: Settled run is immutable
- **WHEN** an analyzer has settled as `failed` and finalization later runs
- **THEN** the AnalyzerRun still has the same `status`, `error` and `finished_at`

### Requirement: Dependency and timeout semantics
An analyzer whose dependencies all `succeeded` SHALL run. One with a `failed` dependency SHALL be `skipped` with `dependency_failed`; one with a `skipped` dependency and no failed one SHALL be `skipped` with `dependency_skipped`. A running analyzer that exceeds its configured timeout SHALL be `failed` with `error.code` `timeout`.

#### Scenario: Failure propagation
- **WHEN** `entities` fails and `claims` depends on it
- **THEN** `claims` is `skipped` with `reason: dependency_failed` and `result: null`

#### Scenario: Timeout
- **WHEN** an analyzer with timeout 30s has not answered after 30s
- **THEN** it is `failed` with `error.code: timeout` and its dependents are `skipped` with `dependency_failed`

### Requirement: Coverage object
The Coverage object SHALL have at least the integer members `total` (number of AnalyzerRuns), `applicable` (runs not skipped with `disabled`, `not_selected` or `not_applicable`), `pending`, `running`, `succeeded`, `failed`, `skipped` (per status, summing to `total`) and `settled` (`succeeded + failed + skipped`).

#### Scenario: Counts are consistent
- **WHEN** a job has 5 analyzers of which 1 is `not_selected`, 2 succeeded, 1 failed and 1 is running
- **THEN** coverage is `total 5, applicable 4, succeeded 2, failed 1, skipped 1, running 1, pending 0, settled 4`

### Requirement: Finalization object
The Finalization object SHALL have at least: `status` (values include `pending`, `running`, `completed`, `failed`, `skipped`); `analyzer_id` (finalizer id, null when none configured); `reason`; `error`; `started_at`, `finished_at` (timestamp or null); `duration_ms` (integer or null); `result` (FinalAssessment when `completed`, otherwise null).

#### Scenario: Completed finalization
- **WHEN** the finalizer returned a valid assessment
- **THEN** `finalization` has `status: completed`, a non-null `result` and `error: null`

### Requirement: Finalization outcomes
For `skipped`, `reason` SHALL be one of values including `not_configured` (no enabled finalizer), `disabled_by_request` (`options.finalize` false) and `cancelled` (job cancelled before finalization started). For `failed`, `error` is `{"code", "message"}` with codes including `timeout`, `adapter_error`, `invalid_output`, `cancelled`. Otherwise `reason` and `error` are null.

#### Scenario: Finalization disabled by request
- **WHEN** a job is created with `"options": {"finalize": false}`
- **THEN** once all analyzers settle, `finalization` is `skipped` with `reason: disabled_by_request` and the job is `completed`

#### Scenario: Finalizer timeout
- **WHEN** the finalizer has timeout 60s and does not answer within 60s
- **THEN** `finalization.status` is `failed` with `error.code: timeout`

### Requirement: Finalization barrier and isolation
Finalization SHALL start only after every AnalyzerRun of the job is settled, regardless of how many failed or were skipped, SHALL run at most once per job even when analyzers settle concurrently, and SHALL NOT modify or remove any AnalyzerRun.

#### Scenario: Finalizer failure keeps results
- **WHEN** the finalizer service returns HTTP 500
- **THEN** `finalization.status` is `failed` with `error.code: adapter_error`, every AnalyzerRun keeps its `result`, and the job ends `completed`

### Requirement: FinalAssessment object
The FinalAssessment object SHALL have at least: `verdict` (see "Verdict values"); `confidence` (number 0–1, or null when the finalizer gave none); `user_text` (non-empty plain-language explanation for the end user); `produced_by` (`finalizer` or `orchestrator`); `usage` (token usage object reported by the finalizer adapter, or null); `attempts` and `retry_reason` (see "FinalAssessment retry members"); `wikipedia_quotes` (see "Wikipedia quotes in the final assessment").

#### Scenario: Risk assessment
- **WHEN** the `llm` finalizer's first reply is `{"verdict": "detected", "confidence": 0.86, "user_text": "This post shows signs of propaganda."}` and the provider reported `{"prompt_tokens": 512, "completion_tokens": 48, "total_tokens": 560}`
- **THEN** `finalization.result` is at least `{"verdict": "detected", "confidence": 0.86, "user_text": "This post shows signs of propaganda.", "produced_by": "finalizer", "usage": {"prompt_tokens": 512, "completion_tokens": 48, "total_tokens": 560}, "attempts": 1, "retry_reason": null, "wikipedia_quotes": []}`

#### Scenario: No confidence and no usage
- **WHEN** an `http_sync` finalizer returns `{"verdict": "uncertain", "user_text": "The analyzers disagree."}`
- **THEN** `finalization.result` has `confidence: null`, `usage: null`, `produced_by: finalizer`, `attempts: null`, `retry_reason: null` and `wikipedia_quotes: []`

### Requirement: Insufficient evidence without fabricated score
When finalization is enabled and configured but no AnalyzerRun that the finalizer would receive has `succeeded` (for the `llm` adapter, the analyzers opted in to LLM input; otherwise every AnalyzerRun), the orchestrator SHALL NOT call the finalizer and SHALL complete finalization with a FinalAssessment of at least `{"verdict": "uncertain", "confidence": null, "user_text": <non-empty fixed text>, "produced_by": "orchestrator", "usage": null, "attempts": null, "retry_reason": null}`.

#### Scenario: All analyzers failed
- **WHEN** every applicable analyzer of a job fails
- **THEN** `finalization.status` is `completed`, `result.verdict` is `uncertain`, `result.confidence` is `null`, `result.user_text` is non-empty, `result.produced_by` is `orchestrator` and `result.attempts` is `null`

#### Scenario: Only analyzers not sent to the LLM succeeded
- **WHEN** the finalizer uses the `llm` adapter, only `propaganda_detection` is opted in to LLM input, `propaganda_detection` fails and `text_stats` succeeds
- **THEN** the LLM provider receives no request, `analysis.finalizing` and `analysis.finalized` are emitted, and `finalization.result` has `verdict: uncertain` and `produced_by: orchestrator`

### Requirement: Get job
`GET /api/v1/jobs/{id}` SHALL respond 200 with the current Job object or 404 `not_found`. The returned state SHALL reflect every event already emitted for the job (analysis-job-events).

#### Scenario: Finalization visible over REST
- **WHEN** a job has emitted `analysis.finalized`
- **THEN** `GET /api/v1/jobs/{id}` returns `finalization.status: completed` with `finalization.result` set

### Requirement: List jobs
`GET /api/v1/jobs` SHALL return only jobs with `public: true` (Listing excludes non-public jobs), newest first (by `created_at`, ties by `id`), with cursor pagination, an optional `status` filter (unknown value: 400 `invalid_request`) and an optional search `q`. Each item SHALL be a JobSummary with at least `id`, `status`, `done`, `created_at`, `finished_at`, `coverage`, `excerpt` and `finalization` as `{"status", "verdict"}`, `verdict` being the FinalAssessment verdict or null.

#### Scenario: Filter by status
- **WHEN** a client calls `GET /api/v1/jobs?status=running`
- **THEN** every item has `status: running`

#### Scenario: Summary carries an excerpt
- **WHEN** a client calls `GET /api/v1/jobs` and a listed job was created with `{"input": {"content": "Some article text"}}`
- **THEN** its item has `excerpt: "Some article text"` besides the other JobSummary members

### Requirement: Cancel job
`POST /api/v1/jobs/{id}/cancel` (no body required) SHALL respond 202 with the Job and cancel it; the job then reaches `status: cancelled`, `done: true`. A job whose `done` is true SHALL yield 409 `job_finished`; an unknown id 404 `not_found`.

#### Scenario: Cancel finished job
- **WHEN** a client cancels a job with `status: completed`
- **THEN** the status is 409 with `error.code: job_finished`

### Requirement: Cancellation effects
On cancellation, pending analyzers SHALL become `skipped` with `cancelled`; running analyzers SHALL be aborted and become `failed` with `error.code` `cancelled`; a pending finalization SHALL become `skipped` with `cancelled`; a running finalization SHALL be aborted and become `failed` with `cancelled`. Already settled AnalyzerRuns and their results SHALL be kept.

#### Scenario: Cancel running job
- **WHEN** a client cancels a job with one succeeded and one running analyzer
- **THEN** the succeeded analyzer keeps its result, the running one becomes `failed` with `cancelled`, and the job reaches `status: cancelled`

### Requirement: List analyzers
`GET /api/v1/analyzers` SHALL respond 200 with `{"items": [...]}` (not paginated), one item per registry analyzer including the finalizer, ordered by id, each with at least `id`, `name`, `category`, `enabled`, `depends_on`, `trigger` (values include `on_dependencies_succeeded`, `after_all_analyzers_settled`) and `selectable` (false for `after_all_analyzers_settled`).

#### Scenario: Finalizer listed
- **WHEN** the registry contains finalizer `final_synthesis`
- **THEN** its item has `trigger: after_all_analyzers_settled` and `selectable: false`

### Requirement: Registry listing hides execution settings
Analyzer listing items MUST NOT contain endpoint URLs, headers, environment values or any other execution setting, because these can carry credentials. This is a deliberate exception to "at least these members": new members exposing execution settings SHALL NOT be added.

#### Scenario: Endpoint not exposed
- **WHEN** the finalizer is configured with `endpoint: ${FINALIZER_URL}`
- **THEN** no member of the analyzers response contains the endpoint value

#### Scenario: LLM settings not exposed
- **WHEN** the finalizer uses the `llm` adapter with `base_url`, `api_key`, `model` and `headers` configured
- **THEN** no member of the analyzers response contains any of these values

### Requirement: Verdict values
`verdict` SHALL be one of `detected` (at least one strong signal of propaganda or manipulation that the content supports), `not_detected` (no strong signal was found; weak hints may exist, see Weak hints and verdict) or `uncertain` (strong signals disagree, a decisive analyzer that applies to the text is unavailable, or there is no analyzer evidence). Clients SHALL treat an unknown `verdict` value like `uncertain`. JobSummary `finalization.verdict` takes the same values.

#### Scenario: Unknown verdict in a client
- **WHEN** a client receives a FinalAssessment with a `verdict` value it does not know
- **THEN** it presents the result as `uncertain`

### Requirement: Confidence semantics
`confidence` SHALL be the finalizer's own confidence that its `verdict` is supported by the available evidence, from 0 to 1. It is not the probability that the content is propaganda; clients MUST NOT present it as such or as a statistical probability. The orchestrator SHALL NOT compute or adjust `verdict` or `confidence`.

#### Scenario: Confidence kept as returned
- **WHEN** an analyzer returned `score: 0.97` and the finalizer returned `"verdict": "uncertain", "confidence": 0.4`
- **THEN** `finalization.result.confidence` is `0.4` and `verdict` is `uncertain`

### Requirement: User text rendering
`user_text` is model output influenced by untrusted content. Clients SHALL render it as plain text, without HTML or Markdown interpretation and without turning its contents into links, and SHALL NOT rely on a maximum length.

#### Scenario: Markup in user text
- **WHEN** `user_text` contains `<b>fake</b> [click](https://example.com)`
- **THEN** a client shows those characters literally and creates no link

### Requirement: Finalization errors hide credentials
`error.message` of a failed finalization MAY include the finalizer service's or LLM provider's own error text but MUST NOT contain credentials: API keys, `Authorization` header values or other configured secret values.

#### Scenario: Provider error without credentials
- **WHEN** the LLM provider answers HTTP 401 with a message that repeats the configured API key
- **THEN** `finalization.status` is `failed` with `error.code: adapter_error` and `error.message` does not contain the API key

### Requirement: ScrapeRequest object
A ScrapeRequest SHALL be `{"url": <absolute http(s) URL, at most 2048 characters, required>, "max_posts": <integer 1–100, default 20>, "max_comments": <integer 0–200, default 50>}`; the orchestrator passes it to the scraper (social-scraper-api) and does not check at creation whether the URL names a supported platform.

#### Scenario: Job created from a URL
- **WHEN** a client posts `{"scrape": {"url": "https://bsky.app/profile/alice.bsky.social/post/3kxyz"}}`
- **THEN** the status is 201 and the body is a Job with `status` `queued` or `scraping`, `done: false`, `input: null` and `scrape` `{"status": "pending" or "running", "url": "https://bsky.app/profile/alice.bsky.social/post/3kxyz", "max_posts": 20, "max_comments": 50, ...}`

### Requirement: Scrape request validation
`POST /api/v1/jobs` SHALL respond 422 `validation_failed` when both or neither of `input` and `scrape` are present (`details.fields` key `input`) or when `scrape.url`, `scrape.max_posts` or `scrape.max_comments` is missing where required, of the wrong type or out of range. It SHALL respond 503 `scrape_unavailable`, creating no job, for a body with `scrape` only when scraping is disabled in the server's configuration.

#### Scenario: Both input forms
- **WHEN** a client posts `{"input": {"content": "x"}, "scrape": {"url": "https://x.com/alice"}}`
- **THEN** the status is 422 with `error.code` `validation_failed` and `error.details.fields` has the key `input`

#### Scenario: Invalid scrape URL
- **WHEN** a client posts `{"scrape": {"url": "ftp://example.com/a"}}`
- **THEN** the status is 422 with `error.code` `validation_failed` and `error.details.fields` has the key `scrape.url`

#### Scenario: Scraper not configured
- **WHEN** the server has scraping disabled in its configuration and a client posts `{"scrape": {"url": "https://x.com/alice"}}`
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
When a job's scrape succeeds, the orchestrator SHALL set `Job.input` from the ScrapeResult (social-scraper-api) before any analyzer starts, with `content_type` `text/plain` and `content` the `post.text` for `url_kind: post`, the `text` for `url_kind: page`, or for `url_kind: profile` the non-empty `text` of `posts`, newest first, joined with `\n\n`. If that `content` is blank after trimming, the scrape SHALL fail with `error.code` `no_text_content` instead.

#### Scenario: Profile history as content
- **WHEN** a profile scrape returns posts with texts `B` (newest), `` and `A`
- **THEN** the job's `input.content` is `B\n\nA`

#### Scenario: Post without text
- **WHEN** the scraped post is an image with an empty caption
- **THEN** the scrape is `failed` with `error.code` `no_text_content` and the job ends `failed`

#### Scenario: Page text as content
- **WHEN** a `web` page scrape returns `text` `First paragraph.\nSecond paragraph.`
- **THEN** the job's `input.content` is `First paragraph.\nSecond paragraph.` and `input.content_type` is `text/plain`

### Requirement: Scraped input source
For a scraped input, `source.platform` SHALL be the ScrapeResult `platform` and `source.metadata` `{"scrape": <the ScrapeResult verbatim>}`. For `url_kind` `profile` and `post`, `source.url` SHALL be the requested URL, `source.author` the `username`, `source.title` the `display_name` when not null, and `source.published_at` the `post.created_at` of a `post` when not null. For `page`, see Scraped page source. Analyzers binding `$input` or `$input.source` thereby receive the scraped data.

#### Scenario: Post URL mapped to input
- **WHEN** the scraper returns `url_kind: post`, `platform: mastodon`, `username: alice@mastodon.social` and `post.text` `Vote no!`
- **THEN** the job's `input` has `content: "Vote no!"`, `source.platform: mastodon`, `source.author: alice@mastodon.social` and `source.metadata.scrape` equal to the ScrapeResult

### Requirement: Scrape failure causes
A scrape SHALL fail when the scraper yields a scrape error (social-scraper-api), yields a result that is not a valid ScrapeResult, or does not finish within the server's scrape timeout. `Scrape.error.code` values include the scraper's error codes other than `internal_error`, passed through with their `details`, and `no_text_content`, `scraper_unavailable`, `timeout` and `cancelled`. `error.message` and `error.details` MUST NOT contain tokens, cookies, API keys or other credentials.

#### Scenario: Scraper error passed through
- **WHEN** the scraper fails with `account_private` and `details.platform` `mastodon`
- **THEN** the job's `scrape.error` has `code: account_private` and `details.platform: mastodon`

#### Scenario: Facebook URL
- **WHEN** a job is created with `{"scrape": {"url": "https://www.facebook.com/examplenews"}}` and the page provider returns a login wall
- **THEN** the job ends `failed` with `scrape.error.code: login_required` and `scrape.error.details.platform: web`

#### Scenario: Unsupported social network URL
- **WHEN** a job is created with `{"scrape": {"url": "https://x.com/alice"}}` on a server whose page provider is not configured
- **THEN** the job ends `failed` with `scrape.error.code: platform_not_configured`, `scrape.error.details.platform: web` and every selected AnalyzerRun `skipped` with `input_unavailable`

#### Scenario: Login wall passed through
- **WHEN** a job scrapes `https://www.instagram.com/nasa/` and the page provider returns a login wall
- **THEN** the job ends `failed` with `scrape.error.code: login_required` and `scrape.error.details.platform: web`

#### Scenario: Unsupported URL
- **WHEN** a job is created with `{"scrape": {"url": "http://127.0.0.1/admin"}}` on a server with scraping enabled
- **THEN** the job ends `failed` with `scrape.error.code: unsupported_url`, every selected AnalyzerRun `skipped` with `input_unavailable`

### Requirement: Scraper unavailable
`Scrape.error.code` SHALL be `scraper_unavailable` when the scraper fails with `internal_error` (for example a panic in a platform module) or yields a result that is not a valid ScrapeResult (missing `platform` or `url_kind`, `url_kind: post` without `post`, or `url_kind: page` without a string `text`).

#### Scenario: Scraper down
- **WHEN** a platform module panics while scraping a job's URL
- **THEN** the job's `scrape.error.code` is `scraper_unavailable`, the job ends `failed` and the server keeps serving other jobs

### Requirement: Scrape failure outcomes
When a scrape fails other than by cancellation, every `pending` AnalyzerRun SHALL be `skipped` with reason `input_unavailable`, `finalization` SHALL be `skipped` with reason `input_unavailable`, the finalizer SHALL NOT be called (no insufficient-evidence assessment is produced), `input` SHALL stay null and the job SHALL end `failed`.

#### Scenario: Unsupported platform
- **WHEN** a job is created with `{"scrape": {"url": "http://localhost/article"}}`
- **THEN** the job ends `failed` with `scrape.error.code: unsupported_url`, every selected AnalyzerRun `skipped` with `input_unavailable` and `finalization` `skipped` with `input_unavailable`

### Requirement: Cancellation during scraping
Cancelling a job whose scrape is `pending` or `running` SHALL abort the scrape, set `scrape` to `failed` with `error.code` `cancelled`, make every `pending` AnalyzerRun `skipped` with `cancelled`, make `finalization` `skipped` with `cancelled`, and end the job `cancelled`.

#### Scenario: Cancel while scraping
- **WHEN** a client cancels a job with `status: scraping`
- **THEN** the response is 202 and the job reaches `status: cancelled` with `scrape.error.code: cancelled` and `input: null`

### Requirement: Scraping available by default
Scraping SHALL be available by default in the backend, with no separately running scraper service or scraper-specific configuration.

#### Scenario: Single backend scrapes
- **WHEN** a backend started without scraper-specific configuration receives `{"scrape": {"url": "https://bsky.app/profile/alice.bsky.social"}}`
- **THEN** the status is 201 and the job's scrape runs inside that backend

### Requirement: AnalyzerRun availability
The AnalyzerRun object SHALL additionally have `availability` (string or null) and `note` (string or null). `availability` values include `ran` (produced a result), `not_applicable` (nothing to check in this input, or not requested) and `unavailable` (failed, cancelled or not set up). Both SHALL be null while the run is `pending` or `running`; a `succeeded` run SHALL have `ran` and `note: null`. Existing AnalyzerRun members keep their meaning.

#### Scenario: Unsettled run
- **WHEN** an analyzer is `running`
- **THEN** its AnalyzerRun has `availability: null` and `note: null`

#### Scenario: Succeeded run availability
- **WHEN** an analyzer has `succeeded`
- **THEN** its AnalyzerRun has `availability: ran` and `note: null`

### Requirement: Availability note text
`note` SHALL be a short fixed English sentence intended for display. Clients SHALL NOT parse it, and its wording may change without a contract change. Clients SHALL treat an unknown `availability` value like `unavailable`.

#### Scenario: Unknown availability value
- **WHEN** a client receives an AnalyzerRun with an `availability` value it does not know
- **THEN** it presents the run as unavailable

### Requirement: Nothing-to-check skips
A `skipped` run SHALL have `availability: not_applicable` and this `note`, by `reason`:
- `no_checkable_claims`: "Not run: the text contains no specific factual claims to check."
- `no_searchable_topics`: "Not run: the text names no concrete topics or events to search news coverage for."
- `no_sources`: "Not run: there were no news articles or page URL to look up."

#### Scenario: No checkable claims
- **WHEN** `fact_check` is `skipped` with `no_checkable_claims`
- **THEN** it has `availability: not_applicable`, `note` "Not run: the text contains no specific factual claims to check." and still `reason: no_checkable_claims`

### Requirement: Input and selection skips
A `skipped` run SHALL have `availability: not_applicable` and this `note`, by `reason`:
- `not_applicable`: "Not run: this analyzer does not apply to this kind of input."
- `not_selected` or `disabled`: "Not run: this analyzer was not requested for this job."

#### Scenario: Not selected
- **WHEN** a job was created with `"analyzers": ["claims"]` and `legacy` is `skipped` with `not_selected`
- **THEN** `legacy` has `availability: not_applicable` and `note` "Not run: this analyzer was not requested for this job."

### Requirement: Unavailable runs
A `failed` run with any `error.code`, and a `skipped` run whose reason is `dependency_failed`, `cancelled`, `input_unavailable` or any reason not listed in "Nothing-to-check skips", "Input and selection skips" or "Dependency-skipped availability", SHALL have `availability: unavailable` and `note` "Unavailable: the analyzer failed or is not set up, so its result is missing."

#### Scenario: Failed dependency
- **WHEN** `news_search` is `failed` with `error.code: adapter_error` and `source_info` is `skipped` with `dependency_failed`
- **THEN** both have `availability: unavailable` and the unavailable note

#### Scenario: Unknown reason
- **WHEN** an analyzer is `skipped` with a reason not listed in this spec
- **THEN** it has `availability: unavailable`

### Requirement: Dependency-skipped availability
A run `skipped` with `dependency_skipped` SHALL take the `availability` and `note` of its root skip: the first id in its `depends_on` whose run is `skipped`, followed again while that run's reason is `dependency_skipped`. After 8 steps, or when no skipped dependency exists, it SHALL be `unavailable` with the unavailable note.

#### Scenario: No checkable content
- **WHEN** `topic_extraction` succeeded with no topics and no claims, `fact_check` is `skipped` with `no_checkable_claims`, `news_search` is `skipped` with `no_searchable_topics` and `source_info` (depending on `news_search`) is `skipped` with `dependency_skipped`
- **THEN** `GET /api/v1/jobs/{id}` shows `availability: not_applicable` for all three, `source_info.note` equals `news_search.note`, and every run keeps its `status` and `reason`

### Requirement: Availability stability
`availability` and `note` SHALL be set when the run settles and SHALL then never change. They SHALL be identical wherever the AnalyzerRun appears: `Job.analyzers` of every endpoint returning a Job, `data.analyzer` of `analyzer.*` events and the `$job.analyzers` binding.

#### Scenario: Same values in the event
- **WHEN** `fact_check` settles as `skipped` with `no_checkable_claims`
- **THEN** the `analyzer.skipped` event's `data.analyzer` has the same `availability` and `note` as the run in `GET /api/v1/jobs/{id}`

### Requirement: FinalAssessment retry members
`attempts` SHALL be an integer, the number of LLM requests that produced replies for an `llm` finalizer (1 or 2), and null when no LLM call was made (`produced_by: orchestrator`, `http_sync` and `http_async` finalizers). `retry_reason` SHALL be a string or null as defined in "LLM reply retry members". The orchestrator SHALL set both itself, never from the finalizer output. Clients SHALL treat an absent member (older results) as null.

#### Scenario: Output members named attempts and retry_reason
- **WHEN** an `http_sync` finalizer returns `{"verdict": "detected", "user_text": "...", "attempts": 5, "retry_reason": "x"}`
- **THEN** the stored result has `attempts: null` and `retry_reason: null`

#### Scenario: Older stored result
- **WHEN** a client reads a FinalAssessment stored before this change, without `attempts` and `retry_reason`
- **THEN** the client treats both as null

### Requirement: LLM reply retry
When an `llm` finalizer's first 2xx provider answer (after the existing 429/5xx retry) has an invalid reply, the orchestrator SHALL send exactly one more request and use its reply instead, unless the deployment disabled reply retry (enabled by default). A reply is invalid when it is cut off (`finish_reason` `length`), its content is empty or not a JSON object after removing a code fence, or it fails "Finalizer response validation".

#### Scenario: Prose reply retried
- **WHEN** the first reply's content is plain prose and the second reply is a valid FinalAssessment output
- **THEN** the provider receives two chat completion requests and finalization is `completed` with `attempts: 2` and `retry_reason: "invalid_json"`

#### Scenario: Schema mismatch retried
- **WHEN** the first reply is `{"verdict": "detected", "confidence": 0.9}` without `user_text` and the second reply is valid
- **THEN** finalization is `completed` with `attempts: 2` and `retry_reason: "schema"`

### Requirement: LLM reply retry exclusions
The orchestrator SHALL NOT send a reply retry for a refusal (non-empty `message.refusal`), a `finish_reason` of `content_filter`, a provider answer with a 4xx status other than 429, a timeout or a cancellation, or when less than the deployment's minimum remaining time of the finalizer's timeout is left. It SHALL send at most one reply retry per finalization.

#### Scenario: Refusal not retried
- **WHEN** the first reply has a non-empty `message.refusal`
- **THEN** the provider receives exactly one chat completion request and finalization is `failed` with `error.code: invalid_output`

#### Scenario: Client error not retried
- **WHEN** the provider answers the first request with HTTP 400
- **THEN** the provider receives exactly one request and finalization is `failed` with `error.code: adapter_error`

### Requirement: LLM reply retry members
For an `llm` finalizer, `attempts` SHALL be 2 when a reply retry was sent and 1 otherwise. `retry_reason` SHALL be null when no reply retry was sent, and otherwise one of values including `length` (first reply cut off), `invalid_json` (empty content or not a JSON object) and `schema` (a JSON object failing "Finalizer response validation"). Clients SHALL treat an unknown `retry_reason` value as "retried for another reason".

#### Scenario: First reply valid
- **WHEN** the first reply is a valid FinalAssessment output
- **THEN** `finalization.result` has `attempts: 1` and `retry_reason: null`

### Requirement: LLM reply retry usage
When a reply retry was sent, `usage` SHALL combine both attempts' provider usage reports: each numeric member is the sum of that member in both reports, nested objects are combined the same way, a member present in only one report keeps that value, and a non-numeric member takes the retry's value. `usage` SHALL be null only when neither attempt reported usage.

#### Scenario: Cut-off reply retried
- **WHEN** the first reply has `finish_reason: "length"` and usage `{"prompt_tokens": 900, "completion_tokens": 600, "total_tokens": 1500, "cost": 0.0012}`, and the second reply is `{"verdict": "detected", "confidence": 0.7, "user_text": "..."}` with `finish_reason: "stop"` and usage `{"prompt_tokens": 950, "completion_tokens": 300, "total_tokens": 1250, "cost": 0.0010}`
- **THEN** `finalization.result` is at least `{"verdict": "detected", "confidence": 0.7, "user_text": "...", "produced_by": "finalizer", "attempts": 2, "retry_reason": "length", "usage": {"prompt_tokens": 1850, "completion_tokens": 900, "total_tokens": 2750, "cost": 0.0022}}`

#### Scenario: Only the retry reported usage
- **WHEN** the first reply had no `usage` and the retry reported `{"total_tokens": 400}`
- **THEN** `finalization.result.usage` is `{"total_tokens": 400}`

### Requirement: LLM reply retry failure
When the retry's reply is invalid too, finalization SHALL be `failed` with `error.code` `invalid_output` and `result: null`, as for any invalid finalizer output; `error.message` is free text naming both reasons.

#### Scenario: Both replies invalid
- **WHEN** the first and the second reply are both plain prose
- **THEN** finalization is `failed` with `error.code: invalid_output`, `finalization.result` is null, every AnalyzerRun keeps its result and the job ends `completed`

### Requirement: Scraped page source
For a scraped input with `url_kind: page`, `source.url` SHALL be the ScrapeResult `canonical_url` when it is not null and its registered domain equals the ScrapeResult `domain`, otherwise its `final_url`. `source.title`, `source.author` and `source.published_at` SHALL be the ScrapeResult `title`, `author` and `published_at` when not null, and absent otherwise.

#### Scenario: Page mapped to input
- **WHEN** a job scrapes `https://www.dw.com/en/some-article/a-12345678?utm_source=x` and the ScrapeResult has `canonical_url` `https://www.dw.com/en/some-article/a-12345678`, `domain` `dw.com`, `title` `Election results`, `author` `Jane Doe` and `published_at` `2026-11-13T07:30:00Z`
- **THEN** the job's `input.source` has `url: "https://www.dw.com/en/some-article/a-12345678"`, `platform: web`, `title: "Election results"`, `author: "Jane Doe"`, `published_at: "2026-11-13T07:30:00Z"` and `metadata.scrape` equal to the ScrapeResult

#### Scenario: Canonical URL on another domain ignored
- **WHEN** a page fetched with `final_url` `https://copycat.example/story` declares `canonical_url` `https://www.dw.com/en/story/a-1`
- **THEN** the job's `input.source.url` is `https://copycat.example/story`, so `source_info.page_outlet` is looked up for `copycat.example`

#### Scenario: Outlet of a news page
- **WHEN** a job scrapes a `dw.com` article and the deployment's outlet table lists `dw.com` as Deutsche Welle
- **THEN** `source_info.page_outlet` is the Deutsche Welle outlet (source-info-result)

### Requirement: Weak hints and verdict
Weak hints alone, such as `weak` technique Detections or low-confidence findings, SHALL NOT make a verdict `uncertain`; without a strong signal the verdict is `not_detected` and the hints only lower `confidence`.

#### Scenario: Only weak hints
- **WHEN** the only signals of a job are `weak` technique Detections and a propaganda classifier result of no propaganda
- **THEN** a conforming finalizer answers `not_detected`, possibly with lower `confidence`, not `uncertain`

### Requirement: Job history persistence
A deployment MAY keep job history persistently. When it does, every job SHALL survive a server restart: `GET /api/v1/jobs/{id}` SHALL then return the same Job as before the restart, every member included and each AnalyzerRun `result` and `finalization.result` verbatim with unknown members preserved, except for the changes made by "Jobs interrupted by a restart". Without persistent history, jobs are lost on restart as before.

#### Scenario: Finished job after a restart
- **WHEN** a job completed with results from `techniques`, `fact_check` and `news_search` and a finalization, and the server is restarted
- **THEN** `GET /api/v1/jobs/{id}` returns the Job with the same `status`, timestamps, `analyzers` (each `result` equivalent JSON, unknown members included) and `finalization.result`

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

### Requirement: Wikipedia quotes in the final assessment
`wikipedia_quotes` of a FinalAssessment SHALL be an array of WikipediaQuote objects, empty when the finalizer kept none, when `produced_by` is `orchestrator` and when the job has no succeeded `wikipedia` AnalyzerRun. A WikipediaQuote SHALL have at least `claim` (a ClaimLookup `claim`), `language` (a WikiLookup `language`), `quote` (string), and `title`, `url`, `revision_id` and `coverage`, which the orchestrator copies from that WikiLookup.

#### Scenario: Assessment without Wikipedia
- **WHEN** the job has no `wikipedia` AnalyzerRun, or finalization is produced by the orchestrator
- **THEN** `finalization.result.wikipedia_quotes` is `[]`

### Requirement: Wikipedia quotes in persisted and interrupted jobs
With persistent history ("Job history persistence"), `wikipedia_quotes` SHALL be returned after a restart unchanged from when the job finalized; the orchestrator SHALL NOT re-verify or change it. A finalization ended by "Interrupted parts" has `result` null and therefore no `wikipedia_quotes`.

#### Scenario: Quotes after a restart
- **WHEN** a job finalized with one kept WikipediaQuote and the server is restarted
- **THEN** `GET /api/v1/jobs/{id}` returns `finalization.result.wikipedia_quotes` with that same entry

#### Scenario: Finalization interrupted
- **WHEN** the server stops while a job's finalization is `running` and starts again
- **THEN** `finalization.status` is `failed` with `error.code: interrupted`, `finalization.result` is null and no Wikipedia quotation is shown

### Requirement: Wikipedia quote verification
The orchestrator SHALL keep a finalizer-proposed quote only when the job's succeeded `wikipedia` AnalyzerRun has a ClaimLookup with an equal `claim` holding a WikiLookup with an equal `language`, `status` `found` and a `coverage` other than `no_coverage` (see "Unverifiable evidence"), whose `passage` contains the proposed `quote`, trimmed and non-empty, as a substring. It SHALL store the trimmed text and drop every other proposed quote without failing finalization.

#### Scenario: Valid quote kept
- **WHEN** the job's `wikipedia` result has a ClaimLookup `claim: "Angela Merkel became chancellor in 2006."` with an `en` WikiLookup `status: "found"`, `coverage: "conflicts"`, `title: "Angela Merkel"`, `revision_id: 1250000000` and a `passage` containing "Chancellor of Germany from 2005 to 2021", and the finalizer returns `"wikipedia_quotes": [{"claim": "Angela Merkel became chancellor in 2006.", "language": "en", "quote": " Chancellor of Germany from 2005 to 2021 "}]`
- **THEN** `finalization.result.wikipedia_quotes` is at least `[{"claim": "Angela Merkel became chancellor in 2006.", "language": "en", "quote": "Chancellor of Germany from 2005 to 2021", "title": "Angela Merkel", "url": "<the WikiLookup url>", "revision_id": 1250000000, "coverage": "conflicts"}]`

#### Scenario: Paraphrase dropped
- **WHEN** the finalizer proposes a quote "Merkel took office in 2005" that is not a substring of the cited `passage`
- **THEN** the quote is not in `finalization.result.wikipedia_quotes`, and finalization is `completed` with the finalizer's `verdict` and `user_text`

#### Scenario: Quote from an uncovered entry dropped
- **WHEN** the finalizer quotes a substring of a `passage` whose WikiLookup has `coverage: "no_coverage"`
- **THEN** the quote is dropped

### Requirement: Wikipedia quotes for clients
Clients SHALL treat an absent `wikipedia_quotes` (results stored before this member existed) as an empty array, SHALL render `quote`, `claim` and `title` as plain text, and SHALL present only `wikipedia_quotes` entries and `term_context` EncyclopediaQuote objects (term-context-result) as quotations from Wikipedia. Within the final assessment, only `wikipedia_quotes` entries SHALL be presented as quotations from Wikipedia.

#### Scenario: Stored assessment without quotes
- **WHEN** a client reads a FinalAssessment without `wikipedia_quotes`
- **THEN** it shows no Wikipedia quotation in the final assessment

#### Scenario: Term context encyclopedia quote
- **WHEN** a job's `term_context` result has a TermContext whose `encyclopedia` is an EncyclopediaQuote
- **THEN** the client may present its `quote` as a quotation from Wikipedia with its `url`, outside the final assessment, while the final assessment still shows only `wikipedia_quotes` entries

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

### Requirement: Job risk member
The Job object SHALL also have `risk`: the job's RiskScore (manipulation-risk-score), or null until every AnalyzerRun is settled (see "When the risk score is computed" and "Jobs without a risk score" there). It SHALL be the same in `GET /api/v1/jobs/{id}` and in every event's `data.job`. Clients SHALL treat a missing `risk` member like `risk: null`.

#### Scenario: Fresh job
- **WHEN** a job has just been created
- **THEN** it has `risk: null`

#### Scenario: Completed job has a risk score
- **WHEN** a job ends `completed`
- **THEN** `GET /api/v1/jobs/{id}` returns it with a non-null `risk` whose `status` is `scored` or `unavailable`

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
