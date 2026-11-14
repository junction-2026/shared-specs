# wikipedia-lookup-result Specification

## Purpose
Result object of the `wikipedia` analyzer: for each checkable claim found by `topic_extraction`, the Wikipedia page and revision that was read in the post's language and in English, with a verbatim passage, as clients read it from the analysis job API and event stream.

## Requirements

### Requirement: Wikipedia analyzer
A deployment that offers Wikipedia lookup SHALL register it as a regular, selectable analyzer with id `wikipedia`, category `fact_check`, trigger `on_dependencies_succeeded` and `depends_on` including `topic_extraction` and `translation`. Clients SHALL locate its result as the AnalyzerRun with `id` `wikipedia` and SHALL treat a missing, `skipped` or `failed` run as "no Wikipedia lookup available", not as "Wikipedia has nothing on it".

#### Scenario: Selected explicitly
- **WHEN** a client posts `{"input": {"content": "..."}, "analyzers": ["wikipedia"]}` to a deployment that has the analyzer enabled
- **THEN** `wikipedia` and its transitive dependencies (at least `topic_extraction` and `translation`) are selected and every other analyzer is `skipped` with reason `not_selected`

#### Scenario: Dependency failed
- **WHEN** `topic_extraction` or `translation` is `failed`
- **THEN** `wikipedia` is `skipped` with reason `dependency_failed` and no Wikipedia request is sent

#### Scenario: Deployment without the analyzer
- **WHEN** the registry has no `wikipedia` analyzer
- **THEN** jobs have no AnalyzerRun with that id and clients show no Wikipedia lookup, without error

### Requirement: Wikipedia lookup inputs
`wikipedia` SHALL search only the `query` and `query_en` of the `claims` of the `topic_extraction` result. It SHALL NOT search the job's input text, Topics or NewsItems, and SHALL NOT call an LLM, a translation service or the fact-check provider.

#### Scenario: Topics are not searched
- **WHEN** `topic_extraction` returned two Topics and one qualifying claim
- **THEN** only the claim's `query` and `query_en` are sent to Wikipedia

### Requirement: Qualifying claims
`wikipedia` SHALL search only claims whose `check_worthiness` is at least the deployment's minimum (default 0.4), taking at most the deployment's maximum number of claims (default 3) in the order of `claims`. Claims below the minimum or beyond the maximum SHALL NOT be searched and SHALL NOT appear in the result.

#### Scenario: Low check-worthiness and cap
- **WHEN** the extraction has five claims with `check_worthiness` 0.9, 0.8, 0.3, 0.6 and 0.5 in this order and the defaults apply
- **THEN** the claims with 0.9, 0.8 and 0.6 are searched, in that order, and the result has three ClaimLookup entries

### Requirement: Nothing to look up
When the `topic_extraction` result has no qualifying claim, including an empty or missing `claims` member, `wikipedia` SHALL settle as `skipped` with reason `no_checkable_claims`, `error: null` and `result: null`, after `analyzer.started`, without sending any Wikipedia request. Its `availability` and `note` follow analysis-jobs-api "Nothing-to-check skips" for that reason.

#### Scenario: Only low-worthiness claims
- **WHEN** `topic_extraction` succeeded with one claim with `check_worthiness` 0.2
- **THEN** the event stream has `analyzer.started` then `analyzer.skipped` for `wikipedia` with `reason: no_checkable_claims` and `availability: not_applicable`, and no Wikipedia request was sent

### Requirement: Wikis searched
The wikis searched SHALL be `{source}.wikipedia.org` with the Claim `query` and `en.wikipedia.org` with the Claim `query_en`, in that order, where `source` is the `translation` result's `source_language` lower-cased, used only when it is a two-letter ISO 639-1 code. The claim's own `language` member SHALL NOT select the wiki.

#### Scenario: German post
- **WHEN** `translation` reported `source_language: "de"` and a qualifying claim has `query: "Rentenalter 70"` and `query_en: "retirement age 70"`
- **THEN** the claim's ClaimLookup has two WikiLookup entries: `{"language": "de", "query": "Rentenalter 70", ...}` then `{"language": "en", "query": "retirement age 70", ...}`

### Requirement: Single English search
When `source` is `en`, or is missing or not a two-letter code, only `en.wikipedia.org` SHALL be searched, with `query_en`, so each qualifying claim gets one search instead of two.

