## Purpose
Country association of an analysis job: an LLM step of the orchestrator that, after the analyzers settle, decides from the original input and the analysis result which countries (zero, one or several ISO 3166-1 alpha-2 codes) the analyzed content is associated with, as clients read it from the analysis job API and as the propaganda map uses it.

## ADDED Requirements

### Requirement: When country association runs
The orchestrator SHALL run the country association step once per job when `analysis.ready_for_finalization` is emitted, concurrently with finalization, when a country association model is configured and the job has detected propaganda (propaganda-map-api "Detected propaganda"). It SHALL NOT run for a job cancelled before that point or whose scrape failed. Otherwise the job SHALL get a `skipped` CountryAssociation and no model call.

#### Scenario: Job with detected propaganda
- **WHEN** a job's `techniques` run succeeded with `Loaded_Language` detected and a country association model is configured
- **THEN** the step runs once after `analysis.ready_for_finalization` and the job gets a settled `country_association`

#### Scenario: No detected propaganda
- **WHEN** a job's `techniques` run succeeded with `detected: []`
- **THEN** no model call is made and `country_association` is `{"status": "skipped", "reason": "no_detected_propaganda", "countries": [], ...}`

#### Scenario: Not configured
- **WHEN** the deployment has no country association model configured and a job with detected propaganda reaches the barrier
- **THEN** `country_association.status` is `skipped` with `reason: not_configured` and the job completes normally

### Requirement: Country association inputs
The step SHALL decide only from the job's `input` (content, `content_type` and `source`), its settled analysis results (at least the `techniques` detections, and the `source_info` page outlet and `translation` `source_language` when known) and the orchestrator's ISO 3166-1 country table. The page outlet MAY be an input but SHALL NOT be required.

#### Scenario: Unknown outlet
- **WHEN** `source_info` succeeded with `page_outlet: null` and `input.content` is a news article about Hungary
- **THEN** the step still runs on the content and may associate `HU`

### Requirement: Country association criteria
The step SHALL associate a country when the content is from, about or clearly related to that country, and SHALL associate no country when none can be determined; it SHALL NOT force a country.

#### Scenario: Pasted text about the US
- **WHEN** a job was created from pasted text with `"source": {}` arguing about a US presidential election and techniques were detected
- **THEN** `country_association.countries` contains `{"country_code": "US", "country": "United States", ...}`

#### Scenario: Several countries
- **WHEN** an article with detected techniques is about a gas dispute between Russia and Ukraine
- **THEN** `country_association.countries` contains both `RU` and `UA`

#### Scenario: No determinable country
- **WHEN** the analyzed text is a generic slogan with no reference to any place
- **THEN** `country_association.status` is `succeeded` with `countries: []`

### Requirement: CountryAssociation object
`Job.country_association` SHALL be a CountryAssociation or null. A CountryAssociation SHALL have at least: `status`; `reason` (string or null); `error` (`{"code", "message"}` or null); `countries` (array of AssociatedCountry); `finished_at` (timestamp when it settled). Clients SHALL ignore unknown members.

#### Scenario: Members present
- **WHEN** the step succeeded with one country
- **THEN** `country_association` has `status: "succeeded"`, `reason: null`, `error: null`, `countries` with one AssociatedCountry and a non-null `finished_at`

### Requirement: CountryAssociation status
`status` values SHALL include `succeeded`, `failed` and `skipped`. When `succeeded`, `reason` and `error` are null and `countries` holds zero or more AssociatedCountry. When `skipped`, `reason` values include `not_configured` and `no_detected_propaganda`, `error` is null and `countries` is `[]`. Clients SHALL treat an unknown `status` like `failed`, and an unknown `reason` or `error.code` without error.

#### Scenario: Skipped members
- **WHEN** the step is skipped with `not_configured`
- **THEN** `country_association` has `status: "skipped"`, `reason: "not_configured"`, `error: null` and `countries: []`

### Requirement: Failed country association
When `status` is `failed`, `reason` SHALL be null, `countries` `[]` and `error` `{"code", "message"}` with codes including `timeout`, `adapter_error`, `invalid_output`, `cancelled` and `interrupted`.

#### Scenario: Model failure
- **WHEN** the model provider answers HTTP 500 for the step
- **THEN** `country_association` is `{"status": "failed", "error": {"code": "adapter_error", ...}, "countries": [], ...}`

#### Scenario: Unparseable reply
- **WHEN** the model replies with text that is not the expected structured answer
- **THEN** `country_association.status` is `failed` with `error.code: invalid_output`

### Requirement: AssociatedCountry object
An AssociatedCountry SHALL have at least `country_code` (an upper-case, officially assigned ISO 3166-1 alpha-2 code) and `country` (that code's English short name from the orchestrator's country table, never text from the model). `countries` SHALL hold each code at most once and at most 10 entries, in the model's order.

