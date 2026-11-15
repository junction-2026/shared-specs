## MODIFIED Requirements

### Requirement: Map analysis
A job SHALL be a map analysis exactly when all of these hold: its `done` is `true`; its `public` is `true` (analysis-jobs-api "Job visibility"), so that `GET /api/v1/jobs` lists it; it has detected propaganda (Detected propaganda); and it has at least one map country (Map country). A job with `public: false`, or otherwise left out of `GET /api/v1/jobs`, SHALL NOT be a map analysis, so the map endpoints never reveal a non-public job.

#### Scenario: Propaganda in a known outlet
- **WHEN** a completed job analyzed `https://www.example-news.ru/a-1`, `source_info` succeeded with `page_outlet.country_code` `RU`, `country_association` succeeded with `countries: []`, and `techniques.result.detected` has `Loaded_Language` and `Doubt`
- **THEN** the job is a map analysis of `RU` with the techniques `Loaded_Language` and `Doubt`

#### Scenario: Propaganda in pasted text
- **WHEN** a completed job was created from pasted text with `"source": {}`, techniques were detected and `country_association.countries` is `[US]`
- **THEN** the job is a map analysis of `US`

#### Scenario: Non-public job left out
- **WHEN** a done job created with `"public": false` has detected techniques and `page_outlet.country_code` `RU`
- **THEN** it is not a map analysis: no CountryAggregate counts it and no `GET /api/v1/map/countries/RU/analyses` page contains it

#### Scenario: Still running
- **WHEN** a job with detected techniques and a known country has `done: false`
- **THEN** it is not a map analysis until it is done

#### Scenario: No country at all
- **WHEN** a done public job with detected techniques has no map outlet country and `country_association` succeeded with `countries: []`
- **THEN** it is not a map analysis and no CountryAggregate counts it

### Requirement: Map country
The map countries of a job SHALL be a list (possibly empty) of distinct upper-case ISO 3166-1 alpha-2 codes, each with a `country` name and a `basis`: first the country of the map outlet (Map outlet), when it has one, with the Outlet's `country` and basis `outlet`; then each AssociatedCountry of the job's `country_association` when its `status` is `succeeded` (country-association), with basis `content`. A code given by both SHALL appear once, at the first position, with both bases.

#### Scenario: Page outlet used
- **WHEN** `source_info` succeeded with `page_outlet` `{"name": "Deutsche Welle", "country_code": "DE", "country": "Germany", ...}` and `country_association` is `skipped`
- **THEN** the map countries are `[DE / Germany, basis outlet]` and the map outlet is Deutsche Welle

#### Scenario: Outlet and associated countries merged
- **WHEN** the page outlet is in `DE` and `country_association.countries` is `[US, DE]`
- **THEN** the map countries are `DE` (bases `outlet` and `content`) then `US` (basis `content`)

#### Scenario: Association failed
- **WHEN** the page outlet is in `PL` and `country_association.status` is `failed`
- **THEN** the map countries are `[PL]`

#### Scenario: Outlet without country
- **WHEN** the page outlet's `country_code` is `""` and `country_association.countries` is `[]`
- **THEN** the job has no map country

### Requirement: Outlet table fallback
When the job's `source_info` gives no page outlet, `input.source.url` is set and the deployment has an outlet table (that of its `source_info` analyzer), the map outlet SHALL be the Outlet that source-info-result "Outlet matching" gives for `input.source.url`. An unmatched URL gives no map outlet.

#### Scenario: source_info did not run
- **WHEN** `news_search` was skipped with `no_searchable_topics`, so `source_info` is `skipped`, `input.source.url` is `https://www.spiegel.de/politik/a-1.html` and the deployment's outlet table lists `spiegel.de` with country `DE`
- **THEN** the map outlet is the `spiegel.de` Outlet and `DE` is a map country

#### Scenario: No URL
- **WHEN** a job was created from pasted text with `"source": {}`
- **THEN** it has no map outlet; its map countries are only those of its `country_association`

### Requirement: Map values fixed when done
The map countries, map outlet and technique set of a job SHALL be determined from the job as it is when `done` becomes `true` and SHALL NOT change afterwards, also when the outlet table is replaced later, with one exception: when "Country association backfill" (country-association) sets a missing or `failed` `country_association` of a done job, its map countries SHALL be determined again with the new `country_association` and the map outlet fixed before.

