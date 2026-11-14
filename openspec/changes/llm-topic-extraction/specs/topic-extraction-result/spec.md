## Purpose
Result object of the LLM topic extraction analyzer: the fact-checkable topics (with search queries) and the news items found in a job's input text, as clients read it from the analysis job API and event stream.

## ADDED Requirements

### Requirement: Topic extraction analyzer
A deployment that offers topic extraction SHALL register it as a regular analyzer with id `topic_extraction` (trigger `on_dependencies_succeeded`, selectable like any other analyzer) that reads only the job's Input. Clients SHALL locate its result as the AnalyzerRun with `id` `topic_extraction` and SHALL treat a missing, `skipped` or `failed` run as "no extraction available".

#### Scenario: Analyzer selected explicitly
- **WHEN** a client posts `{"input": {"content": "..."}, "analyzers": ["topic_extraction"]}` to a deployment that has the analyzer enabled
- **THEN** the job runs `topic_extraction` and every other non-dependency analyzer is `skipped` with reason `not_selected`

#### Scenario: Deployment without the analyzer
- **WHEN** the registry has no `topic_extraction` analyzer
- **THEN** jobs have no AnalyzerRun with that id and clients show no extraction, without error

### Requirement: TopicExtraction object
When `topic_extraction` has `succeeded`, its AnalyzerRun `result` SHALL be a TopicExtraction object with at least: `topics` (array of Topic, possibly empty), `news` (array of NewsItem, possibly empty) and `usage` (token usage object reported by the LLM provider, or null). The same object SHALL appear in `analyzer.succeeded` `data.analyzer.result` and in `GET /api/v1/jobs/{id}`. Clients SHALL ignore unknown members.

#### Scenario: Topics and news
- **WHEN** the model replies `{"topics": [{"title": "Fuel price rise", "query": "fuel price increase November 2026", "description": "Claim that fuel prices rose 40% this month"}], "news": [{"headline": "Government raises fuel tax", "summary": null}]}` and the provider reported `{"prompt_tokens": 300, "completion_tokens": 60, "total_tokens": 360}`
- **THEN** the AnalyzerRun has `status: succeeded` and `result` is at least `{"topics": [{"title": "Fuel price rise", "query": "fuel price increase November 2026", "description": "Claim that fuel prices rose 40% this month"}], "news": [{"headline": "Government raises fuel tax", "summary": null}], "usage": {"prompt_tokens": 300, "completion_tokens": 60, "total_tokens": 360}}`

### Requirement: Topic and NewsItem objects
A Topic SHALL have at least `title` (non-empty short name of the subject or claim), `query` (non-empty search phrase for finding information on it, not a URL) and `description` (string or null: what is claimed about the topic in the text). A NewsItem SHALL have at least `headline` (non-empty short headline of a newsworthy event or story the text refers to) and `summary` (string or null). Strings are in the language chosen by the model, normally that of the input text.

#### Scenario: Optional members absent in the reply
- **WHEN** the model replies with a topic `{"title": "Vaccine safety", "query": "vaccine X side effects study"}` without `description`
- **THEN** the stored Topic has `description: null`

### Requirement: Empty extraction is a success
Text without fact-checkable topics or without news SHALL yield an empty `topics` or `news` array with `status: succeeded`, not a failure or a skip.

#### Scenario: No news in the text
- **WHEN** the input is a personal opinion with one checkable claim and no news reference
- **THEN** the AnalyzerRun is `succeeded` with one Topic in `topics` and `news: []`

### Requirement: Topic extraction output validation
The orchestrator SHALL fail the AnalyzerRun with `error.code` `invalid_output` and `result: null` when the model's reply cannot be decoded into a JSON object, `topics` or `news` is missing or not an array, an item is not an object, `title`, `query` or `headline` is missing, not a string or empty after trimming, or `description` or `summary` is present and neither a string nor null.

#### Scenario: Blank query
- **WHEN** the model replies `{"topics": [{"title": "Election fraud", "query": "  "}], "news": []}`
- **THEN** `topic_extraction` is `failed` with `error.code: invalid_output` and `result: null`

#### Scenario: Missing news array
- **WHEN** the model replies `{"topics": []}`
- **THEN** `topic_extraction` is `failed` with `error.code: invalid_output`

### Requirement: Invalid extraction fails only the analyzer
An `invalid_output` failure of `topic_extraction` SHALL fail only this analyzer: other AnalyzerRuns, finalization and the job outcome follow the usual rules for a failed analyzer.

#### Scenario: Prose instead of JSON
- **WHEN** the model replies with plain prose
- **THEN** `topic_extraction` is `failed` with `error.code: invalid_output`, other analyzers keep their results and the job ends `completed`

### Requirement: Topic extraction output normalization
The orchestrator SHALL store `title`, `query`, `description`, `headline` and `summary` as returned (an absent `description` or `summary` as null), keep item order, set `usage` only from the provider's report (null when none) and drop every other member of the reply and of its items.

#### Scenario: Extra members dropped
- **WHEN** the model replies `{"topics": [], "news": [], "reasoning": "...", "usage": {"total_tokens": 1}}` and the provider reported no usage
- **THEN** the stored result is `{"topics": [], "news": [], "usage": null}`

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
`title`, `query`, `description`, `headline` and `summary` are model output influenced by untrusted content. Clients SHALL render them as plain text, without HTML or Markdown interpretation and without turning their contents into links, and SHALL NOT rely on a maximum number of items or a maximum string length.

#### Scenario: Markup in a headline
- **WHEN** a NewsItem `headline` contains `<script>x</script> [read](https://example.com)`
- **THEN** a client shows those characters literally and creates no link