#### Scenario: Name from the table
- **WHEN** the model answers code `DE` with the name `<b>Germany</b>`
- **THEN** the AssociatedCountry is `{"country_code": "DE", "country": "Germany", ...}`

### Requirement: Invalid country codes
A code in the model's reply SHALL be matched case-insensitively; one that is not an officially assigned ISO 3166-1 alpha-2 code (for example `EU`, `UK`, `XX` or a three-letter code) SHALL be dropped without failing the step. A reply whose codes are all dropped SHALL yield `succeeded` with `countries: []`.

#### Scenario: Invalid code dropped
- **WHEN** the model answers with the codes `us`, `EU` and `US`
- **THEN** `countries` is `[{"country_code": "US", "country": "United States", ...}]` and `status` is `succeeded`

### Requirement: Country association isolation
A failed, timed-out or skipped country association SHALL NOT change the job's `status`, its AnalyzerRuns, its `risk` or its `finalization`, and SHALL NOT delay finalization. Its `error.message` MAY include the provider's own error text but MUST NOT contain credentials (API keys, `Authorization` header values or other configured secret values).

#### Scenario: Step fails, job completes
- **WHEN** the step times out and finalization succeeds
- **THEN** the job ends `completed` with its `finalization.result`, and `country_association.status` is `failed` with `error.code: timeout`

#### Scenario: Provider error without credentials
- **WHEN** the provider answers HTTP 401 with a message that repeats the configured API key
- **THEN** `country_association.error.message` does not contain the API key

### Requirement: Country association before done
`Job.country_association` SHALL be null while the step has not settled and SHALL be settled before the job becomes `done` with `completed`, so that `job.completed` `data.job` and `GET /api/v1/jobs/{id}` after it carry the settled CountryAssociation. No new event type SHALL be added for the step.

#### Scenario: Completed event carries the association
- **WHEN** a job with detected propaganda completes
- **THEN** `job.completed` `data.job.country_association` is a settled CountryAssociation equal to the one `GET /api/v1/jobs/{id}` returns

### Requirement: Country association cancellation and restart
When a job is cancelled while the step runs, the step SHALL settle as `failed` with `error.code: cancelled` before `job.cancelled`. A job ended by "Jobs interrupted by a restart" (analysis-jobs-api) while the step runs SHALL get `failed` with `error.code: interrupted`.

#### Scenario: Cancelled while associating
- **WHEN** a client cancels a job while the step is running
- **THEN** `job.cancelled` `data.job.country_association` has `status: failed` and `error.code: cancelled`

### Requirement: Settled country association
A `succeeded` or `skipped` CountryAssociation SHALL never change. A `failed` one MAY be replaced only by "Country association backfill".

#### Scenario: Succeeded stays
- **WHEN** a job's association succeeded with `["US"]` and the backfill runs later
- **THEN** the job's `country_association` is unchanged

### Requirement: Country association backfill
A deployment with persistent history and a configured model SHALL, in the background after start without delaying requests, run the step for every stored job that is `done`, `public`, has detected propaganda and whose `country_association` is missing, null or `failed`, from its stored input and results, and persist the result without emitting events. Other stored jobs SHALL keep a missing `country_association`, read like null.

#### Scenario: Old US analysis backfilled
- **WHEN** a deployment upgrades with a stored done public job from pasted text about US politics with detected techniques and no `country_association`
- **THEN** after the backfill reaches it, `GET /api/v1/jobs/{id}` has `country_association.countries` containing `US` and the propaganda map counts it for `US`

#### Scenario: Old job without propaganda
- **WHEN** a stored done job has `techniques` `detected: []` and no `country_association`
- **THEN** the backfill makes no model call for it and `GET /api/v1/jobs/{id}` has no or a null `country_association`

### Requirement: Backfill batching and retry
The backfill SHALL process jobs in bounded batches and SHALL retry a job whose attempt fails on later passes, up to a bounded number of attempts. A job finished after the server started SHALL be handled by "When country association runs" and SHALL NOT be called a second time by the backfill unless its association `failed`.

#### Scenario: Backfill attempt fails
- **WHEN** the backfill's model call for a stored job fails with `adapter_error`
- **THEN** the job keeps a `failed` `country_association`, the server keeps serving, and a later pass tries the job again

### Requirement: Country association rendering
`country_association.countries[].country` and `error.message` SHALL be rendered by clients as plain text. Clients MAY show a localized name for `country_code` and SHALL fall back to `country`, then to `country_code`. Clients SHALL present an associated country as a country the content is associated with, not as the origin, author or target of the propaganda and not as a rating of that country.

#### Scenario: Localized name
- **WHEN** the UI locale is `fr` and an AssociatedCountry is `{"country_code": "DE", "country": "Germany"}`
- **THEN** a client may show "Allemagne"