#### Scenario: Outlet table changed
- **WHEN** a done job was placed in `GB` by the outlet table fallback and the deployment later ships a table that lists the domain under `IE`
- **THEN** the job is still counted for `GB`

#### Scenario: Backfill adds countries
- **WHEN** a done job is counted for `GB` by its outlet and the backfill later sets its `country_association.countries` to `[GB, IE]`
- **THEN** the job is counted for both `GB` and `IE`

### Requirement: Country aggregates endpoint
`GET /api/v1/map/countries` SHALL respond 200 with an object with at least `items` (array of CountryAggregate, one per map country with at least one map analysis, ordered by `country_code` ascending; not paginated) and `analyses` (integer, the number of distinct map analyses; see Multi-country analyses). Query parameters SHALL be ignored. Other methods SHALL yield 405 `method_not_allowed`.

#### Scenario: Two countries
- **WHEN** there are three map analyses, two in `RU` and one in `DE`, each with one map country, and five other done jobs without detected techniques
- **THEN** the response has `items` `[<DE with analyses 1>, <RU with analyses 2>]` and `analyses: 3` (possibly with further members)


### Requirement: CountryAggregate object
A CountryAggregate SHALL have at least: `country_code` (upper-case ISO 3166-1 alpha-2); `country` (the `country` of that code among the map countries of the newest map analysis having that code, by `created_at` then `id`; possibly `""`); `analyses` (integer ≥ 1, number of map analyses whose map countries include that code); and `techniques` (array of TechniqueCount). Clients MAY show their own localized name for `country_code` and SHALL fall back to `country`, then to `country_code`.

#### Scenario: Aggregate members
- **WHEN** `RU` has two map analyses
- **THEN** its CountryAggregate has `country_code: "RU"`, a `country` such as `"Russia"`, `analyses: 2` and `techniques`

### Requirement: Country analyses endpoint
`GET /api/v1/map/countries/{country_code}/analyses` SHALL respond 200 with the map analyses whose map countries include `{country_code}`, newest first by `created_at`, ties by `id`, as `{"items": [MapAnalysis], "next_cursor": <string or null>}` with the cursor pagination of api-conventions (`limit` 1–100, default 20, opaque `cursor`; an out-of-range `limit` or undecodable cursor yields 400 `invalid_request`). Other methods SHALL yield 405 `method_not_allowed`.

#### Scenario: Paged list
- **WHEN** `RU` has 25 map analyses and a client calls `GET /api/v1/map/countries/RU/analyses`
- **THEN** it gets the 20 newest and a non-null `next_cursor`, and following it gives the remaining 5 and `next_cursor: null`

#### Scenario: Limit out of range
- **WHEN** a client calls `GET /api/v1/map/countries/RU/analyses?limit=0`
- **THEN** the status is 400 with `error.code` `invalid_request`


