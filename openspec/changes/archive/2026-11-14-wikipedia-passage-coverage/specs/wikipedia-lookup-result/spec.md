## ADDED Requirements

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

## MODIFIED Requirements

### Requirement: No verdict from Wikipedia lookup
A `no_page` or `ambiguous` entry, a `no_coverage` or `mentioned` label, or a passage without a claim's entity or number, means only that Wikipedia was not found to cover the claim, not that the claim is false. An `aligned` or `conflicts` label means only that the `evidence_sentence` states the same or a different number or date; it is a mechanical comparison, not a fact check. Clients SHALL NOT present any WikiLookup or its `coverage` as a verdict on whether a claim is true or false.

#### Scenario: No page found
- **WHEN** every WikiLookup of a claim has `status: "no_page"`
- **THEN** a client does not present the claim as false or unverified by Wikipedia

#### Scenario: Conflicting number
- **WHEN** a WikiLookup has `coverage: "conflicts"`
- **THEN** a client may show that Wikipedia's `evidence_sentence` states a different number or date, but does not present the claim as false
