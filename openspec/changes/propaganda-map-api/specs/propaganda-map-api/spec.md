## Purpose
Read-only REST API of the analysis orchestrator that places finished analyses with detected propaganda techniques in the country of the analyzed page's outlet, with per-country aggregates and a paged per-country list of those analyses, for the Explore world map.

## ADDED Requirements

### Requirement: Map analysis
A job SHALL be a map analysis exactly when all of these hold: its `done` is `true`; `GET /api/v1/jobs` lists it; it has detected propaganda (Detected propaganda); and its map country (Map country) has a non-empty `country_code`. A job left out of `GET /api/v1/jobs`, such as an unlisted job, SHALL NOT be a map analysis.

#### Scenario: Propaganda in a known outlet
- **WHEN** a completed job analyzed `https://www.example-news.ru/a-1`, `source_info` succeeded with `page_outlet.country_code` `RU`, and `techniques.result.detected` has `Loaded_Language` and `Doubt`
- **THEN** the job is a map analysis of `RU` with the techniques `Loaded_Language` and `Doubt`

#### Scenario: Still running
- **WHEN** a job with detected techniques and a known country has `done: false`
- **THEN** it is not a map analysis until it is done

### Requirement: Detected propaganda
A job SHALL have detected propaganda exactly when its AnalyzerRun with `id` `techniques` has `status` `succeeded` and `result.detected` holds at least one Detection whose `name` is a known technique name (technique-classifier-result "Technique names"). Results of other analyzers, such as `llm_techniques`, `propaganda_detection` or the final verdict, SHALL NOT decide it.

#### Scenario: No technique detected
- **WHEN** a done job's `techniques` succeeded with `detected: []`
- **THEN** it is not a map analysis and is counted in no country

#### Scenario: Technique run failed
- **WHEN** a done job's `techniques` run is `failed` and `llm_techniques` found techniques
- **THEN** it is not a map analysis

### Requirement: Map country
The map country and map outlet of a job SHALL be, in this order: (1) when its `source_info` AnalyzerRun `succeeded` and `result.page_outlet` is not null, that Outlet and its `country_code` and `country`; (2) otherwise the Outlet table fallback; (3) otherwise none. A `country_code` of `""` SHALL count as none. `country_code` is the upper-case ISO 3166-1 alpha-2 code of the Outlet object (source-info-result "Outlet object").

#### Scenario: Page outlet used
- **WHEN** `source_info` succeeded with `page_outlet` `{"name": "Deutsche Welle", "country_code": "DE", "country": "Germany", ...}`
- **THEN** the map country is `DE` / `Germany` and the map outlet is Deutsche Welle

#### Scenario: Outlet without country
- **WHEN** the page outlet's `country_code` is `""`
- **THEN** the job has no map country

### Requirement: Outlet table fallback
When rule (1) of Map country does not apply, `input.source.url` is set and the deployment has an outlet table (that of its `source_info` analyzer), the map outlet SHALL be the Outlet that source-info-result "Outlet matching" gives for `input.source.url`, and the map country its `country_code` and `country`. An unmatched URL gives no map country.

#### Scenario: source_info did not run
- **WHEN** `news_search` was skipped with `no_searchable_topics`, so `source_info` is `skipped`, `input.source.url` is `https://www.spiegel.de/politik/a-1.html` and the deployment's outlet table lists `spiegel.de` with country `DE`
- **THEN** the map country is `DE`

#### Scenario: No URL
- **WHEN** a job was created from pasted text with `"source": {}`
- **THEN** it has no map country and is not a map analysis, whatever techniques were detected

### Requirement: No inferred country
The map country SHALL NOT be inferred from the text, its language, the URL's top-level domain or any source other than the Outlet given by Map country and Outlet table fallback.

#### Scenario: No inference from the domain
- **WHEN** `input.source.url` is `https://unknown-blog.fr/post` and no outlet matches it
- **THEN** the job has no map country, although the domain ends in `.fr`

