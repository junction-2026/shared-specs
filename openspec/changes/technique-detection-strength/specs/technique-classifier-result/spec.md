## MODIFIED Requirements

### Requirement: TechniqueClassification object
When `techniques` has `succeeded`, its `result` SHALL be a TechniqueClassification with at least: `words` (integer), `results` (non-empty array of ModelResult, at most one per model, `nci-technique` before `nci-social`), `detected` and `summary` (a StrengthSummary), plus the members of the Span result members requirement and of the Plain-language result members requirement. It SHALL be the same in `analyzer.succeeded` and `GET /api/v1/jobs/{id}`. Clients SHALL ignore unknown members.

#### Scenario: Short text
- **WHEN** a job's English translation has 20 words and the defaults apply
- **THEN** `result.words` is 20 and `result.results` has one ModelResult with `model: "nci-social"` and `cutoff: 0.3`

#### Scenario: Both models ran
- **WHEN** both models classified the text
- **THEN** `results` has two entries, the first with `model: "nci-technique"` and the second with `model: "nci-social"`

#### Scenario: Result from before this change
- **WHEN** a client reads a `techniques` result stored before this change, which has `detected` but no `results` array
- **THEN** it shows the detected techniques as before and shows no per-model scores, without error

## ADDED Requirements

### Requirement: Detection strength members
Besides the members of the Detection object requirement, a Detection SHALL have at least `margin` (number, derived from the scores in `results`; it is not a score of its own), `located` (boolean) and `strength` (string; values include `strong` and `weak`), as defined by the Detection strength requirement, the same in `analyzer.succeeded` and `GET /api/v1/jobs/{id}`.

#### Scenario: Strength members present
- **WHEN** `techniques` succeeds with `Doubt` in `detected`
- **THEN** the `Doubt` Detection has `margin`, `located` and `strength` in both the event and the job response

### Requirement: Detection strength
For each Detection, `margin` SHALL be the highest `score - cutoff` of its `name` across the ModelResults listed in its `models`, rounded half away from zero to 2 decimals (so `margin >= 0`). `located` SHALL be `true` exactly when its final `spans`, after the span step, has at least one entry. `strength` SHALL be `strong` when `located` is `true` or the rounded `margin` is at least the deployment's strong margin, and `weak` otherwise.

#### Scenario: Borderline and clear detections without spans
- **WHEN** a short post's `nci-social` ModelResult (cutoff 0.4) has `Bandwagon` 0.44, the `nci-technique` ModelResult (cutoff 0.5) has `Loaded_Language` 0.70, the strong margin is 0.15 and neither has a span
- **THEN** `Bandwagon` has `margin: 0.04`, `located: false`, `strength: "weak"` and `Loaded_Language` has `margin: 0.2`, `located: false`, `strength: "strong"`

#### Scenario: Located detection is strong
- **WHEN** `Doubt` scores 0.31 with cutoff 0.3 and has one span
- **THEN** its Detection has `margin: 0.01`, `located: true` and `strength: "strong"`

#### Scenario: Highest margin across models
- **WHEN** `Doubt` is above cutoff in both models, 0.55 with cutoff 0.5 and 0.5 with cutoff 0.3
- **THEN** its `margin` is 0.2

#### Scenario: Margin equal to the strong margin
- **WHEN** `Slogans` scores 0.65 with cutoff 0.5, has no span and the strong margin is 0.15
- **THEN** its `margin` is 0.15 and `strength` is `strong`

#### Scenario: Span step failed
- **WHEN** `span_status` is `failed` and `Flag-Waving` has margin 0.05
- **THEN** `Flag-Waving` has `spans: []`, `located: false` and `strength: "weak"`

### Requirement: Strong margin setting
Unless the deployment configures another value, the strong margin SHALL be 0.15. A changed strong margin SHALL apply to results produced after the change and SHALL NOT change stored results.

#### Scenario: Configured strong margin
- **WHEN** the deployment sets the strong margin to 0.05 and `Bandwagon` has margin 0.06 and no span
- **THEN** new results have `Bandwagon` with `strength: "strong"`, and results stored earlier keep their `strength`

### Requirement: StrengthSummary object
A StrengthSummary SHALL have at least `strong` and `weak` (non-negative integers): the number of Detections in `detected` with `strength` `strong` and `weak` respectively. Their sum SHALL equal the length of `detected`.

#### Scenario: Nothing detected
- **WHEN** `detected` is empty
- **THEN** `summary` is `{"strong": 0, "weak": 0}`

#### Scenario: Mixed detections
- **WHEN** `detected` has `Loaded_Language` (`strong`) and `Bandwagon` (`weak`)
- **THEN** `summary` has `strong: 1` and `weak: 1`

### Requirement: Detection strength interpretation
A `weak` Detection is a hint at most (a borderline score with no phrase located), not evidence of propaganda on its own. Clients that show strength SHALL present a `weak` Detection as weaker than a `strong` one and SHALL NOT present `margin` as a probability. Clients SHALL treat an unknown `strength` value as no strength information.

#### Scenario: Unknown strength value
- **WHEN** a client receives a Detection with `strength: "moderate"`
- **THEN** it shows the Detection without a strength indicator, without error

### Requirement: Results without strength
Clients SHALL accept TechniqueClassifications without `summary` and Detections without `margin`, `located` or `strength`, as stored before this change. They SHALL show such Detections as before, with no strength indicator, and SHALL NOT derive a strength for them.

#### Scenario: Result from before strength support
- **WHEN** a client reads a stored `techniques` result whose Detections have `name`, `display`, `explanation`, `models` and `spans` but no `strength`, and no `summary`
- **THEN** it lists the detected techniques and their highlights as before, without a strength indicator and without error
