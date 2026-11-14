## MODIFIED Requirements

### Requirement: Finalization outcomes
For `skipped`, `reason` SHALL be one of values including `not_configured` (no enabled finalizer), `disabled_by_request` (`options.finalize` false) and `cancelled` (job cancelled before finalization started). For `failed`, `error` is `{"code", "message"}` with codes including `timeout`, `adapter_error`, `invalid_output`, `cancelled`. Otherwise `reason` and `error` are null.

#### Scenario: Finalization disabled by request
- **WHEN** a job is created with `"options": {"finalize": false}`
- **THEN** once all analyzers settle, `finalization` is `skipped` with `reason: disabled_by_request` and the job is `completed`

#### Scenario: Finalizer timeout
- **WHEN** the finalizer has timeout 60s and does not answer within 60s
- **THEN** `finalization.status` is `failed` with `error.code: timeout`

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

### Requirement: Registry listing hides execution settings
Analyzer listing items MUST NOT contain endpoint URLs, headers, environment values or any other execution setting, because these can carry credentials. This is a deliberate exception to "at least these members": new members exposing execution settings SHALL NOT be added.

#### Scenario: Endpoint not exposed
- **WHEN** the finalizer is configured with `endpoint: ${FINALIZER_URL}`
- **THEN** no member of the analyzers response contains the endpoint value

#### Scenario: LLM settings not exposed
- **WHEN** the finalizer uses the `llm` adapter with `base_url`, `api_key`, `model` and `headers` configured
- **THEN** no member of the analyzers response contains any of these values

## ADDED Requirements

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

## REMOVED Requirements

### Requirement: Overall score semantics
**Reason**: FinalAssessment no longer has `overall_score`; the LLM finalizer gives a verdict and a confidence instead of a risk score.
**Migration**: Read `verdict` and `confidence` (see "Confidence semantics"). No client used `overall_score`.

### Requirement: Assessment categories
**Reason**: FinalAssessment no longer has `categories`; the finalizer gives one verdict about propaganda or manipulation.
**Migration**: Use `verdict` and `user_text`. Per-analyzer detail stays available in `analyzers[].result`.

### Requirement: Evidence references and limitations
**Reason**: FinalAssessment no longer has `evidence` or `limitations`; unavailable analyzers and weak evidence are expressed by `verdict: uncertain` and explained in `user_text`.
**Migration**: Read analyzer failures from `analyzers[]` and `coverage`. No client used these members.
