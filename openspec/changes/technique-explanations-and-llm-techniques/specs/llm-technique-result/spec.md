## Purpose
Result object of the LLM technique analyzer: findings of three weaknesses that the 18 SemEval-2020 labels do not cover (evidence-certainty mismatch, misleading headline, statistical cherry-picking) in a job's original text and headline, kept separate from and marked weaker than model-detected techniques.

## ADDED Requirements

### Requirement: LLM technique analyzer
A deployment that offers LLM technique detection SHALL register it as a regular, selectable analyzer with id `llm_techniques`, category `propaganda` and `depends_on` including `translation`. Clients SHALL locate its result as the AnalyzerRun with `id` `llm_techniques` and SHALL treat a missing, `skipped` or `failed` run as "no LLM technique analysis available", not as "none found".

#### Scenario: Deployment without the analyzer
- **WHEN** the registry has no `llm_techniques` analyzer
- **THEN** jobs have no AnalyzerRun with that id and clients show no LLM technique section, without error

#### Scenario: Translation failed
- **WHEN** `translation` is `failed`
- **THEN** `llm_techniques` is `skipped` with reason `dependency_failed`, `result: null`, and no LLM request is sent

### Requirement: LLM technique labels
The analyzer SHALL look only for, and emit only, these labels: `evidence_certainty_mismatch` (a claim is stated with more certainty than the evidence in the text supports), `misleading_headline` (the headline states or implies something the body does not support) and `statistical_cherry_picking` (numbers are selected to support a conclusion the fuller data would not).

#### Scenario: Unknown label from the LLM
- **WHEN** the LLM answers with a finding labelled `fabricated_authority`
- **THEN** the finding is dropped

### Requirement: LLM labels stay apart from model labels
The LLM technique labels SHALL NOT be mapped onto, merged with or reported as any of the 18 technique names of technique-classifier-result, and findings SHALL NOT be added to `techniques` `detected`. Clients SHALL ignore findings whose `label` they do not know.

#### Scenario: No SemEval label emitted
- **WHEN** the LLM answers with a finding labelled `Appeal_to_Authority`
- **THEN** the finding is dropped and `techniques` is unchanged

### Requirement: LlmTechniqueResult object
When `llm_techniques` has `succeeded`, its `result` SHALL be an LlmTechniqueResult with at least: `source` (`"llm"`), `title_checked` (boolean), `labels_checked` (array of labels), `explanation_language`, `glossary_version`, `truncated` (boolean) and `findings` (array of LlmTechniqueFinding, possibly empty). It SHALL be the same in `analyzer.succeeded` and `GET /api/v1/jobs/{id}`. Clients SHALL ignore unknown members.

#### Scenario: Nothing found
- **WHEN** the LLM reports no finding for a job without title
- **THEN** `llm_techniques` is `succeeded` with `source: "llm"`, `title_checked: false` and `findings: []`

### Requirement: LlmTechniqueResult member values
`labels_checked` SHALL list the labels the LLM was asked for, in the order of the LLM technique labels requirement: all three when `title_checked` is true, otherwise `evidence_certainty_mismatch` and `statistical_cherry_picking`. `explanation_language` and `glossary_version` SHALL be decided as in technique-classifier-result Plain-language result members. `truncated` SHALL be true when content beyond the input limit was not sent or findings beyond the per-label limit were dropped.

#### Scenario: Labels without title
- **WHEN** `title_checked` is false
- **THEN** `labels_checked` is `["evidence_certainty_mismatch", "statistical_cherry_picking"]`

### Requirement: LlmTechniqueFinding object
An LlmTechniqueFinding SHALL have at least `label` (an LLM technique label), `source` (`"llm"`), `name`, `definition`, `explanation` (non-empty strings), `confidence` (number 0 to 1) and `span` (an LlmTechniqueSpan).

#### Scenario: Finding members
- **WHEN** an English job has a cherry-picked statistic in its content
- **THEN** its finding has `label: "statistical_cherry_picking"`, `source: "llm"`, non-empty `name`, `definition` and `explanation`, a `confidence` between 0 and 1 and a `span` with `field: "content"`

### Requirement: LlmTechniqueFinding texts
`name` and `definition` SHALL come from the same fixed, versioned glossary as technique-classifier-result, in `explanation_language`, and SHALL NOT be generated per request. `explanation` SHALL be one plain-language sentence written by the LLM in `explanation_language` saying why the span is an instance of the label. `confidence` is the LLM's own uncalibrated rating.

#### Scenario: Same definition across jobs
- **WHEN** two English jobs both have a `misleading_headline` finding with the same `glossary_version`
- **THEN** both findings have identical `name` and `definition`

### Requirement: LlmTechniqueSpan object
An LlmTechniqueSpan SHALL have at least `field` (values include `content` and `title`), `text` (non-empty string), `start` and `end` (integers). `misleading_headline` findings SHALL have `field: "title"`; the other labels SHALL have `field: "content"`.

#### Scenario: Content span
- **WHEN** an `evidence_certainty_mismatch` finding is kept
- **THEN** its span has `field: "content"`

### Requirement: LLM span offsets
With `field: "content"` the offsets SHALL follow technique-classifier-result Span offsets on `Job.input.content`. With `field: "title"` they SHALL be half-open UTF-16 code-unit offsets such that `Job.input.source.title.slice(start, end)` equals `text`. Offsets SHALL never refer to the translation.

