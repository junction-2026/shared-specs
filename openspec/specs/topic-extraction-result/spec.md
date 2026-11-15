# topic-extraction-result Specification

## Purpose
Result object of the LLM topic extraction analyzer: the fact-checkable topics (with search queries) and the news items found in a job's input text, as clients read it from the analysis job API and event stream.

## Requirements

### Requirement: Topic extraction analyzer
A deployment that offers topic extraction SHALL register it as a regular analyzer with id `topic_extraction` (trigger `on_dependencies_succeeded`, selectable like any other analyzer) that reads only the job's Input. Clients SHALL locate its result as the AnalyzerRun with `id` `topic_extraction` and SHALL treat a missing, `skipped` or `failed` run as "no extraction available".

#### Scenario: Analyzer selected explicitly
- **WHEN** a client posts `{"input": {"content": "..."}, "analyzers": ["topic_extraction"]}` to a deployment that has the analyzer enabled
- **THEN** the job runs `topic_extraction` and every other non-dependency analyzer is `skipped` with reason `not_selected`

#### Scenario: Deployment without the analyzer
- **WHEN** the registry has no `topic_extraction` analyzer
- **THEN** jobs have no AnalyzerRun with that id and clients show no extraction, without error

### Requirement: TopicExtraction object
When `topic_extraction` has `succeeded`, its AnalyzerRun `result` SHALL be a TopicExtraction object with at least: `topics` (Topic array), `news` (NewsItem array), `claims` (Claim array), each possibly empty, `input_truncated` (boolean, see "Topic extraction input"), `usage` (provider token usage object or null), `attempts`, `retry_reason` ("Topic extraction reply retry"). It SHALL be the same in the `analyzer.succeeded` event and `GET /api/v1/jobs/{id}`. Clients SHALL ignore unknown members.

#### Scenario: Topics and news
- **WHEN** the model replies `{"topics": [{"title": "Fuel price rise", "query": "fuel price increase November 2026", "description": "Claim that fuel prices rose 40% this month"}], "news": [{"headline": "Government raises fuel tax", "summary": null}], "claims": []}` on the first request and the provider reported `{"prompt_tokens": 300, "completion_tokens": 60, "total_tokens": 360}`
- **THEN** the AnalyzerRun has `status: succeeded` and `result` is at least `{"topics": [{"title": "Fuel price rise", "query": "fuel price increase November 2026", "description": "Claim that fuel prices rose 40% this month"}], "news": [{"headline": "Government raises fuel tax", "summary": null}], "claims": [], "input_truncated": false, "usage": {"prompt_tokens": 300, "completion_tokens": 60, "total_tokens": 360}, "attempts": 1, "retry_reason": null}`

### Requirement: Topic and NewsItem objects
A Topic SHALL have at least `title` (non-empty short name of the subject or claim), `query` (non-empty search phrase for finding information on it, not a URL) and `description` (string or null: what is claimed about the topic in the text). A NewsItem SHALL have at least `headline` (non-empty short headline of a newsworthy event or story the text refers to) and `summary` (string or null). Strings are in the language chosen by the model, normally that of the input text.

#### Scenario: Optional members absent in the reply
- **WHEN** the model replies with a topic `{"title": "Vaccine safety", "query": "vaccine X side effects study"}` without `description`
- **THEN** the stored Topic has `description: null`

### Requirement: Topic extraction input
The analyzer SHALL analyse the job's Input `content` as data, never as instructions; for jobs created from a social-media URL this is the content set from the scrape (post text or joined posting history). Content longer than the deployment's input limit SHALL be cut to a leading part before analysis and reported with `input_truncated: true`; blank content SHALL fail the analyzer with `error.code` `adapter_error` without calling the LLM.

#### Scenario: Long scraped input
- **WHEN** the job's Input `content` (for example the joined posting history of a scrape job) is longer than the deployment's input limit
- **THEN** the analyzer analyses only the leading part, succeeds with `input_truncated: true`, and topics or news found only in the cut part are absent

### Requirement: Empty extraction is a success
Text without fact-checkable topics, without news or without checkable claims SHALL yield an empty `topics`, `news` or `claims` array with `status: succeeded`, not a failure or a skip. The analyzer SHALL NOT invent claims that the content does not state.

#### Scenario: No news in the text
- **WHEN** the input is a personal opinion with one checkable claim and no news reference
- **THEN** the AnalyzerRun is `succeeded` with one Topic in `topics`, one Claim in `claims` and `news: []`

#### Scenario: No claim in the text
- **WHEN** the input is an opinion with no checkable statement
- **THEN** the AnalyzerRun is `succeeded` with `claims: []`

### Requirement: Topic extraction output validation
The orchestrator SHALL fail the AnalyzerRun with `error.code` `invalid_output` and `result: null` when the model's reply cannot be decoded into a JSON object; `topics`, `news` or `claims` is missing or not an array; an item is not an object; `title`, `query` or `headline` is missing, not a string or empty after trimming; `description` or `summary` is present and neither a string nor null, or a Claim is invalid (see "Claim validation").

#### Scenario: Blank query
- **WHEN** the model replies `{"topics": [{"title": "Election fraud", "query": "  "}], "news": [], "claims": []}`
- **THEN** `topic_extraction` is `failed` with `error.code: invalid_output` and `result: null`

#### Scenario: Missing news array
- **WHEN** the model replies `{"topics": [], "claims": []}`
- **THEN** `topic_extraction` is `failed` with `error.code: invalid_output`

#### Scenario: Missing claims array
- **WHEN** the model replies `{"topics": [], "news": []}`
- **THEN** `topic_extraction` is `failed` with `error.code: invalid_output` and `result: null`

