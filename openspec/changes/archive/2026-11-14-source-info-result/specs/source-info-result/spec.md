## Purpose
Result object of the outlet information analyzer: the news outlet, political leaning and country behind each article found by `news_search` and behind the analyzed page's own URL, with a summary of the leaning and country mix, as clients read it from the analysis job API and event stream.

## ADDED Requirements

### Requirement: Outlet information analyzer
A deployment that offers outlet information SHALL register it as a regular, selectable analyzer with id `source_info`, category `coverage`, trigger `on_dependencies_succeeded` and `depends_on` including `news_search`. Clients SHALL locate its result as the AnalyzerRun with `id` `source_info` and SHALL treat a missing, `skipped` or `failed` run as "no outlet information available", not as "no known outlets".

#### Scenario: Selected explicitly
- **WHEN** a client posts `{"input": {"content": "..."}, "analyzers": ["source_info"]}` to a deployment that has the analyzer enabled
- **THEN** `source_info` and its transitive dependencies (at least `news_search` and `topic_extraction`) are selected

#### Scenario: News search did not succeed
- **WHEN** `news_search` is `failed`
- **THEN** `source_info` is `skipped` with reason `dependency_failed` and `result: null`, also when `input.source.url` is set

#### Scenario: News search skipped
- **WHEN** `news_search` is `skipped` (for example with reason `no_searchable_topics`)
- **THEN** `source_info` is `skipped` with reason `dependency_skipped` and `result: null`

#### Scenario: Deployment without the analyzer
- **WHEN** the registry has no `source_info` analyzer
- **THEN** jobs have no AnalyzerRun with that id and clients show no outlet information, without error

### Requirement: No sources
When `news_search` succeeded with an empty `articles` array and the job's `input.source.url` is absent, `source_info` SHALL settle as `skipped` with `reason` `no_sources` and `result: null`, after `analyzer.started`. `no_sources` is an AnalyzerRun skip reason in addition to the canonical ones; clients SHALL treat any skip reason they do not know as "not run".

#### Scenario: Nothing found and no page URL
- **WHEN** `news_search` succeeded with `articles: []` and the job was created with `"source": {}`
- **THEN** the event stream has `analyzer.started` then `analyzer.skipped` for `source_info` with `reason: no_sources`

#### Scenario: Nothing found but a page URL
- **WHEN** `news_search` succeeded with `articles: []` and `input.source.url` is `https://www.spiegel.de/politik/a-1.html`
- **THEN** `source_info` is `succeeded` with `articles: []` and `page_outlet` set to the outlet of `spiegel.de` when the deployment's outlet table lists it, otherwise `null`

### Requirement: SourceInfo object
When `source_info` has `succeeded`, its AnalyzerRun `result` SHALL be a SourceInfo object with at least: `articles` (array of SourceArticle), `page_outlet` (Outlet or null), `summary` (SourceSummary) and `table` (OutletTable). It SHALL be the same in `analyzer.succeeded` `data.analyzer.result` and `GET /api/v1/jobs/{id}`. Clients SHALL ignore unknown members.

#### Scenario: Twelve articles
- **WHEN** `news_search` succeeded with 12 Articles, 7 of whose URLs match outlets in the table
- **THEN** `result.articles` has 12 entries, 7 with `matched: true`, and `result.summary.articles` is 12 and `result.summary.matched` is 7

### Requirement: SourceArticle order
`articles` SHALL contain exactly one SourceArticle per Article of the `news_search` result, in the same order, so `articles[i]` describes `news_search` `articles[i]`.

#### Scenario: Order kept
- **WHEN** `news_search` returned Articles for `https://a.example/1`, `https://bbc.com/2` in this order
- **THEN** `articles[0].url` is `https://a.example/1` and `articles[1].url` is `https://bbc.com/2`

