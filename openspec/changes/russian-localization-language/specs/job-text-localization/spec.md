## MODIFIED Requirements

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