### Requirement: Invalid extraction fails only the analyzer
An `invalid_output` failure of `topic_extraction` SHALL fail only this analyzer: other AnalyzerRuns, finalization and the job outcome follow the usual rules for a failed analyzer.

#### Scenario: Prose instead of JSON
- **WHEN** the model replies with plain prose
- **THEN** `topic_extraction` is `failed` with `error.code: invalid_output`, other analyzers keep their results and the job ends `completed`

### Requirement: Topic extraction output normalization
The orchestrator SHALL store `title`, `query`, `description`, `headline` and `summary` as returned (an absent `description` or `summary` as null), keep the order of topics and news, set `input_truncated`, `attempts` and `retry_reason` itself, set `usage` only from the provider's reports (null when none, combined after a reply retry) and drop every other member of the reply and of its items. Claims follow "Claim normalization".

#### Scenario: Extra members dropped
- **WHEN** the model replies on the first request `{"topics": [], "news": [], "claims": [], "reasoning": "...", "usage": {"total_tokens": 1}, "attempts": 7}` and the provider reported no usage
- **THEN** the stored result is at least `{"topics": [], "news": [], "claims": [], "input_truncated": false, "usage": null, "attempts": 1, "retry_reason": null}` and has no `reasoning` member

### Requirement: Topic extraction failures
Provider failures SHALL use the existing AnalyzerRun error codes: `adapter_error` for a connection error or a non-2xx provider answer remaining after the orchestrator's single retry of 429 and 5xx answers, `timeout` when the analyzer's configured timeout (default 30s) elapses, `cancelled` when the job is cancelled. Analyzers depending on `topic_extraction` follow the usual `dependency_failed` rule.

#### Scenario: Provider unavailable
- **WHEN** the LLM provider answers HTTP 503 twice
- **THEN** `topic_extraction` is `failed` with `error.code: adapter_error`

### Requirement: Topic extraction errors hide credentials
`error.message` of a failed `topic_extraction` run MAY include the LLM provider's own error text but MUST NOT contain credentials: the API key, `Authorization` header values or other configured secret header values.

#### Scenario: Provider echoes the key
- **WHEN** the provider answers HTTP 401 with a message that repeats the configured API key
- **THEN** `error.message` does not contain the API key

### Requirement: Extracted text rendering
`title`, `query`, `description`, `headline`, `summary` and every string member of a Claim are model output influenced by untrusted content. Clients SHALL render them as plain text, without HTML or Markdown interpretation and without turning their contents into links, and SHALL NOT rely on a maximum number of items or a maximum string length.

#### Scenario: Markup in a headline
- **WHEN** a NewsItem `headline` contains `<script>x</script> [read](https://example.com)`
- **THEN** a client shows those characters literally and creates no link

#### Scenario: Link in a claim
- **WHEN** a Claim `text` contains `https://example.com/proof`
- **THEN** a client shows it as plain text and creates no link

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

### Requirement: Claims from older deployments
Clients SHALL treat a `succeeded` `topic_extraction` result without a `claims` member (produced by an older deployment) as having `claims: []`.

#### Scenario: Result from an older deployment
- **WHEN** a client reads a `succeeded` `topic_extraction` result without a `claims` member
- **THEN** it treats it as `claims: []` without error

### Requirement: Claim validation
The orchestrator SHALL fail the AnalyzerRun with `error.code` `invalid_output` and `result: null` when a Claim's `text`, `language`, `query` or `query_en` is missing, not a string or empty after trimming, its `entities` is present and neither null nor an array of strings, or its `check_worthiness` is missing or not a number.

#### Scenario: Claim without check_worthiness
- **WHEN** the model replies with a claim `{"text": "X happened.", "language": "en", "query": "X happened", "query_en": "X happened"}`
- **THEN** `topic_extraction` is `failed` with `error.code: invalid_output`

### Requirement: Claim normalization
The orchestrator SHALL store `text`, `language`, `query`, `query_en` and `entities` as returned (absent or null `entities` as `[]`), clamp `check_worthiness` to 0..1, drop every other member of a Claim, order claims by `check_worthiness` descending (ties keep the model's order) and keep at most the deployment's maximum (default 5), dropping the lowest-ranked.

#### Scenario: Claims ordered, clamped and capped
- **WHEN** the deployment allows at most 2 claims and the model replies claims with `check_worthiness` 0.3, 1.4 and 0.6, in that order
- **THEN** `claims` holds two Claims with `check_worthiness` 1 and 0.6, in that order

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

### Requirement: Topic extraction reply retry
`topic_extraction` SHALL send reply retries and set `attempts` (1 or 2), `retry_reason` and the combined `usage` by the "LLM reply retry" rules of analysis-jobs-api, with `schema` meaning a JSON object that fails "Topic extraction output validation" or "Claim validation". A second invalid reply fails the run with `invalid_output` and `result: null`. Clients SHALL treat an absent `attempts` or `retry_reason` (older results) as null.

#### Scenario: Missing query retried
- **WHEN** the first reply has a topic without `query` and the second reply is valid
- **THEN** `topic_extraction` is `succeeded` with `attempts: 2` and `retry_reason: "schema"`

#### Scenario: Cut-off reply retried
- **WHEN** the first reply has `finish_reason: "length"` and the second reply is valid
- **THEN** `topic_extraction` is `succeeded` with `attempts: 2`, `retry_reason: "length"` and `usage` combining both reports

#### Scenario: Both replies invalid
- **WHEN** both replies are plain prose
- **THEN** `topic_extraction` is `failed` with `error.code: invalid_output`, other analyzers keep their results and the job ends `completed`

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
