## Purpose
Result object of the propaganda technique analyzer: for the English translation of a job's text, every technique label with its score from the NCI document model, the NCI short-post model or both, with each model's cutoff, as clients read it from the analysis job API and event stream.

## ADDED Requirements

### Requirement: Technique classifier analyzer
A deployment that offers technique classification SHALL register it as a regular, selectable analyzer with id `techniques`, category `propaganda` and `depends_on` including `translation`. Clients SHALL locate its result as the AnalyzerRun with `id` `techniques` and SHALL treat a missing, `skipped` or `failed` run as "no technique analysis available", not as "no techniques found".

#### Scenario: Translation failed
- **WHEN** `translation` is `failed`
- **THEN** `techniques` is `skipped` with reason `dependency_failed`, `result: null`, and no model request is sent

#### Scenario: Deployment without the analyzer
- **WHEN** the registry has no `techniques` analyzer
- **THEN** jobs have no AnalyzerRun with that id and clients show no technique analysis, without error

### Requirement: English translation only
The `techniques` analyzer SHALL classify only the `translated_text` of the `translation` result and SHALL NOT send the job's original-language text to either model.

#### Scenario: Non-English job
- **WHEN** a job's content is German and `translation` succeeds with an English `translated_text`
- **THEN** each model request carries only the English `translated_text` and none carries the German content

### Requirement: Technique labels
The known technique labels SHALL be these 18 strings: `Loaded_Language`, `Appeal_to_fear-prejudice`, `Exaggeration,Minimisation`, `Repetition`, `Flag-Waving`, `Name_Calling,Labeling`, `Reductio_ad_hitlerum`, `Black-and-White_Fallacy`, `Causal_Oversimplification`, `Whataboutism,Straw_Men,Red_Herring`, `Straw_Man`, `Red_Herring`, `Doubt`, `Appeal_to_Authority`, `Thought-terminating_Cliches`, `Bandwagon`, `Slogans`, `Obfuscation,Intentional_Vagueness,Confusion`.

#### Scenario: Known labels
- **WHEN** a ModelResult is produced
- **THEN** each of these 18 strings appears as a `label` with `known: true`

### Requirement: Label handling by clients
Clients SHALL use `label` as the stable key of a technique and SHALL accept and show labels outside the known list.

#### Scenario: Labels are stable identifiers
- **WHEN** a client groups scores by technique
- **THEN** it uses `label` as the key

### Requirement: TechniqueAnalysis object
When `techniques` has `succeeded`, its `result` SHALL be a TechniqueAnalysis with at least: `words` (integer, whitespace-separated words of the classified text), `results` (non-empty array of ModelResult, at most one per model, `nci-technique` before `nci-social`) and `latency_ms` (number or null). It SHALL be the same in `analyzer.succeeded` and `GET /api/v1/jobs/{id}`. Clients SHALL ignore unknown members.

#### Scenario: Both models ran
- **WHEN** both models classified the text
- **THEN** `results` has two entries, the first with `model: "nci-technique"` and the second with `model: "nci-social"`

### Requirement: Model selection
`nci-social` (short-post model, at most 128 model tokens) SHALL run when the text fits the deployment's short-post bound, and `nci-technique` (document model) SHALL run when the text exceeds that bound or reaches the deployment's document minimum; every succeeded result SHALL contain at least one ModelResult. Selection SHALL depend only on the classified text, not on `input.source`.

#### Scenario: Short post
- **WHEN** the translated text has 20 words and the deployment's document minimum is 40 words
- **THEN** `results` has one ModelResult with `model: "nci-social"`

#### Scenario: Long document
- **WHEN** the translated text has 500 words
- **THEN** `results` has one ModelResult with `model: "nci-technique"`

#### Scenario: Platform does not matter
- **WHEN** two jobs have the same text, one with `source.platform: "x"` and one without `source`
- **THEN** both results have the same `results[].model` values and scores

### Requirement: Separate model results
When both models run, both ModelResults SHALL be kept separately. The analyzer SHALL NOT average, merge or combine their scores, and clients SHALL NOT compare or combine scores across models.

#### Scenario: No averaging
- **WHEN** both models ran and `Doubt` scored 0.6 from `nci-technique` and 0.2 from `nci-social`
- **THEN** the `nci-technique` ModelResult has `Doubt` with `score: 0.6`, the `nci-social` ModelResult has `Doubt` with `score: 0.2`, and no other `Doubt` score appears

