# manipulation-risk-score Specification

## Purpose
Manipulation Risk Score of an analysis job: one transparent, deterministic 0–1 score with band, dimension breakdown, detected techniques, main drivers, caveats and the configuration used, computed only from the existing technique, propaganda and bot-detection analyzer results, as clients read it from the analysis job API and event stream.

## Requirements

### Requirement: Risk score inputs
The orchestrator SHALL compute the risk score without any model, provider or network call, only from the settled AnalyzerRuns `techniques` (results `nci-technique` and `nci-social`), `propaganda_detection` and `bot_detection`, plus `Job.input.source`, `Job.scrape` and the `translation` result's `source_language`. No other analyzer, the finalizer or the FinalAssessment SHALL influence it.

#### Scenario: Fact check does not count
- **WHEN** two jobs have equal `techniques`, `propaganda_detection` and `bot_detection` results and inputs, and only one has a succeeded `fact_check`
- **THEN** both have equal `risk` objects

#### Scenario: Finalizer failure
- **WHEN** finalization fails with `error.code: timeout`
- **THEN** `Job.risk` is unchanged and still non-null

### Requirement: Missing input runs
An input AnalyzerRun that is missing, `skipped` or `failed` SHALL make only its own dimension unavailable; the score SHALL be computed from the remaining dimensions as defined in this capability.

#### Scenario: Bot detector not configured
- **WHEN** the registry has no `bot_detection` analyzer and `techniques` and `propaganda_detection` succeeded
- **THEN** `risk.status` is `scored` and only `dimensions.amplification` is unavailable

### Requirement: Risk score determinism
The same inputs and configuration SHALL always yield an equal RiskScore. Numbers SHALL be the computed IEEE-754 double values, not rounded by the server; clients round for display only. Scenario values in this capability are rounded to 4 decimals.

#### Scenario: Same input twice
- **WHEN** two jobs are created with the same text and their three input runs return equal results
- **THEN** their `risk` objects are equal

### Requirement: When the risk score is computed
The orchestrator SHALL compute the RiskScore once per job when every AnalyzerRun is settled and SHALL set `Job.risk` when `analysis.ready_for_finalization` is emitted, before finalization starts. A set RiskScore SHALL never change. Every job that reaches this point SHALL get a non-null RiskScore, also when no input run succeeded.

#### Scenario: Completed job
- **WHEN** a job ends `completed`
- **THEN** `risk` is a RiskScore and `job.completed` `data.job.risk` equals the `data.risk` of its `analysis.ready_for_finalization`

### Requirement: Jobs without a risk score
`Job.risk` SHALL be null before every AnalyzerRun is settled and SHALL stay null for jobs that never reach that point (cancelled before it, failed scrape, interrupted by a restart before it). Jobs stored before this change have no `risk`. Clients SHALL then show no risk score, without error.

#### Scenario: Running job
- **WHEN** a client reads a job whose `techniques` run is still `running`
- **THEN** `risk` is null

#### Scenario: Stored before this change
- **WHEN** a client reads a persisted job completed before this change
- **THEN** it has no `risk` member and the client shows no risk score, without error

### Requirement: RiskScore object
A RiskScore SHALL have at least: `version` (integer, 1); `status`; `reason`; `score` and `raw_score`; `band`; `dampened` (boolean); `summary` (non-empty one-line English plain text); `dimensions` (members `intensity`, `confirmation`, `amplification`, each a RiskDimension); `techniques` (array of RiskTechnique); `drivers` (array of RiskDriver); `caveats` (array of RiskCaveat); `config` (RiskConfig). Clients SHALL ignore unknown members.

#### Scenario: Members present
- **WHEN** a job reaches the barrier with `techniques` and `propaganda_detection` succeeded
- **THEN** `risk` has `version: 1`, `status`, `reason`, `score`, `raw_score`, `band`, `dampened`, a non-empty `summary`, all three dimensions, `techniques`, `drivers`, `caveats` and `config`

