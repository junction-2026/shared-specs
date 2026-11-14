## MODIFIED Requirements

### Requirement: Analyzer result conventions
An analyzer result SHALL be a JSON object stored verbatim. Services SHOULD expose evidence as `result.evidence`, an array of objects each with a unique string `id` and optional `kind`, `excerpt`, `score`. A `result.score` is on the service's own scale; the orchestrator MUST NOT aggregate scores across analyzers.

#### Scenario: Evidence reference
- **WHEN** analyzer `claims` returns `{"evidence": [{"id": "c1", "excerpt": "..."}]}`
- **THEN** its AnalyzerRun `result` contains that `evidence` array verbatim

### Requirement: Finalizer response
For every adapter the finalizer output SHALL be a JSON object with at least `verdict` and `user_text` and optionally `confidence`, as defined for FinalAssessment (analysis-jobs-api). For `http_sync` and `http_async` the output is the result object; for `llm` it is the JSON object decoded from the model's reply.

#### Scenario: Minimal valid response
- **WHEN** the finalizer returns `{"verdict": "not_detected", "user_text": "No signs of propaganda were found."}`
- **THEN** the stored result has `confidence: null`, `usage: null` and `produced_by: finalizer`

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

## ADDED Requirements

### Requirement: Finalizer output normalization
The orchestrator SHALL store `verdict`, `confidence` and `user_text` unchanged (an absent or null `confidence` as null), set `produced_by: finalizer`, set `usage` to the token usage reported by the adapter (null when none) and drop every other member of the output. It SHALL NOT compute or adjust the verdict or confidence.

#### Scenario: Extra members dropped
- **WHEN** the finalizer returns `{"verdict": "detected", "confidence": 0.9, "user_text": "...", "reasoning": "..."}`
- **THEN** the stored result has no `reasoning` member

#### Scenario: Output member named usage
- **WHEN** an `http_sync` finalizer returns `{"verdict": "detected", "user_text": "...", "usage": {"total_tokens": 1}}`
- **THEN** the stored result has `usage: null`, because `usage` is set only from the adapter's report
