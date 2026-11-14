## Purpose

HTTP protocol between the analysis orchestrator and external analyzer services, including the finalizer service: request body and binding sources, synchronous and asynchronous (polling) execution, result conventions and the finalizer response.

## ADDED Requirements

### Requirement: Analyzer request
For adapters `http_sync` and `http_async` the orchestrator SHALL send the configured method (default `POST`) to the configured endpoint with a JSON body of at least `{"job_id", "analyzer_id", "inputs": <object>}`. `inputs` has one member per configured input binding; with no bindings configured it is `{"content": <$input>}`.

#### Scenario: Default inputs
- **WHEN** analyzer `sentiment` has no input bindings and job `j1` has content `hi`
- **THEN** the service receives `{"job_id": "j1", "analyzer_id": "sentiment", "inputs": {"content": {"content": "hi", "normalized_content": "hi", "content_type": "text/plain", "source": {}}}}`

### Requirement: Request headers
Analyzer requests SHALL carry `Content-Type: application/json`, `Accept: application/json`, `X-Analysis-Job-Id: <job id>` and `X-Analysis-Analyzer-Id: <analyzer id>`, plus any headers configured for the analyzer (for example service credentials).

#### Scenario: Correlation headers
- **WHEN** the orchestrator calls analyzer `claims` for job `j1`
- **THEN** the request has `X-Analysis-Job-Id: j1` and `X-Analysis-Analyzer-Id: claims`

### Requirement: Input binding sources
Binding sources SHALL include `$input` (the job's Input object plus `normalized_content`), `$input.source` (the Input's `source`), `$job.id` (job id) and `$analyzers.<id>` (the `result` of dependency `<id>`; only ids in the analyzer's `depends_on`). `normalized_content` is `content` in Unicode NFC with `\n` line endings, trimmed, and for `text/html` with markup removed.

#### Scenario: Dependency result binding
- **WHEN** `claims` binds `entities: "$analyzers.entities"` and `entities` returned `{"items": []}`
- **THEN** the `claims` request has `inputs.entities` `{"items": []}`

### Requirement: Job-wide binding sources
Binding sources SHALL include `$job.analyzers` (array of every AnalyzerRun of the job, with results, errors and skip reasons) and `$job.coverage` (Coverage object). Only analyzers with trigger `after_all_analyzers_settled` may bind them, and they receive them only once every AnalyzerRun is settled.

#### Scenario: Finalizer inputs
- **WHEN** the finalizer binds `content: "$input"`, `results: "$job.analyzers"`, `coverage: "$job.coverage"`
- **THEN** its request `inputs` has members `content`, `results` (every AnalyzerRun, all settled) and `coverage`

### Requirement: Synchronous execution
For `http_sync`, a 2xx response with a JSON object body SHALL be the analyzer result. A non-2xx status, a connection error or a non-object body SHALL fail the analyzer with `adapter_error`; no response within the configured timeout fails it with `timeout`; a result violating the configured output schema fails it with `invalid_output`. The orchestrator SHALL NOT retry automatically.

#### Scenario: Service error
- **WHEN** a service answers HTTP 503
- **THEN** the analyzer is `failed` with `error.code: adapter_error`

### Requirement: Asynchronous submission
For `http_async`, the service SHALL answer the request with 202 and at least `{"status_url": <absolute URL>}`, after which the orchestrator polls. A 200 response with a JSON object body SHALL be accepted as an immediate result. Any other answer SHALL fail the analyzer with `adapter_error`.

#### Scenario: Missing status URL
- **WHEN** an async service answers 202 with `{}`
- **THEN** the analyzer is `failed` with `error.code: adapter_error`

### Requirement: Asynchronous polling
The orchestrator SHALL `GET` `status_url` at its configured interval. A poll answer is 200 with at least `{"status"}`, values including `pending`, `running`, `succeeded` (with `result` object) and `failed` (optional `error.message`). `succeeded` yields the result; `failed` or a non-200 answer fails the analyzer with `adapter_error`; unknown values count as `running`. The configured timeout covers submission and all polls.

#### Scenario: Async success
- **WHEN** the service answers 202 `{"status_url": "https://svc/tasks/1"}` and a later poll returns `{"status": "succeeded", "result": {"score": 12}}`
- **THEN** the analyzer is `succeeded` with `result: {"score": 12}`

### Requirement: Asynchronous abort
When an `http_async` analyzer times out or its job is cancelled while polling, the orchestrator SHALL send one best-effort `DELETE` to `status_url` and ignore the answer.

#### Scenario: Async timeout
- **WHEN** polls keep returning `running` beyond the timeout
- **THEN** the analyzer is `failed` with `timeout` and the orchestrator sends `DELETE https://svc/tasks/1`

### Requirement: Analyzer result conventions
An analyzer result SHALL be a JSON object stored verbatim. Services SHOULD expose evidence as `result.evidence`, an array of objects each with a unique string `id` and optional `kind`, `excerpt`, `score`; EvidenceRefs cite them by `analyzer_id` and `evidence_id`. A `result.score` is on the service's own scale; the orchestrator MUST NOT aggregate scores across analyzers.

#### Scenario: Evidence reference
- **WHEN** analyzer `claims` returns `{"evidence": [{"id": "c1", "excerpt": "..."}]}`
- **THEN** the finalizer may cite it as `{"analyzer_id": "claims", "evidence_id": "c1"}`

### Requirement: Finalizer response
The finalizer service SHALL return a FinalAssessment (analysis-jobs-api) without `produced_by`, through any adapter. The orchestrator SHALL store an absent `overall_score` as null and absent `evidence`/`limitations` as `[]`, set `produced_by: finalizer`, keep other members verbatim, and SHALL NOT compute or adjust any score.

#### Scenario: Minimal valid response
- **WHEN** the finalizer returns `{"verdict": "low_risk", "categories": [], "explanation": "No signs found."}`
- **THEN** the stored result has `overall_score: null`, `evidence: []`, `limitations: []` and `produced_by: finalizer`

### Requirement: Finalizer response validation
The orchestrator SHALL fail finalization with `invalid_output` when the response is not an object, `verdict` is not one of the four verdicts, `categories` is not an array, `explanation` is not a string, `overall_score` or a category `score` is neither null nor a number 0–100, `overall_score` is non-null with verdict `insufficient_evidence`, or the configured output schema is violated.

#### Scenario: Missing required member
- **WHEN** the finalizer returns `{"verdict": "low_risk"}` without `categories` and `explanation`
- **THEN** finalization is `failed` with `error.code: invalid_output` and all AnalyzerRun results remain unchanged

#### Scenario: Contradictory response
- **WHEN** the finalizer returns `{"verdict": "insufficient_evidence", "overall_score": 40, "categories": [], "explanation": "..."}`
- **THEN** finalization is `failed` with `error.code: invalid_output`