### Requirement: RiskScore status
`status` values SHALL include `scored` and `unavailable`. When `scored`: `reason` is null, `score` and `raw_score` are numbers 0 to 1 and `band` is a band id. When `unavailable`: `reason` values include `no_content_signals`, and `score`, `raw_score` and `band` are null. Clients SHALL treat an unknown `status` like `unavailable`.

#### Scenario: Nothing to score
- **WHEN** `techniques` and `propaganda_detection` both failed
- **THEN** `risk.status` is `unavailable`, `reason` is `no_content_signals` and `score`, `raw_score` and `band` are null

### Requirement: No score without context
When `status` is `scored`, the RiskScore SHALL have at least one RiskDriver and at least one RiskCaveat. When `unavailable`, `drivers` SHALL be `[]` and `caveats` SHALL still be non-empty. Clients SHALL NOT show a score without its band, its drivers and access to its caveats.

#### Scenario: Unavailable keeps caveats
- **WHEN** `risk.status` is `unavailable`
- **THEN** `drivers` is `[]` and `caveats` contains `content_not_reader`

### Requirement: RiskDimension object
A RiskDimension SHALL have at least: `available` (boolean); `score` (number 0 to 1, null when not available); `weight` (effective weight in the combination, 0 when not available); `contribution` (`weight * score`, 0 when not available); `confidence` (`normal`, `low`, or null when not available); `reason`; `source` (analyzer id read, or null).

#### Scenario: Available dimension
- **WHEN** confirmation is read from a succeeded `propaganda_detection`
- **THEN** `dimensions.confirmation` has `available: true`, `confidence: "normal"`, `reason: null` and `source: "propaganda_detection"`

### Requirement: Dimension unavailability reasons
`reason` SHALL be null for an available dimension; otherwise its values include `analyzer_unavailable`, `no_scores`, `no_author_context` and `no_bot_score`. Clients SHALL treat an unknown `reason` as "input not available".

#### Scenario: Unavailable dimension
- **WHEN** the job has no `bot_detection` AnalyzerRun and a non-empty `input.source.author`
- **THEN** `dimensions.amplification` has `available: false`, `score: null`, `weight: 0`, `contribution: 0`, `confidence: null` and `reason: "analyzer_unavailable"`

