# technique-classifier-result Specification

## Purpose
Result object of the propaganda technique classifier analyzer: per-technique scores for the 18 SemEval-2020 Task 11 techniques on a job's English text, the detected techniques and the sentences that carry them, as clients read it from the analysis job API and event stream.

## Requirements

### Requirement: Technique classifier analyzer
A deployment that offers technique classification SHALL register it as a regular, selectable analyzer with id `techniques`, category `propaganda` and `depends_on` including `translation`. Clients SHALL locate its result as the AnalyzerRun with `id` `techniques` and SHALL treat a missing, `skipped` or `failed` run as "no technique analysis available", not as "no techniques found".

#### Scenario: Translation failed
- **WHEN** `translation` is `failed`
- **THEN** `techniques` is `skipped` with reason `dependency_failed`, `result: null`, and no classifier request is sent

#### Scenario: Deployment without the analyzer
- **WHEN** the registry has no `techniques` analyzer
- **THEN** jobs have no AnalyzerRun with that id and clients show no technique analysis, without error

### Requirement: Technique names
Technique `name` values SHALL be these 18 strings: `Loaded_Language`, `Appeal_to_fear-prejudice`, `Exaggeration,Minimisation`, `Repetition`, `Flag-Waving`, `Name_Calling,Labeling`, `Reductio_ad_hitlerum`, `Black-and-White_Fallacy`, `Causal_Oversimplification`, `Whataboutism,Straw_Men,Red_Herring`, `Straw_Man`, `Red_Herring`, `Doubt`, `Appeal_to_Authority`, `Thought-terminating_Cliches`, `Bandwagon`, `Slogans`, `Obfuscation,Intentional_Vagueness,Confusion`.

#### Scenario: Names are stable identifiers
- **WHEN** a client groups detections by technique
- **THEN** it uses `name` as the key and `display` only as the label

### Requirement: TechniqueClassification object
When `techniques` has `succeeded`, its `result` SHALL be a TechniqueClassification with at least: `model` (`short` or `long`), `words` (integer), `threshold` (number), `thresholds`, `techniques`, `detected`, `max_score` (number 0 to 1), `sentences`, `offsets_in`, `sentences_truncated` (boolean) and `latency_ms` (number or null). It SHALL be the same in `analyzer.succeeded` and `GET /api/v1/jobs/{id}`. Clients SHALL ignore unknown members.

#### Scenario: Short text
- **WHEN** a job's English translation has 40 words and the deployment's short limit is 80 words
- **THEN** `result.model` is `short`, `result.words` is 40 and `result.threshold` is the short model's configured threshold

### Requirement: Model and words
`words` SHALL be the number of whitespace-separated words of the classified English text. `model` SHALL be `short` when `words` is at most the deployment's short limit and `long` otherwise, independent of `input.source`. `threshold` SHALL be the chosen model's default threshold. Clients SHALL NOT compare scores across results with different `model`.

#### Scenario: Platform does not matter
- **WHEN** two jobs have the same text, one with `source.platform: "x"` and one without `source`
- **THEN** both results have the same `model`, `techniques` and `detected`

### Requirement: Scores and thresholds
`techniques` SHALL contain one TechniqueScore per technique name (18 entries), sorted by `score` descending. `thresholds` SHALL be an object mapping each of the 18 names to its effective threshold (the per-technique override or else `threshold`). `max_score` SHALL be the highest `score` in `techniques`. A TechniqueScore SHALL have at least `name`, `display` (non-empty string) and `score` (independent probability, 0 to 1).

#### Scenario: Scores are not a distribution
- **WHEN** a client reads `techniques`
- **THEN** it does not expect the scores to sum to 1

### Requirement: Detected techniques
`detected` SHALL list a Detection for each technique whose document score is at or above its `thresholds` value, sorted by `score` descending, and SHALL be empty when none is. A Detection SHALL have at least `name`, `display`, `explanation` (non-empty one-line string) and `score`. Each Detection in `detected` SHALL also have `spans` (array of TechniqueSpan, possibly empty).

#### Scenario: Same scores, different model
- **WHEN** `Loaded_Language` scores 0.4 and every other technique below 0.3, with short threshold 0.3 and long threshold 0.5
- **THEN** a `short` result's `detected` lists only `Loaded_Language` and a `long` result's `detected` is empty

#### Scenario: Per-technique override
- **WHEN** the long model's threshold is 0.5, `Doubt` has an override of 0.7 and `Doubt` scores 0.6
- **THEN** `thresholds.Doubt` is 0.7 and `Doubt` is not in `detected`

### Requirement: Sentence detections
`sentences` SHALL list a SentenceDetection for each scored sentence with at least one technique at or above its `thresholds` value, ordered by `start`. A SentenceDetection SHALL have at least `text` (the sentence), `start` and `end` (integers) and `techniques` (array of Detection for that sentence's scores, sorted by `score` descending, non-empty). `sentences_truncated` SHALL be `true` when sentences beyond the deployment's limit were not scored.

#### Scenario: No sentence over threshold
- **WHEN** no scored sentence reaches a threshold
- **THEN** `sentences` is an empty array

### Requirement: Sentence offsets
`start` and `end` SHALL be half-open UTF-16 code-unit offsets such that `S.slice(start, end)` equals `text`, where `S` is `Job.input.content` when `offsets_in` is `original` and the `translated_text` of the `translation` AnalyzerRun result when it is `translation`. `offsets_in` SHALL be `original` only when `source_language` is `en` and every reported sentence was found in `Job.input.content`.

#### Scenario: English job
- **WHEN** an English job with content `"Wake up. They are LYING to you."` gets a detection in the second sentence
- **THEN** `offsets_in` is `original` and the sentence has `start: 9`, `end: 31` and `text: "They are LYING to you."`

#### Scenario: German job
- **WHEN** `translation` reports `source_language: "de"`
- **THEN** `offsets_in` is `translation` and every `sentences[]` slice of `translated_text` equals its `text`

### Requirement: Technique classifier failures
`techniques` SHALL be `failed` with `result: null` and `error.code` `invalid_output` when the classifier response has a missing or unknown label, not all 18 labels, a score outside 0 to 1, or a different number of result lists than texts sent; `adapter_error` for a non-2xx answer, a connection error or an unreadable translation result; `timeout` when its timeout elapses; `cancelled` on job cancellation. It SHALL NOT fail the job or other analyzers.

#### Scenario: Unnamed labels
- **WHEN** the classifier answers with labels `LABEL_0` to `LABEL_17`
- **THEN** `techniques` is `failed` with `error.code: invalid_output` and the job ends `completed`

#### Scenario: No fallback model
- **WHEN** the chosen model's service answers HTTP 503
- **THEN** `techniques` is `failed` with `error.code: adapter_error` and the other model's service received no request

### Requirement: Technique classifier errors hide credentials
`error.message` of a failed `techniques` run and every member of its result MUST NOT contain credentials: no configured header value (such as `Authorization`) and no token, even when the classifier echoes them.

#### Scenario: Service echoes the token
- **WHEN** the classifier answers HTTP 401 with a body that repeats the bearer token
- **THEN** `error.message` does not contain the token

### Requirement: Technique result presentation
Sentence `text` and span `text` come from untrusted content; clients SHALL render them, `display` and `explanation` as plain text without HTML or Markdown interpretation. Clients SHALL present detections as indicators of a technique, not as proof of propaganda, and SHALL NOT present `score` as a calibrated probability across models.

#### Scenario: Markup in a sentence
- **WHEN** a SentenceDetection `text` contains `<b>LIES</b>`
- **THEN** a client shows those characters literally

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
