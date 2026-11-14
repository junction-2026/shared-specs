# job-text-localization Specification

## Purpose
Lets a client read the model-written presentation texts of a finished analysis job (final assessment explanation and LLM technique explanations) in the user's interface language, without re-running any analysis and without translating original source material.

## Requirements

### Requirement: Get job localization
`GET /api/v1/jobs/{id}/localization?language=<code>` SHALL respond 200 with a JobLocalization object for the job's model-written presentation texts in `language`. An unknown id SHALL yield 404 `not_found`. A job whose `done` is false SHALL yield 409 `job_not_finished`. A missing or empty `language` SHALL yield 400 `invalid_request`; a `language` that is not a supported localization language SHALL yield 400 `unsupported_language` with `error.details.supported` listing the supported codes.

#### Scenario: Completed job in Arabic
- **WHEN** a client calls `GET /api/v1/jobs/j1/localization?language=ar` for a completed job
- **THEN** the status is 200 and the body is a JobLocalization with `job_id: "j1"` and `language: "ar"`

#### Scenario: Completed job in Russian
- **WHEN** a client calls `GET /api/v1/jobs/j1/localization?language=ru` for a completed job
- **THEN** the status is 200 and the body is a JobLocalization with `job_id: "j1"` and `language: "ru"`

#### Scenario: Running job
- **WHEN** a client requests the localization of a job with `done: false`
- **THEN** the status is 409 with `error.code` `job_not_finished`

#### Scenario: Unsupported language
- **WHEN** a client calls it with `language=xx`
- **THEN** the status is 400 with `error.code` `unsupported_language` and `error.details.supported` includes `en`, `fr`, `ar`, `de`, `fi` and `ru`

### Requirement: Localization languages
The supported localization languages SHALL include `en`, `fr`, `ar`, `de`, `fi` and `ru`. The server SHALL compare `language` case-insensitively by its primary subtag (`fr-CA` means `fr`, `ru-RU` means `ru`) and SHALL report the lower-case primary subtag in `JobLocalization.language`. Clients SHALL treat the list as open: a deployment MAY support further languages and `error.details.supported` lists at least the languages named here.

#### Scenario: Region subtag
- **WHEN** a client calls it with `language=DE-at`
- **THEN** the response has `language: "de"`

#### Scenario: Russian with region subtag
- **WHEN** a client calls it with `language=RU-ru` for a completed job
- **THEN** the status is 200 and the response has `language: "ru"`

#### Scenario: Orchestrator fixed text in Russian
- **WHEN** a job finalized by the orchestrator with `verdict: uncertain` is localized with `language=ru`
- **THEN** `final_assessment.user_text` has `status: translated`, `source_language: "en"` and a Russian `text`, and no LLM request is sent

### Requirement: JobLocalization object
A JobLocalization SHALL have at least `job_id`, `language`, `final_assessment` and `llm_findings`. `final_assessment` SHALL be `{"user_text": LocalizedText}` when the job's `finalization.result` is set, otherwise null. `llm_findings` SHALL hold one LlmFindingLocalization per finding of the job's `llm_techniques` result, in result order, and SHALL be `[]` when the job has no succeeded `llm_techniques` run or it has no findings. Clients SHALL ignore unknown members.

#### Scenario: Job without finalization and LLM findings
- **WHEN** the job's `finalization.result` is null and it has no `llm_techniques` run
- **THEN** the body is at least `{"job_id": "<id>", "language": "<code>", "final_assessment": null, "llm_findings": []}`

