## MODIFIED Requirements

### Requirement: Verdict values
`verdict` SHALL be one of `detected` (at least one strong signal of propaganda or manipulation that the content supports), `not_detected` (no strong signal was found; weak hints may exist, see Weak hints and verdict) or `uncertain` (strong signals disagree, a decisive analyzer that applies to the text is unavailable, or there is no analyzer evidence). Clients SHALL treat an unknown `verdict` value like `uncertain`. JobSummary `finalization.verdict` takes the same values.

#### Scenario: Unknown verdict in a client
- **WHEN** a client receives a FinalAssessment with a `verdict` value it does not know
- **THEN** it presents the result as `uncertain`

## ADDED Requirements

### Requirement: Weak hints and verdict
Weak hints alone, such as `weak` technique Detections or low-confidence findings, SHALL NOT make a verdict `uncertain`; without a strong signal the verdict is `not_detected` and the hints only lower `confidence`.

#### Scenario: Only weak hints
- **WHEN** the only signals of a job are `weak` technique Detections and a propaganda classifier result of no propaganda
- **THEN** a conforming finalizer answers `not_detected`, possibly with lower `confidence`, not `uncertain`
