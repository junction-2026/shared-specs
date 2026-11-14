## Purpose
Result object of the news coverage search analyzer: the searches it ran for the topics and news items of a job's text and the news and web articles it found, as clients read it from the analysis job API and event stream.

## ADDED Requirements

### Requirement: News search analyzer
A deployment that offers news coverage search SHALL register it as a regular analyzer with id `news_search` (trigger `on_dependencies_succeeded`, selectable like any other analyzer) that depends on `topic_extraction` and searches the `query` of its Topics and the `headline` of its NewsItems. Clients SHALL locate its result as the AnalyzerRun with `id` `news_search` and SHALL treat a missing, `skipped` or `failed` run as "no coverage search available", not as "no coverage exists".

#### Scenario: Selected explicitly
- **WHEN** a client posts `{"input": {"content": "..."}, "analyzers": ["news_search"]}` to a deployment that has the analyzer enabled
- **THEN** `news_search` and its transitive dependencies (at least `topic_extraction`) are selected and every other analyzer is `skipped` with reason `not_selected`

#### Scenario: Topic extraction failed
- **WHEN** `topic_extraction` is `failed`
- **THEN** `news_search` is `skipped` with reason `dependency_failed` and no search is sent

#### Scenario: Deployment without the analyzer
- **WHEN** the registry has no `news_search` analyzer
- **THEN** jobs have no AnalyzerRun with that id and clients show no coverage search, without error

### Requirement: Nothing to search
When the `topic_extraction` result has no Topic and no NewsItem, `news_search` SHALL settle as `skipped` with `reason` `no_searchable_topics` and `result: null`, after `analyzer.started`, without sending any search or translation request. `no_searchable_topics` is an AnalyzerRun skip reason in addition to the canonical ones; clients SHALL treat any skip reason they do not know as "not run".

#### Scenario: Empty extraction
- **WHEN** `topic_extraction` succeeded with `{"topics": [], "news": [], "input_truncated": false, "usage": null}`
- **THEN** the event stream has `analyzer.started` then `analyzer.skipped` for `news_search` with `reason: no_searchable_topics`, and the search provider received no request

### Requirement: NewsSearch object
When `news_search` has `succeeded`, its AnalyzerRun `result` SHALL be a NewsSearch object with at least: `languages` (array of ISO 639-1 codes searched, in configured order, no duplicates), `queries` (array of SearchQuery, one per query and language), `articles` (array of Article, possibly empty) and the counters `searches_used` and `cached`. It SHALL be the same in `analyzer.succeeded` `data.analyzer.result` and `GET /api/v1/jobs/{id}`. Clients SHALL ignore unknown members.

#### Scenario: Two topics in German and English
- **WHEN** `topic_extraction` returned two Topics and no NewsItem, `translation` reported `source_language: "de"`, the deployment searches `[source, en]`, every news search returns at least the deployment's minimum and nothing is cached
- **THEN** `result` has `languages: ["de", "en"]`, four SearchQuery entries all with `endpoint: "news"` and `status: "succeeded"`, `searches_used: 4` and `cached: 0`

### Requirement: Search counters
`searches_used` SHALL be the number of search requests this run sent to the search provider, counting web search fallbacks and retries and not counting cache hits. `cached` SHALL be the number of searches answered from the deployment's cache instead of the provider.

#### Scenario: Repeated job served from cache
- **WHEN** a second job with the same input runs while the first job's searches are still cached
- **THEN** its `searches_used` is 0 and `cached` is greater than 0

### Requirement: SearchQuery object
A SearchQuery SHALL have at least: `q` (query string sent, in `language`), `original` (the Topic `query` or NewsItem `headline` it was made from), `origin` (`topic` or `news`), `language` (ISO 639-1 code), `endpoint` (`news`, or `search` when the web search fallback ran), `status` (`succeeded` or `failed`), `results` (integer: provider results for this entry before merging, 0 when failed), `cached` (boolean: all its searches came from the cache) and `error` (null or `{"code", "message"}`).

#### Scenario: Translated query
- **WHEN** a Topic `query` is `"Spritpreis Erhöhung November 2026"`, the source language is `de` and `en` is searched
- **THEN** the `en` entry has `original: "Spritpreis Erhöhung November 2026"`, an English `q`, and `language: "en"`

### Requirement: SearchQuery order and errors
SearchQuery entries SHALL be ordered by Topic order, then NewsItem order, and within one item by `languages` order. A failed entry's `error.code` values include `search_failed` and `translation_failed`.

#### Scenario: Order of entries
- **WHEN** one Topic and one NewsItem are searched in `["de", "en"]`
- **THEN** `queries` lists topic/de, topic/en, news/de, news/en

### Requirement: Web search fallback
For a query and language whose news search returns fewer results than the deployment's minimum, the backend SHALL send one web search for that query and language only and report the entry with `endpoint: "search"` and `results` counting both searches.

