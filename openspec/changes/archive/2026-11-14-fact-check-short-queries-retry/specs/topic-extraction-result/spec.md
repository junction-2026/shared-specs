## ADDED Requirements

### Requirement: Claim query wording
A Claim's `query` and `query_en` SHALL leave out dates and years, relative time ("gestern", "next month"), numbers unless the number is the claim, verbs of deciding or saying ("beschließt", "decided", "announced", "admitted"), hedges ("angeblich", "allegedly") and framing ("breaking", "Eilmeldung", "share before deleted"), and SHALL prefer infinitive or noun form. `text` keeps the full claim.

#### Scenario: Decision with date and framing
- **WHEN** the content is "EILMELDUNG: Die EU hat gestern beschlossen, das Bargeld ab 2027 komplett abzuschaffen!"
- **THEN** `claims` holds one Claim with `text` "Die EU hat gestern beschlossen, das Bargeld ab 2027 komplett abzuschaffen.", `query` such as "EU Bargeld abschaffen" and `query_en` such as "EU abolish cash", neither containing a year, "gestern", "beschließt" or "Eilmeldung"

### Requirement: Plans and decisions are claims
Statements that someone has decided, plans, wants, announced, is going to or will do something SHALL be claims (checkable: did they decide or announce it?). Forecasts about uncertain outcomes nobody controls ("the economy will collapse next year", "this will end badly") SHALL NOT be claims.

#### Scenario: Plan is a claim
- **WHEN** the content is "Die EU will das Bargeld 2027 abschaffen"
- **THEN** `claims` holds one Claim such as `{"text": "Die EU plant, das Bargeld 2027 abzuschaffen.", "language": "de", "query": "EU Bargeld abschaffen", "query_en": "EU abolish cash", ...}`, not `[]`

#### Scenario: Forecast is not a claim
- **WHEN** the content is "The economy will collapse next year, wake up"
- **THEN** the AnalyzerRun is `succeeded` with `claims: []`

## MODIFIED Requirements

### Requirement: Claim object
A Claim SHALL have at least: `text` (one self-contained statement from the content, in its language, close to its wording, pronouns resolved), `language` (BCP-47 code of `text`), `query` (keyword phrase in the claim's language, normally 2-4 words: main actor plus key object or action noun), `query_en` (the same phrase in English; equal to `query` for English content), `entities` (array of strings) and `check_worthiness` (number from 0 to 1). The strings are non-empty.

#### Scenario: Checkable claim with an opinion
- **WHEN** the content is "The government raised the pension age to 70 last year, they are robbing us!" and the model replies with one claim `{"text": "The government raised the pension age to 70 last year.", "language": "en", "query": "pension age 70", "query_en": "pension age 70", "entities": ["government", "pension age", "70"], "check_worthiness": 0.8}`
- **THEN** `claims` holds that one Claim and the opinion "they are robbing us" is not a Claim

### Requirement: What counts as a claim
A Claim SHALL be a statement of fact that could be true or false and be verified: events, numbers, quotes, causal claims, attributions, decisions and plans. Opinions, insults, forecasts, questions, calls to action and vague accusations without checkable content SHALL NOT be claims. `entities` holds the named people, organisations, places and numbers of the claim; `check_worthiness` says how concrete and verifiable it is.

#### Scenario: Opinion only
- **WHEN** the content is "politicians are all the same, wake up" and the model replies `"claims": []`
- **THEN** the AnalyzerRun is `succeeded` with `claims: []`
