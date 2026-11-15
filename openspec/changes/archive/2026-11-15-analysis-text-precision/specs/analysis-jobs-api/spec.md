## ADDED Requirements

### Requirement: FinalAssessment user_text language
An `llm` finalizer SHALL be asked to write `user_text` in the job's source language: the `$job.source_language` value of analyzer-service-protocol, or `en` when that is null. When the model cannot write that language it writes English. Fixed texts with `produced_by: orchestrator` stay English. Clients SHALL NOT assume more about the language of `user_text`; job-text-localization governs its `source_language` member.

#### Scenario: German job
- **WHEN** the job's `translation` run succeeded with `source_language: "de"` and the finalizer's reply passes the output language check
- **THEN** `finalization.result.user_text` is the German text of that reply

#### Scenario: No translation run
- **WHEN** the job has no succeeded `translation` run
- **THEN** the finalizer is asked for English `user_text`

### Requirement: Finalizer output language check
After an `llm` finalizer's reply passes "Finalizer response validation", the orchestrator SHALL check the language of `user_text` with the deployment's deterministic word-list detector (knowing at least `en`, `de`, `fr`, `es`, `it`, `nl`, `pt`). The reply is in the wrong language only when the expected language is one the detector knows and the detector confidently identifies another language it knows; short, mixed or unrecognised text counts as matching.

#### Scenario: Short text
- **WHEN** the job's source language is `en` and `user_text` has too few words for a confident detection
- **THEN** no reply retry is sent for the language

### Requirement: Finalizer output language retry
A wrong-language first reply SHALL trigger the single reply retry of "LLM reply retry", under "LLM reply retry exclusions". A wrong language SHALL NOT make a reply invalid: finalization SHALL complete with the retry's reply when it is valid, in whichever language, otherwise with the first reply. Its `retry_reason` SHALL be `user_text must be written in <language>`, `<language>` being the expected language's English name.

#### Scenario: German answer for an English job, then English
- **WHEN** the job's source language is `en`, the first reply is a valid output with a German `user_text` and the retry's reply is a valid output with an English `user_text`
- **THEN** the provider receives two chat completion requests and `finalization.result` has the English `user_text`, `attempts: 2` and `retry_reason: "user_text must be written in English"`

#### Scenario: English on the first try
- **WHEN** the job's source language is `en` and the first reply is a valid output with an English `user_text`
- **THEN** the provider receives one chat completion request and `finalization.result` has `attempts: 1` and `retry_reason: null`

#### Scenario: Retry still in the wrong language
- **WHEN** the job's source language is `en` and both replies are valid outputs with a German `user_text`
- **THEN** finalization is `completed` with the retry's reply, `attempts: 2` and `retry_reason: "user_text must be written in English"`

#### Scenario: Retry reply invalid
- **WHEN** the first reply is a valid output with a German `user_text` for an `en` job and the retry's reply is not a JSON object
- **THEN** finalization is `completed` with the first reply, `attempts: 2` and `retry_reason: "user_text must be written in English"`

#### Scenario: Language the detector does not know
- **WHEN** the job's source language is `fi` and the reply's `user_text` is English
- **THEN** no reply retry is sent for the language

#### Scenario: Retried for another reason
- **WHEN** the first reply has no `user_text` and the retry's reply is a valid output with a German `user_text` for an `en` job
- **THEN** no third request is sent and finalization is `completed` with the retry's reply, `attempts: 2` and `retry_reason: "schema"`

#### Scenario: Retry disabled
- **WHEN** the deployment disabled reply retry and the first reply is a valid output with a German `user_text` for an `en` job
- **THEN** finalization is `completed` with that reply, `attempts: 1` and `retry_reason: null`

## MODIFIED Requirements

### Requirement: LLM reply retry members
For an `llm` finalizer, `attempts` SHALL be 2 when a reply retry was sent and 1 otherwise. `retry_reason` SHALL be null without a reply retry, otherwise a value including `length` (first reply cut off), `invalid_json` (empty content or not a JSON object), `schema` (a JSON object failing "Finalizer response validation") or `user_text must be written in <language>` ("Finalizer output language retry"). Clients SHALL treat an unknown `retry_reason` value as "retried for another reason".

#### Scenario: First reply valid
- **WHEN** the first reply is a valid FinalAssessment output in the expected language
- **THEN** `finalization.result` has `attempts: 1` and `retry_reason: null`

#### Scenario: Language retry reason
- **WHEN** a German job's first reply is a valid output with an English `user_text` that the detector confidently identifies as English
- **THEN** `finalization.result` has `attempts: 2` and `retry_reason: "user_text must be written in German"`