### Requirement: Map values fixed when done
The map country, map outlet and technique set of a job SHALL be determined from the job as it is when `done` becomes `true` and SHALL NOT change afterwards, also when the outlet table is replaced later.

#### Scenario: Outlet table changed
- **WHEN** a done job was placed in `GB` by the outlet table fallback and the deployment later ships a table that lists the domain under `IE`
- **THEN** the job is still counted for `GB`

### Requirement: Jobs stored before the map
Jobs persisted before this capability existed SHALL be map analyses when they meet the Map analysis requirement, with their map values determined from their stored results and, for the Outlet table fallback, the outlet table at the time the deployment first determines them.

#### Scenario: Job stored before this change
- **WHEN** a deployment with persistent history has a job finished last week with detected techniques and a `page_outlet` in `FI`, and it is upgraded to a version with this capability
- **THEN** after the restart `GET /api/v1/map/countries` counts that job for `FI`

### Requirement: Removed jobs leave the map
A job removed by history retention (analysis-jobs-api "History retention"), or otherwise no longer listed by `GET /api/v1/jobs`, SHALL no longer be counted or listed by the map endpoints.

#### Scenario: Retention removes a job
- **WHEN** history retention deletes a map analysis of `PL`
- **THEN** the `PL` CountryAggregate no longer counts it and the `PL` list no longer contains it

### Requirement: Map technique set
The technique set of a map analysis SHALL be the distinct `name` values of the Detections in its `techniques` `result.detected` that are known technique names, in the order of technique-classifier-result "Technique names". Every detected technique SHALL count, `weak` ones included; a Detection's `strength` SHALL NOT exclude it.

#### Scenario: Weak detection counted
- **WHEN** `detected` has only `Bandwagon` with `strength: "weak"`
- **THEN** the job is a map analysis (given a map country) with the technique set `["Bandwagon"]`

### Requirement: Map freshness
A job SHALL be counted and listed by the map endpoints in every response to a request received after `GET /api/v1/jobs/{id}` first reports it with `done: true`, as long as it remains a map analysis.

#### Scenario: Just finished
- **WHEN** a job with detected techniques and page outlet in `PL` finishes and the client then calls `GET /api/v1/map/countries`
- **THEN** the `PL` item counts that job

### Requirement: Country aggregates endpoint
`GET /api/v1/map/countries` SHALL respond 200 with an object with at least `items` (array of CountryAggregate, one per map country with at least one map analysis, ordered by `country_code` ascending; not paginated) and `analyses` (integer, the number of map analyses, equal to the sum of `items[].analyses`). Query parameters SHALL be ignored. Other methods SHALL yield 405 `method_not_allowed`.

#### Scenario: Two countries
- **WHEN** there are three map analyses, two in `RU` and one in `DE`, and five other done jobs without detected techniques
- **THEN** the response has `items` `[<DE with analyses 1>, <RU with analyses 2>]` and `analyses: 3` (possibly with further members)

### Requirement: Empty map
With no map analyses, including in a deployment without an outlet table or without a `techniques` analyzer, `GET /api/v1/map/countries` SHALL respond 200 with `items: []` and `analyses: 0`.

#### Scenario: Empty history
- **WHEN** no job has finished yet
- **THEN** the response is 200 with `items: []` and `analyses: 0`

### Requirement: CountryAggregate object
A CountryAggregate SHALL have at least: `country_code` (upper-case ISO 3166-1 alpha-2); `country` (the `country` of the map country of the newest map analysis with that code, by `created_at` then `id`; possibly `""`); `analyses` (integer ≥ 1, number of map analyses with that map country); and `techniques` (array of TechniqueCount). Clients MAY show their own localized name for `country_code` and SHALL fall back to `country`, then to `country_code`.

#### Scenario: Aggregate members
- **WHEN** `RU` has two map analyses
- **THEN** its CountryAggregate has `country_code: "RU"`, a `country` such as `"Russia"`, `analyses: 2` and `techniques`

