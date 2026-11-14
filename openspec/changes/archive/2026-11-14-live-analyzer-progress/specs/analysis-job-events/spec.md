## ADDED Requirements

### Requirement: Run plan event
The server SHALL emit `analysis.planned` exactly once per job whose input is available, with `data` having at least `analyzers` (array of PlanEntry) and `total` (integer, the length of `analyzers`). It SHALL NOT be emitted for a job whose scrape did not succeed, nor after cancellation was accepted.

#### Scenario: Failed scrape has no plan
- **WHEN** the scrape of a job fails
- **THEN** the stream contains no `analysis.planned`

### Requirement: Run plan event position
For a job created with `input`, `analysis.planned` SHALL directly follow `job.started` and precede every `analyzer.skipped` and `analyzer.started` of the job. For a job created with `scrape`, it SHALL directly follow `scrape.succeeded` and precede every `analyzer.skipped` emitted after it and every `analyzer.started`.

#### Scenario: Text job plan comes first
- **WHEN** a client follows a job created with `{"input": {"content": "..."}}` from the start
- **THEN** it receives `job.started`, then `analysis.planned`, and only then `analyzer.skipped` or `analyzer.started` events

#### Scenario: Scrape job plan after the scrape
- **WHEN** a client follows a job created with `scrape` from the start and the scrape succeeds
- **THEN** `analysis.planned` directly follows `scrape.succeeded` and precedes every `analyzer.started`

### Requirement: Planned analyzers
`data.analyzers` SHALL contain one PlanEntry for each AnalyzerRun of the job that is not `skipped` with reason `disabled` or `not_selected` and is not hidden, followed by one PlanEntry for the finalizer when finalization will run (an enabled finalizer exists and `options.finalize` is true). Analyzers skipped as `not_applicable`, or later skipped or failed for any reason, SHALL stay planned. The plan SHALL NOT change after it was emitted.

#### Scenario: Not applicable stays planned
- **WHEN** an analyzer is skipped with `not_applicable` at creation of a text job
- **THEN** it is in `analysis.planned` `data.analyzers` and its `analyzer.skipped` follows the plan

#### Scenario: Unselected analyzer not planned
- **WHEN** a job is created with `"analyzers": ["translation"]`
- **THEN** the plan holds `translation` and the finalizer only

#### Scenario: Finalization disabled
- **WHEN** a job is created with `"options": {"finalize": false}`
- **THEN** the plan has no finalizer entry

### Requirement: Hidden analyzers
The deployment MAY mark analyzers as hidden from progress and SHALL mark `text_stats` as hidden by default. A hidden analyzer keeps its AnalyzerRun and its `analyzer.*` events but SHALL NOT appear in any PlanEntry, Progress, `previews` or `activities`, and SHALL NOT be counted in any `total`.

#### Scenario: text_stats excluded
- **WHEN** the registry enables `translation`, `techniques`, `text_stats` and `final_synthesis` and a job selects all analyzers
- **THEN** `data.analyzers` lists `translation`, `techniques` and `final_synthesis`, and `total` is 3

