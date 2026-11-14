## MODIFIED Requirements

### Requirement: Detected techniques
`detected` SHALL list a Detection for each technique whose document score is at or above its `thresholds` value, sorted by `score` descending, and SHALL be empty when none is. A Detection SHALL have at least `name`, `display`, `explanation` (non-empty one-line string) and `score`. Each Detection in `detected` SHALL also have `spans` (array of TechniqueSpan, possibly empty).

#### Scenario: Same scores, different model
- **WHEN** `Loaded_Language` scores 0.4 and every other technique below 0.3, with short threshold 0.3 and long threshold 0.5
- **THEN** a `short` result's `detected` lists only `Loaded_Language` and a `long` result's `detected` is empty

#### Scenario: Per-technique override
- **WHEN** the long model's threshold is 0.5, `Doubt` has an override of 0.7 and `Doubt` scores 0.6
- **THEN** `thresholds.Doubt` is 0.7 and `Doubt` is not in `detected`

### Requirement: Technique result presentation
Sentence `text` and span `text` come from untrusted content; clients SHALL render them, `display` and `explanation` as plain text without HTML or Markdown interpretation. Clients SHALL present detections as indicators of a technique, not as proof of propaganda, and SHALL NOT present `score` as a calibrated probability across models.

#### Scenario: Markup in a sentence
- **WHEN** a SentenceDetection `text` contains `<b>LIES</b>`
- **THEN** a client shows those characters literally

## ADDED Requirements

### Requirement: Span result members
A succeeded TechniqueClassification SHALL also have at least `span_method` (values include `sentence` and `phrase`), `span_status` (values include `ok`, `failed` and `timeout`) and `spans_truncated` (boolean), the same in `analyzer.succeeded` and `GET /api/v1/jobs/{id}`.

#### Scenario: Span members present
- **WHEN** `techniques` has `succeeded` for an English job
- **THEN** `result.span_method` is `sentence` and `result.span_status` and `result.spans_truncated` are present

### Requirement: Span status
`span_status` SHALL be `ok` when the span step completed or was not needed, `failed` or `timeout` as defined in "Span failures keep the classification". Clients SHALL treat an unknown `span_status` value like `failed`, and a result without `span_status` (produced before span support) as having no span analysis.

#### Scenario: Result from before span support
- **WHEN** a client reads a stored TechniqueClassification that has no `span_status` and Detections without `spans`
- **THEN** it shows the detected techniques without highlights and without error

### Requirement: Detected techniques keep empty spans
A technique SHALL NOT be removed from `detected` because it has no span, and no paraphrased or translated text SHALL be substituted as its span. Detections inside `sentences[].techniques` do not carry `spans`.

#### Scenario: Detected technique without span
- **WHEN** `Doubt` is at or above its threshold and no span is accepted for it
- **THEN** `Doubt` is in `detected` with `spans: []`

### Requirement: Span highlighting presentation
Clients that highlight techniques in the user's text SHALL highlight the `[start, end)` ranges of `detected[].spans` in `Job.input.content` rendered as plain text, and SHALL list a detected technique whose `spans` is empty or missing without a highlight. Clients SHALL NOT present `sentences[].text` of a result with `offsets_in: translation`, or any part of the translation, as the user's words.

#### Scenario: Markup in highlighted content
- **WHEN** `Job.input.content` is `"<i>They</i> are LYING"` and a span covers `"LYING"`
- **THEN** a client shows `<i>They</i>` literally and highlights only `LYING`

### Requirement: TechniqueSpan object
A TechniqueSpan SHALL have at least `technique` (the `name` of the Detection that holds it), `text` (string, non-empty), `start` and `end` (integers). Offsets SHALL never refer to the translation.

#### Scenario: Span member values
- **WHEN** a Detection with `name: "Doubt"` holds a span
- **THEN** the span has `technique: "Doubt"` and a non-empty `text`

### Requirement: Span offsets
`start` and `end` SHALL be half-open UTF-16 code-unit offsets into `Job.input.content` such that `Job.input.content.slice(start, end)` equals `text`, compared on the characters as submitted: not `normalized_content`, not trimmed and not case-folded.

#### Scenario: Characters outside the BMP
- **WHEN** `Job.input.content` is `"😡 They are LYING to you."` and the sentence `"They are LYING to you."` is a span
- **THEN** the span has `start: 3`, `end: 25`, because the emoji is two UTF-16 code units followed by a space