### Requirement: SourceArticle object
A SourceArticle SHALL have at least: `url` (the Article's `url`), `domain` (the normalized host of `url` used for matching, or null when `url` has no parsable host) and `matched` (boolean); when `matched` is `true` also `match` (`host` or `domain`) and `outlet` (Outlet). An unmatched entry SHALL have no `outlet` and no `match` member; clients SHALL decide by `matched`.

#### Scenario: Unmatched article
- **WHEN** an Article's URL is `https://example-blog.net/post` and no outlet lists that host or domain
- **THEN** its SourceArticle is `{"url": "https://example-blog.net/post", "domain": "example-blog.net", "matched": false}` (possibly with further members)

#### Scenario: Unparsable URL
- **WHEN** an Article's `url` cannot be parsed as a URL with a host
- **THEN** its SourceArticle has `matched: false` and `domain: null`, and `source_info` still succeeds

### Requirement: Host normalization
The normalized host of a URL SHALL be its host name without port, lower-cased, without a trailing `.` and without one leading `www.`.

#### Scenario: Normalized
- **WHEN** a URL is `https://WWW.Example.COM.:443/a`
- **THEN** its normalized host is `example.com`

### Requirement: Outlet matching
For each Article URL and for `input.source.url`, the backend SHALL look up the normalized host (Host normalization) exactly among every outlet's hosts and domains, giving `match: "host"`; otherwise look up the host's registered domain (public suffix list, eTLD+1) among every outlet's domains, giving `match: "domain"`; otherwise the URL is unmatched. A URL matches at most one outlet. Matching SHALL NOT make network requests.

#### Scenario: Registered domain
- **WHEN** the table has BBC News with domains `bbc.co.uk|bbc.com` and no host `news.bbc.co.uk`, and an Article URL is `https://news.bbc.co.uk/x`
- **THEN** its SourceArticle has `domain: "news.bbc.co.uk"`, `matched: true`, `match: "domain"` and `outlet.name: "BBC News"`

#### Scenario: Exact host
- **WHEN** The Hindu (domain `thehindu.com`) lists host `sportstar.thehindu.com` and an Article URL is `https://sportstar.thehindu.com/x`
- **THEN** it matches The Hindu with `match: "host"`

#### Scenario: Case, www and trailing dot
- **WHEN** an Article URL is `https://WWW.BBC.COM./x`
- **THEN** its `domain` is `bbc.com` and it matches BBC News with `match: "host"`

#### Scenario: Unknown host
- **WHEN** an Article URL is `https://unknown.example/x`
- **THEN** it is unmatched

### Requirement: Outlet object
An Outlet SHALL have at least: `name` (non-empty string), `domain` (the outlet's main registered domain, lower case), `country_code` (ISO 3166-1 alpha-2, upper case, or `""` when unknown), `country` (country name, or `""` when unknown), `bias` and `factuality` (Outlet ratings).

#### Scenario: Outlet with unknown leaning
- **WHEN** a matched outlet's table row has `bias` `unknown` and no country
- **THEN** its Outlet has `bias: "unknown"`, `country_code: ""` and `country: ""`

### Requirement: Outlet ratings
`bias` values SHALL include `farLeft`, `left`, `leanLeft`, `center`, `leanRight`, `right`, `farRight` and `unknown`; `factuality` values SHALL include `veryLow`, `low`, `mixed`, `high`, `veryHigh` and `unknown`. Clients SHALL treat a value they do not know like `unknown`.

#### Scenario: New rating value
- **WHEN** a client reads `bias: "mixedLeaning"`
- **THEN** it shows the outlet as not rated

### Requirement: Page outlet
`page_outlet` SHALL be the Outlet matched (Outlet matching) for the job's `input.source.url`, and `null` when `input.source.url` is absent or unmatched. It SHALL NOT be counted in `summary`.

#### Scenario: Analyzed page on a news site
- **WHEN** `input.source.url` is `https://www.spiegel.de/politik/a-1.html` and the table has an outlet with domain `spiegel.de`
- **THEN** `page_outlet.domain` is `spiegel.de`

### Requirement: SourceSummary object
`summary` SHALL have at least: `articles` (integer, length of `articles`), `matched` (integer, SourceArticles with `matched: true`), `bias` and `countries` (Summary counts) and `outlets` (integer, distinct outlets among matched SourceArticles).

#### Scenario: Two articles from one outlet
- **WHEN** 3 Articles are matched, two to BBC News (`center`, `GB`) and one to an outlet with `bias: "unknown"` and no country
- **THEN** `summary` has `matched: 3`, `bias: {"center": 2, "unknown": 1}`, `countries: {"GB": 2, "": 1}` and `outlets: 2`

### Requirement: Summary counts
`summary.bias` SHALL map each `bias` value (`unknown` included) to the number of matched SourceArticles whose outlet has it; `summary.countries` SHALL map each `country_code` (`""` for no country) likewise. Only keys with a count above 0 appear, and each object's values sum to `matched`.

#### Scenario: Empty when nothing matched
- **WHEN** no SourceArticle is matched
- **THEN** `summary.bias` and `summary.countries` are `{}` and `summary.outlets` is 0

### Requirement: OutletTable object
`table` SHALL have at least `outlets` (integer, number of outlets in the loaded table) and `source` (string naming the table file, without its directory).

#### Scenario: Shipped table
- **WHEN** the deployment uses the outlet table shipped with the backend image
- **THEN** `table.source` is `outlets.csv` and `table.outlets` is greater than 5000

### Requirement: Outlet information failures
`source_info` SHALL be `failed` with `result: null` and `error.code` `adapter_error` when the `news_search` result cannot be read as a NewsSearch object, and with `cancelled` when the job is cancelled. An unparsable or unmatched URL is not a failure. Its skip or failure SHALL NOT fail the job or other analyzers.

#### Scenario: Malformed dependency result
- **WHEN** the `news_search` result has `articles` that is not an array
- **THEN** `source_info` is `failed` with `error.code: adapter_error` and the job still ends `completed`

### Requirement: Outlet information rendering
`name`, `country` and `domain` come from a data file and article URLs; clients SHALL render them as plain text. An outlet's `bias` and `factuality` describe the outlet, not the article or the analyzed text: clients SHALL present them as context on how broad and balanced the coverage is, SHALL NOT present them as evidence that a claim is true or false, and SHALL present an unmatched article or `bias: "unknown"` as "not rated", not as neutral.

#### Scenario: Unknown leaning shown
- **WHEN** a client shows the leaning mix and `summary.bias.unknown` is 4
- **THEN** it labels those 4 as not rated rather than as `center`
