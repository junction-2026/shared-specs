## Purpose
Result object of the `fact_check` analyzer: existing fact-checks published by fact-checking organisations (Google Fact Check Tools, ClaimReview), found by searching the claims extracted by `topic_extraction`, as clients read it from the analysis job API and event stream.

## ADDED Requirements

### Requirement: Fact check analyzer
A deployment that offers fact-check lookup SHALL register it as a regular, selectable analyzer with id `fact_check`, category `fact_check`, trigger `on_dependencies_succeeded` and `depends_on: ["topic_extraction"]`. It SHALL use only the `claims` of the `topic_extraction` result and SHALL NOT call an LLM or a translation service. Clients SHALL locate its result as the AnalyzerRun with `id` `fact_check` and treat a missing, `skipped` or `failed` run as "no lookup available".

#### Scenario: Analyzer selected explicitly
- **WHEN** a client posts `{"input": {"content": "..."}, "analyzers": ["fact_check"]}` to a deployment that has both analyzers enabled
- **THEN** the job runs `topic_extraction` and then `fact_check`, and every other analyzer is `skipped` with reason `not_selected`

#### Scenario: Extraction failed
- **WHEN** `topic_extraction` is `failed`
- **THEN** `fact_check` is `skipped` with reason `dependency_failed` and no fact-check request is sent

### Requirement: Qualifying claims
`fact_check` SHALL search only claims whose `check_worthiness` is at least the deployment's minimum (default 0.4), taking at most the deployment's maximum number of claims (default 3) in the order of `claims`.

#### Scenario: Low check-worthiness
- **WHEN** the extraction has claims with `check_worthiness` 0.7 and 0.2 and the minimum is 0.4
- **THEN** only the first claim is searched and `queries` holds no entry for the second

### Requirement: Search queries per claim
For a claim whose `language` has the primary subtag `en` (case-insensitive) it SHALL send one search: `query` with `languageCode` set to the claim's `language`. For any other claim it SHALL send two searches: `query` with `languageCode` set to the claim's `language`, and `query_en` with `languageCode` `en`. A `(query, languageCode)` pair already planned for an earlier claim SHALL NOT be searched again.

#### Scenario: German text with two qualifying claims
- **WHEN** the extraction has two claims with `language: de` and `check_worthiness` 0.9 and 0.5
- **THEN** `fact_check` sends at most 4 searches: per claim, its `query` with `languageCode=de` and its `query_en` with `languageCode=en`

#### Scenario: English claim
- **WHEN** a qualifying claim has `language: en-GB`
- **THEN** `fact_check` sends one search for it: `query` with `languageCode=en-GB`

### Requirement: Nothing to check
When the `topic_extraction` result has no qualifying claim, including an empty or missing `claims` member, `fact_check` SHALL settle as `skipped` with reason `no_checkable_claims`, `error: null` and `result: null`, after `analyzer.started`, without sending any request to the fact-check provider. `no_checkable_claims` is an AnalyzerRun skip reason in addition to the canonical ones; clients SHALL treat any skip reason they do not know as "not run".

#### Scenario: Opinion-only text
- **WHEN** `topic_extraction` succeeded with `claims: []`
- **THEN** the event stream has `analyzer.started` then `analyzer.skipped` for `fact_check` with `reason: no_checkable_claims`, and zero provider requests were sent

#### Scenario: Older extractor without claims
- **WHEN** `topic_extraction` succeeded with a result that has no `claims` member
- **THEN** `fact_check` is `skipped` with `reason: no_checkable_claims` and does not fail

### Requirement: FactCheckResult object
When `fact_check` has `succeeded`, its AnalyzerRun `result` SHALL be a FactCheckResult object with at least: `queries` (Query array, one per planned search, see "Query order"), `fact_checks` (FactCheck array, possibly empty), `requests_used` and `cached` (integers). It SHALL be the same in the `analyzer.succeeded` event and `GET /api/v1/jobs/{id}`; clients SHALL ignore unknown members. Empty `fact_checks` means none was found, not that a claim is true.

