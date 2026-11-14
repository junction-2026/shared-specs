## ADDED Requirements

### Requirement: English translation only
The `techniques` analyzer SHALL classify only the `translated_text` of the `translation` result and SHALL NOT send `Job.input.content` or any other original-language text to either model.

#### Scenario: Non-English job
- **WHEN** a job's content is German and `translation` succeeds with an English `translated_text`
- **THEN** every model request carries only the English `translated_text` and none carries the German content

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
A label returned by a model that is not one of the 18 known labels SHALL be kept as a TechniqueScore with `known: false` and `above_cutoff` evaluated against that model's cutoff; it SHALL NOT make the run fail. Clients SHALL key techniques by `label` and SHALL accept and show labels outside the known list.

#### Scenario: Extra label
- **WHEN** a model returns the 18 known labels plus `Appeal_to_Pity` with score 0.7
- **THEN** the run succeeds and that model's ModelResult has 19 scores, the last with `label: "Appeal_to_Pity"`, `display: "Appeal_to_Pity"`, `known: false` and `score: 0.7`

### Requirement: Separate model results
When both models run, both ModelResults SHALL be kept separately. The analyzer SHALL NOT average, merge or otherwise combine their scores, and clients SHALL NOT compare or combine scores across models.

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

### Requirement: Technique score presentation
Clients SHALL render `label` and `display` as plain text without HTML or Markdown interpretation. Clients SHALL present `above_cutoff` labels as indicators of a technique on the English translation, not as proof of propaganda; SHALL treat several labels above cutoff at once as normal; SHALL NOT present a below-cutoff score as a detected technique; and SHALL NOT present `score` as a calibrated probability or compare it across models.

#### Scenario: Several techniques at once
- **WHEN** `Loaded_Language` and `Flag-Waving` are both `above_cutoff` in one ModelResult
- **THEN** a client shows both as indicated techniques

#### Scenario: Markup in a label
- **WHEN** an unfamiliar `label` is `<b>LIES</b>`
- **THEN** a client shows those characters literally

## MODIFIED Requirements

### Requirement: Technique classifier analyzer
A deployment that offers technique classification SHALL register it as a regular, selectable analyzer with id `techniques`, category `propaganda` and `depends_on` including `translation`. Clients SHALL locate its result as the AnalyzerRun with `id` `techniques` and SHALL treat a missing, `skipped` or `failed` run as "no technique analysis available", not as "no techniques found".

#### Scenario: Translation failed
- **WHEN** `translation` is `failed`
- **THEN** `techniques` is `skipped` with reason `dependency_failed`, `result: null`, and no model request is sent

#### Scenario: Deployment without the analyzer
- **WHEN** the registry has no `techniques` analyzer
- **THEN** jobs have no AnalyzerRun with that id and clients show no technique analysis, without error

### Requirement: Technique names
Known `label` values SHALL be these 18 strings: `Loaded_Language`, `Appeal_to_fear-prejudice`, `Exaggeration,Minimisation`, `Repetition`, `Flag-Waving`, `Name_Calling,Labeling`, `Reductio_ad_hitlerum`, `Black-and-White_Fallacy`, `Causal_Oversimplification`, `Whataboutism,Straw_Men,Red_Herring`, `Straw_Man`, `Red_Herring`, `Doubt`, `Appeal_to_Authority`, `Thought-terminating_Cliches`, `Bandwagon`, `Slogans`, `Obfuscation,Intentional_Vagueness,Confusion`.

#### Scenario: Names are stable identifiers
- **WHEN** a client groups scores by technique
- **THEN** it uses `label` as the key and `display` only as the shown name

### Requirement: TechniqueClassification object
When `techniques` has `succeeded`, its `result` SHALL be a TechniqueClassification with at least `words` (integer, the number of whitespace-separated words of the classified English text) and `results` (non-empty array of ModelResult, at most one per model, `nci-technique` before `nci-social`). It SHALL be the same in `analyzer.succeeded` and `GET /api/v1/jobs/{id}`. Clients SHALL ignore unknown members.

#### Scenario: Short text
- **WHEN** a job's English translation has 20 words and the defaults apply
- **THEN** `result.words` is 20 and `result.results` has one ModelResult with `model: "nci-social"` and `cutoff: 0.3`

#### Scenario: Both models ran
- **WHEN** both models classified the text
- **THEN** `results` has two entries, the first with `model: "nci-technique"` and the second with `model: "nci-social"`

#### Scenario: Result from before this change
- **WHEN** a client reads a `techniques` result stored before this change, which has no `results` array
- **THEN** it shows no technique analysis for that job, without error

### Requirement: Model and words
`nci-social` (the short-post model, at most 128 model tokens) SHALL run when `words` is at most the deployment's short-post bound. `nci-technique` (the document model) SHALL run when `words` is at least the deployment's document minimum or above the short-post bound. The defaults SHALL be 80 words for the short-post bound and 40 words for the document minimum. Selection SHALL NOT depend on `input.source`.

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
- **THEN** both results have the same `results[].model` values and scores

### Requirement: Technique classifier failures
`techniques` SHALL be `failed` with `result: null` and an `error.code` that includes: `invalid_output` when a model response misses a known label, repeats a label, has a missing or empty label or a score outside 0 to 1; `adapter_error` for a non-2xx answer, a connection error or an unreadable `translated_text`; `timeout` when its timeout elapses; `cancelled` on job cancellation. It SHALL NOT fail the job or other analyzers or affect `propaganda_detection`.

#### Scenario: Unnamed labels
- **WHEN** a model answers with labels `LABEL_0` to `LABEL_17` only
- **THEN** `techniques` is `failed` with `error.code: invalid_output` (known labels missing) and the job ends `completed`

#### Scenario: No fallback model
- **WHEN** only `nci-technique` is selected and its service answers HTTP 503
- **THEN** `techniques` is `failed` with `error.code: adapter_error` and the `nci-social` service received no request

## REMOVED Requirements

### Requirement: Scores and thresholds
**Reason**: Replaced by ModelResult and TechniqueScore: one cutoff per model, echoed in every score; no `techniques`, `thresholds` or `max_score` members and no per-technique overrides.
**Migration**: Read `results[].scores[]` (`label`, `score`, `cutoff`, `above_cutoff`) instead of `techniques`, `thresholds` and `max_score`.

### Requirement: Detected techniques
**Reason**: `detected` and the Detection object are replaced by `above_cutoff` on every TechniqueScore of every ModelResult.
**Migration**: Filter `results[].scores[]` by `above_cutoff: true`.

### Requirement: Sentence detections
**Reason**: The NCI models score the whole text; per-sentence detections are out of scope of junction-2026/project#16.
**Migration**: None; no client reads `sentences`. Highlighting may return later as an additive member.

### Requirement: Sentence offsets
**Reason**: Removed together with sentence detections; `offsets_in` no longer exists.
**Migration**: None; no client reads `offsets_in`.

### Requirement: Technique result presentation
**Reason**: Sentence `text`, Detection `display` and `explanation` no longer exist; replaced by the Technique score presentation requirement for `label`, `display` and `above_cutoff`.
**Migration**: Apply the Technique score presentation requirement.
