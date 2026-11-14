## ADDED Requirements

### Requirement: Wikipedia quotes in the final assessment
`wikipedia_quotes` of a FinalAssessment SHALL be an array of WikipediaQuote objects, empty when the finalizer kept none, when `produced_by` is `orchestrator` and when the job has no succeeded `wikipedia` AnalyzerRun. A WikipediaQuote SHALL have at least `claim` (a ClaimLookup `claim`), `language` (a WikiLookup `language`), `quote` (string), and `title`, `url`, `revision_id` and `coverage`, which the orchestrator copies from that WikiLookup.

#### Scenario: Assessment without Wikipedia
- **WHEN** the job has no `wikipedia` AnalyzerRun, or finalization is produced by the orchestrator
- **THEN** `finalization.result.wikipedia_quotes` is `[]`

### Requirement: Wikipedia quote verification
The orchestrator SHALL keep a finalizer-proposed quote only when the job's succeeded `wikipedia` AnalyzerRun has a ClaimLookup with an equal `claim` holding a WikiLookup with an equal `language`, `status` `found` and a `coverage` other than `no_coverage` (see "Unverifiable evidence"), whose `passage` contains the proposed `quote`, trimmed and non-empty, as a substring. It SHALL store the trimmed text and drop every other proposed quote without failing finalization.

#### Scenario: Valid quote kept
- **WHEN** the job's `wikipedia` result has a ClaimLookup `claim: "Angela Merkel became chancellor in 2006."` with an `en` WikiLookup `status: "found"`, `coverage: "conflicts"`, `title: "Angela Merkel"`, `revision_id: 1250000000` and a `passage` containing "Chancellor of Germany from 2005 to 2021", and the finalizer returns `"wikipedia_quotes": [{"claim": "Angela Merkel became chancellor in 2006.", "language": "en", "quote": " Chancellor of Germany from 2005 to 2021 "}]`
- **THEN** `finalization.result.wikipedia_quotes` is at least `[{"claim": "Angela Merkel became chancellor in 2006.", "language": "en", "quote": "Chancellor of Germany from 2005 to 2021", "title": "Angela Merkel", "url": "<the WikiLookup url>", "revision_id": 1250000000, "coverage": "conflicts"}]`

#### Scenario: Paraphrase dropped
- **WHEN** the finalizer proposes a quote "Merkel took office in 2005" that is not a substring of the cited `passage`
- **THEN** the quote is not in `finalization.result.wikipedia_quotes`, and finalization is `completed` with the finalizer's `verdict` and `user_text`

#### Scenario: Quote from an uncovered entry dropped
- **WHEN** the finalizer quotes a substring of a `passage` whose WikiLookup has `coverage: "no_coverage"`
- **THEN** the quote is dropped

### Requirement: Wikipedia quotes for clients
Clients SHALL treat an absent `wikipedia_quotes` (results stored before this member existed) as an empty array, SHALL render `quote`, `claim` and `title` as plain text, and SHALL present only `wikipedia_quotes` entries as quotations from Wikipedia.

#### Scenario: Stored assessment without quotes
- **WHEN** a client reads a FinalAssessment without `wikipedia_quotes`
- **THEN** it shows no Wikipedia quotation

## MODIFIED Requirements

### Requirement: FinalAssessment object
The FinalAssessment object SHALL have at least: `verdict` (see "Verdict values"); `confidence` (number 0–1, or null when the finalizer gave none); `user_text` (non-empty plain-language explanation for the end user); `produced_by` (`finalizer` or `orchestrator`); `usage` (token usage object reported by the finalizer adapter, or null); `attempts` and `retry_reason` (see "FinalAssessment retry members"); `wikipedia_quotes` (see "Wikipedia quotes in the final assessment").

#### Scenario: Risk assessment
- **WHEN** the `llm` finalizer's first reply is `{"verdict": "detected", "confidence": 0.86, "user_text": "This post shows signs of propaganda."}` and the provider reported `{"prompt_tokens": 512, "completion_tokens": 48, "total_tokens": 560}`
- **THEN** `finalization.result` is at least `{"verdict": "detected", "confidence": 0.86, "user_text": "This post shows signs of propaganda.", "produced_by": "finalizer", "usage": {"prompt_tokens": 512, "completion_tokens": 48, "total_tokens": 560}, "attempts": 1, "retry_reason": null, "wikipedia_quotes": []}`

#### Scenario: No confidence and no usage
- **WHEN** an `http_sync` finalizer returns `{"verdict": "uncertain", "user_text": "The analyzers disagree."}`
- **THEN** `finalization.result` has `confidence: null`, `usage: null`, `produced_by: finalizer`, `attempts: null`, `retry_reason: null` and `wikipedia_quotes: []`