#### Scenario: Matches found
- **WHEN** one German claim is searched with two queries, the first returns one claim with one review and the second returns nothing
- **THEN** the result is at least `{"queries": [{"q": "<query>", "language": "de", "for_claim": "<claim text>", "claims": 1, "status": "succeeded", "cached": false, "error": null}, {"q": "<query_en>", "language": "en", "for_claim": "<claim text>", "claims": 0, "status": "succeeded", "cached": false, "error": null}], "fact_checks": [<one FactCheck>], "requests_used": 2, "cached": 0}`

### Requirement: Query order
`queries` SHALL list the planned searches with claims in `claims` order and, within a claim, the `query` search before the `query_en` search.

#### Scenario: Two German claims
- **WHEN** two German claims A and B are searched
- **THEN** `queries` lists A/de, A/en, B/de, B/en

### Requirement: Request accounting
`requests_used` SHALL be the number of HTTP requests this run sent to the provider, retries included. `cached` SHALL be the number of `queries` answered from the deployment's in-memory cache without a request. Only successful provider answers SHALL be cached.

#### Scenario: Repeated job within the cache lifetime
- **WHEN** a second job with identical qualifying claims runs while the first job's searches are still cached
- **THEN** its `fact_check` result has `requests_used: 0` and `cached` equal to the number of `queries`

### Requirement: Query object
A Query SHALL have at least `q` (the search phrase sent), `language` (the `languageCode` sent), `for_claim` (the `text` of the extracted Claim it was planned for), `claims` (integer: number of claims the provider returned for it; 0 when it failed), `status` (`succeeded` or `failed`), `cached` (boolean: answered from the cache) and `error` (null, or `{"code", "message"}` when `failed`).

#### Scenario: Query listed
- **WHEN** the claim "Die Regierung hat das Rentenalter 2025 auf 70 erhöht." is searched with `q` "Rentenalter auf 70 erhöht" and `languageCode=de` and the provider returns 3 claims
- **THEN** `queries` holds `{"q": "Rentenalter auf 70 erhöht", "language": "de", "for_claim": "Die Regierung hat das Rentenalter 2025 auf 70 erhöht.", "claims": 3, "status": "succeeded", "cached": false, "error": null}`

### Requirement: Partial fact check failure
When some queries fail (HTTP 429 or 5xx remaining after the single retry, a connection error, or an answer that cannot be decoded) and at least one succeeds, `fact_check` SHALL be `succeeded`, list every failed query in `queries` with `status: "failed"`, `claims: 0` and its `error`, and build `fact_checks` from the succeeded queries. A failed query's `error.code` values include `search_failed`.

#### Scenario: One query rate limited
- **WHEN** one of three queries answers HTTP 429 twice and the other two succeed
- **THEN** `fact_check` is `succeeded`, that Query has `status: "failed"` and `error.code: "search_failed"`, `requests_used` counts both attempts, and `fact_checks` holds the matches of the other two

### Requirement: FactCheck object
A FactCheck SHALL be one provider claim/review pair with at least: `for_claim` (extracted Claim `text`), `query` (the `q` that found it), `url` (non-empty), `rating_normalized`, and `claim`, `claimant`, `claim_date`, `publisher`, `site`, `title`, `rating` (verbatim `textualRating`), `language`, `review_date` (string or null, as the provider sent them). A match is a similar checked claim: clients SHALL compare `claim` with `for_claim` before presenting it as a check of the extracted claim.

#### Scenario: Review fields mapped
- **WHEN** the provider returns `{"claims": [{"text": "Rente mit 70 beschlossen", "claimant": "Facebook-Beitrag", "claimDate": "2025-03-01T00:00:00Z", "claimReview": [{"publisher": {"name": "Correctiv", "site": "correctiv.org"}, "url": "https://correctiv.org/x", "title": "Nein, ...", "reviewDate": "2025-03-04T00:00:00Z", "textualRating": "Falsch", "languageCode": "de"}]}]}`
- **THEN** a FactCheck has at least `{"claim": "Rente mit 70 beschlossen", "claimant": "Facebook-Beitrag", "claim_date": "2025-03-01T00:00:00Z", "publisher": "Correctiv", "site": "correctiv.org", "url": "https://correctiv.org/x", "title": "Nein, ...", "rating": "Falsch", "rating_normalized": "false", "language": "de", "review_date": "2025-03-04T00:00:00Z"}` plus its `for_claim` and `query`

