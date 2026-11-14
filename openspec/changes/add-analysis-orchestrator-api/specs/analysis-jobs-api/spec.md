## Purpose

REST API of the analysis orchestrator for creating, listing, reading and cancelling content analysis jobs and for listing configured analyzers, including the job, analyzer-run, coverage, finalization and final-assessment objects shared with the event stream.

## ADDED Requirements

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
The FinalAssessment object SHALL have at least: `verdict` (`low_risk`, `medium_risk`, `high_risk` or `insufficient_evidence`); `overall_score` (number 0–100 or null); `categories` (array of FinalCategory); `explanation` (concise human-readable string); `evidence` (array of EvidenceRef, default `[]`); `limitations` (array of Limitation, default `[]`); `produced_by` (`finalizer` or `orchestrator`). Other members returned by the finalizer SHALL be kept verbatim.

#### Scenario: Risk assessment
- **WHEN** the finalizer returns `{"verdict": "high_risk", "overall_score": 82, "categories": [{"id": "emotional_manipulation", "score": 90}], "explanation": "..."}`
- **THEN** `finalization.result` contains those values with `evidence: []`, `limitations: []` and `produced_by: finalizer`

### Requirement: Overall score semantics
`overall_score` SHALL be a risk score produced by the finalizer service's methodology and SHALL be `null` when `verdict` is `insufficient_evidence`. It is not a probability; clients MUST NOT present it or any category score as a statistical probability. The orchestrator SHALL NOT compute, average or adjust any score.

#### Scenario: Score is not averaged
- **WHEN** analyzers returned scores 20 and 80 and the finalizer returned `overall_score: 35`
- **THEN** `finalization.result.overall_score` is `35`

### Requirement: Assessment categories
A FinalCategory SHALL have at least `id` (string) and `score` (number 0–100 or null), optionally `label`, `rationale` and `evidence` (array of EvidenceRef). Category ids include `emotional_manipulation`, `misleading_claims`, `coordinated_amplification`, `selective_reporting`; other ids are allowed.

#### Scenario: Category with evidence
- **WHEN** the finalizer returns a category `{"id": "misleading_claims", "score": 70, "evidence": [{"analyzer_id": "claims", "evidence_id": "c1"}]}`
- **THEN** `finalization.result.categories` contains it verbatim

### Requirement: Evidence references and limitations
An EvidenceRef SHALL have at least `analyzer_id`, optionally `evidence_id` and `note`. A Limitation SHALL have at least `kind` and `message`, optionally `analyzer_ids`; kinds include `missing_evidence`, `failed_analyzer`, `conflicting_findings`, `other`.

#### Scenario: Limitation for failed analyzer
- **WHEN** the finalizer reports that analyzer `claims` failed
- **THEN** `limitations` may contain `{"kind": "failed_analyzer", "message": "...", "analyzer_ids": ["claims"]}`

### Requirement: Insufficient evidence without fabricated score
When finalization is enabled and configured but no AnalyzerRun `succeeded`, the orchestrator SHALL NOT call the finalizer and SHALL complete finalization with `{"verdict": "insufficient_evidence", "overall_score": null, "categories": [], "explanation": <non-empty>, "evidence": [], "limitations": [...], "produced_by": "orchestrator"}`, with one `missing_evidence` limitation plus one `failed_analyzer` limitation per failed analyzer.

#### Scenario: All analyzers failed
- **WHEN** every applicable analyzer of a job fails
- **THEN** `finalization.status` is `completed`, `result.verdict` is `insufficient_evidence`, `result.overall_score` is `null` and `result.produced_by` is `orchestrator`

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
