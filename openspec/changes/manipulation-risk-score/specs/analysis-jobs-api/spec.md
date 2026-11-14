## ADDED Requirements

### Requirement: Job risk member
The Job object SHALL also have `risk`: the job's RiskScore (manipulation-risk-score), or null until every AnalyzerRun is settled (see "When the risk score is computed" and "Jobs without a risk score" there). It SHALL be the same in `GET /api/v1/jobs/{id}` and in every event's `data.job`. Clients SHALL treat a missing `risk` member like `risk: null`.

#### Scenario: Fresh job
- **WHEN** a job has just been created
- **THEN** it has `risk: null`

#### Scenario: Completed job has a risk score
- **WHEN** a job ends `completed`
- **THEN** `GET /api/v1/jobs/{id}` returns it with a non-null `risk` whose `status` is `scored` or `unavailable`
