## ADDED Requirements

### Requirement: English translation only
Every classification request of the `techniques` analyzer to `nci-technique` or `nci-social` SHALL carry only the `translated_text` of the `translation` result and SHALL NOT carry `Job.input.content` or any other original-language text. The span step is governed by the span requirements: it sends sentences of `Job.input.content` to the sentence model only when `span_method` is `sentence` (`source_language` `en`).

#### Scenario: Non-English job
- **WHEN** a job's content is German and `translation` succeeds with an English `translated_text`
- **THEN** every request to `nci-technique` and `nci-social` carries only English text from `translated_text` and none carries the German content

### Requirement: ModelResult object
A ModelResult SHALL have at least `model` (values include `nci-technique` and `nci-social`), `cutoff` (number 0 to 1, the cutoff the deployment configured for that model when the job ran), `scores` (array of TechniqueScore) and `latency_ms` (number or null, as reported by the model service). Scores below the cutoff SHALL be present.

#### Scenario: Below-cutoff scores kept
- **WHEN** every label scores below the cutoff
- **THEN** `scores` still has an entry for each of the 18 known labels, each with `above_cutoff: false`

### Requirement: Score list order
`scores` SHALL hold exactly one TechniqueScore per known label (so a client indexing by `label` never sees two scores for one label from one model), in the order of the Technique names requirement, followed by one TechniqueScore for each other label the model returned, in the model's order. Clients sort for display.

#### Scenario: Known labels first
- **WHEN** a model returns `Appeal_to_Pity` before the 18 known labels
- **THEN** `scores` starts with `Loaded_Language` and ends with `Appeal_to_Pity`

