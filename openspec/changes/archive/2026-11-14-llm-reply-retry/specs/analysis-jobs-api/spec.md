## MODIFIED Requirements

### Requirement: FinalAssessment object
The FinalAssessment object SHALL have at least: `verdict` (see "Verdict values"); `confidence` (number 0–1, or null when the finalizer gave none); `user_text` (non-empty plain-language explanation for the end user); `produced_by` (`finalizer` or `orchestrator`); `usage` (token usage object reported by the finalizer adapter, or null); `attempts` and `retry_reason` (see "FinalAssessment retry members").

#### Scenario: Risk assessment
- **WHEN** the `llm` finalizer's first reply is `{"verdict": "detected", "confidence": 0.86, "user_text": "This post shows signs of propaganda."}` and the provider reported `{"prompt_tokens": 512, "completion_tokens": 48, "total_tokens": 560}`
- **THEN** `finalization.result` is at least `{"verdict": "detected", "confidence": 0.86, "user_text": "This post shows signs of propaganda.", "produced_by": "finalizer", "usage": {"prompt_tokens": 512, "completion_tokens": 48, "total_tokens": 560}, "attempts": 1, "retry_reason": null}`

#### Scenario: No confidence and no usage
- **WHEN** an `http_sync` finalizer returns `{"verdict": "uncertain", "user_text": "The analyzers disagree."}`
- **THEN** `finalization.result` has `confidence: null`, `usage: null`, `produced_by: finalizer`, `attempts: null` and `retry_reason: null`

### Requirement: Insufficient evidence without fabricated score
When finalization is enabled and configured but no AnalyzerRun that the finalizer would receive has `succeeded` (for the `llm` adapter, the analyzers opted in to LLM input; otherwise every AnalyzerRun), the orchestrator SHALL NOT call the finalizer and SHALL complete finalization with a FinalAssessment of at least `{"verdict": "uncertain", "confidence": null, "user_text": <non-empty fixed text>, "produced_by": "orchestrator", "usage": null, "attempts": null, "retry_reason": null}`.

#### Scenario: All analyzers failed
- **WHEN** every applicable analyzer of a job fails
- **THEN** `finalization.status` is `completed`, `result.verdict` is `uncertain`, `result.confidence` is `null`, `result.user_text` is non-empty, `result.produced_by` is `orchestrator` and `result.attempts` is `null`

#### Scenario: Only analyzers not sent to the LLM succeeded
- **WHEN** the finalizer uses the `llm` adapter, only `propaganda_detection` is opted in to LLM input, `propaganda_detection` fails and `text_stats` succeeds
- **THEN** the LLM provider receives no request, `analysis.finalizing` and `analysis.finalized` are emitted, and `finalization.result` has `verdict: uncertain` and `produced_by: orchestrator`

## ADDED Requirements

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
