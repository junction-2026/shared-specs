## Purpose

WebSocket event stream of an analysis job: the endpoint, the event envelope, snapshot-on-connect, the event types for analyzer results, finalization and job completion, and their ordering and exactly-once guarantees.

## ADDED Requirements

### Requirement: Event stream endpoint
`GET /api/v1/jobs/{id}/events` SHALL upgrade to a WebSocket connection for an existing job; for an unknown id it SHALL respond HTTP 404 `not_found` without upgrading. The server SHALL send only text frames, each one JSON event envelope, SHALL ignore client messages, and SHALL send a ping at least every 30 seconds.

#### Scenario: Unknown job
- **WHEN** a client opens `/api/v1/jobs/does-not-exist/events`
- **THEN** the response is HTTP 404 with `error.code: not_found` and no upgrade happens

### Requirement: Event envelope
Every event SHALL have at least `type` (string), `job_id` (string), `seq` (integer), `emitted_at` (timestamp) and `data` (object). `seq` is per job, starts at 1 and increases by exactly 1 per event of that job. Clients MUST ignore unknown `type`s and MAY discard events whose `seq` is not greater than the last one processed.

#### Scenario: Monotonic sequence
- **WHEN** a client receives events with `seq` 4 and then 5
- **THEN** no other event of that job was emitted between them

### Requirement: Snapshot on connect
The first event on every connection SHALL be `job.snapshot` with `data.job` the full Job object and `seq` equal to the job's last emitted `seq` (0 if none). The connection SHALL then deliver every later event of the job in order without gaps. If the job is already `done`, the server SHALL send only the snapshot and close with code 1000.

#### Scenario: Late subscriber
- **WHEN** a client connects after 3 of 5 analyzers have succeeded
- **THEN** it first receives `job.snapshot` containing the 3 results, then events for the remaining 2 analyzers

#### Scenario: Finished job
- **WHEN** a client connects to a job with `done: true`
- **THEN** it receives exactly one `job.snapshot` and the server closes with code 1000

### Requirement: Analyzer events
The server SHALL emit `analyzer.started` (AnalyzerRun now `running`), `analyzer.succeeded` (with `result`), `analyzer.failed` (with `error`) and `analyzer.skipped` (with `reason`), each with `data.analyzer` the AnalyzerRun, as soon as the state change happens, without waiting for other analyzers or the finalizer.

#### Scenario: Result streamed when it settles
- **WHEN** analyzer `sentiment` succeeds while analyzer `claims` is still running
- **THEN** `analyzer.succeeded` for `sentiment` is emitted immediately with its `result`

### Requirement: One settle event per analyzer
Each AnalyzerRun SHALL produce exactly one settle event (`analyzer.succeeded`, `analyzer.failed` or `analyzer.skipped`). Analyzers skipped at creation (`disabled`, `not_selected`, `not_applicable`) SHALL get their `analyzer.skipped` right after `job.started`. `analyzer.started` SHALL precede the settle event of every analyzer that ran.

#### Scenario: Unselected analyzer
- **WHEN** a job is created selecting only `sentiment` out of 3 analyzers
- **THEN** the stream contains `analyzer.skipped` with `reason: not_selected` for the other 2

### Requirement: Job lifecycle events
The server SHALL emit `job.started` (`data.job_id`) once when the job leaves `queued`, and exactly one terminal event per job: `job.completed`, `job.cancelled` or `job.failed`, each with `data.job` the Job object in that status. No event of the job SHALL follow the terminal event, and the server SHALL then close the job's connections with code 1000.

#### Scenario: Terminal event closes stream
- **WHEN** `job.completed` has been sent
- **THEN** the server closes the connection with code 1000

### Requirement: Finalization events
The server SHALL emit `analysis.ready_for_finalization` (`data.coverage`) when every AnalyzerRun is settled, `analysis.finalizing` when finalization starts running, `analysis.finalized` when it completes with a result and `analysis.finalization_failed` when it fails, times out or is cancelled; the last three carry `data.finalization` (Finalization object).

#### Scenario: Finalizer failure event
- **WHEN** the finalizer times out
- **THEN** `analysis.finalization_failed` carries `finalization.status: failed` and `finalization.error.code: timeout`

### Requirement: Event and REST consistency
Objects in event data SHALL equal what `GET /api/v1/jobs/{id}` returns for the same entity immediately after the event was emitted.

#### Scenario: Consistent finalization state
- **WHEN** a client receives `analysis.finalizing` and then calls `GET /api/v1/jobs/{id}` before any further event
- **THEN** the REST response has `status: finalizing` and `finalization.status: running`

### Requirement: Exactly-once barrier
`analysis.ready_for_finalization` SHALL be emitted exactly once per non-cancelled job, after the settle event of its last AnalyzerRun, also when analyzers settle concurrently and when finalization will be skipped. The job status becomes `finalizing` at that point.

#### Scenario: Concurrent completions
- **WHEN** the last two analyzers settle at the same moment
- **THEN** `analysis.ready_for_finalization` and `analysis.finalizing` are each emitted once and the finalizer service is called once

#### Scenario: Slow analyzer delays only finalization
- **WHEN** analyzer `slow` takes 50s and the others take 1s
- **THEN** the other analyzers' settle events are emitted after about 1s and `analysis.ready_for_finalization` only after `slow` settles

### Requirement: Finalization and completion ordering
If finalization runs (including the insufficient-evidence short-circuit), `analysis.finalizing` SHALL be emitted once, followed by exactly one of `analysis.finalized` or `analysis.finalization_failed`, then `job.completed`. If finalization is `skipped`, `job.completed` SHALL directly follow `analysis.ready_for_finalization`.

#### Scenario: No finalizer configured
- **WHEN** the registry has no enabled finalizer
- **THEN** the stream ends with `analysis.ready_for_finalization` then `job.completed`, with `finalization.status: skipped` and `reason: not_configured`

### Requirement: Cancellation events
On cancellation the server SHALL emit the settle events of the affected analyzers, then `analysis.finalization_failed` with `error.code: cancelled` if finalization was running, then `job.cancelled`. Neither `analysis.ready_for_finalization` nor `job.completed` SHALL be emitted after cancellation was accepted.

#### Scenario: Cancel during finalization
- **WHEN** a job is cancelled while the finalizer is running
- **THEN** the stream contains `analysis.finalization_failed` with `error.code: cancelled` followed by `job.cancelled`, and no `job.completed`

### Requirement: Slow consumers
If a client cannot keep up and its buffered events exceed the server's limit, the server SHALL close that connection with code 4001 and reason `slow_consumer` instead of silently dropping events. A reconnecting client receives a fresh `job.snapshot`.

#### Scenario: Reconnect after overflow
- **WHEN** a connection is closed with 4001
- **THEN** reconnecting yields a `job.snapshot` reflecting all events up to its `seq`