### Requirement: ModelResult object
A ModelResult SHALL have at least `model` (values include `nci-technique` and `nci-social`), `cutoff` (number 0 to 1, the cutoff the deployment configured for that model when the job ran) and `scores` (array of TechniqueScore). `scores` SHALL contain exactly one TechniqueScore for each of the 18 known labels, in the order of the Technique labels requirement, followed by one TechniqueScore for each other label the model returned, in the model's order. Scores below the cutoff SHALL be present.

#### Scenario: Below-cutoff scores kept
- **WHEN** every label scores below the cutoff
- **THEN** `scores` still has 18 entries for the known labels, each with `above_cutoff: false`

### Requirement: TechniqueScore object
A TechniqueScore SHALL have at least `label` (string), `score` (number 0 to 1, the model's confidence in that technique on the English text; scores are independent and need not sum to 1), `model` and `cutoff` (equal to its ModelResult's), `above_cutoff` (boolean, `true` exactly when `score >= cutoff`) and `known` (boolean, `true` for the 18 known labels).

#### Scenario: Equality counts
- **WHEN** the `nci-social` cutoff is 0.3 and `Loaded_Language` scores 0.3
- **THEN** its TechniqueScore has `above_cutoff: true`

#### Scenario: Same score, different cutoffs
- **WHEN** `Loaded_Language` scores 0.4 from both models with cutoffs 0.5 (`nci-technique`) and 0.3 (`nci-social`)
- **THEN** it has `above_cutoff: false` in the `nci-technique` ModelResult and `above_cutoff: true` in the `nci-social` ModelResult

#### Scenario: Unfamiliar label
- **WHEN** a model returns the 18 known labels plus `Appeal_to_Pity` with score 0.7
- **THEN** the run succeeds and its ModelResult has 19 scores, the last with `label: "Appeal_to_Pity"`, `known: false`, `score: 0.7` and `above_cutoff` computed against the model's cutoff

### Requirement: Default cutoffs
Unless the deployment configures other values, `cutoff` SHALL be 0.5 for `nci-technique` and 0.3 for `nci-social`. A changed configuration SHALL be visible in `cutoff` of every result produced after the change.

#### Scenario: Configured cutoff
- **WHEN** the deployment sets the `nci-technique` cutoff to 0.6
- **THEN** new `nci-technique` ModelResults have `cutoff: 0.6` and `above_cutoff` is evaluated against 0.6

### Requirement: Technique classifier failures
`techniques` SHALL be `failed` with `result: null` and `error.code` `invalid_output` when a model response misses one of the 18 known labels, repeats a label, has a non-string label or a score outside 0 to 1; `adapter_error` for a non-2xx answer, a connection error or a missing or unreadable `translated_text`; `timeout` when its timeout elapses; `cancelled` on job cancellation. It SHALL NOT fail the job or other analyzers, and `propaganda_detection` SHALL be unaffected.

#### Scenario: Unnamed labels
- **WHEN** a model answers with labels `LABEL_0` to `LABEL_17`
- **THEN** `techniques` is `failed` with `error.code: invalid_output` and the job ends `completed`

### Requirement: No partial technique result
When two models are needed and either fails, `techniques` SHALL be `failed` with that model's error and `result: null`; a succeeded result SHALL contain every model the routing selected.

#### Scenario: One of two models fails
- **WHEN** both models are needed and the `nci-social` service answers HTTP 503
- **THEN** `techniques` is `failed` with `error.code: adapter_error` and `result: null`

### Requirement: Technique classifier errors hide credentials
`error.message` of a failed `techniques` run and every member of its result MUST NOT contain credentials: no configured header value (such as `Authorization`) and no token, even when a model service echoes them.

#### Scenario: Service echoes the token
- **WHEN** a model service answers HTTP 401 with a body that repeats the bearer token
- **THEN** `error.message` does not contain the token

### Requirement: Technique result presentation
Clients SHALL render `label` as plain text without HTML or Markdown interpretation. Clients SHALL present `above_cutoff` labels as indicators of a technique on the English translation, not as proof of propaganda; SHALL treat several labels being above cutoff at once as normal; SHALL NOT present a below-cutoff score as a detected technique; and SHALL NOT present `score` as a calibrated probability or compare it across models.

#### Scenario: Several techniques at once
- **WHEN** `Loaded_Language` and `Flag-Waving` are both `above_cutoff` in one ModelResult
- **THEN** a client shows both as indicated techniques