### Requirement: LlmFindingLocalization object
An LlmFindingLocalization SHALL have at least `index` (integer, position of the finding in the `llm_techniques` result `findings`), `label` (that finding's `label`) and `explanation` (a LocalizedText of its `explanation`). It SHALL NOT carry a translation of the finding's span `text`.

#### Scenario: Two findings
- **WHEN** `llm_techniques` has findings `[misleading_headline, statistical_cherry_picking]`
- **THEN** `llm_findings` is `[{"index": 0, "label": "misleading_headline", "explanation": {...}}, {"index": 1, "label": "statistical_cherry_picking", "explanation": {...}}]` at least

### Requirement: LocalizedText object
A LocalizedText SHALL have at least `status`, `text` and `source_language` (ISO 639-1 code of the source text's language, or null when not known). Clients SHALL ignore unknown members.

#### Scenario: Translated explanation
- **WHEN** a French job's `user_text` is translated to Arabic
- **THEN** `final_assessment.user_text` is at least `{"status": "translated", "text": "<Arabic text>", "source_language": "fr"}`

### Requirement: LocalizedText status
`status` values include `original` (`text` is the source text verbatim, already in `language`), `translated` (`text` is a non-empty machine translation of the source text into `language`) and `unavailable` (no text in `language` could be produced; `text` is null). Clients SHALL treat an unknown `status` like `unavailable`.

#### Scenario: Unknown status
- **WHEN** a client receives a LocalizedText with `status: "pending"`
- **THEN** it presents it like `unavailable`

### Requirement: Source language of localized texts
For `user_text` written by the finalizer, `source_language` SHALL be the job's `translation` result `source_language` when that run succeeded, otherwise null. For an LLM finding `explanation`, `source_language` SHALL be the `llm_techniques` result's `explanation_language`. When `source_language` equals `language`, the server SHALL return `status: original` with the source text and SHALL NOT call a translation provider for it.

#### Scenario: Same language
- **WHEN** a German job with `translation.source_language: "de"` is localized with `language=de`
- **THEN** `final_assessment.user_text` has `status: original` and `text` equal to `finalization.result.user_text`

### Requirement: Orchestrator fixed text
When `finalization.result.produced_by` is `orchestrator`, `final_assessment.user_text` SHALL be the deployment's fixed translation of that fixed text into `language` with `status: translated` and `source_language: "en"` (or `status: original` when `language` is `en`), and SHALL NOT be produced by a model call.

#### Scenario: Insufficient evidence in Finnish
- **WHEN** a job finalized by the orchestrator with `verdict: uncertain` is localized with `language=fi`
- **THEN** `final_assessment.user_text` has `status: translated`, `source_language: "en"` and a Finnish `text`, and no LLM request is sent

### Requirement: Localization does not re-run analysis
Serving a localization SHALL NOT start, re-run or change any analyzer, scrape or finalization, SHALL NOT change the Job returned by `GET /api/v1/jobs/{id}` or `GET /api/v1/jobs`, and SHALL NOT emit job events. It SHALL translate only the texts named in JobLocalization; it SHALL NOT translate `Job.input`, span `text`, claims, topics, news articles, fact-check reviews, Wikipedia passages or any other original source material.

#### Scenario: Job unchanged
- **WHEN** a client requests the localization of a completed job in three languages
- **THEN** `GET /api/v1/jobs/{id}` returns the same verdict, confidence, `user_text`, analyzer results and `finished_at` as before, and the event stream emits no new event

### Requirement: Localization failures
When a text cannot be translated (no translation provider configured, provider error, invalid reply or the deployment's localization timeout), its LocalizedText SHALL have `status: unavailable` and `text: null`, and the response SHALL still be 200 with every other text. Error responses and `unavailable` texts SHALL NOT expose credentials, endpoint URLs or provider messages.

#### Scenario: Provider down
- **WHEN** the translation provider answers 503 for an Arabic localization of a French job
- **THEN** the status is 200, `final_assessment.user_text` is `{"status": "unavailable", "text": null, "source_language": "fr"}` and the job is unchanged

### Requirement: Localization stability
While the deployment runs, repeated requests for the same job and `language` SHALL return the same `text` for every LocalizedText with `status` `original` or `translated`, without a new provider call. An `unavailable` text SHALL NOT be remembered: a later request SHALL try again. After a restart a `translated` text MAY be produced again and MAY differ in wording.

#### Scenario: Second request is served from the cache
- **WHEN** a client requests `language=ar` for a job twice and the first answer had `status: translated`
- **THEN** the second answer has the same `text` and the translation provider received one request in total

### Requirement: Localized text rendering
Localized texts are model output influenced by untrusted content. Clients SHALL render `text` as plain text, without HTML or Markdown interpretation and without turning its contents into links. A client SHALL mark a `translated` text as machine-translated (naming its `source_language` when not null) and SHALL keep the original reachable; for an `unavailable` text it SHALL show the original text marked as not available in the UI language, never presented as localized.

#### Scenario: Translation unavailable
- **WHEN** `final_assessment.user_text.status` is `unavailable` and the UI language is Arabic
- **THEN** the client shows `finalization.result.user_text` as plain text with an Arabic note that it is shown in the original language

### Requirement: Original evidence stays verbatim
Clients SHALL show span `text`, quotations, claims, article headlines, Wikipedia passages and fact-check `claim` and `rating` in their original wording in every UI language, never replaced by a translation. In a right-to-left UI they SHALL isolate such text so that its own direction is kept.

#### Scenario: French quote on an Arabic page
- **WHEN** the UI language is `ar` and a span `text` is French
- **THEN** the span `text` is shown verbatim and laid out left-to-right inside the Arabic text
