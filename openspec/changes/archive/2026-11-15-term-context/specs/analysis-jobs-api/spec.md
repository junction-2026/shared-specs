## MODIFIED Requirements

### Requirement: Wikipedia quotes for clients
Clients SHALL treat an absent `wikipedia_quotes` (results stored before this member existed) as an empty array, SHALL render `quote`, `claim` and `title` as plain text, and SHALL present only `wikipedia_quotes` entries and `term_context` EncyclopediaQuote objects (term-context-result) as quotations from Wikipedia. Within the final assessment, only `wikipedia_quotes` entries SHALL be presented as quotations from Wikipedia.

#### Scenario: Stored assessment without quotes
- **WHEN** a client reads a FinalAssessment without `wikipedia_quotes`
- **THEN** it shows no Wikipedia quotation in the final assessment

#### Scenario: Term context encyclopedia quote
- **WHEN** a job's `term_context` result has a TermContext whose `encyclopedia` is an EncyclopediaQuote
- **THEN** the client may present its `quote` as a quotation from Wikipedia with its `url`, outside the final assessment, while the final assessment still shows only `wikipedia_quotes` entries
