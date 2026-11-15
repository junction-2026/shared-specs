# public-analysis-api Specification

## Purpose
Unauthenticated public API for platforms and news outlets: submit a post, comments or both (or a URL) as one analysis job of the existing pipeline, and poll a stable, flattened JSON summary of its result.

## Requirements

### Requirement: Public analysis endpoints
The orchestrator SHALL serve `POST /api/v1/public/analyses` (submit) and `GET /api/v1/public/analyses/{id}` (get). Both SHALL follow api-conventions (base path, JSON, error envelope, tolerant reader) and SHALL NOT require or check any API key, bearer token, cookie, session or other credential; credential headers SHALL be ignored. Other methods on these paths SHALL yield 405 `method_not_allowed`.

#### Scenario: No credentials needed
- **WHEN** a client without any `Authorization` header or cookie posts `{"post": "Some post text"}` to `/api/v1/public/analyses`
- **THEN** the status is 201

#### Scenario: Wrong method
- **WHEN** a client sends `DELETE /api/v1/public/analyses/{id}`
- **THEN** the status is 405 with `error.code` `method_not_allowed`

### Requirement: Submit request members
The submit body SHALL be a JSON object with the optional members `post` (string), `text` (string, alias of `post`), `comments` (string, or array of at most 100 strings), `url` (absolute `http`/`https` URL, at most 2048 characters) and `public` (boolean, default `true`, as in analysis-jobs-api "Job visibility"). A `null` member SHALL be treated as absent and unknown members ignored. A string `comments` SHALL count as a one-element array.

#### Scenario: Comments as a single string
- **WHEN** a client posts `{"comments": "Nice try, liar"}`
- **THEN** the job is created as for `{"comments": ["Nice try, liar"]}`

#### Scenario: Unknown member ignored
- **WHEN** a client posts `{"post": "x", "api_key": "abc"}`
- **THEN** the status is 201 and `api_key` has no effect

### Requirement: Submit content rules
A post, text or comment SHALL be blank when it is empty after trimming white space. A request SHALL have content when it has a non-blank `post`, `text` or comment, or a `url`. `post` and `text` SHALL NOT both be present, and `url` SHALL NOT be combined with a non-blank `post`, `text` or comment: `url` is the alternative to pasted text.

#### Scenario: Blank comments only
- **WHEN** a client posts `{"comments": ["", " "]}`
- **THEN** the request has no content

### Requirement: Submit validation order
The submit endpoint SHALL answer the first case that applies, in this order: create rate limit exceeded: 429 (Public rate limits); body over 1 MiB (1 048 576 bytes): 413 `payload_too_large`; empty body (zero bytes or only white space), invalid JSON or a non-object: 400 `invalid_request`; a member violation (Submit member violations): 422 `validation_failed`; no content: 400 `missing_content`; `url` only while scraping is disabled: 503 `scrape_unavailable`. None of these SHALL create a job.

#### Scenario: Empty body
- **WHEN** a client posts an empty body to `/api/v1/public/analyses`
- **THEN** the status is 400 with `error.code` `invalid_request` and no job is created

#### Scenario: No content
- **WHEN** a client posts `{}`, `{"post": "   "}`, `{"comments": []}` or `{"comments": ["", " "]}`
- **THEN** the status is 400 with `error.code` `missing_content` and no job is created

#### Scenario: Body too large
- **WHEN** a client posts a body of 2 MiB
- **THEN** the status is 413 with `error.code` `payload_too_large`

#### Scenario: Type error before missing content
- **WHEN** a client posts `{"post": 5}`
- **THEN** the status is 422 with `error.code` `validation_failed`, not 400

### Requirement: Submit member violations
422 `validation_failed` SHALL carry `details.fields` keyed by member path for: `post`, `text` or `url` not a string; `comments` neither a string nor an array, or with more than 100 elements (key `comments`); a non-string element (key `comments[<index>]`); `post` and `text` both present (key `text`); `url` not an absolute `http`/`https` URL of at most 2048 characters, or combined with pasted text (key `url`); `public` not a boolean (key `public`).

