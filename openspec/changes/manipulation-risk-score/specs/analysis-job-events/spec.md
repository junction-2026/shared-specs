## ADDED Requirements

### Requirement: Risk score with the settle barrier
`analysis.ready_for_finalization` SHALL also carry `data.risk`: the job's RiskScore (manipulation-risk-score), equal to `Job.risk` from that event on. This SHALL NOT add, remove or reorder events.

#### Scenario: Risk score with the barrier
- **WHEN** the last AnalyzerRun of a job settles
- **THEN** `analysis.ready_for_finalization` carries `data.coverage` and a non-null `data.risk`, and `GET /api/v1/jobs/{id}` called right after it returns the same `risk`

#### Scenario: No finalizer configured
- **WHEN** the registry has no enabled finalizer
- **THEN** the stream still ends with `analysis.ready_for_finalization` (now with `data.risk`) then `job.completed`
