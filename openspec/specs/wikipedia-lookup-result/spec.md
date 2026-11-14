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
A ClaimLookup SHALL have at least: `claim` (the Claim `text`), `check_worthiness` (the Claim's number), `search_mode` (values include `title` and `fulltext`), `wikis` (WikiLookup array, one per wiki searched for the claim, in `languages` order), `cross_language` (string or null, see "Cross-language state") and `cross_language_differences` (array or null, see "Cross-language differences").

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
A `no_page` or `ambiguous` entry, a `no_coverage` or `mentioned` label, or a passage without a claim's entity or number, means only that Wikipedia was not found to cover the claim, not that the claim is false. An `aligned` or `conflicts` label means only that the `evidence_sentence` states the same or a different number or date; it is a mechanical comparison, not a fact check. Clients SHALL NOT present any WikiLookup or its `coverage` as a verdict on whether a claim is true or false.

#### Scenario: No page found
- **WHEN** every WikiLookup of a claim has `status: "no_page"`
- **THEN** a client does not present the claim as false or unverified by Wikipedia

#### Scenario: Conflicting number
- **WHEN** a WikiLookup has `coverage: "conflicts"`
- **THEN** a client may show that Wikipedia's `evidence_sentence` states a different number or date, but does not present the claim as false

### Requirement: Wikipedia coverage label
Every WikiLookup of a succeeded `wikipedia` result SHALL have `coverage`, whose values include `no_coverage`, `mentioned`, `aligned` and `conflicts`, decided by the backend without an LLM (see "Wikipedia coverage rule order"), and `evidence_sentence`, a string when `coverage` is `aligned` or `conflicts` and null otherwise. A WikiLookup whose `status` is not `found` SHALL have `coverage: "no_coverage"` and `evidence_sentence: null`.

#### Scenario: Page not found
- **WHEN** a WikiLookup has `status: "no_page"` or `status: "ambiguous"`
- **THEN** it has `coverage: "no_coverage"` and `evidence_sentence: null`

### Requirement: Unknown or absent coverage
Clients SHALL treat an unknown `coverage` value, and an absent `coverage` (results stored before this member existed), like `no_coverage`.

#### Scenario: Unknown coverage value
- **WHEN** a client reads a WikiLookup with `coverage: "partially_aligned"`
- **THEN** it presents the entry like `no_coverage`

#### Scenario: Result stored before the label existed
- **WHEN** a client reads a stored WikiLookup with `status: "found"` and no `coverage` member
- **THEN** it presents the entry like `no_coverage`

### Requirement: Coverage entities
For the coverage rules, a named entity of a claim SHALL be an element of its `entities` that contains a character other than decimal digits, whitespace and punctuation, and the matched named entities SHALL be the named entities listed in `matched_entities`. A sentence contains a named entity when it contains it as a case-insensitive substring.

#### Scenario: Numeric entity is not a named entity
- **WHEN** a claim has `entities: ["pension age", "70"]`
- **THEN** its only named entity is `pension age` and its claim numbers include `70`

### Requirement: Coverage numbers
The claim numbers SHALL be the numbers of "Matched entities and numbers": each maximal run of decimal digits (`0`-`9`) in the claim's `text`, without duplicates. A number occurs in a text when it appears there as a digit run not directly preceded or followed by a decimal digit; the numbers of a text are its maximal digit runs. A number's kind is `year` when it has exactly four digits and `count` otherwise. Dates are compared only through their digit runs.

#### Scenario: Date digit runs
- **WHEN** the claim text is "The law passed on 3 May 2025." and a passage writes the date as "2025-05-03"
- **THEN** the claim numbers are `3` and `2025`; `2025` occurs in the passage and `3` does not

#### Scenario: Numbers in words are not compared
- **WHEN** the claim text contains `70` and the passage says "seventy" but has no digit run `70`
- **THEN** `70` does not occur in the passage

### Requirement: Passage sentences
The sentences of `passage` SHALL be the parts between sentence boundaries, with leading and trailing whitespace removed and empty parts ignored. A boundary follows each `.`, `!`, `?`, `…`, `。`, `！` or `？` that is followed by whitespace or by the end of `passage` (the punctuation stays in the preceding sentence), and each line break. A `.` between two digits is no boundary.

#### Scenario: Sentences of a lead
- **WHEN** `passage` is "Angela Merkel is a German politician. She was Chancellor of Germany from 2005 to 2021.\nShe led the CDU."
- **THEN** its sentences are "Angela Merkel is a German politician.", "She was Chancellor of Germany from 2005 to 2021." and "She led the CDU."

### Requirement: Wikipedia coverage rule order
For a WikiLookup with `status: "found"` the backend SHALL use the first that applies of: `no_coverage` when there is no matched named entity; `mentioned` when the claim has no claim number (a relation without a number or date is not compared); `aligned` per "Aligned coverage"; `conflicts` per "Conflicting coverage"; otherwise `mentioned`.

#### Scenario: Claim without a number
- **WHEN** the claim text is "Angela Merkel was a member of the CDU." with `entities: ["Angela Merkel", "CDU"]` and `passage` names both
- **THEN** the WikiLookup has `coverage: "mentioned"` and `evidence_sentence: null`

#### Scenario: Number shared but no entity
- **WHEN** the claim's numbers occur in `passage` but none of its named entities does
- **THEN** the WikiLookup has `coverage: "no_coverage"`

#### Scenario: Mentioned without the number
- **WHEN** the claim text is "The government raised the pension age to 70 in 2025." with `entities: ["government", "pension age", "70"]` and `passage` is "In many countries the pension age is 67; some plan 70."
- **THEN** the WikiLookup has `coverage: "mentioned"` and `evidence_sentence: null`, because `2025` does not occur and the claim's only count `70` occurs in the sentence

### Requirement: Aligned coverage
A found WikiLookup SHALL be `aligned` when a sentence of `passage` contains every claim number, with the first such sentence as `evidence_sentence`.

#### Scenario: Aligned
- **WHEN** the claim text is "Germany raised the retirement age to 67 in 2007." with `entities: ["Germany", "retirement age"]` and `passage` is "In 2007, Germany decided to raise the retirement age to 67 by 2029. The change took effect gradually."
- **THEN** the WikiLookup has `coverage: "aligned"` and `evidence_sentence: "In 2007, Germany decided to raise the retirement age to 67 by 2029."`

### Requirement: Conflicting coverage
A found WikiLookup that is not `aligned` SHALL be `conflicts` when a sentence of `passage` contains a matched named entity and a standalone number X that is not a claim number, where the claim has exactly one claim number of X's kind and that number does not occur in the sentence (see "Standalone numbers"). The first such sentence is `evidence_sentence`.

#### Scenario: Conflicts on a date
- **WHEN** the claim text is "Angela Merkel became chancellor in 2006." with `entities: ["Angela Merkel"]` and `passage` is "Angela Merkel is a German politician who was Chancellor of Germany from 2005 to 2021. She led the CDU."
- **THEN** the WikiLookup has `coverage: "conflicts"` and `evidence_sentence: "Angela Merkel is a German politician who was Chancellor of Germany from 2005 to 2021."`

#### Scenario: Conflicts on a number
- **WHEN** the claim text is "The pension age in Germany is 70." with `entities: ["Germany", "pension age"]` and `passage` is "In Germany the pension age is 67."
- **THEN** the WikiLookup has `coverage: "conflicts"` and `evidence_sentence: "In Germany the pension age is 67."`

#### Scenario: Two counts are not compared
- **WHEN** the claim text is "Today the Bundestag voted 412 to 180 to ban cash payments." with `entities: ["Bundestag"]` and `passage` is "The Bundestag is the German federal parliament. It has 630 members."
- **THEN** the WikiLookup has `coverage: "mentioned"`, because the claim has two counts and so no single count to compare

### Requirement: Standalone numbers
A digit run of a sentence SHALL be a standalone number unless it is directly preceded or followed by `.`, `,`, `'`, U+00A0 or U+202F that is itself adjacent to another decimal digit; a grouped or decimal number such as `1.500`, `1,500` or `2,5` gives no standalone number.

#### Scenario: Grouped number is not compared
- **WHEN** the claim text is "Die Stadt hat 1500 Einwohner." with `entities: ["Stadt"]` and `passage` is "Die Stadt hat 1.500 Einwohner."
- **THEN** the WikiLookup has `coverage: "mentioned"`, because `1500` does not occur and `1` and `500` are not standalone numbers

### Requirement: Evidence sentence is verbatim
A non-null `evidence_sentence` SHALL be a non-empty substring of `passage`, character for character, containing every claim number for `aligned` and the differing number X for `conflicts`. When the backend cannot produce such a sentence it SHALL report `mentioned` instead of `aligned` or `conflicts`.

#### Scenario: Evidence copied from the passage
- **WHEN** a WikiLookup has `coverage: "conflicts"`
- **THEN** its `evidence_sentence` occurs in its `passage` exactly as written and contains the differing number

### Requirement: Unverifiable evidence
A consumer, including the finalizer and the orchestrator, SHALL treat a WikiLookup with `coverage` `aligned` or `conflicts` whose `evidence_sentence` is missing, null or not a substring of `passage` as `mentioned`; a label is never upgraded without a verifiable span.

#### Scenario: Unverifiable evidence downgraded
- **WHEN** a client reads a WikiLookup with `coverage: "aligned"` whose `evidence_sentence` does not occur in `passage`
- **THEN** it presents the entry as `mentioned`, not as `aligned`

### Requirement: Coverage is per WikiLookup
The backend SHALL decide each WikiLookup's `coverage` and `evidence_sentence` from that WikiLookup and its claim only, independent of the claim's other WikiLookups, of any comparison between language editions and of any other ClaimLookup member. `conflicts` states only that one passage gives a number or date other than the claim's; clients SHALL NOT present it as a disagreement between language editions, and a difference between language editions SHALL NOT change any WikiLookup's `coverage`.

#### Scenario: Two editions labelled separately
- **WHEN** a claim "Das Rentenalter in Deutschland ist 67." with `entities: ["Deutschland", "Rentenalter"]` has a `de` WikiLookup whose `passage` is "In Deutschland liegt das Rentenalter bei 67 Jahren." and an `en` WikiLookup with `status: "no_page"`
- **THEN** the `de` WikiLookup has `coverage: "aligned"` and the `en` WikiLookup has `coverage: "no_coverage"`, and neither label is affected by the other edition

### Requirement: Claims about recent events
The backend SHALL decide the coverage label only from `passage`, `entities` and the claim's `text`, never from another source. A claim about an event Wikipedia does not describe yet thus gets `no_coverage` or at most `mentioned`, which SHALL NOT be read as the event being false; `news_search` remains the analyzer that shows whether outlets report it.

#### Scenario: Event of today
- **WHEN** the claim text is "Today the Bundestag voted 412 to 180 to ban cash payments." and the full-text search for its `query_en` returns no hits
- **THEN** its WikiLookup has `status: "no_page"`, `coverage: "no_coverage"` and `evidence_sentence: null`, and no client or finalizer presents the claim as false because of it

### Requirement: Missing cross-language members
Clients SHALL treat a missing `cross_language` or `cross_language_differences` member like `null`, so results produced before these members existed stay readable.

#### Scenario: Older result without cross-language members
- **WHEN** a client reads a ClaimLookup that has no `cross_language` and no `cross_language_differences` member
- **THEN** it presents the claim as having no cross-language comparison, without error

### Requirement: Cross-language state
For each ClaimLookup the backend SHALL set `cross_language` from its WikiLookups, where a WikiLookup "returned a page" when its `status` is `found` and its `passage` is non-null. `cross_language` SHALL be `null` when the claim has fewer than two WikiLookups (single English search) or when none of its WikiLookups returned a page. Clients SHALL treat an unknown `cross_language` value like `null`.

#### Scenario: Single-wiki search is not a gap
- **WHEN** `source_language` is `en` or unknown and the claim has one WikiLookup
- **THEN** `cross_language` is `null`

#### Scenario: Neither language returned a page
- **WHEN** both WikiLookups of a claim are `no_page`
- **THEN** `cross_language` is `null`

#### Scenario: Unknown state
- **WHEN** a client reads `cross_language: "partial"`
- **THEN** it presents the claim like `cross_language: null`

### Requirement: Cross-language gap
`cross_language` SHALL be `gap` when the claim has two WikiLookups and exactly one of them returned a page. A WikiLookup with `status` `no_page`, `ambiguous` or any other value than `found` did not return a page.

#### Scenario: Only one language returned a page
- **WHEN** a claim's `de` WikiLookup is `no_page` or `ambiguous` and its `en` WikiLookup is `found`
- **THEN** `cross_language` is `gap` and `cross_language_differences` is `null`

### Requirement: Cross-language agree and discrepancy
When both WikiLookups of a claim returned a page, `cross_language` SHALL be `agree` when the two passages have the same set of comparison values (see "Cross-language comparison values"), including when neither passage has any, and `discrepancy` when the two sets differ.

#### Scenario: Same numbers and dates
- **WHEN** a claim's `de` passage is "Das Rentenalter liegt seit 2012 bei 67 Jahren." and its `en` passage is "Since 2012 the retirement age has been 67."
- **THEN** `cross_language` is `agree` and `cross_language_differences` is `null`

#### Scenario: Neither passage has a number or date
- **WHEN** both WikiLookups of a claim are `found` and neither passage contains a decimal digit
- **THEN** `cross_language` is `agree`

#### Scenario: A number differs
- **WHEN** a claim's `de` passage is "Das Rentenalter liegt bei 67 Jahren." and its `en` passage is "The retirement age is 70."
- **THEN** `cross_language` is `discrepancy` and `cross_language_differences` quotes `67` with language `de` and the `de` url, and `70` with language `en` and the `en` url

### Requirement: Cross-language comparison values
The comparison values of a passage SHALL be the dates and numbers the backend recognises in it, each with `kind` (values include `date` and `number`) and a normalized `value` (see "Date comparison values" and "Number comparison values"). Two values are equal when both `kind` and `value` are equal; the set comparison ignores order and repetition. Signs, units, percent signs and words are not part of a value.

#### Scenario: Repetition ignored
- **WHEN** the `de` passage mentions `67` twice and the `en` passage once, and neither has other digits
- **THEN** `cross_language` is `agree`

### Requirement: Date comparison values
A calendar date written with a day, month and year SHALL give a `date` value `YYYY-MM-DD`, and a month with a year a `date` value `YYYY-MM`, when written in a notation of the wiki's language or in ISO 8601. Digits that belong to a recognised date SHALL NOT also give a `number` value.

#### Scenario: Same date in two languages
- **WHEN** the `de` passage contains "am 2. März 2025" and the `en` passage contains "on 2 March 2025", and no other digits
- **THEN** both passages have the single value `{"kind": "date", "value": "2025-03-02"}` and `cross_language` is `agree`

#### Scenario: Year only on one side
- **WHEN** the `de` passage contains "im März 2025" and the `en` passage contains "in 2025", and no other digits
- **THEN** the `de` value is `{"kind": "date", "value": "2025-03"}`, the `en` value is `{"kind": "number", "value": "2025"}` and `cross_language` is `discrepancy`

### Requirement: Number comparison values
Every other number in a passage, including a standalone year, SHALL give a `number` value, read with the wiki language's digit-group and decimal separators. `value` SHALL be plain decimal notation: no group separators, `.` as decimal separator, no leading zeros in the integer part except a single `0`, no trailing fractional zeros.

#### Scenario: Grouped numbers in two notations
- **WHEN** the `de` passage contains "1.500 Einwohner" and the `en` passage contains "1,500 inhabitants" and nothing else with digits
- **THEN** both passages have the single value `{"kind": "number", "value": "1500"}` and `cross_language` is `agree`

#### Scenario: Decimal comma
- **WHEN** a `de` passage contains "2,50 Euro"
- **THEN** it has the value `{"kind": "number", "value": "2.5"}`

### Requirement: Cross-language differences
`cross_language_differences` SHALL be non-null exactly when `cross_language` is `discrepancy`. It SHALL then have one CrossLanguageDifference per WikiLookup of the claim, in `languages` order, with at least `language` and `url` (equal to that WikiLookup's) and `values`: an array, possibly empty, of the comparison values of that passage that do not occur in the other passage. At least one `values` SHALL be non-empty.

#### Scenario: Values on one side only
- **WHEN** the `de` passage is "Die Partei wurde gegründet." and the `en` passage is "The party was founded in 1945."
- **THEN** `cross_language` is `discrepancy` and `cross_language_differences` is `[{"language": "de", "url": "<de url>", "values": []}, {"language": "en", "url": "<en url>", "values": [{"kind": "number", "value": "1945", "text": "1945"}]}]` (at least)

#### Scenario: Shared values are not listed
- **WHEN** the `de` passage has the values `2012` and `67` and the `en` passage has `2012` and `70`
- **THEN** the `de` entry lists only `67`, the `en` entry lists only `70`, and `2012` appears in neither

### Requirement: Compared value object
Each entry of a CrossLanguageDifference `values` SHALL have at least `kind`, `value` and `text`, where `text` is the verbatim substring of that wiki's `passage` the value was read from, at its first occurrence. Entries SHALL be in order of first appearance in the passage, without duplicate values.

#### Scenario: Quoted as written
- **WHEN** the differing `de` value was read from "1.500"
- **THEN** its entry is `{"kind": "number", "value": "1500", "text": "1.500"}` (at least)

### Requirement: Cross-language comparison is deterministic
The backend SHALL compute `cross_language` and `cross_language_differences` only from the `status`, `passage`, `language` and `url` of the claim's WikiLookups, deterministically, without an LLM, a translation service or another network request, and SHALL NOT change, merge or translate any `passage`. They SHALL NOT read or change any WikiLookup's `coverage` or `evidence_sentence` (see "Coverage is per WikiLookup"). The same WikiLookups SHALL give the same members, cached or not.

#### Scenario: Cached rerun
- **WHEN** a job is rerun and every WikiLookup is answered from the cache with the same passages
- **THEN** every ClaimLookup has the same `cross_language` and `cross_language_differences` as in the first run

#### Scenario: Coverage unaffected
- **WHEN** a claim's `de` WikiLookup has `coverage: "aligned"` and its `en` WikiLookup has `coverage: "mentioned"`, and the two passages give `cross_language: "discrepancy"`
- **THEN** both WikiLookups keep the `coverage` and `evidence_sentence` they have without the comparison

#### Scenario: Passages untouched
- **WHEN** `cross_language` is `discrepancy`
- **THEN** each WikiLookup's `passage` is the same verbatim text it would have without the comparison

### Requirement: Cross-language rendering
Clients SHALL show each WikiLookup's passage separately and verbatim, SHALL NOT combine the passages or their values into one fact, and SHALL NOT present one passage as a translation of the other. `text` and `value` are untrusted and SHALL be rendered as plain text; a CrossLanguageDifference `url` follows "Wikipedia result rendering". No state is a verdict on the claim ("No verdict from Wikipedia lookup").

#### Scenario: Discrepancy is not a verdict
- **WHEN** a claim has `cross_language: "discrepancy"`
- **THEN** a client quotes the differing values with their language and link and does not present the claim as true or false

### Requirement: Gap is not a conflict
A `gap` means only that one language edition had no page for the claim. Clients SHALL NOT present, count or style a `gap` as a discrepancy, disagreement or conflict, and SHALL NOT present it like a WikiLookup `coverage: "conflicts"`. A `discrepancy` compares the two passages with each other, not with the claim, and is likewise distinct from `coverage: "conflicts"`: clients SHALL NOT merge the two into one count or label.

#### Scenario: Gap shown neutrally
- **WHEN** a claim has `cross_language: "gap"`
- **THEN** a client shows that only one language edition had a page, with no discrepancy or conflict wording, styling or count

#### Scenario: Gap next to a conflicts label
- **WHEN** a claim has `cross_language: "gap"` and its one found WikiLookup has `coverage: "conflicts"`
- **THEN** a client shows the `conflicts` label for that WikiLookup only, and the gap neutrally, and counts no conflict for the gap
