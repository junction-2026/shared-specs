# analyzer-service-protocol Specification

## Purpose
HTTP protocol between the analysis orchestrator and external analyzer services, including the finalizer service: request body and binding sources, synchronous and asynchronous (polling) execution, result conventions and the finalizer response.

## Requirements

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
An analyzer result SHALL be a JSON object stored verbatim. Services SHOULD expose evidence as `result.evidence`, an array of objects each with a unique string `id` and optional `kind`, `excerpt`, `score`. A `result.score` is on the service's own scale; the orchestrator MUST NOT aggregate scores across analyzers.

#### Scenario: Evidence reference
- **WHEN** analyzer `claims` returns `{"evidence": [{"id": "c1", "excerpt": "..."}]}`
- **THEN** its AnalyzerRun `result` contains that `evidence` array verbatim

### Requirement: Finalizer response
For every adapter the finalizer output SHALL be a JSON object with at least `verdict` and `user_text` and optionally `confidence` and `wikipedia_quotes`, as defined for FinalAssessment (analysis-jobs-api). For `http_sync` and `http_async` the output is the result object; for `llm` it is the JSON object decoded from the model's reply.

#### Scenario: Minimal valid response
- **WHEN** the finalizer returns `{"verdict": "not_detected", "user_text": "No signs of propaganda were found."}`
- **THEN** the stored result has `confidence: null`, `usage: null`, `produced_by: finalizer` and `wikipedia_quotes: []`

### Requirement: Finalizer response validation
The orchestrator SHALL fail finalization with `invalid_output` when the adapter cannot decode the output into a JSON object, `verdict` is not `detected`, `not_detected` or `uncertain`, `user_text` is missing, not a string or empty after trimming, `confidence` is present and neither null nor a number from 0 to 1, or the configured output schema is violated. Invalid output SHALL NOT be stored or shown as a verdict.

#### Scenario: Missing required member
- **WHEN** the finalizer returns `{"verdict": "detected"}` without `user_text`
- **THEN** finalization is `failed` with `error.code: invalid_output`, `finalization.result` is null, all AnalyzerRun results remain unchanged and the job ends `completed`

#### Scenario: Contradictory response
- **WHEN** the finalizer returns the old shape `{"verdict": "insufficient_evidence", "overall_score": 40, "categories": [], "explanation": "..."}`
- **THEN** finalization is `failed` with `error.code: invalid_output`

#### Scenario: Confidence out of range
- **WHEN** the finalizer returns `{"verdict": "detected", "confidence": 86, "user_text": "..."}`
- **THEN** finalization is `failed` with `error.code: invalid_output`

#### Scenario: Reply is not JSON
- **WHEN** the `llm` adapter receives a reply whose message content is plain prose
- **THEN** finalization is `failed` with `error.code: invalid_output` and the job ends `completed`

### Requirement: Finalizer output normalization
The orchestrator SHALL store `verdict`, `confidence` and `user_text` unchanged (an absent or null `confidence` as null), set `produced_by: finalizer`, set `usage` to the token usage reported by the adapter (null when none), set `wikipedia_quotes` to the verified quotes (see "Proposed Wikipedia quotes") and drop every other member of the output. It SHALL NOT compute or adjust the verdict or confidence.

#### Scenario: Extra members dropped
- **WHEN** the finalizer returns `{"verdict": "detected", "confidence": 0.9, "user_text": "...", "reasoning": "..."}`
- **THEN** the stored result has no `reasoning` member

#### Scenario: Output member named usage
- **WHEN** an `http_sync` finalizer returns `{"verdict": "detected", "user_text": "...", "usage": {"total_tokens": 1}}`
- **THEN** the stored result has `usage: null`, because `usage` is set only from the adapter's report

### Requirement: Proposed Wikipedia quotes
A finalizer MAY return `wikipedia_quotes`, an array of objects with at least `claim`, `language` and `quote` (strings), as proposals that the orchestrator verifies (analysis-jobs-api "Wikipedia quote verification"). The orchestrator SHALL store `[]` when the member is absent or not an array, SHALL drop entries that are not objects with string `claim`, `language` and `quote`, and SHALL NOT fail finalization because of `wikipedia_quotes`.

#### Scenario: Malformed quotes ignored
- **WHEN** the finalizer returns `{"verdict": "not_detected", "user_text": "...", "wikipedia_quotes": "see Wikipedia"}`
- **THEN** finalization is `completed` with `wikipedia_quotes: []`

### Requirement: Wikipedia labels in finalizer input
The finalizer's input SHALL carry the job's `wikipedia` AnalyzerRun result unchanged when the finalizer receives that run (for the `llm` adapter, when `wikipedia` is opted in to LLM input), including each WikiLookup's `coverage`, `evidence_sentence` and `passage`.

#### Scenario: Labels reach the LLM finalizer
- **WHEN** `wikipedia` succeeded, is opted in to LLM input and a WikiLookup has `coverage: "conflicts"`
- **THEN** the finalizer's input contains that WikiLookup with its `coverage`, `evidence_sentence` and `passage`