#### Scenario: Title span
- **WHEN** a job has `source.title` `"Vaccine KILLS thousands"` and the LLM flags `"KILLS thousands"` as a misleading headline
- **THEN** the finding has `span` `{field: "title", text: "KILLS thousands", start: 8, end: 23}`

### Requirement: LLM span acceptance
A finding SHALL be kept only if its candidate span text is non-empty and occurs in the field's string as an exact, case-sensitive substring; its span SHALL be the leftmost occurrence with `text` the candidate unchanged. Candidates SHALL NOT be repaired by fuzzy matching, trimming, normalization or translation. A finding without an accepted span SHALL be dropped. Findings with equal `label`, `field`, `start` and `end` SHALL be collapsed into one.

#### Scenario: Paraphrased span dropped
- **WHEN** the content is `"Crime rose 300% in May."` and the LLM quotes `"crime rose 300 percent"`
- **THEN** that finding is dropped

### Requirement: Headline input
`title_checked` SHALL be true only when the job was created with `input` rather than `scrape`, `Job.input.source.title` is non-empty after trimming, and it differs from `Job.input.content` after trimming both. A scraped job's `source.title` is an account display name (analysis-jobs-api Scraped input source), not a headline.

#### Scenario: Scraped job
- **WHEN** a scraped Mastodon job has `source.title` set to the account's display name
- **THEN** `title_checked` is false and the display name is not sent to the LLM

#### Scenario: Title equal to body
- **WHEN** `source.title` equals `content` after trimming
- **THEN** `title_checked` is false

### Requirement: No guessed headline
When `title_checked` is false, the title SHALL NOT be sent to the LLM, `misleading_headline` SHALL NOT be asked for, and no `misleading_headline` finding SHALL exist; none SHALL be derived from the first sentence or any other part of the content.

#### Scenario: No title
- **WHEN** a job has no `source.title` and its first sentence reads like a headline
- **THEN** `findings` has no `misleading_headline` entry

### Requirement: Original text only
The analyzer SHALL send the LLM `Job.input.content` (up to the deployment's input limit) and, when `title_checked`, `Job.input.source.title`, and SHALL NOT send the translation.

#### Scenario: German job
- **WHEN** a German job is analyzed
- **THEN** the LLM request carries the German content and no text of `translated_text`

### Requirement: LLM finding filtering
Findings whose `confidence` is below the deployment's minimum confidence (default 0.5) or outside 0 to 1 SHALL be dropped. At most the deployment's per-label limit (default 5) findings per label SHALL be kept, highest `confidence` first; dropping beyond it sets `truncated: true`.

#### Scenario: Low confidence dropped
- **WHEN** the LLM rates an `evidence_certainty_mismatch` finding with confidence 0.3 and the default minimum applies
- **THEN** that finding is not in `findings`

### Requirement: LLM finding order
`findings` SHALL be ordered by label in the order of the LLM technique labels requirement, then by `field` (`title` before `content`), then `start`, then `end`.

#### Scenario: Order by label
- **WHEN** a result has a `statistical_cherry_picking` and an `evidence_certainty_mismatch` finding
- **THEN** the `evidence_certainty_mismatch` finding comes first

### Requirement: LLM technique failures
`llm_techniques` SHALL be `failed` with `result: null` and an `error.code` that includes: `invalid_output` when the LLM answer is not readable as findings; `adapter_error` for a non-2xx answer or a connection error; `timeout` when its timeout elapses; `cancelled` on job cancellation. Findings dropped by acceptance or filtering SHALL NOT make the run fail.

#### Scenario: LLM unreachable
- **WHEN** the LLM endpoint answers HTTP 503
- **THEN** `llm_techniques` is `failed` with `error.code: adapter_error`, `techniques` is unaffected and the job ends `completed`

### Requirement: LLM technique isolation and credentials
The outcome of `llm_techniques` SHALL NOT change the status or result of `techniques` or any other analyzer. `error.message` and every result member MUST NOT contain credentials (configured header values, API keys, tokens), even when the LLM echoes them.

#### Scenario: LLM echoes the key
- **WHEN** the LLM answers HTTP 401 with a body repeating the API key
- **THEN** `error.message` does not contain the key

### Requirement: LLM technique presentation
Clients that show `llm_techniques` findings SHALL show them as a group separate from `techniques` detections, marked as assessed by an LLM and weaker than model-detected techniques. They SHALL NOT merge them into the `techniques` list, compare `confidence` with model `score` values or present `confidence` as a probability.

#### Scenario: Both groups present
- **WHEN** `techniques` detected `Loaded_Language` and `llm_techniques` found `statistical_cherry_picking`
- **THEN** a client shows `Loaded_Language` among model-detected techniques and `statistical_cherry_picking` in a separate group marked as LLM-assessed and weaker

### Requirement: LLM finding rendering
Clients SHALL render span `text`, `name`, `definition` and `explanation` as plain text without HTML or Markdown interpretation. They SHALL highlight a `field: "content"` span in `Job.input.content`, a `field: "title"` span in the shown `Job.input.source.title`, and SHALL show a finding without highlight when its offsets do not match the field's string.

#### Scenario: Offsets do not match
- **WHEN** a finding's span `text` differs from `Job.input.content.slice(start, end)`
- **THEN** the client lists the finding without a highlight