### Requirement: Span ordering and overlap
Spans of one Detection SHALL be ordered by `start`, then `end`, and no two of them SHALL have the same `start` and `end`. Spans of different techniques MAY overlap or coincide.

#### Scenario: Overlapping techniques
- **WHEN** the same sentence carries `Loaded_Language` and `Doubt`
- **THEN** both Detections hold a span with the same `start`, `end` and `text`, each with its own `technique`

### Requirement: Span method
`span_method` SHALL be `sentence` when the `translation` result's `source_language` is `en`, and `phrase` for any other or missing `source_language`. When `detected` is empty, no span request SHALL be sent and `span_status` SHALL be `ok`.

#### Scenario: Nothing detected
- **WHEN** `detected` is empty for a German job
- **THEN** `span_method` is `phrase`, `span_status` is `ok` and no span model or LLM request is sent

### Requirement: Sentence spans for English input
When `span_method` is `sentence`, the deployment SHALL split `Job.input.content` into sentences and score them with its sentence-level technique model (`nci-social`), independent of `model` and of the word count. For each Detection in `detected`, every scored sentence whose sentence-model score for that technique is at or above the sentence model's effective threshold for it SHALL be a span whose `text` is the sentence.

#### Scenario: English job
- **WHEN** an English job with content `"Wake up. They are LYING to you."` has `Loaded_Language` in `detected`, the sentence model scores `"They are LYING to you."` above its `Loaded_Language` threshold and `"Wake up."` below it
- **THEN** `Loaded_Language` has one span `{technique: "Loaded_Language", text: "They are LYING to you.", start: 9, end: 31}`

### Requirement: Sentence spans only for detected techniques
Sentence-model scores of techniques not in `detected` SHALL produce no span and SHALL NOT change `detected`. `spans_truncated` SHALL be `true` when sentences beyond the deployment's span sentence limit were not scored.

#### Scenario: Sentence above cutoff for an undetected technique
- **WHEN** the sentence model scores a sentence above its `Doubt` threshold but `Doubt` is not in `detected`
- **THEN** no span with `technique: "Doubt"` exists and `Doubt` is not added to `detected`

### Requirement: Phrase spans for other languages
When `span_method` is `phrase`, the deployment SHALL ask an LLM for candidate phrases of `Job.input.content` for each technique in `detected`. A candidate SHALL be accepted only if it is non-empty and occurs in `Job.input.content` as an exact, case-sensitive substring; its span SHALL be its leftmost occurrence, with `text` the candidate unchanged.

#### Scenario: Translated candidate rejected
- **WHEN** a German job's content is `"Sie LÜGEN euch an."` and the LLM returns `"They are LYING"` and `"LÜGEN euch"` for `Loaded_Language`
- **THEN** `Loaded_Language` has one span `{text: "LÜGEN euch", start: 4, end: 14}`

#### Scenario: Repeated phrase
- **WHEN** an accepted candidate occurs twice in the content
- **THEN** its span is the first occurrence

### Requirement: Phrase candidate rejection
Candidates that are not exact substrings SHALL be rejected without fuzzy matching, trimming, normalization, translation or repair. Candidates for techniques not in `detected` SHALL be ignored. `spans_truncated` SHALL be `true` when candidates beyond the deployment's per-technique limit were dropped.

#### Scenario: All candidates rejected
- **WHEN** every candidate for `Doubt` differs from the content (for example in case or whitespace)
- **THEN** `Doubt` stays in `detected` with `spans: []` and `span_status` is `ok`

### Requirement: Span failures keep the classification
A failure of the span step SHALL NOT change the AnalyzerRun status, `techniques`, `detected` membership, `sentences` or `offsets_in`. When the sentence model or the LLM answers non-2xx, cannot be reached or gives an unreadable answer, `span_status` SHALL be `failed`; when the span step's own deadline elapses it SHALL be `timeout`; in both cases every `detected[].spans` SHALL be `[]`. The existing `timeout` failure of the whole run applies only when the analyzer's overall timeout elapses.

#### Scenario: LLM times out
- **WHEN** a German job has `Doubt` in `detected` and the span LLM does not answer before the span deadline
- **THEN** `techniques` is `succeeded`, `span_status` is `timeout` and `Doubt` is in `detected` with `spans: []`

#### Scenario: Sentence model error
- **WHEN** the sentence model answers HTTP 503 for an English job
- **THEN** `techniques` is `succeeded` with `span_status: failed`, every `detected[].spans` empty and the same `detected` as without span support
