## ADDED Requirements

### Requirement: Shorter retry for empty searches
When a search (planned or answered from the cache) succeeds with 0 claims, `fact_check` SHALL send exactly one more search for the same claim with the same `languageCode` and the shorter query of "Shorter retry query", built without an LLM call, unless that query is empty or equals the original `q` after trimming and collapsing whitespace, compared case-insensitively.

#### Scenario: Empty German search retried with entities
- **WHEN** a claim with `language: de`, `query` "EU beschließt Bargeld abschaffen 2027" and `entities` ["EU", "Bargeld", "2027"] is searched and the provider returns 0 claims for that query
- **THEN** exactly one more request is sent with `query=EU Bargeld` and `languageCode=de`

#### Scenario: Empty English search retried with three words
- **WHEN** the `query_en` search "EU decides to abolish cash 2027" returns 0 claims
- **THEN** exactly one more request is sent with `query=EU decides to` and `languageCode=en`

#### Scenario: No retry when the shorter query is the same or empty
- **WHEN** a `query_en` search "abolish cash" returns 0 claims, or a `query` search returns 0 claims for a claim whose `entities` is `[]`
- **THEN** no retry is sent for that search

#### Scenario: Retry that also finds nothing
- **WHEN** a retry returns 0 claims
- **THEN** no further search is sent for that claim and language

#### Scenario: Default request bound
- **WHEN** defaults apply (at most 3 claims), all claims are non-English and every search returns 0 claims without errors
- **THEN** `requests_used` is at most 12

### Requirement: Shorter retry limits
A failed search and a shorter retry SHALL NOT get a shorter retry; a retry may get the single 429/5xx backoff retry of "Fact check failures". The duplicate rule of "Search queries per claim" SHALL apply only to planned searches. Shorter retries SHALL be cached and answered from the cache like any search.

#### Scenario: Failed search
- **WHEN** a planned search answers HTTP 503 twice
- **THEN** it is listed as `failed` and no shorter retry is sent for it

### Requirement: Shorter retry query
For the search of a claim's `query`, the shorter query SHALL be the first two entries of the claim's `entities` that are non-blank after trimming, trimmed and joined by one space. For the search of `query_en`, it SHALL be the first three whitespace-separated words of `query_en`, joined by one space.

#### Scenario: Fewer than two entities
- **WHEN** a claim's `entities` is `["  ", "Bargeld"]`
- **THEN** the shorter query for its `query` search is `Bargeld`

### Requirement: Query retry member
A Query SHALL also have `retry_of`: null for a planned search; for a shorter retry, the `q` of the search it retries. A retry's `for_claim` and `language` SHALL equal those of the search it retries. Clients SHALL treat an absent `retry_of` (older deployments) as null.

#### Scenario: Retry with results
- **WHEN** the search "EU beschließt Bargeld abschaffen 2027" (`de`) returns 0 claims and its retry "EU Bargeld" returns 5 claims with reviews
- **THEN** `queries` holds the retry as `{"q": "EU Bargeld", "language": "de", "claims": 5, "status": "succeeded", "retry_of": "EU beschließt Bargeld abschaffen 2027", ...}` and its reviews are in `fact_checks` with `query: "EU Bargeld"`

## MODIFIED Requirements

### Requirement: FactCheckResult object
When `fact_check` has `succeeded`, its AnalyzerRun `result` SHALL be a FactCheckResult object with at least: `queries` (Query array, one per planned search and one per shorter retry, see "Query order"), `fact_checks` (FactCheck array, possibly empty), `requests_used` and `cached` (integers). It SHALL be the same in the `analyzer.succeeded` event and `GET /api/v1/jobs/{id}`; clients SHALL ignore unknown members. Empty `fact_checks` means none was found, not that a claim is true.

#### Scenario: Matches found
- **WHEN** one German claim is searched with two queries, the first returns one claim with one review and the second returns nothing, and the shorter retry of the second also returns nothing
- **THEN** the result is at least `{"queries": [{"q": "<query>", "language": "de", "for_claim": "<claim text>", "claims": 1, "status": "succeeded", "cached": false, "error": null, "retry_of": null}, {"q": "<query_en>", "language": "en", "for_claim": "<claim text>", "claims": 0, "status": "succeeded", "cached": false, "error": null, "retry_of": null}, {"q": "<first 3 words of query_en>", "language": "en", "for_claim": "<claim text>", "claims": 0, "status": "succeeded", "cached": false, "error": null, "retry_of": "<query_en>"}], "fact_checks": [<one FactCheck>], "requests_used": 3, "cached": 0}`

### Requirement: Query order
`queries` SHALL list the planned searches with claims in `claims` order and, within a claim, the `query` search before the `query_en` search; a shorter retry SHALL directly follow the search it retries. This order is the "query planning order".

#### Scenario: Two German claims
- **WHEN** two German claims A and B are searched and no search returns 0 claims
- **THEN** `queries` lists A/de, A/en, B/de, B/en

#### Scenario: Retry placement
- **WHEN** A/de returns 0 claims and gets a shorter retry
- **THEN** `queries` lists A/de, A/de retry, A/en, B/de, B/en

### Requirement: Request accounting
`requests_used` SHALL be the number of HTTP requests this run sent to the provider, including backoff retries of 429/5xx answers and shorter retries. `cached` SHALL be the number of `queries` (shorter retries included) answered from the deployment's in-memory cache without a request. Only successful provider answers SHALL be cached.

#### Scenario: Repeated job within the cache lifetime
- **WHEN** a second job with identical qualifying claims runs while the first job's searches, retries included, are still cached
- **THEN** its `fact_check` result has `requests_used: 0` and `cached` equal to the number of `queries`
