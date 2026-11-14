## MODIFIED Requirements

### Requirement: ClaimLookup object
A ClaimLookup SHALL have at least: `claim` (the Claim `text`), `check_worthiness` (the Claim's number), `search_mode` (values include `title` and `fulltext`), `wikis` (WikiLookup array, one per wiki searched for the claim, in `languages` order), `cross_language` (string or null, see "Cross-language state") and `cross_language_differences` (array or null, see "Cross-language differences").

#### Scenario: Claim echoed
- **WHEN** the claim `{"text": "Die EU plant, das Bargeld abzuschaffen.", "check_worthiness": 0.7, ...}` is searched
- **THEN** its ClaimLookup has `claim: "Die EU plant, das Bargeld abzuschaffen."` and `check_worthiness: 0.7`

## ADDED Requirements

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
The backend SHALL compute `cross_language` and `cross_language_differences` only from the `status`, `passage`, `language` and `url` of the claim's WikiLookups, deterministically, without an LLM, a translation service or another network request, and SHALL NOT change, merge or translate any `passage`. The same WikiLookups SHALL give the same members, cached or not.

#### Scenario: Cached rerun
- **WHEN** a job is rerun and every WikiLookup is answered from the cache with the same passages
- **THEN** every ClaimLookup has the same `cross_language` and `cross_language_differences` as in the first run

#### Scenario: Passages untouched
- **WHEN** `cross_language` is `discrepancy`
- **THEN** each WikiLookup's `passage` is the same verbatim text it would have without the comparison

### Requirement: Cross-language rendering
Clients SHALL show each WikiLookup's passage separately and verbatim, SHALL NOT combine the passages or their values into one fact, and SHALL NOT present one passage as a translation of the other. `text` and `value` are untrusted and SHALL be rendered as plain text; a CrossLanguageDifference `url` follows "Wikipedia result rendering". No state is a verdict on the claim ("No verdict from Wikipedia lookup").

#### Scenario: Discrepancy is not a verdict
- **WHEN** a claim has `cross_language: "discrepancy"`
- **THEN** a client quotes the differing values with their language and link and does not present the claim as true or false

### Requirement: Gap is not a conflict
A `gap` means only that one language edition had no page for the claim. Clients SHALL NOT present, count or style a `gap` as a discrepancy, disagreement or conflict.

#### Scenario: Gap shown neutrally
- **WHEN** a claim has `cross_language: "gap"`
- **THEN** a client shows that only one language edition had a page, with no discrepancy or conflict wording, styling or count
