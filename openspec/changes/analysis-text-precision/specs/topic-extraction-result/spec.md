## MODIFIED Requirements

### Requirement: Claim object
A Claim SHALL have at least: `text` (one self-contained statement from the content, in its language, close to its wording, pronouns resolved), `language` (BCP-47 code of `text`), `query` (keyword phrase in the claim's language, see "Claim query"), `query_en` (the same phrase in English; equal to `query` for English content), `entities` (array of strings) and `check_worthiness` (number from 0 to 1). The strings are non-empty.

#### Scenario: Checkable claim with an opinion
- **WHEN** the content is "The government raised the pension age to 70 last year, they are robbing us!" and the model replies with one claim `{"text": "The government raised the pension age to 70 last year.", "language": "en", "query": "government raised pension age 70", "query_en": "government raised pension age 70", "entities": ["government", "pension age", "70"], "check_worthiness": 0.8}`
- **THEN** `claims` holds that one Claim and the opinion "they are robbing us" is not a Claim

### Requirement: What counts as a claim
A Claim SHALL be a statement of fact that could be true or false and be verified: events, numbers, quotes, causal claims, attributions, decisions and plans. Opinions, insults, forecasts, questions, calls to action and vague accusations without checkable content SHALL NOT be claims. `entities` holds the named people, organisations, places and numbers of the claim; `check_worthiness` says how concrete and verifiable it is (see "Check-worthiness of group generalisations").

#### Scenario: Opinion only
- **WHEN** the content is "politicians are all the same, wake up" and the model replies `"claims": []`
- **THEN** the AnalyzerRun is `succeeded` with `claims: []`

## ADDED Requirements

### Requirement: Claim query
A Claim's `query` and `query_en` SHALL normally be 3-8 words naming the specific actor, what they did or what is asserted, and the key number or place. A lone entity or a whole sentence SHALL NOT be a query. The orchestrator's validation of `query` is unchanged ("Claim validation").

#### Scenario: Specific query
- **WHEN** the content claims that Haitian immigrants in Springfield eat pets
- **THEN** the extractor's instructions ask for a query such as "Haitian immigrants Springfield eating pets" and name a lone entity such as "Taiwan country" as a bad query

### Requirement: One assertion per claim
Each Claim SHALL hold one checkable assertion. A sentence listing several accusations or facts SHALL yield one Claim per assertion, each with its own `check_worthiness`; "Claim normalization" then keeps the most check-worthy up to the deployment's maximum.

#### Scenario: Bundled accusations split
- **WHEN** the content is "They're given housing preference, organise Land Grabs, bring violent crime and vote ANC." and the model follows the instructions
- **THEN** the reply holds separate claims for "housing preference", "organise land grabs", "bring violent crime" and "vote ANC"

### Requirement: Check-worthiness of group generalisations
Generalisations about the behaviour of a named group of people (e.g. "migrants bring violent crime") SHALL count as checkable claims with `check_worthiness` of at least 0.6.

#### Scenario: Group generalisation
- **WHEN** the content says "migrants bring violent crime" and the model follows the instructions
- **THEN** the reply holds that claim with `check_worthiness` of at least 0.6