#### Scenario: Wrong element type
- **WHEN** a client posts `{"comments": ["ok", 5]}`
- **THEN** the status is 422 with `error.code` `validation_failed` and `error.details.fields` has the key `comments[1]`

#### Scenario: Too many comments
- **WHEN** a client posts `comments` with 101 strings
- **THEN** the status is 422 and `error.details.fields` has the key `comments`

#### Scenario: Post and text together
- **WHEN** a client posts `{"post": "a", "text": "b"}`
- **THEN** the status is 422 and `error.details.fields` has the key `text`

#### Scenario: URL with pasted text
- **WHEN** a client posts `{"post": "a", "url": "https://example.com/x"}`
- **THEN** the status is 422 and `error.details.fields` has the key `url`

### Requirement: One job per request
A valid submit SHALL create exactly one job through the existing job pipeline and store (analysis-jobs-api), with every analyzer selected (as when `analyzers` is omitted), `options.finalize: true` and `public` as requested. It SHALL respond 201 with the job's PublicAnalysis and `Location: /api/v1/public/analyses/{id}`, without waiting for the scraper or any analyzer.

#### Scenario: Post and three comments
- **WHEN** a client posts `{"post": "P", "comments": ["A", "B", "C"]}`
- **THEN** exactly one job is created, the response is 201 with a PublicAnalysis whose `id` is that job's id, `status` `queued` or `running` and `done: false`, and `Location` is `/api/v1/public/analyses/<id>`

### Requirement: Public-API jobs are ordinary jobs
A job created through the submit endpoint SHALL be readable through `GET /api/v1/jobs/{id}` and `GET /api/v1/jobs/{id}/events` like any job, and listed by `GET /api/v1/jobs` unless it has `public: false`.

#### Scenario: Same job through the jobs API
- **WHEN** a job was created through `POST /api/v1/public/analyses`
- **THEN** `GET /api/v1/jobs/{id}` returns it with `options.finalize: true` and every non-finalizer registry analyzer in `analyzers`

#### Scenario: Unlisted public-API job
- **WHEN** a client posts `{"post": "P", "public": false}`
- **THEN** the job has `public: false` and `GET /api/v1/jobs` does not list it

### Requirement: Composed input content
The job's `input.content_type` SHALL be `text/plain`. With a non-blank post and no non-blank comment, `input.content` SHALL be the post exactly as sent. Otherwise it SHALL be these blocks joined by `\n\n`: `Post:\n` plus the trimmed post when the post is non-blank, then per non-blank comment in request order `Comment <n>:\n` plus the trimmed comment, `<n>` counting non-blank comments from 1. Blank comments SHALL be dropped.

#### Scenario: Post only is verbatim
- **WHEN** a client posts `{"post": "  Vote no!\n"}`
- **THEN** the job's `input.content` is `"  Vote no!\n"`

#### Scenario: Post and comments
- **WHEN** a client posts `{"text": " Vote no! ", "comments": ["  Agreed", "", "Liar!"]}`
- **THEN** the job's `input.content` is `"Post:\nVote no!\n\nComment 1:\nAgreed\n\nComment 2:\nLiar!"`

#### Scenario: Comments only
- **WHEN** a client posts `{"comments": "Agreed"}`
- **THEN** the job's `input.content` is `"Comment 1:\nAgreed"`

### Requirement: Public-API input metadata
For pasted text, the job's `input.source` SHALL be `{"metadata": {"public_api": {"has_post": <boolean>, "comment_count": <number of non-blank comments>}}}`, a member of the free-form `source.metadata` object of analysis-jobs-api "Input object".

#### Scenario: Counts recorded
- **WHEN** a client posts `{"text": "Vote no!", "comments": ["Agreed", "", "Liar!"]}`
- **THEN** `input.source.metadata.public_api` is `{"has_post": true, "comment_count": 2}`

### Requirement: URL submissions
With `url` only, the job SHALL be created as analysis-jobs-api creates `{"scrape": {"url": <url>}}` (ScrapeRequest defaults), and its input comes from the scrape as there.

