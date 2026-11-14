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
`POST /api/v1/jobs` SHALL accept the body `{"input": Input, "analyzers": [<analyzer id>] (optional), "options": {"finalize": <boolean, default true>} (optional)}`, or the same body with `"scrape": ScrapeRequest` instead of `input`, and respond 201 with the created Job and the header `Location: /api/v1/jobs/{id}`. Scraping and analysis SHALL start asynchronously; the response MUST NOT wait for the scraper or any analyzer.

#### Scenario: Job created
- **WHEN** a client posts `{"input": {"content": "Some article text"}}`
- **THEN** the status is 201, the body is a Job with `status` `queued` or `running` and `done: false`, and every non-finalizer registry analyzer appears in `analyzers`

### Requirement: Create job validation
`POST /api/v1/jobs` SHALL reject a body larger than 1 MiB (1 048 576 bytes) with 413 `payload_too_large`, and SHALL respond 422 `validation_failed` for a missing or blank `input.content`, wrong member types, an unsupported `content_type`, an invalid `source.url` or `source.published_at`, duplicate ids in `analyzers`, or an invalid ScrapeRequest (Scrape request validation).

#### Scenario: Blank content
- **WHEN** a client posts `{"input": {"content": "   "}}`
- **THEN** the status is 422 with `error.code` `validation_failed`

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
The FinalAssessment object SHALL have at least: `verdict` (see "Verdict values"); `confidence` (number 0–1, or null when the finalizer gave none); `user_text` (non-empty plain-language explanation for the end user); `produced_by` (`finalizer` or `orchestrator`); `usage` (token usage object reported by the finalizer adapter, or null).

#### Scenario: Risk assessment
- **WHEN** the finalizer returns `{"verdict": "detected", "confidence": 0.86, "user_text": "This post shows signs of propaganda."}` and the provider reported `{"prompt_tokens": 512, "completion_tokens": 48, "total_tokens": 560}`
- **THEN** `finalization.result` is at least `{"verdict": "detected", "confidence": 0.86, "user_text": "This post shows signs of propaganda.", "produced_by": "finalizer", "usage": {"prompt_tokens": 512, "completion_tokens": 48, "total_tokens": 560}}`

#### Scenario: No confidence and no usage
- **WHEN** an `http_sync` finalizer returns `{"verdict": "uncertain", "user_text": "The analyzers disagree."}`
- **THEN** `finalization.result` has `confidence: null`, `usage: null` and `produced_by: finalizer`

### Requirement: Insufficient evidence without fabricated score
When finalization is enabled and configured but no AnalyzerRun that the finalizer would receive has `succeeded` (for the `llm` adapter, the analyzers opted in to LLM input; otherwise every AnalyzerRun), the orchestrator SHALL NOT call the finalizer and SHALL complete finalization with `{"verdict": "uncertain", "confidence": null, "user_text": <non-empty fixed text>, "produced_by": "orchestrator", "usage": null}`.

#### Scenario: All analyzers failed
- **WHEN** every applicable analyzer of a job fails
- **THEN** `finalization.status` is `completed`, `result.verdict` is `uncertain`, `result.confidence` is `null`, `result.user_text` is non-empty and `result.produced_by` is `orchestrator`

#### Scenario: Only analyzers not sent to the LLM succeeded
- **WHEN** the finalizer uses the `llm` adapter, only `propaganda_detection` is opted in to LLM input, `propaganda_detection` fails and `text_stats` succeeds
- **THEN** the LLM provider receives no request, `analysis.finalizing` and `analysis.finalized` are emitted, and `finalization.result` has `verdict: uncertain` and `produced_by: orchestrator`

### Requirement: Get job
`GET /api/v1/jobs/{id}` SHALL respond 200 with the current Job object or 404 `not_found`. The returned state SHALL reflect every event already emitted for the job (analysis-job-events).

#### Scenario: Finalization visible over REST
- **WHEN** a job has emitted `analysis.finalized`
- **THEN** `GET /api/v1/jobs/{id}` returns `finalization.status: completed` with `finalization.result` set

### Requirement: List jobs
`GET /api/v1/jobs` SHALL return jobs newest first (by `created_at`, ties by `id`) with cursor pagination and an optional `status` filter (an unknown value yields 400 `invalid_request`). Each item SHALL be a JobSummary with at least `id`, `status`, `done`, `created_at`, `finished_at`, `coverage` and `finalization` as `{"status", "verdict"}`, where `verdict` is the FinalAssessment verdict or null.

#### Scenario: Filter by status
- **WHEN** a client calls `GET /api/v1/jobs?status=running`
- **THEN** every item has `status: running`

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
`verdict` SHALL be one of `detected` (the analyzers give clear evidence of propaganda or manipulation in the content), `not_detected` (they clearly indicate none) or `uncertain` (evidence is weak, mixed, contradictory or missing). Clients SHALL treat an unknown `verdict` value like `uncertain`. JobSummary `finalization.verdict` takes the same values.

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
A scrape SHALL fail when the scraper yields a scrape error (social-scraper-api), yields a result that is not a valid ScrapeResult, or does not finish within the server's scrape timeout. `Scrape.error.code` values include the scraper's error codes other than `internal_error`, passed through with their `details`, and `no_text_content`, `scraper_unavailable`, `timeout` and `cancelled`. `error.message` MUST NOT contain tokens, cookies or other platform credentials.

#### Scenario: Scraper error passed through
- **WHEN** the scraper fails with `account_private` and `details.platform` `instagram`
- **THEN** the job's `scrape.error` has `code: account_private` and `details.platform: instagram`

#### Scenario: Facebook URL
- **WHEN** a job is created with `{"scrape": {"url": "https://www.facebook.com/examplenews"}}`
- **THEN** the job ends `failed` with `scrape.error.code: unsupported_url`

### Requirement: Scraper unavailable
`Scrape.error.code` SHALL be `scraper_unavailable` when the scraper fails with `internal_error` (for example a panic in a platform module) or yields a result that is not a valid ScrapeResult (missing `platform` or `url_kind`, or `url_kind: post` without `post`).

#### Scenario: Scraper down
- **WHEN** a platform module panics while scraping a job's URL
- **THEN** the job's `scrape.error.code` is `scraper_unavailable`, the job ends `failed` and the server keeps serving other jobs

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
