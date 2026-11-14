## ADDED Requirements

### Requirement: Event stream of a persisted job
With persistent history (analysis-jobs-api), a job read from history after a restart SHALL be an existing job for `GET /api/v1/jobs/{id}/events`. The server SHALL send one `job.snapshot` with the same `data` members as for a live done job (at least `job`, equal to `GET /api/v1/jobs/{id}`) and `seq` the last `seq` emitted for that job before the restart (0 if none), then close with code 1000.

#### Scenario: Connect after a restart
- **WHEN** a job completed after emitting events up to `seq` 42, the server is restarted and a client connects to its event stream
- **THEN** it receives exactly one `job.snapshot` with `seq: 42` and `data.job.status: completed`, and the server closes with code 1000

### Requirement: No events for an interruption
A job ended by "Jobs interrupted by a restart" (analysis-jobs-api) SHALL NOT emit events for that ending; a client connecting afterwards receives the snapshot of the ended state.

#### Scenario: Interrupted job stream
- **WHEN** a client connects after a restart to a job that was running at the stop
- **THEN** it receives one `job.snapshot` with `data.job.status: failed` and `data.job.done: true`, and the server closes with code 1000