#### Scenario: Fallback for one query
- **WHEN** the German news search for one topic returns 1 result, the deployment's minimum is 2, and the web search for it returns 6
- **THEN** that entry has `endpoint: "search"` and `results: 7`, and every other entry keeps `endpoint: "news"`

### Requirement: Article object
An Article SHALL have at least: `title` (non-empty string), `url` (absolute `http` or `https` URL), `domain` (lower-case host of `url` without a leading `www.`), `source` (outlet name or null), `date` (provider's date text or null; no format is guaranteed), `snippet` (string or null), `language` and `query` (`language` and `q` of the SearchQuery that found it) and `origin` (`topic` or `news`). Results without an `http`/`https` URL SHALL be dropped.

#### Scenario: Web result without date
- **WHEN** a web search fallback result has a title, link and snippet but no date or outlet
- **THEN** its Article has `date: null` and `source: null`

#### Scenario: Relative date
- **WHEN** the provider reports a news result's date as `"3 hours ago"`
- **THEN** the Article has `date: "3 hours ago"`

### Requirement: Article merging
`articles` SHALL contain no two Articles with the same URL (scheme and host compared lower-case, fragment removed; the first in result order is kept), at most the deployment's per-domain limit of Articles per `domain` and at most its total limit. Clients SHALL NOT rely on a maximum number of Articles or SearchQuery entries.

#### Scenario: Same article found in two languages
- **WHEN** the `de` and `en` searches both return `https://www.example.com/a#top` and `https://WWW.EXAMPLE.COM/a`
- **THEN** `articles` contains one Article for that URL

#### Scenario: Domain limit
- **WHEN** the per-domain limit is 2 and the searches return 5 distinct articles from `example.com`
- **THEN** `articles` contains 2 Articles with `domain: "example.com"`

### Requirement: Article order
Articles SHALL be ordered by the rank at which the provider returned them (best first), ties ordered newest first where the date can be interpreted, then by SearchQuery order.

#### Scenario: Rank first
- **WHEN** an article is rank 1 in the `en` search and another is rank 2 in the `de` search
- **THEN** the rank 1 article comes first

### Requirement: Partial search failure
When some SearchQuery entries fail (a search failing after the orchestrator's single retry of HTTP 429 and 5xx answers, a connection error, or a failed query translation) and at least one succeeds, `news_search` SHALL be `succeeded`, list every failed entry with `status: "failed"` and its `error`, and merge the Articles of the succeeded entries. A failed entry SHALL NOT fail the job or any other analyzer.

#### Scenario: One query rate-limited
- **WHEN** the provider answers HTTP 429 twice for the `en` search of one topic and the other searches succeed
- **THEN** `news_search` is `succeeded`, that entry has `status: "failed"` and `error.code: "search_failed"`, and `searches_used` counts both attempts

#### Scenario: Translation unavailable
- **WHEN** the query translation request fails and the source-language searches succeed
- **THEN** the source-language entries are `succeeded`, the entries of the other languages are `failed` with `error.code: "translation_failed"` and no search was sent for them

### Requirement: News search failures
`news_search` SHALL be `failed` with `result: null` and `error.code` `adapter_error` when the search provider or the translation provider answers HTTP 401 or 403 (no further searches are sent), when every SearchQuery entry failed, or when the `topic_extraction` result cannot be read as a TopicExtraction object; with `timeout` when the analyzer's configured timeout elapses; with `cancelled` when the job is cancelled. Its failure SHALL NOT fail the job or other analyzers.

#### Scenario: Rejected API key
- **WHEN** the search provider answers HTTP 401
- **THEN** `news_search` is `failed` with `error.code: adapter_error`, `error.message` says the search provider rejected the configured API key, other analyzers keep their results and the job ends `completed`

#### Scenario: All searches fail
- **WHEN** every search answers HTTP 503 twice
- **THEN** `news_search` is `failed` with `error.code: adapter_error`

### Requirement: News search errors hide credentials
`error.message` of a failed `news_search` run, every SearchQuery `error.message` and every other member of the result MAY include provider error text but MUST NOT contain credentials: the search API key, the translation API key, `X-API-KEY` or `Authorization` header values. An error caused by a rejected key SHALL name which configured key was rejected without its value.

#### Scenario: Provider echoes the key
- **WHEN** the search provider answers HTTP 403 with a body that repeats the configured API key
- **THEN** `error.message` names the search API key setting and does not contain the key

### Requirement: Search result rendering
`title`, `source`, `date`, `snippet`, `q` and `original` come from untrusted web content or model output. Clients SHALL render them as plain text, without HTML or Markdown interpretation and without turning their contents into links. Clients MAY render `url` as a link only after checking that its scheme is `http` or `https`. An empty `articles` array means nothing was found; clients SHALL NOT present it as evidence that a claim is false.

#### Scenario: Markup in a snippet
- **WHEN** an Article `snippet` contains `<img src=x onerror=alert(1)>`
- **THEN** a client shows those characters literally