### Requirement: Intensity dimension members
`dimensions.intensity` SHALL also have at least: `model` (`nci-technique`, `nci-social` or null); `words` (integer or null, the `techniques` result's `words`); `short_text` (boolean, true when `model` is `nci-social`); `detected_count` (integer); `density`, `weighted_sum` and `weighted_intensity` (numbers, null when not available). Its `confidence` SHALL be `normal` when available.

#### Scenario: Short post members
- **WHEN** a 30-word text is analysed and the defaults apply
- **THEN** `dimensions.intensity` has `model: "nci-social"`, `words: 30` and `short_text: true`

### Requirement: Technique model choice
Intensity SHALL be read from exactly one ModelResult of a succeeded `techniques` result: `nci-social` when it exists and `words` is at most `config.short_text_max_words`; otherwise `nci-technique` when it exists; otherwise `nci-social`. Scores of the two models SHALL NOT be combined.

#### Scenario: Both models ran
- **WHEN** the text has 60 words, both ModelResults exist and the defaults apply
- **THEN** intensity uses `nci-social` and `short_text` is true

#### Scenario: Long document
- **WHEN** the text has 300 words and only the `nci-technique` ModelResult exists
- **THEN** intensity uses `nci-technique` and `short_text` is false

### Requirement: Intensity unavailable
When `techniques` is not `succeeded`, intensity SHALL be unavailable with `analyzer_unavailable`. When its result has no non-empty `results` array (stored before per-model scores), intensity SHALL be unavailable with `no_scores`.

#### Scenario: Technique run failed
- **WHEN** `techniques` is `failed`
- **THEN** `dimensions.intensity` has `available: false`, `reason: "analyzer_unavailable"` and `risk.techniques` is `[]`

### Requirement: Risk-detected techniques
A technique SHALL count for the risk score when its TechniqueScore in the chosen ModelResult has `known: true` and `score` strictly greater than `config.detection_threshold`. This threshold is independent of the ModelResult `cutoff`, so the risk list MAY differ from the `techniques` result's `detected`.

#### Scenario: Equal to the threshold
- **WHEN** the threshold is 0.3 and `Doubt` scores exactly 0.3
- **THEN** `Doubt` is not in `risk.techniques`

#### Scenario: Below the document cutoff
- **WHEN** `nci-technique` has cutoff 0.5 and `Loaded_Language` scores 0.4
- **THEN** `Loaded_Language` is in `risk.techniques` although it is not in the `techniques` result's `detected`

### Requirement: High and medium impact groups
Each known technique SHALL belong to one impact group, whose weight is `config.impact_weights.<group>`. Group `high`: `Appeal_to_fear-prejudice`, `Loaded_Language`, `Reductio_ad_hitlerum`, `Black-and-White_Fallacy`. Group `medium`: `Name_Calling,Labeling`, `Exaggeration,Minimisation`, `Causal_Oversimplification`, `Thought-terminating_Cliches`, `Bandwagon`, `Slogans`.

#### Scenario: High-impact technique
- **WHEN** `Loaded_Language` counts with defaults
- **THEN** its RiskTechnique has `impact: "high"` and `weight: 1`

### Requirement: Lower impact group
Group `lower` SHALL hold `Doubt`, `Repetition`, `Flag-Waving`, `Straw_Man`, `Red_Herring`, `Whataboutism,Straw_Men,Red_Herring`, `Appeal_to_Authority` and `Obfuscation,Intentional_Vagueness,Confusion`.

#### Scenario: Lower-impact technique
- **WHEN** `Flag-Waving` counts with defaults
- **THEN** its RiskTechnique has `impact: "lower"` and `weight: 0.4`

### Requirement: RiskTechnique object
A RiskTechnique SHALL have at least `label` (technique name), `display` (the TechniqueScore's `display`), `probability` (its `score`), `impact` (`high`, `medium` or `lower`), `weight` (the impact weight) and `contribution` (`probability * weight`).

#### Scenario: Contribution
- **WHEN** `Doubt` counts with score 0.35 and defaults
- **THEN** its RiskTechnique has `probability: 0.35`, `impact: "lower"`, `weight: 0.4` and `contribution: 0.14`

### Requirement: Risk technique list
`techniques` SHALL hold one RiskTechnique per counted technique, ordered by `probability` descending, ties in the order of the Technique names requirement of technique-classifier-result. It SHALL be `[]` when intensity is unavailable or nothing counts.

#### Scenario: Ordering
- **WHEN** `Doubt` 0.35, `Appeal_to_fear-prejudice` 0.9 and `Loaded_Language` 0.7 count
- **THEN** `techniques` lists `Appeal_to_fear-prejudice`, `Loaded_Language`, `Doubt`

### Requirement: Intensity computation
With N counted techniques: `density = min(1, N / config.reference_technique_count)`; `weighted_sum` is the sum of the RiskTechnique `contribution`s; `weighted_intensity = min(1, weighted_sum / config.weighted_sum_reference)`; intensity `score = (density + weighted_intensity) / 2`; `detected_count = N`. With N = 0 intensity SHALL be available with score 0.

#### Scenario: Three techniques
- **WHEN** the defaults apply and `Appeal_to_fear-prejudice` 0.9, `Loaded_Language` 0.7 and `Doubt` 0.35 count
- **THEN** `detected_count` is 3, `density` 0.5, `weighted_sum` 1.74, `weighted_intensity` 0.348 and intensity `score` 0.424

#### Scenario: Plausible maximum stays below 1
- **WHEN** the defaults apply and six high-impact techniques each score 0.8
- **THEN** `weighted_intensity` is 0.96 and intensity `score` is 0.98

### Requirement: Confirmation dimension
Confirmation SHALL be available when `propaganda_detection` is `succeeded` and its `result.result` array holds an element with label `PROPAGANDA` or `NO_PROPAGANDA`; its `score` SHALL be the `score` of the first `PROPAGANDA` element, else `1 - score` of the first `NO_PROPAGANDA` element. Otherwise it SHALL be unavailable with `analyzer_unavailable`.

#### Scenario: Propaganda answer
- **WHEN** `propaganda_detection` returns `{"result": [{"label": "PROPAGANDA", "score": 0.8}]}`
- **THEN** confirmation has `score` 0.8

### Requirement: Confirmation dimension members
`dimensions.confirmation` SHALL also have at least `label` and `model_score` (label and score of the element used, null when not available) and `weak_signal` (boolean, true when available and `score < config.dampening_threshold`).

#### Scenario: No propaganda answer
- **WHEN** `propaganda_detection` returns `{"result": [{"label": "NO_PROPAGANDA", "score": 0.9}]}`
- **THEN** confirmation has `score` 0.1, `label: "NO_PROPAGANDA"`, `model_score: 0.9` and `weak_signal: true`

### Requirement: Author context
A job SHALL have author context when `Job.scrape` is non-null with `status: succeeded`, or `Job.input.source.author` is a string that is non-empty after trimming. Without author context, amplification SHALL be unavailable with `no_author_context`, regardless of `bot_detection`.

#### Scenario: Plain text job
- **WHEN** a job is created with `{"input": {"content": "..."}}` only
- **THEN** `dimensions.amplification.reason` is `no_author_context`

### Requirement: Bot detection reading
With author context, amplification SHALL read a succeeded `bot_detection` result through the deployment's mapping to an author-level score (0 to 1), an author post count (integer) and a single-text score (0 to 1), each possibly absent. A `bot_detection` run that is missing, skipped or failed SHALL make amplification unavailable with `analyzer_unavailable`.

#### Scenario: Bot detector failed
- **WHEN** a scrape job's `bot_detection` is `failed`
- **THEN** `dimensions.amplification.reason` is `analyzer_unavailable`

### Requirement: Amplification basis
When the author-level score and a post count of at least `config.min_author_posts` are present, amplification `score` SHALL be the author-level score with `basis: "author"`, `confidence: "normal"`. Otherwise, with a single-text score, `score` SHALL be it with `basis: "single_text"`, `confidence: "low"`. Otherwise amplification SHALL be unavailable with `no_bot_score`.

#### Scenario: Author history
- **WHEN** a scrape job's bot result maps to author score 0.9 over 120 posts and the defaults apply
- **THEN** amplification has `score` 0.9, `basis: "author"`, `author_posts: 120` and `confidence: "normal"`

#### Scenario: Too few posts
- **WHEN** the bot result maps to author score 0.9 over 12 posts and single-text score 0.6
- **THEN** amplification has `score` 0.6, `basis: "single_text"`, `author_posts: 12` and `confidence: "low"`

### Requirement: Amplification dimension members
`dimensions.amplification` SHALL also have at least `basis` (`author`, `single_text` or null) and `author_posts` (integer or null, the mapped post count).

#### Scenario: Without author context
- **WHEN** amplification has reason `no_author_context`
- **THEN** it has `basis: null` and `author_posts: null`

### Requirement: Dimension weights
The base weights SHALL be `config.weights_with_amplification` when amplification is available, otherwise `config.weights_without_amplification`. When intensity or confirmation is unavailable, the base weights of the available dimensions SHALL be divided by their sum. Each available dimension's `weight` SHALL be its effective weight.

#### Scenario: Confirmation missing
- **WHEN** the defaults apply, intensity is 0.424, `propaganda_detection` failed and amplification 0.9
- **THEN** intensity `weight` is 0.5714, amplification `weight` 0.4286 and `raw_score` 0.6280

### Requirement: Dimension combination
`raw_score` SHALL be the sum of the available dimensions' `contribution`s. When neither intensity nor confirmation is available, `status` SHALL be `unavailable` with `no_content_signals`, also when amplification is available.

#### Scenario: Without amplification
- **WHEN** the defaults apply, intensity is 0.424, confirmation 0.8 and amplification unavailable
- **THEN** `weight`s are 0.55 and 0.45, `raw_score` is 0.5932, `score` 0.5932 and `band` `high`

#### Scenario: All three dimensions
- **WHEN** the defaults apply, intensity is 0.424, confirmation 0.8 and amplification 0.9
- **THEN** `weight`s are 0.4, 0.3 and 0.3, `raw_score` is 0.6796 and `band` `high`

#### Scenario: Only amplification
- **WHEN** `techniques` and `propaganda_detection` failed and amplification is 0.9
- **THEN** `status` is `unavailable` with `reason: "no_content_signals"`

### Requirement: Weak-signal dampening
When confirmation is available with `weak_signal: true`, `score` SHALL be `raw_score * config.dampening_factor` and `dampened` SHALL be true; otherwise `score` SHALL equal `raw_score` and `dampened` SHALL be false.

#### Scenario: Dampened
- **WHEN** the defaults apply, intensity is 0.424, confirmation 0.1 and amplification unavailable
- **THEN** `raw_score` is 0.2782, `score` is 0.1669, `dampened` is true and `band` is `low`

### Requirement: Bands
`band` SHALL be the `band` of the last entry of `config.bands` (ascending `min`) whose `min` is at most `score`. With the defaults: `low` below 0.25, `moderate` from 0.25, `high` from 0.5, `critical` from 0.75. Clients SHALL style an unknown `band` like `moderate` and show its id.

#### Scenario: Boundary
- **WHEN** `score` is exactly 0.5 with default bands
- **THEN** `band` is `high`

### Requirement: RiskConfig object
`config` SHALL echo the configuration the RiskScore was computed with, so it can be reconstructed by hand from its own members. A deployment MAY configure values other than the defaults of the RiskConfig defaults requirements; a RiskScore SHALL keep the values it was computed with.

#### Scenario: Recalibrated deployment
- **WHEN** the deployment sets `dampening_factor` to 0.5
- **THEN** new RiskScores have `config.dampening_factor: 0.5` and earlier stored RiskScores keep 0.6

### Requirement: RiskConfig threshold defaults
`config` SHALL have at least: `detection_threshold` (default 0.3); `reference_technique_count` (default 6); `weighted_sum_reference` (default 5.0); `impact_weights` `{high, medium, lower}` (defaults 1.0, 0.7, 0.4); `dampening_threshold` (default 0.2); `dampening_factor` (default 0.6); `min_author_posts` (default 20); `short_text_max_words` (default 80); `driver_min_contribution` (default 0.05).

#### Scenario: Default thresholds
- **WHEN** the deployment configures nothing
- **THEN** `config.detection_threshold` is 0.3 and `config.min_author_posts` is 20

### Requirement: RiskConfig weight and band defaults
`config` SHALL also have at least `weights_with_amplification` `{intensity, confirmation, amplification}` (defaults 0.4, 0.3, 0.3), `weights_without_amplification` `{intensity, confirmation}` (defaults 0.55, 0.45) and `bands` (array of `{band, min}`, default `low` 0, `moderate` 0.25, `high` 0.5, `critical` 0.75).

#### Scenario: Default bands
- **WHEN** the deployment configures nothing
- **THEN** `config.bands` is `[{"band": "low", "min": 0}, {"band": "moderate", "min": 0.25}, {"band": "high", "min": 0.5}, {"band": "critical", "min": 0.75}]`

### Requirement: RiskDriver object
A RiskDriver SHALL have at least `kind` (values include `technique`, `propaganda_pattern`, `amplification` and `none`), `dimension` (`intensity`, `confirmation`, `amplification` or null), `technique`, `contribution` (number) and `text` (non-empty short English plain text). `technique` SHALL be the `label` of the RiskTechnique with the largest `contribution` (ties in `techniques` order) when `kind` is `technique`, otherwise null.

#### Scenario: Technique driver
- **WHEN** intensity is the top dimension and `Appeal_to_fear-prejudice` has the largest technique contribution
- **THEN** the driver has `kind: "technique"`, `dimension: "intensity"`, `technique: "Appeal_to_fear-prejudice"` and a `text` naming that technique

### Requirement: Driver selection
When `scored`, drivers SHALL be the available dimensions with `contribution > 0`, by `contribution` descending (ties intensity, confirmation, amplification): the first, and the second only when its `contribution` is at least `config.driver_min_contribution`. Intensity maps to `technique`, confirmation to `propaganda_pattern`, amplification to `amplification`.

#### Scenario: Two drivers
- **WHEN** contributions are intensity 0.1696, confirmation 0.24 and amplification 0.27
- **THEN** `drivers` is amplification then confirmation

### Requirement: No-signal driver
When `scored` and no dimension has a positive contribution, `drivers` SHALL be one entry with `kind: "none"`, `dimension: null`, `technique: null` and `contribution: 0`.

#### Scenario: Nothing found
- **WHEN** no technique counts, confirmation is 0 and amplification is unavailable
- **THEN** `drivers` is one entry with `kind: "none"`

### Requirement: RiskCaveat object
A RiskCaveat SHALL have at least `id` and `text` (non-empty English plain text). Clients SHALL show a caveat with an unknown `id` using its `text`.

#### Scenario: Always-present caveat
- **WHEN** any RiskScore is set
- **THEN** its first caveat has `id: "content_not_reader"` and a text saying the rating describes the content, not whether a reader will be manipulated

### Requirement: Content caveats
`caveats` SHALL start with `content_not_reader` (always), then `language` when the `translation` result's `source_language` is not `en` or is unknown, then `short_text` when intensity `short_text` is true.

#### Scenario: Long English text
- **WHEN** a 300-word English text job without author has intensity and confirmation available and is not dampened
- **THEN** `caveats` ids are `content_not_reader`, `amplification_missing`

### Requirement: Signal caveats
After the content caveats, `caveats` SHALL contain in this order, each only when its condition holds: `bot_not_intent` (amplification available), `amplification_low_confidence` (amplification `confidence` is `low`), `amplification_missing` (amplification unavailable), `signal_missing` (intensity or confirmation unavailable), `weak_signal` (`dampened` is true).

#### Scenario: Translated scrape job with few posts
- **WHEN** a German scrape job with a 30-word translation has intensity and confirmation available, is not dampened and has amplification with `basis: "single_text"`
- **THEN** `caveats` ids are `content_not_reader`, `language`, `short_text`, `bot_not_intent`, `amplification_low_confidence`

### Requirement: Risk texts
`summary`, driver `text` and caveat `text` SHALL come from fixed English templates filled only with the band and technique `display` names, and SHALL NOT name a model, classifier, algorithm or probability value. `summary` SHALL state the band's meaning and, when `scored`, the first driver.

#### Scenario: No model names
- **WHEN** a RiskScore is `scored` with an amplification driver
- **THEN** no `summary`, driver or caveat `text` contains `nci-`, `classifier`, `model` or a digit

### Requirement: Risk text rendering
Clients SHALL render `summary`, driver and caveat texts as plain text and MAY replace them with localized texts keyed by `band`, driver `kind` and `technique`, and caveat `id`.

#### Scenario: Markup in a text
- **WHEN** a technique `display` contains `<b>`
- **THEN** clients show `<b>` literally