#### Scenario: URL only
- **WHEN** a client posts `{"url": "https://bsky.app/profile/alice.bsky.social/post/3kxyz"}` and scraping is enabled
- **THEN** the job has `scrape.url` that URL with `max_posts: 20` and `max_comments: 50`, and `input` is null while scraping

### Requirement: Get analysis
`GET /api/v1/public/analyses/{id}` SHALL respond 200 with the PublicAnalysis of the job with that id, whichever endpoint created it and whatever its `public` value, or 404 `not_found` for an unknown id. It SHALL reflect the job's current state in the job store, like `GET /api/v1/jobs/{id}`, so a client can poll until `done` is `true`.

#### Scenario: Unknown id
- **WHEN** a client calls `GET /api/v1/public/analyses/does-not-exist`
- **THEN** the status is 404 with `error.code` `not_found`

#### Scenario: Polling a running job
- **WHEN** a client reads a job whose analyzers are still running
- **THEN** the status is 200 with `done: false`, `status` `running`, the job's current `coverage` and `result: null`

#### Scenario: Job created in the UI
- **WHEN** a client reads the id of a job created through `POST /api/v1/jobs`
- **THEN** the status is 200 with that job's PublicAnalysis

### Requirement: PublicAnalysis object
A PublicAnalysis SHALL have at least: `id`, `status`, `done`, `created_at`, `finished_at` and `coverage` (as in the Job); `input` (`{"content": <Job.input.content or null>, "url": <Job.scrape.url or null>}`); `finalization_status` (the Job's `finalization.status`); `result`; `techniques`; `bot_signal`; `evidence`; `error`; `share_url`. Every member SHALL be present in every response, also while the job runs.

#### Scenario: Fresh job
- **WHEN** a job has just been created from `{"post": "P"}`
- **THEN** its PublicAnalysis has `done: false`, `finished_at: null`, `input` `{"content": "P", "url": null}`, `result: null`, `techniques: null`, `bot_signal: null`, `error: null` and `evidence` `{"fact_checks": null, "news": null, "wikipedia": null}`

### Requirement: PublicAnalysis derivation
Every PublicAnalysis member SHALL be derived only from the stored Job, with values copied unchanged from the source objects named in this capability; reading SHALL NOT call an analyzer, model or external service. A summary SHALL appear as soon as its AnalyzerRun has `succeeded`, also before the job is done.

#### Scenario: Partial summaries while finalizing
- **WHEN** a job is `finalizing` and its `bot_detection` run has succeeded
- **THEN** its PublicAnalysis has a non-null `bot_signal` and `result: null`

### Requirement: PublicResult object
`result` SHALL be null unless the Job's `finalization.status` is `completed`; then it SHALL be at least `{"verdict", "confidence", "user_text", "produced_by"}` copied from `finalization.result`. Their meaning is that of analysis-jobs-api "Verdict values", "Confidence semantics" and "User text rendering": unknown `verdict` reads as `uncertain`, `confidence` is not a propaganda probability, and `user_text` is plain text.

#### Scenario: Completed analysis
- **WHEN** the job's finalization completed with `{"verdict": "detected", "confidence": 0.86, "user_text": "This post shows signs of propaganda.", "produced_by": "finalizer", ...}`
- **THEN** the PublicAnalysis has `finalization_status: completed` and `result` at least `{"verdict": "detected", "confidence": 0.86, "user_text": "This post shows signs of propaganda.", "produced_by": "finalizer"}`

#### Scenario: Finalization failed
- **WHEN** the job is `completed` and its finalization `failed` with `error.code: timeout`
- **THEN** the PublicAnalysis has `done: true`, `finalization_status: failed` and `result: null`, and its other summaries are still filled from the analyzer runs

### Requirement: Techniques summary
`techniques` SHALL be null while neither the `techniques` nor the `llm_techniques` AnalyzerRun has `succeeded`; otherwise an array, possibly empty, holding first one PublicTechnique per Detection of the `techniques` result's `detected`, in that order, then one per LlmTechniqueFinding of the `llm_techniques` result's `findings`, in that order.

#### Scenario: Nothing detected
- **WHEN** `techniques` succeeded with an empty `detected` and `llm_techniques` succeeded with no findings
- **THEN** `techniques` is `[]`

#### Scenario: No technique analysis
- **WHEN** both `techniques` and `llm_techniques` are `failed`, `skipped` or missing
- **THEN** `techniques` is null

### Requirement: PublicTechnique object
A PublicTechnique SHALL have at least `source` (`classifier` or `llm`), `label` (Detection `name` or finding `label`), `name` (Detection `display` or finding `name`), `score` (classifier: the highest TechniqueScore `score` of the label among the ModelResults in the Detection's `models`; llm: the finding's `confidence`), `strength` (Detection `strength`, else null) and `spans`.

#### Scenario: Classifier detection with a span
- **WHEN** `techniques` succeeded with `detected` holding `Doubt` (`display` `Doubt`, `models: ["nci-technique"]`, `strength: "strong"`, one span `{start: 0, end: 12, text: "Is it true?!"}`), its `nci-technique` score is 0.71, and `llm_techniques` is `skipped`
- **THEN** `techniques` is `[{"source": "classifier", "label": "Doubt", "name": "Doubt", "score": 0.71, "strength": "strong", "spans": [{"field": "content", "start": 0, "end": 12, "text": "Is it true?!"}]}]` (at least these members)

### Requirement: PublicTechnique spans
`spans` SHALL be an array of `{"field", "start", "end", "text"}`: for `classifier` one per TechniqueSpan of the Detection with `field: "content"`, for `llm` the finding's one `span`. Offsets SHALL be those of the source objects: UTF-16 offsets into `input.content`, or into the job's `source.title` for `field: "title"`.

#### Scenario: LLM finding
- **WHEN** `llm_techniques` succeeded with a `statistical_cherry_picking` finding, `confidence` 0.6, span `{field: "content", text: "90%", start: 10, end: 13}`
- **THEN** `techniques` has an entry with `source: "llm"`, `label: "statistical_cherry_picking"`, `score: 0.6`, `strength: null` and `spans: [{"field": "content", "start": 10, "end": 13, "text": "90%"}]`

### Requirement: PublicTechnique interpretation
Clients SHALL key techniques by `source` and `label`, SHALL NOT compare or combine `score` across sources, SHALL NOT present `score` as a probability that the content is propaganda, and SHALL present a `weak` `strength` as a hint, not evidence.

#### Scenario: Same label from two sources
- **WHEN** a client reads two entries with different `source` values
- **THEN** it shows them as separate findings

### Requirement: Bot signal summary
`bot_signal` SHALL be null unless the `bot_detection` AnalyzerRun has `succeeded` with a result clients may read under bot-detection-result "Text scope is not an account verdict"; then it SHALL be at least `{"label", "score", "scope"}` copied from it. `score` is the probability of `bot_or_generated`, also when `label` is `human`. Clients SHALL NOT present it as a verdict about the author or account.

#### Scenario: Generated text
- **WHEN** `bot_detection` succeeded with `{"label": "bot_or_generated", "score": 0.87, "scope": "text"}`
- **THEN** `bot_signal` is at least `{"label": "bot_or_generated", "score": 0.87, "scope": "text"}`

#### Scenario: Older account-level result
- **WHEN** `bot_detection` succeeded with `{"author": {"score": 0.9}}`
- **THEN** `bot_signal` is null

### Requirement: Evidence summary
`evidence` SHALL be an object with at least `fact_checks`, `news` and `wikipedia`, each null unless its AnalyzerRun (`fact_check`, `news_search`, `wikipedia`) has `succeeded`, otherwise an array, possibly empty. Null means "no lookup available" and an empty array "nothing found"; neither means a claim is true or false.

#### Scenario: News search not run
- **WHEN** `news_search` is `skipped` with reason `dependency_failed`
- **THEN** `evidence.news` is null

### Requirement: Fact check evidence entries
`evidence.fact_checks` SHALL hold one entry per FactCheck in the result's `fact_checks` order, with at least `claim`, `for_claim`, `rating`, `rating_normalized`, `publisher`, `url` and `review_date`.

#### Scenario: Fact check found
- **WHEN** `fact_check` succeeded with one FactCheck `{"claim": "Rente mit 70 beschlossen", "rating": "Falsch", "rating_normalized": "false", "publisher": "Correctiv", "url": "https://correctiv.org/x", "review_date": "2025-03-04T00:00:00Z", ...}`
- **THEN** `evidence.fact_checks` has one entry with those values and its `for_claim`

### Requirement: News evidence entries
`evidence.news` SHALL hold one entry per Article in the result's `articles` order, with at least `title`, `url`, `domain`, `source` and `date`.

#### Scenario: Article without date
- **WHEN** `news_search` succeeded with one Article whose `date` is null
- **THEN** `evidence.news` has one entry with `date: null`

### Requirement: Wikipedia evidence entries
`evidence.wikipedia` SHALL hold one entry per WikiLookup with `status: "found"`, in ClaimLookup order and then `wikis` order, with at least `claim` (the ClaimLookup `claim`), `language`, `title`, `url`, `passage` and `coverage` (the WikiLookup `coverage`, or null when absent).

#### Scenario: Wikipedia misses dropped
- **WHEN** `wikipedia` succeeded with one claim whose `de` WikiLookup is `no_page` and `en` WikiLookup is `found`
- **THEN** `evidence.wikipedia` has one entry, with `language: "en"`

### Requirement: PublicAnalysis error member
`error` SHALL be null unless the job's `status` is `failed`; then it SHALL be the Job's `scrape.error` (`code`, `message`) when the scrape failed, otherwise `{"code": "internal_error", "message": <text>}`. It SHALL NOT contain credentials, stack traces or analyzer endpoint URLs.

#### Scenario: Private account
- **WHEN** a URL-only submission's scrape failed with `error.code` `account_private`
- **THEN** the PublicAnalysis has `status: failed`, `done: true` and `error.code: account_private`

### Requirement: Share URL
When the deployment configures its web client's public base URL, `share_url` SHALL be that URL without trailing slash, then `/jobs/`, then the URL-path-escaped job id; otherwise null. The server SHALL NOT derive `share_url` from request headers. The web client SHALL keep serving the job's result page at `/jobs/<id>`.

#### Scenario: Configured base URL
- **WHEN** the deployment's public base URL is `https://veil.example.org/` and the job id is `j_123`
- **THEN** `share_url` is `https://veil.example.org/jobs/j_123`

#### Scenario: Not configured
- **WHEN** no public base URL is configured
- **THEN** `share_url` is null

### Requirement: Public rate limits
The server SHALL apply one global, deployment-configurable request rate limit to the submit endpoint and a separate one to the get endpoint, shared by all clients (no per-client keys). The limit SHALL be checked before the body is read; every request reaching it SHALL count, including ones rejected later. `/api/v1/jobs` and its sub-paths SHALL NOT be counted or limited.

#### Scenario: Polling does not consume submissions
- **WHEN** the get limit is exhausted
- **THEN** `GET /api/v1/public/analyses/{id}` gets 429 and `POST /api/v1/public/analyses` within its own limit still gets 201

#### Scenario: Jobs API unaffected
- **WHEN** the submit limit is exhausted
- **THEN** `POST /api/v1/jobs` with a valid body still gets 201

### Requirement: Rate limit response
A request over a public rate limit SHALL yield 429 `rate_limited` with a `Retry-After` header and `error.details.retry_after_s` (equal integer seconds, at least 1), SHALL create no job and SHALL NOT read the job store.

#### Scenario: Submissions over the limit
- **WHEN** the submit limit allows 2 requests per minute and a client posts 3 valid bodies within one second
- **THEN** the first two get 201, the third gets 429 with `error.code` `rate_limited`, a `Retry-After` header and `error.details.retry_after_s` of at least 1, and only two jobs exist
