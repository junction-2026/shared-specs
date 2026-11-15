## Purpose
Result object of the text-level bot detection analyzer: whether one job text looks human-written or bot / generated according to the multilingual bot-detector model run on the original text, as clients read it from the analysis job API and event stream.

## ADDED Requirements

### Requirement: Text bot detection analyzer
A deployment that offers text-level bot detection SHALL register it as a regular, selectable analyzer with id `bot_detection` and category `bot_detection`. Clients SHALL locate its result as the AnalyzerRun with `id` `bot_detection` and SHALL treat a missing, `skipped` or `failed` run as "no text-origin signal available", not as "human-written".

#### Scenario: Deployment without the analyzer
- **WHEN** the registry has no `bot_detection` analyzer
- **THEN** jobs have no AnalyzerRun with that id and clients show no text-origin signal, without error

### Requirement: Original text input
`bot_detection` SHALL NOT depend on `translation` and SHALL classify the job's original text (`input.normalized_content`), never the English translation instead of it or in addition to it.

#### Scenario: Non-English job
- **WHEN** a job is created with `{"input": {"content": "Это пример текста."}}` and `translation` succeeds with an English `translated_text`
- **THEN** the detector receives the original Russian `normalized_content` and not the `translated_text`

#### Scenario: Translation failed
- **WHEN** `translation` is `failed`
- **THEN** `bot_detection` still runs and can be `succeeded`

### Requirement: TextBotDetection object
When `bot_detection` has `succeeded` with a text-level result, its AnalyzerRun `result` SHALL be a TextBotDetection object with at least: `label` (string, values include `human` and `bot_or_generated`), `score` (number from 0 to 1, the probability that the text is bot-written or generated) and `scope` (string, `text` for this object). It SHALL be the same in `analyzer.succeeded` `data.analyzer.result` and `GET /api/v1/jobs/{id}`. Clients SHALL ignore unknown members.

#### Scenario: Generated text
- **WHEN** the model answers its bot / generated label (`LABEL_1`) with probability 0.87
- **THEN** `result` has `label: "bot_or_generated"`, `score: 0.87` and `scope: "text"`

#### Scenario: Human text
- **WHEN** the model answers its human label (`LABEL_0`) with probability 0.9
- **THEN** `result` has `label: "human"`, `score: 0.1` and `scope: "text"`

### Requirement: Score orientation
`score` SHALL always be the probability of `bot_or_generated`, also when `label` is `human`. `label` SHALL be `bot_or_generated` when the model's top label is its bot / generated label and `human` when it is its human label.

#### Scenario: Reading the score
- **WHEN** a client shows the result with `label: "human"` and `score: 0.1`
- **THEN** it does not present 0.1 as the confidence in `human`

### Requirement: Text scope is not an account verdict
A TextBotDetection describes one text only. Clients SHALL NOT present it as a verdict about the author or account, and SHALL NOT present it as propaganda detection. A `bot_detection` result whose `scope` is absent or not `text`, or whose `label` or `score` is missing or outside the values above, SHALL be treated by clients as "no text-origin signal available", without error.

#### Scenario: Result of an older account-level entry
- **WHEN** a deployment's `bot_detection` returns `{"author": {"score": 0.9}}` without `scope`
- **THEN** clients show no text-origin signal and no error

#### Scenario: Unknown label
- **WHEN** a result has `label: "mixed"`, `score: 0.5`, `scope: "text"`
- **THEN** clients show no text-origin signal and no error

### Requirement: Text bot detection failures
`bot_detection` SHALL be `failed` with `result: null` and an `error.code` that includes: `invalid_output` when the detector's answer is not readable as a label with a score, has a label other than the model's human and bot / generated labels, or a score outside 0 to 1; `adapter_error` for a non-2xx answer, a connection error or a job without text to classify; `timeout` when its timeout elapses; `cancelled` on job cancellation.

#### Scenario: Unknown model label
- **WHEN** the detector answers `{"label": "LABEL_7", "score": 0.8}`
- **THEN** `bot_detection` is `failed` with `error.code: invalid_output` and the job ends `completed`

### Requirement: Text bot detection is isolated
A failed or skipped `bot_detection` SHALL NOT fail the job or other analyzers. Its result SHALL NOT change the results of `propaganda_detection` or `techniques`, nor the Manipulation Risk Score formula.

#### Scenario: Detector unavailable
- **WHEN** the detector answers HTTP 503
- **THEN** `bot_detection` is `failed` with `error.code: adapter_error` and `propaganda_detection` and `techniques` settle as they would without it

### Requirement: Text bot detection errors hide credentials
`error.message` of a failed `bot_detection` run and every member of its result MUST NOT contain credentials: no configured header value (such as `Authorization`) and no token, even when the detector echoes them.

#### Scenario: Service echoes the token
- **WHEN** the detector answers HTTP 401 with a body that repeats the bearer token
- **THEN** `error.message` does not contain the token