### Requirement: Fact check list assembly
`fact_checks` SHALL contain the claim/review pairs of all successful queries, flattened; a review without a `url` SHALL be dropped; of reviews with the same `url` only the first in query planning order SHALL be kept. The list SHALL be ordered by `review_date`, newest first, with items without a parseable `review_date` last and ties kept in planning order, and SHALL hold at most the deployment's maximum (default 10), dropping the oldest.

#### Scenario: Duplicate review across queries
- **WHEN** the German and the English query of one claim both return a review with URL `https://correctiv.org/x`
- **THEN** `fact_checks` holds it once, with the `query` of the German search

#### Scenario: Cap and order
- **WHEN** the searches return 14 distinct reviews and the maximum is 10
- **THEN** `fact_checks` holds the 10 with the newest `review_date`, newest first

### Requirement: Rating normalization
`rating_normalized` SHALL take values including `false`, `misleading`, `mixed`, `true` and `unrated`, derived from `rating` by a built-in term table without an LLM call, matched case-insensitively after trimming whitespace and trailing punctuation; any other or missing rating is `unrated`. The table SHALL map at least: False, Falsch, Faux, Falso to `false`; Misleading, Irreführend, Trompeur to `misleading`; Partly true, Teilweise richtig, Mixture to `mixed`; True, Richtig, Vrai to `true`.

#### Scenario: Required terms
- **WHEN** reviews have `textualRating` `Faux`, `Irreführend`, `Mixture` and `Vrai`
- **THEN** their `rating_normalized` values are `false`, `misleading`, `mixed` and `true`

### Requirement: Normalized rating reading
Clients SHALL treat an unknown `rating_normalized` value as `unrated` and SHALL show `rating` verbatim next to it.

#### Scenario: Unknown rating
- **WHEN** a review's `textualRating` is `Fehlender Kontext`, and the table has no entry for it
- **THEN** the FactCheck has `rating: "Fehlender Kontext"` and `rating_normalized: "unrated"`

#### Scenario: Case and punctuation
- **WHEN** a review's `textualRating` is ` FALSCH. `
- **THEN** `rating_normalized` is `false` and `rating` is ` FALSCH. ` verbatim

### Requirement: Fact check failures
`fact_check` SHALL be `failed` with `result: null` and `error.code` `adapter_error` on a rejected key (see "Rejected fact check key"), when every planned query failed, or when the `topic_extraction` result is not a JSON object; with `timeout` or `cancelled` as for any analyzer. A 429 or 5xx answer SHALL be retried once with backoff before the query counts as failed. A failure SHALL NOT change the job outcome or other analyzers' results.

#### Scenario: API not enabled
- **WHEN** the provider answers HTTP 403
- **THEN** `fact_check` is `failed` with `error.code: adapter_error`, `error.message` names the API key or the API not being enabled, other analyzers keep their results and the job ends `completed`

#### Scenario: Every query fails
- **WHEN** both planned queries answer HTTP 503 twice
- **THEN** `fact_check` is `failed` with `error.code: adapter_error`

### Requirement: Rejected fact check key
On an HTTP 400, 401 or 403 provider answer `fact_check` SHALL send no further requests, and its `error.message` SHALL say that the configured API key is invalid or that the Fact Check Tools API is not enabled for the key's Google Cloud project.

#### Scenario: Invalid key
- **WHEN** the provider answers HTTP 400 for the first request
- **THEN** no further request is sent and `error.message` names the API key setting

### Requirement: Fact check credentials hidden
The provider API key SHALL NOT appear in the FactCheckResult, in `error.message` of a `fact_check` run or of a Query, or in any job event, also when the provider echoes it or the request URL in an error.

#### Scenario: Provider echoes the request URL
- **WHEN** the provider answers HTTP 400 with a message containing the request URL with `key=<api key>`
- **THEN** `error.message` does not contain the API key

### Requirement: Fact check rendering
`for_claim`, `query`, `q`, `claim`, `claimant`, `publisher`, `site`, `title` and `rating` come from untrusted content or third parties. Clients SHALL render them as plain text, without HTML or Markdown interpretation and without turning their contents into links. Clients MAY render `url` as a link only when it is an absolute `http` or `https` URL, and SHALL NOT rely on a maximum number of items or a maximum string length.

#### Scenario: Script URL
- **WHEN** a FactCheck `url` is `javascript:alert(1)`
- **THEN** a client shows it as plain text and creates no link