#### Scenario: English post
- **WHEN** `translation` reported `source_language: "en"` and two claims qualify
- **THEN** each ClaimLookup has exactly one WikiLookup, with `language: "en"`, and at most two searches are sent

#### Scenario: Unknown source language
- **WHEN** the `translation` result has no `source_language`
- **THEN** each ClaimLookup has one WikiLookup with `language: "en"` and `query` equal to the claim's `query_en`

### Requirement: Search mode
Each ClaimLookup SHALL have a `search_mode` of `fulltext` when the claim is about a number, a date or an event, and `title` otherwise. A claim is about a number or a date when its `text` contains a decimal digit (`0`-`9`); it is about an event when none of its `entities` contains a character other than digits, whitespace and punctuation. `search_mode` applies to every WikiLookup of the claim.

#### Scenario: Number claim
- **WHEN** a claim's `text` is "The government raised the pension age to 70."
- **THEN** its `search_mode` is `fulltext`

#### Scenario: Entity claim
- **WHEN** a claim's `text` is "Angela Merkel was a member of the CDU." and its `entities` are `["Angela Merkel", "CDU"]`
- **THEN** its `search_mode` is `title`

### Requirement: Page selection
For each WikiLookup the backend SHALL run one Wikipedia search for `query`, consider its hits in rank order and choose the page as follows (entity match: see "Entity match"):
- no hits: `status: "no_page"`;
- `search_mode: "title"`: the first entity match; when there is none, the top hit;
- `search_mode: "fulltext"`: the top hit;
- when the page so chosen is a disambiguation page: the first entity match when there is one, otherwise `status: "ambiguous"` and no page is chosen.

#### Scenario: No hits
- **WHEN** the search returns no hits
- **THEN** the WikiLookup has `status: "no_page"` and the `query` that was sent

#### Scenario: Full-text top hit
- **WHEN** a `fulltext`-mode claim's search returns the non-disambiguation hits `Retirement in Germany` then `Pension`
- **THEN** the WikiLookup has `status: "found"` and `title: "Retirement in Germany"`

### Requirement: Entity match
An entity match SHALL be a search hit that is not a disambiguation page and whose title, compared case-insensitively, equals an entity of the claim or equals it followed by a space and a parenthesised qualifier (for example `Mercury (planet)` for `Mercury`).

#### Scenario: Qualified title
- **WHEN** a claim has `entities: ["Mercury"]` and a hit is titled `Mercury (planet)`
- **THEN** that hit is an entity match

#### Scenario: Entity title preferred
- **WHEN** a `title`-mode claim has `entities: ["CDU"]` and the search hits are, in order, `Christian Democratic Union of Germany` and `CDU`
- **THEN** the WikiLookup has `status: "found"` and `title: "CDU"`

#### Scenario: Ambiguous top hit
- **WHEN** the top hit is the disambiguation page `Mercury` and no other hit's title matches an entity of the claim
- **THEN** the WikiLookup has `status: "ambiguous"`, `title: null`, `url: null` and `passage: null`

#### Scenario: Disambiguated by another entity
- **WHEN** the top hit is the disambiguation page `Mercury`, the claim's `entities` are `["Mercury", "Freddie Mercury"]` and a later hit is titled `Freddie Mercury`
- **THEN** the WikiLookup has `status: "found"` and `title: "Freddie Mercury"`

### Requirement: WikipediaLookup object
When `wikipedia` has `succeeded`, its AnalyzerRun `result` SHALL be a WikipediaLookup object with at least: `languages` (array of the wiki language codes searched, in search order, no duplicates), `claims` (ClaimLookup array, one per searched claim, in `claims` order, non-empty), `requests_used` and `cached` (integers, see "Wikipedia request accounting"). It SHALL be the same in the `analyzer.succeeded` event and `GET /api/v1/jobs/{id}`. Clients SHALL ignore unknown members.

#### Scenario: One German claim, both wikis hit
- **WHEN** one claim qualifies, `source_language` is `de`, both searches find a page and nothing is cached
- **THEN** `result` is at least `{"languages": ["de", "en"], "claims": [{"claim": "<claim text>", "check_worthiness": 0.8, "search_mode": "title", "wikis": [<WikiLookup de>, <WikiLookup en>]}], "requests_used": <n>, "cached": 0}` with `n` greater than 0