### Requirement: MapAnalysis object
A MapAnalysis SHALL have at least: `job_id` (the job's `id`); `created_at`, `finished_at` and `status` (the job's); `country_code` and `country` (the map country of the list it is in, that is `{country_code}` of the request, and its `country` among the job's map countries); `countries` (array of MapCountry, all map countries of the job in their order); `outlet`, `source`, `techniques` and `verdict` (MapAnalysis members); and `snippet` (Map snippet).

#### Scenario: Item identifies the job
- **WHEN** a map analysis has job id `j-42`
- **THEN** its MapAnalysis has `job_id: "j-42"` and the job's `created_at`, `finished_at` and `status`

#### Scenario: Item in the second country's list
- **WHEN** a map analysis has the map countries `DE` then `US` and a client calls `GET /api/v1/map/countries/US/analyses`
- **THEN** its MapAnalysis has `country_code: "US"` and `countries` with `DE` then `US`

### Requirement: MapAnalysis members
`outlet` SHALL be the map outlet with at least `name`, `domain`, `country_code` and `country` (source-info-result "Outlet object"), or null when the job has no map outlet. `source` SHALL have `url` (the job's `input.source.url`, or `""` when the job has none) and `title` (`input.source.title`, or null when absent). `techniques` SHALL be one MapTechnique per technique of the technique set, in order. `verdict` SHALL be the FinalAssessment `verdict` of `finalization.result`, or null.

#### Scenario: Item members
- **WHEN** a map analysis was scraped from `https://www.dw.com/en/a-1` titled `Election results`, detected `Doubt` (`strong`), its verdict is `detected` and `country_association.countries` is `[]`
- **THEN** its MapAnalysis has `country_code: "DE"`, `countries: [{"country_code": "DE", "country": "Germany", "basis": ["outlet"]}]`, `outlet.name: "Deutsche Welle"`, `source: {"url": "https://www.dw.com/en/a-1", "title": "Election results"}`, `techniques: [{"name": "Doubt", "display": "Doubt", "strength": "strong"}]` and `verdict: "detected"`

#### Scenario: Pasted text item
- **WHEN** a map analysis was created from pasted text with `"source": {}` and associated with `US`
- **THEN** its MapAnalysis has `outlet: null`, `source: {"url": "", "title": null}` and `countries: [{"country_code": "US", "country": "United States", "basis": ["content"]}]`

#### Scenario: No final assessment
- **WHEN** the job was created with `"options": {"finalize": false}`
- **THEN** its MapAnalysis has `verdict: null`

### Requirement: Map rendering
`country`, `countries[].country`, `outlet.name`, `outlet.domain`, `source.title`, `source.url`, `snippet` and `display` come from data files, scraped pages and user input; clients SHALL render them as plain text and SHALL NOT interpret HTML or Markdown in them. Clients SHALL link a MapAnalysis to its job by `job_id`, not by `source.url`, and SHALL NOT show or link an empty `source.url`.

#### Scenario: Markup in a title
- **WHEN** a MapAnalysis has `source.title` `<b>Breaking</b>`
- **THEN** a client shows the literal text `<b>Breaking</b>`

### Requirement: Map country meaning
A map analysis's countries are the countries the analysis is associated with: the country of the analyzed page's outlet and the countries the content is associated with by country association. Clients SHALL NOT present a map country as the origin, author or target of the propaganda, and SHALL NOT present a country's count as a rating of that country.

#### Scenario: Tooltip wording
- **WHEN** a client shows the `RU` tooltip
- **THEN** it describes the count as analyses associated with that country, not as propaganda by that country

## ADDED Requirements

### Requirement: Map outlet
The map outlet of a job SHALL be, in this order: the Outlet of its `source_info` AnalyzerRun when it `succeeded` and `result.page_outlet` is not null; otherwise the Outlet table fallback; otherwise none. A map outlet `country_code` of `""` or one that is not two ASCII letters SHALL give no map country.

#### Scenario: Unusable outlet code
- **WHEN** the map outlet's `country_code` is `""` or not two ASCII letters
- **THEN** it gives no map country

#### Scenario: Page outlet is the map outlet
- **WHEN** `source_info` succeeded with `page_outlet` Deutsche Welle
- **THEN** the map outlet is Deutsche Welle

### Requirement: Multi-country analyses
A map analysis with several map countries SHALL be counted in the CountryAggregate of each of them and listed once in each of their `GET /api/v1/map/countries/{country_code}/analyses` lists, but only once in the top-level `analyses`. The sum of `items[].analyses` MAY therefore exceed `analyses`; clients SHALL NOT sum `items` to get the number of analyses.

#### Scenario: Analysis in two countries
- **WHEN** the only map analysis has the map countries `RU` and `UA`
- **THEN** `GET /api/v1/map/countries` has `items` `[<RU with analyses 1>, <UA with analyses 1>]` and `analyses: 1`, and the job is in the lists of both `RU` and `UA`

### Requirement: MapCountry object
A MapCountry SHALL have at least `country_code` (upper-case ISO 3166-1 alpha-2), `country` (its name per Map country, possibly `""`) and `basis` (non-empty array; values include `outlet`, the map outlet's country, and `content`, from country association). Clients SHALL ignore unknown `basis` values.

#### Scenario: Both bases
- **WHEN** the map outlet is in `DE` and `country_association.countries` contains `DE`
- **THEN** the MapCountry is `{"country_code": "DE", "country": "Germany", "basis": ["outlet", "content"]}` (possibly with further members)

## REMOVED Requirements

### Requirement: No inferred country
**Reason**: The parent feature (junction-2026/project#75) asks for an LLM step that associates analyses with countries from their content, so analyses of pasted text and unknown outlets can appear on the map.
**Migration**: Map countries now also come from `Job.country_association` (country-association). Clients that described the map as "outlet country only" update their wording per "Map country meaning".
