## MODIFIED Requirements

### Requirement: One settle event per analyzer
Each AnalyzerRun SHALL produce exactly one settle event (`analyzer.succeeded`, `analyzer.failed` or `analyzer.skipped`). Analyzers skipped at creation (`disabled`, `not_selected`, `not_applicable`) SHALL get their `analyzer.skipped` right after `job.started`; for a job created with `scrape`, `not_applicable` skips SHALL instead follow `scrape.succeeded`. `analyzer.started` SHALL precede the settle event of every analyzer that ran.

#### Scenario: Unselected analyzer
- **WHEN** a job is created selecting only `sentiment` out of 3 analyzers
- **THEN** the stream contains `analyzer.skipped` with `reason: not_selected` for the other 2

### Requirement: Job lifecycle events
The server SHALL emit `job.started` (`data.job_id`) once when the job leaves `queued` (for a job created with `scrape`, when its scrape starts), and exactly one terminal event per job: `job.completed`, `job.cancelled` or `job.failed`, each with `data.job` the Job object in that status. No event of the job SHALL follow the terminal event, and the server SHALL then close the job's connections with code 1000.

#### Scenario: Terminal event closes stream
- **WHEN** `job.completed` has been sent
- **THEN** the server closes the connection with code 1000

### Requirement: Exactly-once barrier
`analysis.ready_for_finalization` SHALL be emitted exactly once per non-cancelled job whose input is available (created with `input`, or whose scrape `succeeded`), after the settle event of its last AnalyzerRun, also when analyzers settle concurrently and when finalization will be skipped. The job status becomes `finalizing` at that point. It SHALL NOT be emitted for a job whose scrape failed.

#### Scenario: Concurrent completions
- **WHEN** the last two analyzers settle at the same moment
- **THEN** `analysis.ready_for_finalization` and `analysis.finalizing` are each emitted once and the finalizer service is called once

#### Scenario: Slow analyzer delays only finalization
- **WHEN** analyzer `slow` takes 50s and the others take 1s
- **THEN** the other analyzers' settle events are emitted after about 1s and `analysis.ready_for_finalization` only after `slow` settles

## ADDED Requirements

### Requirement: Scrape events
For a job created with `scrape`, the server SHALL emit `scrape.started` (`data.scrape`, the Scrape object now `running`) right after `job.started`, then exactly one of `scrape.succeeded` (`data.scrape` and `data.input`, the Input mapped from the ScrapeResult) or `scrape.failed` (`data.scrape` with its `error`). No `analyzer.started` SHALL precede `scrape.succeeded`; after it the job continues like a job created with `input`.

#### Scenario: Successful scrape stream
- **WHEN** a client follows a job created from a public Bluesky post URL from the start
- **THEN** it receives `job.started`, `scrape.started`, `scrape.succeeded` with `data.input.source.platform: bluesky`, then the analyzer events and `job.completed`

### Requirement: Events after a failed scrape
After `scrape.failed` the server SHALL emit `analyzer.skipped` for every AnalyzerRun not yet settled, then `job.failed`, or `job.cancelled` when the failure was a cancellation, and no finalization event.

#### Scenario: Failed scrape stream
- **WHEN** the scrape of a job fails with `account_not_found`
- **THEN** the stream contains `scrape.failed` with `data.scrape.error.code: account_not_found`, then `analyzer.skipped` with `reason: input_unavailable` for each pending analyzer, then `job.failed`, and no `analysis.ready_for_finalization`