### Requirement: ClaimLookup object
A ClaimLookup SHALL have at least: `claim` (the Claim `text`), `check_worthiness` (the Claim's number), `search_mode` (values include `title` and `fulltext`) and `wikis` (WikiLookup array, one per wiki searched for the claim, in `languages` order).

#### Scenario: Claim echoed
- **WHEN** the claim `{"text": "Die EU plant, das Bargeld abzuschaffen.", "check_worthiness": 0.7, ...}` is searched
- **THEN** its ClaimLookup has `claim: "Die EU plant, das Bargeld abzuschaffen."` and `check_worthiness: 0.7`

### Requirement: WikiLookup object
A WikiLookup SHALL have at least: `language` (wiki language code), `query` (the search string sent, verbatim), `status` (values include `found`, `no_page` and `ambiguous`), `cached` (boolean: answered from the deployment's cache), and `title`, `url`, `page_id`, `revision_id`, `revised_at`, `passage`, `passage_source`, `matched_entities` and `matched_numbers`. Clients SHALL treat an unknown `status` like `no_page`.

#### Scenario: Unknown status
- **WHEN** a client reads a WikiLookup with `status: "redirect_loop"`
- **THEN** it presents the entry like `no_page`

### Requirement: WikiLookup page members
With `status: "found"`, a WikiLookup SHALL have `title` (page title), `url` (see "Revision permalink"), `page_id` and `revision_id` (positive integers of that wiki), `revised_at` (RFC 3339 UTC timestamp of that revision), `passage` (non-empty string), `passage_source` (values include `lead` and `snippet`), `matched_entities` and `matched_numbers` (string arrays, possibly empty). With any other `status` these members SHALL be null.

#### Scenario: Hit
- **WHEN** a `fulltext`-mode claim's `en` search for "retirement age 70" chooses page id 1234 at revision 1250000000 saved at 2026-10-02T08:15:00Z
- **THEN** the WikiLookup is at least `{"language": "en", "query": "retirement age 70", "status": "found", "cached": false, "title": "Retirement age", "url": "https://en.wikipedia.org/w/index.php?title=Retirement_age&oldid=1250000000", "page_id": 1234, "revision_id": 1250000000, "revised_at": "2026-10-02T08:15:00Z", "passage": "<verbatim text>", "passage_source": "snippet", "matched_entities": [...], "matched_numbers": ["70"]}`

#### Scenario: Miss
- **WHEN** the `de` search for "Rentenalter 70" returns no hits
- **THEN** the WikiLookup is `{"language": "de", "query": "Rentenalter 70", "status": "no_page", "cached": false, "title": null, "url": null, "page_id": null, "revision_id": null, "revised_at": null, "passage": null, "passage_source": null, "matched_entities": null, "matched_numbers": null}` (at least)

### Requirement: Revision permalink
A found WikiLookup's `url` SHALL be an absolute `https` URL on host `{language}.wikipedia.org` with path `/w/index.php` and a query parameter `oldid` equal to `revision_id`, so that opening it shows the revision whose text was read, also after the page is edited.

#### Scenario: Page edited later
- **WHEN** a page is edited after a job read revision 1250000000
- **THEN** the job's `url` still has `oldid=1250000000` and opens the revision that was read

### Requirement: Passage
`passage` SHALL be text Wikipedia returned for the chosen page: with `search_mode: "title"` the plain-text lead section (`passage_source: "lead"`); with `search_mode: "fulltext"` the search snippet of the chosen hit (`passage_source: "snippet"`), or the lead when the snippet is empty. A lead longer than the deployment's limit (default 1500 characters) MAY be cut to a leading part.

#### Scenario: Lead for a title-mode claim
- **WHEN** a `title`-mode claim's chosen page has the plain-text lead "The Christian Democratic Union of Germany (CDU) is a political party in Germany."
- **THEN** `passage` is that text and `passage_source` is `lead`

### Requirement: Passage is verbatim
The backend SHALL store `passage` verbatim: it SHALL NOT summarise, translate, reword, merge or otherwise change the text, except removing the HTML markup of a search snippet and decoding its HTML character references. It SHALL NOT produce a passage when Wikipedia returned none.

#### Scenario: Snippet markup removed
- **WHEN** the search snippet of the chosen hit is `the retirement age to <span class="searchmatch">70</span> &amp; more`
- **THEN** `passage` is `the retirement age to 70 & more` and `passage_source` is `snippet`

### Requirement: Matched entities and numbers
`matched_entities` SHALL list the claim's `entities` that occur in `passage` (case-insensitive substring), in `entities` order without duplicates. `matched_numbers` SHALL list the numbers of the claim — each maximal run of decimal digits in the claim's `text` — that occur in `passage` as a digit run not directly preceded or followed by another digit, in order of first appearance without duplicates. Every listed value SHALL occur in `passage`; a value that does not occur SHALL NOT be listed.

#### Scenario: Partial match
- **WHEN** the claim text is "The government raised the pension age to 70 in 2025.", its `entities` are `["government", "pension age", "70"]` and `passage` is "In many countries the pension age is 67; some plan 70."
- **THEN** `matched_entities` is `["pension age", "70"]` and `matched_numbers` is `["70"]`

#### Scenario: Digit run inside a longer number
- **WHEN** the claim text contains `70` and the passage contains `1970` but no standalone `70`
- **THEN** `matched_numbers` is `[]`

### Requirement: Wikipedia request accounting
`requests_used` SHALL be the number of HTTP requests this run sent to Wikipedia, including retries. `cached` SHALL be the number of WikiLookup entries answered without a request, from the deployment's cache or from an identical `(language, query, search_mode)` lookup earlier in the same run. The cache SHALL persist across backend restarts and SHALL store only successful answers, including `no_page` and `ambiguous`; failed requests SHALL NOT be cached.

#### Scenario: Second run after a restart
- **WHEN** the backend is restarted and a job with the same qualifying claims and source language runs while the first job's lookups are still cached
- **THEN** its `wikipedia` result has `requests_used: 0`, `cached` equal to the number of WikiLookup entries, every WikiLookup has `cached: true`, and the WikiLookup values other than `cached` equal those of the first run

### Requirement: Wikipedia failures
`wikipedia` SHALL be `failed` with `result: null` and `error.code` `adapter_error` when any Wikipedia request fails (a connection error, an HTTP answer other than 2xx remaining after a single retry of 429 and 5xx answers, or an answer that cannot be decoded), or when the `topic_extraction` result is not a JSON object; with `timeout` when the analyzer's configured timeout elapses; with `cancelled` when the job is cancelled. A failure SHALL NOT fail the job or change other analyzers' results.

#### Scenario: Wikipedia down
- **WHEN** the `en` search answers HTTP 503 twice
- **THEN** `wikipedia` is `failed` with `error.code: adapter_error`, `result: null` and `availability: unavailable`, other analyzers keep their results and the job ends `completed`

### Requirement: No partial Wikipedia result
A failed `wikipedia` run SHALL report no partial result and no passage, and has `availability: unavailable` (analysis-jobs-api "Unavailable runs"). Lookups that succeeded before the failure SHALL NOT be shown.

#### Scenario: Second search fails
- **WHEN** the `de` search of a claim succeeded and its `en` search answers HTTP 500 twice
- **THEN** `wikipedia` is `failed` with `result: null` and no passage of the `de` page appears in the job

### Requirement: Wikipedia result rendering
`claim`, `query`, `title` and `passage` come from untrusted content or third parties. Clients SHALL render them as plain text, without HTML or Markdown interpretation and without turning their contents into links. Clients MAY render `url` as a link only when it is an absolute `https` URL whose host ends in `.wikipedia.org`. Clients SHALL NOT rely on a maximum number of entries or a maximum string length.

#### Scenario: Markup in a passage
- **WHEN** a `passage` contains `<b>bold</b> [x](https://example.com)`
- **THEN** a client shows those characters literally and creates no link

### Requirement: No verdict from Wikipedia lookup
A `no_page` or `ambiguous` entry, or a passage without a claim's entity or number, means only that Wikipedia was not found to cover the claim. Clients SHALL NOT present any WikiLookup as a verdict on whether a claim is true or false.

#### Scenario: No page found
- **WHEN** every WikiLookup of a claim has `status: "no_page"`
- **THEN** a client does not present the claim as false or unverified by Wikipedia