### Requirement: PlanEntry object
A PlanEntry SHALL have at least `id` (the analyzer id), `name` (the AnalyzerRun `name`, or the finalizer's registry name), `activity_key` (the `key` its Activity will have), `depends_on` (array of ids: the AnalyzerRun `depends_on`, or `["*"]` for the finalizer) and `phase` (integer, at least 1). Entries SHALL be ordered by `phase`, then by `id`, with the finalizer last.

#### Scenario: Finalizer entry
- **WHEN** the finalizer `final_synthesis` is planned
- **THEN** its PlanEntry is last and has `activity_key: "finalizer"` and `depends_on: ["*"]`

### Requirement: Plan phases
An analyzer's `phase` SHALL be 1 when none of its `depends_on` ids is planned, otherwise 1 plus the highest `phase` among its planned dependencies. The finalizer's `phase` SHALL be 1 plus the highest analyzer `phase`, or 1 when no analyzer is planned.

#### Scenario: Phases follow dependencies
- **WHEN** the plan holds `translation` and `topic_extraction` (no dependencies), `techniques` (depends on `translation`), `news_search` (depends on `topic_extraction` and `translation`), `source_info` (depends on `news_search`) and the finalizer
- **THEN** `translation` and `topic_extraction` have `phase` 1, `techniques` and `news_search` `phase` 2, `source_info` `phase` 3 and the finalizer `phase` 4

### Requirement: Activity object
An Activity SHALL have at least `key` (string), `text` (non-empty string), `detail` (string or null) and `params` (object, possibly empty). `key` SHALL default to the analyzer id; a deployment MAY assign an analyzer another key. Values of `key` include `translation`, `propaganda_detection`, `techniques`, `llm_techniques`, `topic_extraction`, `news_search`, `fact_check`, `source_info`, `finalizer` and `scrape`.

#### Scenario: Default key
- **WHEN** `fact_check` starts on a deployment that assigns it no other key
- **THEN** its Activity has `key: "fact_check"`

### Requirement: Activity texts
`text` SHALL be a fixed short English description of the key from a built-in table, or the analyzer's `name` for a key the table does not have. `detail` SHALL be a fixed English phrase built only from facts known when the work starts, or null. Neither SHALL contain model output or be produced by an LLM or translation call, and the server SHALL NOT localize them.

#### Scenario: Unknown key
- **WHEN** a deployment-specific analyzer `bot_detection` named "Bot detection" starts
- **THEN** its Activity has `key: "bot_detection"`, `text: "Bot detection"`, `detail: null` and `params: {}`

### Requirement: Activity rendering
Clients SHALL localize an Activity from `key` and `params`, SHALL fall back to `text` and `detail` for keys they do not know, SHALL NOT parse `text` or `detail`, and SHALL render both as plain text. Their wording may change without a contract change.

#### Scenario: Client without a translation for the key
- **WHEN** a client receives an Activity whose `key` it does not know
- **THEN** it shows `text`, and `detail` when not null, as plain text

### Requirement: Activity params
`params` SHALL have, by key: `news_search` `languages` (ISO 639-1 codes that will be searched, in search order); `fact_check` `claims` (integer, claims that will be searched, fact-check-result Qualifying claims); `techniques` `models` (models that will run, `nci-technique` before `nci-social`); `llm_techniques` `title_checked` (boolean, llm-technique-result Headline input); `scrape` `host` (lower-case host of the requested URL without a leading `www.`). Other keys SHALL have `{}`.

#### Scenario: Techniques models
- **WHEN** `techniques` starts on a translation of 30 words with the default bounds
- **THEN** its Activity has `params.models: ["nci-social"]`

### Requirement: Activity details
`detail` SHALL name the `params` facts in English: `news_search` the languages (e.g. "in German and English"), `fact_check` the claim count (e.g. "for 2 claims"), `techniques` "short-post model" for `nci-social` and "document model" for `nci-technique`, `llm_techniques` "including the headline" when `title_checked` is true, `scrape` the host (e.g. "from bsky.app"). A fact that cannot be determined at start SHALL be left out of `params`, and `detail` SHALL then be null.

#### Scenario: News search languages
- **WHEN** `news_search` starts for a German text on a deployment that searches `[source, en]`
- **THEN** `activity` is at least `{"key": "news_search", "text": "Searching news coverage", "detail": "in German and English", "params": {"languages": ["de", "en"]}}`

#### Scenario: Fact check claim count
- **WHEN** `fact_check` starts and 2 claims qualify
- **THEN** its Activity has `params.claims: 2` and `detail` "for 2 claims"

#### Scenario: No headline
- **WHEN** `llm_techniques` starts on a job without a title
- **THEN** its Activity has `params.title_checked: false` and `detail: null`

### Requirement: Progress object
A Progress SHALL have at least `done` (integer: planned analyzers other than the finalizer whose AnalyzerRun is settled, plus 1 once finalization has ended), `running` (ids of planned analyzers whose AnalyzerRun is `running`, ordered by id, plus the finalizer id while finalization is `running`) and `total` (integer, `analysis.planned` `data.total`). It SHALL describe the job state right after the event that carries it.

#### Scenario: Progress values
- **WHEN** the plan has 10 entries, 3 planned analyzers have settled and `news_search` and `techniques` are running
- **THEN** a Progress emitted in that state is `{"done": 3, "running": ["news_search", "techniques"], "total": 10}`

### Requirement: Analyzer start activity and progress
Every `analyzer.started` SHALL keep `data.analyzer` and additionally carry `data.activity` (the Activity of that analyzer) and `data.progress`. For a hidden analyzer `data.progress` SHALL be the job's unchanged Progress.

#### Scenario: Started event members
- **WHEN** `news_search` starts while `techniques` is running and 3 of 10 planned entries are done
- **THEN** the event `data` is at least `{"analyzer": {...}, "activity": {"key": "news_search", "text": "Searching news coverage", "detail": "in German and English", "params": {"languages": ["de", "en"]}}, "progress": {"done": 3, "running": ["news_search", "techniques"], "total": 10}}`

### Requirement: Settle event progress
Every `analyzer.succeeded`, `analyzer.failed` and `analyzer.skipped` emitted after `analysis.planned` SHALL keep its members and additionally carry `data.progress`. Settle events emitted before `analysis.planned` SHALL NOT carry it. `progress.done` SHALL grow by exactly 1 with each settle event of a planned analyzer and SHALL stay unchanged with a settle event of an unplanned analyzer.

#### Scenario: Done reaches total minus one before finalization
- **WHEN** a job with a plan of 10 entries including the finalizer runs to finalization
- **THEN** the planned analyzers' settle events carry `progress.done` 1 to 9 in emission order and `analysis.finalizing` carries `progress.done: 9`

#### Scenario: Unplanned settle event
- **WHEN** a job created with `"analyzers": ["translation"]` emits `analyzer.skipped` with `not_selected` for `fact_check`
- **THEN** that event carries `progress` with `done: 0` while no planned analyzer has settled, and the next planned settle event carries `done: 1`

### Requirement: Settle event availability
`analyzer.failed` and `analyzer.skipped` SHALL additionally carry `data.availability` and `data.note`, equal to `data.analyzer.availability` and `data.analyzer.note`.

#### Scenario: Skipped fact check
- **WHEN** `fact_check` is skipped with `no_checkable_claims` after the plan
- **THEN** `analyzer.skipped` `data` has `availability: "not_applicable"`, `note` "Not run: the text contains no specific factual claims to check." and a `progress`

### Requirement: Result preview
Every `analyzer.succeeded` SHALL carry `data.preview`: an object built by the server from the run's `result`, without any model, provider or network call, for `translation`, `topic_extraction`, `propaganda_detection`, `techniques`, `llm_techniques`, `news_search`, `fact_check` and `source_info`, and null for every other analyzer. The full result stays in `data.analyzer.result` and `GET /api/v1/jobs/{id}`.

#### Scenario: Analyzer without a preview shape
- **WHEN** `text_stats` succeeds
- **THEN** its `analyzer.succeeded` has `data.preview: null` and `data.analyzer.result` as before

### Requirement: Preview content
A preview SHALL contain only members defined in this spec, each copied unchanged from the result (strings not truncated, rewritten or translated) or counted from it. It SHALL NOT contain raw provider data, prompts, credentials, token usage or model output other than the texts named in this spec. Clients SHALL render every preview string as plain text.

#### Scenario: No usage in previews
- **WHEN** `topic_extraction` succeeds with a `usage` object
- **THEN** its preview has no `usage` member

### Requirement: Preview robustness
A result member that is missing or of the wrong type SHALL yield null, or `[]` for a list, in the preview. A preview that cannot be built SHALL be null and SHALL NOT change the run's outcome or its other event members.

#### Scenario: Older result without plain language
- **WHEN** a `techniques` result has a Detection without `plain_language`
- **THEN** that preview entry has `name`, `definition` and `why` null and the run stays `succeeded`

### Requirement: Translation and propaganda previews
The `translation` preview SHALL have at least `source_language` (the result's, string or null) and `translated` (boolean: false when the result has a non-empty `skipped` member or `source_language` is `en`, otherwise true). The `propaganda_detection` preview SHALL have at least `label` (string or null) and `score` (number or null), the result's `label` and `score`.

#### Scenario: English input
- **WHEN** `translation` succeeds with `skipped: "detected_english"` and `source_language: "en"`
- **THEN** its preview is at least `{"source_language": "en", "translated": false}`

### Requirement: Topic extraction preview
The `topic_extraction` preview SHALL have at least `claims` (the `text` of the first 5 `claims` in result order), `topics` (the `title` of the first 5 `topics` in result order), `claims_total` and `topics_total` (integers, the lengths of the result's lists).

#### Scenario: More than five claims
- **WHEN** `topic_extraction` succeeds with 7 claims and 2 topics
- **THEN** its preview has the first 5 claim texts in `claims`, both topic titles in `topics`, `claims_total: 7` and `topics_total: 2`

### Requirement: News search preview
The `news_search` preview SHALL have at least `articles` (integer, number of `articles`), `outlets` (the distinct `domain` values of `articles` in article order, at most 6) and `languages` (the result's `languages`).

#### Scenario: Outlets capped
- **WHEN** `news_search` succeeds with 12 articles from 8 domains
- **THEN** its preview has `articles: 12` and the first 6 distinct domains in `outlets`

### Requirement: Fact check preview
The `fact_check` preview SHALL have at least `fact_checks` (integer, number of `fact_checks`) and `top` (the first 3 `fact_checks` in result order, each with at least `publisher`, `rating`, `rating_normalized` and `url`).

#### Scenario: Four fact checks
- **WHEN** `fact_check` succeeds with 4 `fact_checks`
- **THEN** its preview has `fact_checks: 4` and `top` holds the first 3 in result order

### Requirement: Source info preview
The `source_info` preview SHALL have at least `summary` (the result's `summary`, with at least `matched`, `bias`, `countries` and `outlets`) and `page_outlet` (the result's `page_outlet`, Outlet or null).

#### Scenario: Page outlet passed on
- **WHEN** `source_info` succeeds with `page_outlet.domain: "spiegel.de"`
- **THEN** its preview has `page_outlet.domain: "spiegel.de"` and the result's `summary`

### Requirement: Technique preview
The `techniques` preview SHALL have at least `models` (each `results` entry's `model`, in order), `explanation_language` and `glossary_version` (the result's), `detected_total` (length of `detected`) and `detected` (at most 8 TechniquePreview, by `score` highest first, null last, ties in result order). Its span offsets SHALL be passed unchanged: half-open UTF-16 code-unit offsets into `Job.input.content`.

#### Scenario: More than eight detections
- **WHEN** 10 techniques are detected
- **THEN** `detected_total` is 10 and `detected` holds the 8 with the highest scores

### Requirement: TechniquePreview object
A TechniquePreview SHALL have at least `label` (the Detection `name`), `name`, `definition` and `why` (its `plain_language` members, verbatim), `score` (the highest `score` of a TechniqueScore with that `label` and `above_cutoff: true` in any ModelResult, or null), `models` (the Detection's `models`) and `spans` (its first 3 `spans` in result order, each with at least `start`, `end`, `text` and `why`, verbatim).

#### Scenario: German job
- **WHEN** `techniques` succeeds on a German job with `explanation_language: "de"` and `Loaded_Language` detected with one span
- **THEN** the preview's `Loaded_Language` entry has `name`, `definition` and `why` equal to the result's German `plain_language`, `glossary_version` is set, and its span's `start` and `end` slice `Job.input.content` to its `text`, with its `why`

### Requirement: LLM technique preview
The `llm_techniques` preview SHALL have at least `source` (`"llm"`), `title_checked`, `explanation_language` and `glossary_version` (the result's), `findings_total` (length of the result's `findings`) and `findings`: at most 6 findings whose `label` is `evidence_certainty_mismatch`, `misleading_headline` or `statistical_cherry_picking`, by `confidence` highest first, ties in result order.

#### Scenario: Only closed labels
- **WHEN** `llm_techniques` succeeds with 2 findings
- **THEN** both preview findings have one of the three labels and `source: "llm"`

### Requirement: LLM technique preview finding
Each preview finding SHALL have at least `label`, `source` (`"llm"`), `name`, `definition`, `explanation`, `confidence` and `span` (at least `field`, `start`, `end`, `text`), verbatim from the result. Span offsets SHALL be passed unchanged: half-open UTF-16 offsets into `Job.input.content` when `field` is `content`, into `Job.input.source.title` when `field` is `title`.

#### Scenario: Headline finding
- **WHEN** `llm_techniques` succeeds with a `misleading_headline` finding with span `{field: "title", text: "KILLS thousands", start: 8, end: 23}`
- **THEN** the preview finding has that span, and `Job.input.source.title.slice(8, 23)` is `"KILLS thousands"`

### Requirement: LLM findings kept apart in previews
LLM findings SHALL appear only in the `llm_techniques` preview and SHALL NOT be merged into the `techniques` preview. `explanation` is model text that the preview passes on unchanged.

#### Scenario: Both technique analyzers succeed
- **WHEN** both `techniques` and `llm_techniques` succeed with findings
- **THEN** the `techniques` preview `detected` contains no LLM label and the `llm_techniques` preview holds the LLM findings

### Requirement: Finalization activity and progress
`analysis.finalizing` SHALL keep its members and additionally carry `data.activity` (`key: "finalizer"`, `text` "Writing the verdict", `detail: null`, `params: {}`) and `data.progress` (`done` equal to `total - 1`, `running` holding the finalizer id). `analysis.finalized` and `analysis.finalization_failed` SHALL keep their members and additionally carry `data.progress`.

#### Scenario: Finalizing event
- **WHEN** finalization starts on a job with a plan of 10 entries
- **THEN** `analysis.finalizing` `data` is at least `{"finalization": {...}, "activity": {"key": "finalizer", "text": "Writing the verdict", "detail": null, "params": {}}, "progress": {"done": 9, "running": ["final_synthesis"], "total": 10}}`

#### Scenario: Finalized event
- **WHEN** finalization completes on a job with a plan of 10 entries
- **THEN** `analysis.finalized` keeps `data.finalization` and has `progress` `{"done": 10, "running": [], "total": 10}`

### Requirement: Scrape activity
`scrape.started` SHALL keep `data.scrape` and additionally carry `data.activity` with `key: "scrape"`.

#### Scenario: Scrape started
- **WHEN** a job is created from `https://www.bsky.app/profile/alice.bsky.social`
- **THEN** `scrape.started` `data.activity` has `key: "scrape"`, a non-empty `text`, `params.host: "bsky.app"` and `detail` "from bsky.app"

### Requirement: Snapshot progress members
`job.snapshot` SHALL keep `data.job` and additionally carry `plan` (the `data` of `analysis.planned`, or null before it), `progress` (the current Progress, or null before `analysis.planned`), `previews` (object: id of each succeeded planned analyzer with a non-null preview to that preview) and `activities` (object: id of each running planned analyzer, and of the finalizer while finalization runs, to the Activity of its start event). Each SHALL equal what the events carried.

#### Scenario: Late subscriber rebuilds the view
- **WHEN** a client connects after `translation` and `techniques` succeeded and `news_search` is running
- **THEN** `job.snapshot` `data` has the job's `plan`, a `progress` with `done: 2` and `running: ["news_search"]`, `previews` with the `translation` and `techniques` previews and `activities` with the `news_search` Activity

#### Scenario: Snapshot before the plan
- **WHEN** a client connects while a scrape job is still scraping
- **THEN** `job.snapshot` `data` has `plan: null`, `progress: null`, `previews: {}` and `activities: {}`

### Requirement: Snapshot members are not Job members
The snapshot members `plan`, `progress`, `previews` and `activities` are event-stream state, not members of the Job object. `GET /api/v1/jobs/{id}` and every other endpoint returning a Job SHALL NOT change, and `data.job` SHALL still equal the REST Job.

#### Scenario: REST unchanged
- **WHEN** a client calls `GET /api/v1/jobs/{id}` on a job whose `techniques` run succeeded
- **THEN** the response has no `preview`, `plan` or `progress` member and the run's `result` is the full result
