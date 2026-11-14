## MODIFIED Requirements

### Requirement: TopicExtraction object
When `topic_extraction` has `succeeded`, its AnalyzerRun `result` SHALL be a TopicExtraction object with at least: `topics` (Topic array), `news` (NewsItem array), `claims` (Claim array), each possibly empty, `input_truncated` (boolean, see "Topic extraction input"), `usage` (provider token usage object or null), `attempts`, `retry_reason` ("Topic extraction reply retry"). It SHALL be the same in the `analyzer.succeeded` event and `GET /api/v1/jobs/{id}`. Clients SHALL ignore unknown members.

#### Scenario: Topics and news
- **WHEN** the model replies `{"topics": [{"title": "Fuel price rise", "query": "fuel price increase November 2026", "description": "Claim that fuel prices rose 40% this month"}], "news": [{"headline": "Government raises fuel tax", "summary": null}], "claims": []}` on the first request and the provider reported `{"prompt_tokens": 300, "completion_tokens": 60, "total_tokens": 360}`
- **THEN** the AnalyzerRun has `status: succeeded` and `result` is at least `{"topics": [{"title": "Fuel price rise", "query": "fuel price increase November 2026", "description": "Claim that fuel prices rose 40% this month"}], "news": [{"headline": "Government raises fuel tax", "summary": null}], "claims": [], "input_truncated": false, "usage": {"prompt_tokens": 300, "completion_tokens": 60, "total_tokens": 360}, "attempts": 1, "retry_reason": null}`

### Requirement: Topic extraction output normalization
The orchestrator SHALL store `title`, `query`, `description`, `headline` and `summary` as returned (an absent `description` or `summary` as null), keep the order of topics and news, set `input_truncated`, `attempts` and `retry_reason` itself, set `usage` only from the provider's reports (null when none, combined after a reply retry) and drop every other member of the reply and of its items. Claims follow "Claim normalization".

#### Scenario: Extra members dropped
- **WHEN** the model replies on the first request `{"topics": [], "news": [], "claims": [], "reasoning": "...", "usage": {"total_tokens": 1}, "attempts": 7}` and the provider reported no usage
- **THEN** the stored result is at least `{"topics": [], "news": [], "claims": [], "input_truncated": false, "usage": null, "attempts": 1, "retry_reason": null}` and has no `reasoning` member

## ADDED Requirements

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