### Requirement: TechniqueCount object
A TechniqueCount SHALL have at least `name` (a known technique name), `display` (its built-in English display name, as TechniqueScore `display` in technique-classifier-result) and `analyses` (integer ≥ 1, the number of the country's map analyses whose technique set contains `name`).

#### Scenario: Count per technique
- **WHEN** the two `RU` map analyses have the technique sets `["Loaded_Language", "Doubt"]` and `["Loaded_Language"]`
- **THEN** the `Loaded_Language` TechniqueCount has `analyses: 2` and the `Doubt` TechniqueCount has `analyses: 1`

### Requirement: Technique count order
A CountryAggregate's `techniques` SHALL hold one TechniqueCount per technique with `analyses` ≥ 1 and none for other techniques, ordered by `analyses` descending, then by the order of technique-classifier-result "Technique names". As one analysis can carry several techniques, the sum of `techniques[].analyses` MAY exceed the aggregate's `analyses`.

#### Scenario: Ordered by count
- **WHEN** `RU` has `Loaded_Language` in 2 analyses and `Doubt` in 1
- **THEN** `techniques[0].name` is `Loaded_Language` and `techniques[1].name` is `Doubt`

### Requirement: Country analyses endpoint
`GET /api/v1/map/countries/{country_code}/analyses` SHALL respond 200 with the map analyses whose map country is `{country_code}`, newest first by `created_at`, ties by `id`, as `{"items": [MapAnalysis], "next_cursor": <string or null>}` with the cursor pagination of api-conventions (`limit` 1–100, default 20, opaque `cursor`; an out-of-range `limit` or undecodable cursor yields 400 `invalid_request`). Other methods SHALL yield 405 `method_not_allowed`.

#### Scenario: Paged list
- **WHEN** `RU` has 25 map analyses and a client calls `GET /api/v1/map/countries/RU/analyses`
- **THEN** it gets the 20 newest and a non-null `next_cursor`, and following it gives the remaining 5 and `next_cursor: null`

#### Scenario: Limit out of range
- **WHEN** a client calls `GET /api/v1/map/countries/RU/analyses?limit=0`
- **THEN** the status is 400 with `error.code` `invalid_request`

### Requirement: Country code parameter
`{country_code}` SHALL be two ASCII letters, matched case-insensitively (`ru` is `RU`); any other value SHALL yield 400 `invalid_request`. A well-formed code with no map analyses SHALL yield 200 with `{"items": [], "next_cursor": null}`, not 404.

#### Scenario: Lower-case code
- **WHEN** a client calls `GET /api/v1/map/countries/de/analyses`
- **THEN** the response lists the `DE` map analyses

#### Scenario: Malformed code
- **WHEN** a client calls `GET /api/v1/map/countries/DEU/analyses` or `GET /api/v1/map/countries/1A/analyses`
- **THEN** the status is 400 with `error.code` `invalid_request`

#### Scenario: Country without analyses
- **WHEN** a client calls `GET /api/v1/map/countries/FR/analyses` and no map analysis is in `FR`
- **THEN** the status is 200 with `items: []` and `next_cursor: null`

### Requirement: Aggregates and lists agree
While the set of map analyses does not change, paging through `GET /api/v1/map/countries/{country_code}/analyses` SHALL return each map analysis of that country exactly once, so their number equals the `analyses` of its CountryAggregate.

#### Scenario: Consistent with aggregates
- **WHEN** `GET /api/v1/map/countries` reports `analyses: 2` for `RU` and no job finishes or is removed meanwhile
- **THEN** paging through `GET /api/v1/map/countries/RU/analyses` returns exactly those 2 jobs

### Requirement: MapAnalysis object
A MapAnalysis SHALL have at least: `job_id` (the job's `id`); `created_at`, `finished_at` and `status` (the job's); `country_code` and `country` (its map country); `outlet`, `source`, `techniques` and `verdict` (MapAnalysis members); and `snippet` (Map snippet).

#### Scenario: Item identifies the job
- **WHEN** a map analysis has job id `j-42`
- **THEN** its MapAnalysis has `job_id: "j-42"` and the job's `created_at`, `finished_at` and `status`

### Requirement: MapAnalysis members
`outlet` SHALL be the map outlet with at least `name`, `domain`, `country_code` and `country` (source-info-result "Outlet object"). `source` SHALL have `url` (the job's `input.source.url`) and `title` (`input.source.title`, or null when absent). `techniques` SHALL be one MapTechnique per technique of the technique set, in its order. `verdict` SHALL be the FinalAssessment `verdict` of `finalization.result`, or null when there is none.

#### Scenario: Item members
- **WHEN** a map analysis was scraped from `https://www.dw.com/en/a-1` titled `Election results`, detected `Doubt` (`strong`), and its verdict is `detected`
- **THEN** its MapAnalysis has `country_code: "DE"`, `outlet.name: "Deutsche Welle"`, `source: {"url": "https://www.dw.com/en/a-1", "title": "Election results"}`, `techniques: [{"name": "Doubt", "display": "Doubt", "strength": "strong"}]` and `verdict: "detected"`

#### Scenario: No final assessment
- **WHEN** the job was created with `"options": {"finalize": false}`
- **THEN** its MapAnalysis has `verdict: null`

### Requirement: MapTechnique object
A MapTechnique SHALL have at least `name` and `display` (as in the job's Detection) and, when the stored Detection has `strength`, `strength` with the same value. A MapTechnique of a Detection stored without `strength` SHALL have no `strength` member, and clients SHALL then show no strength indicator (technique-classifier-result "Results without strength").

#### Scenario: Old result without strength
- **WHEN** a map analysis's Detection `Repetition` was stored before strength support
- **THEN** its MapTechnique is `{"name": "Repetition", "display": "Repetition"}` (possibly with further members) without `strength`

### Requirement: Map snippet
`snippet` SHALL be the job's `input.content` with every run of whitespace replaced by one space and leading and trailing whitespace removed, cut to at most 200 Unicode code points; when it was cut, `…` (U+2026, not counted in the 200) SHALL follow. For `content_type` `text/html` or `text/markdown` the snippet is taken from the content as stored, without rendering.

#### Scenario: Long content
- **WHEN** `input.content` is 5 000 characters of prose
- **THEN** `snippet` is its first 200 code points (whitespace collapsed) followed by `…`

#### Scenario: Short content
- **WHEN** `input.content` is `"  Short\n\ntext "`
- **THEN** `snippet` is `"Short text"`

### Requirement: Map rendering
`country`, `outlet.name`, `outlet.domain`, `source.title`, `source.url`, `snippet` and `display` come from data files, scraped pages and user input; clients SHALL render them as plain text and SHALL NOT interpret HTML or Markdown in them. Clients SHALL link a MapAnalysis to its job by `job_id`, not by `source.url`.

#### Scenario: Markup in a title
- **WHEN** a MapAnalysis has `source.title` `<b>Breaking</b>`
- **THEN** a client shows the literal text `<b>Breaking</b>`

### Requirement: Map country meaning
A map analysis's country is the country of the analyzed page's outlet. Clients SHALL NOT present it as the origin, author or target of the propaganda, and SHALL NOT present a country's count as a rating of that country.

#### Scenario: Tooltip wording
- **WHEN** a client shows the `RU` tooltip
- **THEN** it describes the count as analyses of pages from outlets in that country, not as propaganda by that country

### Requirement: Map endpoints do not run analyzers
The map endpoints SHALL be read-only: they SHALL NOT create, re-run or change jobs, call analyzers or the scraper, or make network requests.

#### Scenario: Read only
- **WHEN** a client calls both map endpoints
- **THEN** no analyzer, scraper or network outlet lookup is triggered and no job changes
