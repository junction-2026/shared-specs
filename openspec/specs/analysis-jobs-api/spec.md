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
`POST /api/v1/jobs` SHALL accept the body `{"input": Input, "analyzers": [<analyzer id>] (optional), "options": {"finalize": <boolean, default true>} (optional)}` and respond 201 with the created Job and the header `Location: /api/v1/jobs/{id}`. Analysis SHALL start asynchronously; the response MUST NOT wait for any analyzer.

#### Scenario: Job created
- **WHEN** a client posts `{"input": {"content": "Some article text"}}`
- **THEN** the status is 201, the body is a Job with `status` `queued` or `running` and `done: false`, and every non-finalizer registry analyzer appears in `analyzers`

### Requirement: Create job validation
`POST /api/v1/jobs` SHALL reject a body larger than 1 MiB (1 048 576 bytes) with 413 `payload_too_large`, and SHALL respond 422 `validation_failed` for a missing or blank `input.content`, wrong member types, an unsupported `content_type`, an invalid `source.url` or `source.published_at`, or duplicate ids in `analyzers`.

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
The Job object SHALL have at least: `id`; `status`; `done` (boolean); `created_at`; `started_at` and `finished_at` (timestamp or null, `finished_at` set when `done` becomes true); `input` (Input with defaults applied); `options` with at least `finalize` (boolean); `analyzers` (array of AnalyzerRun); `coverage` (Coverage); `finalization` (Finalization).

#### Scenario: Fresh job
- **WHEN** a job has just been created
- **THEN** it has `done: false`, `finished_at: null` and `finalization.status` `pending` or `skipped`

### Requirement: Job status
Job `status` values SHALL include `queued` (no analyzer started), `running`, `finalizing` (all AnalyzerRuns settled, finalization not yet ended), `completed` (all settled and finalization ended as `completed`, `failed` or `skipped`), `cancelled` and `failed` (orchestrator-internal error only). `done` SHALL be `true` if and only if status is `completed`, `cancelled` or `failed`. Analyzer or finalization failures SHALL NOT make the job `failed`.

#### Scenario: Analyzer failure does not fail the job
- **WHEN** one analyzer fails, the others succeed and finalization completes
- **THEN** the job ends with `status: completed` and `done: true`

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
`succeeded`, `failed` and `skipped` are settled states; a settled AnalyzerRun SHALL never change. For `skipped`, `reason` values include `disabled`, `not_selected`, `not_applicable`, `dependency_failed`, `dependency_skipped`, `cancelled`. For `failed`, `error` is `{"code", "message"}` with codes including `timeout`, `adapter_error`, `invalid_output`, `cancelled`. Otherwise `reason` and `error` are null.

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