### Requirement: TechniqueScore object
A TechniqueScore SHALL have at least `label` (string), `display` (non-empty string: the built-in display name of a known label, otherwise the label itself), `score` (number 0 to 1, the model's confidence in that technique on the English translation; scores are independent and need not sum to 1), `model` and `cutoff` (equal to those of its ModelResult), `above_cutoff` (boolean, `true` when `score >= cutoff` and `false` otherwise) and `known` (boolean, `true` for the 18 known labels).

#### Scenario: Equality counts
- **WHEN** the `nci-social` cutoff is 0.3 and `Loaded_Language` scores 0.3
- **THEN** its TechniqueScore has `above_cutoff: true`

#### Scenario: Just below the cutoff
- **WHEN** the `nci-technique` cutoff is 0.5 and `Doubt` scores 0.49
- **THEN** its TechniqueScore is present with `score: 0.49` and `above_cutoff: false`

#### Scenario: Same score, different cutoffs
- **WHEN** both models ran with cutoffs 0.5 (`nci-technique`) and 0.3 (`nci-social`) and `Loaded_Language` scores 0.4 from both
- **THEN** it has `above_cutoff: false` in the `nci-technique` ModelResult and `above_cutoff: true` in the `nci-social` ModelResult

### Requirement: Unfamiliar labels
A label returned by a model that is not one of the 18 known labels SHALL be kept as a TechniqueScore with `known: false` and `above_cutoff` evaluated against that model's cutoff; it SHALL NOT make the run fail and SHALL NOT appear in `detected`. Clients SHALL key scores by `label` and SHALL accept labels outside the known list.

#### Scenario: Extra label
- **WHEN** a model returns the 18 known labels plus `Appeal_to_Pity` with score 0.7
- **THEN** the run succeeds, that model's ModelResult has 19 scores, the last with `label: "Appeal_to_Pity"`, `display: "Appeal_to_Pity"`, `known: false`, `score: 0.7` and `above_cutoff: true`, and `detected` has no `Appeal_to_Pity` entry

### Requirement: Separate model results
When both models run, both ModelResults SHALL be kept separately. The analyzer SHALL NOT average, merge or otherwise combine their scores into one score, and clients SHALL NOT compare or combine scores across models.

#### Scenario: No averaging
- **WHEN** both models ran and `Doubt` scored 0.6 from `nci-technique` and 0.2 from `nci-social`
- **THEN** the `nci-technique` ModelResult has `Doubt` with `score: 0.6`, the `nci-social` ModelResult has `Doubt` with `score: 0.2`, and no other `Doubt` score appears in the result

### Requirement: Default cutoffs
Unless the deployment configures other values, `cutoff` SHALL be 0.5 for `nci-technique` and 0.3 for `nci-social`. A changed configuration SHALL be visible in `cutoff` of every result produced after the change.

#### Scenario: Configured cutoff
- **WHEN** the deployment sets the `nci-technique` cutoff to 0.6
- **THEN** new `nci-technique` ModelResults have `cutoff: 0.6` and every `above_cutoff` in them is evaluated against 0.6

### Requirement: No partial technique result
When two models are selected and either fails, `techniques` SHALL be `failed` with that model's error and `result: null`. A succeeded result SHALL contain a ModelResult for every model the routing selected.

#### Scenario: One of two models fails
- **WHEN** both models are selected and the `nci-social` service answers HTTP 503
- **THEN** `techniques` is `failed` with `error.code: adapter_error` and `result: null`

### Requirement: Detected techniques by cutoff
`detected` SHALL list a Detection for each known technique name that has `above_cutoff: true` in at least one ModelResult, in the order of the Technique names requirement, and SHALL be empty when there is none. Unfamiliar labels SHALL NOT appear in `detected`.

#### Scenario: Above cutoff in one model only
- **WHEN** both models ran with default cutoffs and `Loaded_Language` scores 0.4 from both
- **THEN** `detected` has `Loaded_Language` with `models: ["nci-social"]`

#### Scenario: Above cutoff in both models
- **WHEN** `Doubt` is above cutoff in both ModelResults
- **THEN** `detected` has one `Doubt` entry with `models: ["nci-technique", "nci-social"]`

#### Scenario: Nothing above cutoff
- **WHEN** no known label is above cutoff in any ModelResult
- **THEN** `detected` is an empty array and every score is still present in `results`

### Requirement: Detection object
A Detection SHALL have at least `name`, `display`, `explanation` (non-empty one-line string), `models` (non-empty array of the `model` values of the ModelResults in which it is above cutoff, in `results` order) and `spans` (array of TechniqueSpan, possibly empty). A Detection carries no score of its own; clients read scores from `results`.

#### Scenario: Detection members
- **WHEN** `Doubt` is above cutoff only in the `nci-technique` ModelResult
- **THEN** its Detection has `name: "Doubt"`, a non-empty `display` and `explanation`, `models: ["nci-technique"]` and a `spans` array

### Requirement: Technique score presentation
Span `text`, `label`, `display` and `explanation` come from untrusted content or model output; clients SHALL render them as plain text without HTML or Markdown interpretation. Clients SHALL present detections as indicators of a technique on the English translation, not as proof of propaganda, and SHALL treat several techniques at once as normal.

#### Scenario: Markup in a label
- **WHEN** an unfamiliar `label` is `<b>LIES</b>`
- **THEN** a client that shows it shows those characters literally

#### Scenario: Several techniques at once
- **WHEN** `Loaded_Language` and `Flag-Waving` are both in `detected`
- **THEN** a client shows both as indicated techniques

### Requirement: Technique score interpretation
Clients that show scores SHALL NOT present a below-cutoff score as a detected technique, SHALL NOT present `score` as a calibrated probability and SHALL NOT compare or combine scores across models.

#### Scenario: Below-cutoff score shown
- **WHEN** a client lists `Doubt` with `score: 0.2` and `above_cutoff: false`
- **THEN** it does not mark `Doubt` as an indicated technique

## MODIFIED Requirements

### Requirement: Technique names
Known technique names SHALL be these 18 strings: `Loaded_Language`, `Appeal_to_fear-prejudice`, `Exaggeration,Minimisation`, `Repetition`, `Flag-Waving`, `Name_Calling,Labeling`, `Reductio_ad_hitlerum`, `Black-and-White_Fallacy`, `Causal_Oversimplification`, `Whataboutism,Straw_Men,Red_Herring`, `Straw_Man`, `Red_Herring`, `Doubt`, `Appeal_to_Authority`, `Thought-terminating_Cliches`, `Bandwagon`, `Slogans`, `Obfuscation,Intentional_Vagueness,Confusion`. They are the known `label` values.

#### Scenario: Names are stable identifiers
- **WHEN** a client groups detections or scores by technique
- **THEN** it uses `name` (Detection) or `label` (TechniqueScore) as the key and `display` only as the shown name

### Requirement: TechniqueClassification object
When `techniques` has `succeeded`, its `result` SHALL be a TechniqueClassification with at least: `words` (integer), `results` (non-empty array of ModelResult, at most one per model, `nci-technique` before `nci-social`) and `detected`, plus the members of the Span result members requirement. It SHALL be the same in `analyzer.succeeded` and `GET /api/v1/jobs/{id}`. Clients SHALL ignore unknown members.

#### Scenario: Short text
- **WHEN** a job's English translation has 20 words and the defaults apply
- **THEN** `result.words` is 20 and `result.results` has one ModelResult with `model: "nci-social"` and `cutoff: 0.3`

#### Scenario: Both models ran
- **WHEN** both models classified the text
- **THEN** `results` has two entries, the first with `model: "nci-technique"` and the second with `model: "nci-social"`

#### Scenario: Result from before this change
- **WHEN** a client reads a `techniques` result stored before this change, which has `detected` but no `results` array
- **THEN** it shows the detected techniques as before and shows no per-model scores, without error

### Requirement: Model and words
`words` SHALL be the number of whitespace-separated words of the classified English text. `nci-social` (the short-post model, at most 128 model tokens) SHALL run when `words` is at most the deployment's short-post bound. `nci-technique` (the document model) SHALL run when `words` is at least the deployment's document minimum or above the short-post bound. The defaults SHALL be 80 words for the short-post bound and 40 words for the document minimum. Selection SHALL NOT depend on `input.source`.

#### Scenario: Short post
- **WHEN** the translated text has 39 words and the defaults apply
- **THEN** `results` has one ModelResult with `model: "nci-social"`

#### Scenario: Both models
- **WHEN** the translated text has 40 words, then 80 words, and the defaults apply
- **THEN** each `results` has a `nci-technique` and a `nci-social` ModelResult

#### Scenario: Long document
- **WHEN** the translated text has 81 words and the defaults apply
- **THEN** `results` has one ModelResult with `model: "nci-technique"`

#### Scenario: Platform does not matter
- **WHEN** two jobs have the same text, one with `source.platform: "x"` and one without `source`
- **THEN** both results have the same `results[].model` values, scores and `detected` names

### Requirement: Technique classifier failures
`techniques` SHALL be `failed` with `result: null` and an `error.code` that includes: `invalid_output` when a model response misses a known label, repeats a label, has a missing or empty label, has a score outside 0 to 1 or is not readable as label scores; `adapter_error` for a non-2xx answer, a connection error or an unreadable translation result; `timeout` when its timeout elapses; `cancelled` on job cancellation. It SHALL NOT fail the job or other analyzers or affect `propaganda_detection`.

#### Scenario: Unnamed labels
- **WHEN** a model answers with labels `LABEL_0` to `LABEL_17` only
- **THEN** `techniques` is `failed` with `error.code: invalid_output` (known labels missing) and the job ends `completed`

#### Scenario: No fallback model
- **WHEN** only `nci-technique` is selected and its service answers HTTP 503
- **THEN** `techniques` is `failed` with `error.code: adapter_error` and the `nci-social` service received no classification request

### Requirement: Detected techniques keep empty spans
A technique SHALL NOT be removed from `detected` because it has no span, and no paraphrased or translated text SHALL be substituted as its span.

#### Scenario: Detected technique without span
- **WHEN** `Doubt` is above cutoff in a ModelResult and no span is accepted for it
- **THEN** `Doubt` is in `detected` with `spans: []`

### Requirement: Span highlighting presentation
Clients that highlight techniques in the user's text SHALL highlight the `[start, end)` ranges of `detected[].spans` in `Job.input.content` rendered as plain text, and SHALL list a detected technique whose `spans` is empty or missing without a highlight. Clients SHALL NOT present any part of the translation, including `sentences[].text` of results stored before this change, as the user's words.

#### Scenario: Markup in highlighted content
- **WHEN** `Job.input.content` is `"<i>They</i> are LYING"` and a span covers `"LYING"`
- **THEN** a client shows `<i>They</i>` literally and highlights only `LYING`

### Requirement: Sentence spans for English input
When `span_method` is `sentence`, the deployment SHALL split `Job.input.content` into sentences and score them with its sentence-level technique model (`nci-social`), independent of which models produced `results` and of `words`. For each Detection in `detected`, every scored sentence whose sentence-model score for that technique is at or above the sentence model's effective threshold for it SHALL be a span whose `text` is the sentence.

#### Scenario: English job
- **WHEN** an English job with content `"Wake up. They are LYING to you."` has `Loaded_Language` in `detected`, the sentence model scores `"They are LYING to you."` above its `Loaded_Language` threshold and `"Wake up."` below it
- **THEN** `Loaded_Language` has one span `{technique: "Loaded_Language", text: "They are LYING to you.", start: 9, end: 31}`

### Requirement: Span failures keep the classification
A failure of the span step SHALL NOT change the AnalyzerRun status, `results` or `detected` membership. When the sentence model or the LLM answers non-2xx, cannot be reached or gives an unreadable answer, `span_status` SHALL be `failed`; when the span step's own deadline elapses it SHALL be `timeout`; in both cases every `detected[].spans` SHALL be `[]`. The `timeout` failure of the whole run applies only when the analyzer's overall timeout elapses.

#### Scenario: LLM times out
- **WHEN** a German job has `Doubt` in `detected` and the span LLM does not answer before the span deadline
- **THEN** `techniques` is `succeeded`, `span_status` is `timeout` and `Doubt` is in `detected` with `spans: []`

#### Scenario: Sentence model error
- **WHEN** the sentence model answers HTTP 503 for an English job
- **THEN** `techniques` is `succeeded` with `span_status: failed`, every `detected[].spans` empty and the same `results` and `detected` names as without span support

## REMOVED Requirements

### Requirement: Scores and thresholds
**Reason**: Replaced by ModelResult and TechniqueScore: one cutoff per model, echoed in every score; no top-level `model`, `threshold`, `thresholds`, `techniques`, `max_score` or `latency_ms` and no per-technique overrides.
**Migration**: Read `results[].scores[]` (`label`, `score`, `cutoff`, `above_cutoff`) and `results[].latency_ms` instead. The frontend @ 1abe19a reads none of the removed members.

### Requirement: Sentence detections
**Reason**: The NCI models score the whole translated text; per-sentence detections on the translation are out of scope of junction-2026/project#16. Highlighting in the user's text is provided by `detected[].spans`.
**Migration**: Use `detected[].spans`. The frontend @ 1abe19a never renders `sentences`.

### Requirement: Sentence offsets
**Reason**: Removed together with sentence detections; `offsets_in` no longer exists.
**Migration**: None; span offsets always refer to `Job.input.content`. The frontend @ 1abe19a does not read `offsets_in`.

### Requirement: Detected techniques
**Reason**: Membership by one model's document score and per-technique thresholds, sorted by score, is replaced by "Detected techniques by cutoff": `above_cutoff` in at least one ModelResult, Detection with `models` and without its own `score`; `name`, `display`, `explanation` and `spans` are unchanged.
**Migration**: Keep reading `detected[].name`, `display`, `explanation` and `spans`; read per-model scores from `results[].scores[]` instead of Detection `score`. The frontend @ 1abe19a does not read Detection `score`.

### Requirement: Technique result presentation
**Reason**: Sentence `text` no longer exists; replaced by "Technique score presentation", which keeps the plain-text and indicator rules and adds `label` and `above_cutoff`.
**Migration**: Apply "Technique score presentation"; span `text` stays plain text.
