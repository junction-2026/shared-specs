## MODIFIED Requirements

### Requirement: Job-wide binding sources
Binding sources SHALL include `$job.analyzers` (array of every AnalyzerRun of the job, with results, errors and skip reasons), `$job.coverage` (Coverage object) and `$job.source_language` (see "Source language binding source"). Only analyzers with trigger `after_all_analyzers_settled` may bind them, and they receive them only once every AnalyzerRun is settled.

#### Scenario: Finalizer inputs
- **WHEN** the finalizer binds `content: "$input"`, `results: "$job.analyzers"`, `coverage: "$job.coverage"`
- **THEN** its request `inputs` has members `content`, `results` (every AnalyzerRun, all settled) and `coverage`

#### Scenario: Source language binding outside the finalizer trigger
- **WHEN** an analyzer with a trigger other than `after_all_analyzers_settled` binds `$job.source_language`
- **THEN** the registry is rejected at startup, as for `$job.analyzers`

## ADDED Requirements

### Requirement: Source language binding source
`$job.source_language` SHALL resolve to the `source_language` member of the job's `succeeded` `translation` AnalyzerRun result, trimmed and lower-cased, when that value is a two-letter ISO 639-1 code (`^[a-z]{2}$`). Otherwise it SHALL resolve to JSON `null`, and the bound member SHALL be present with value `null`, not omitted. A null value SHALL NOT fail or skip the analyzer; services SHALL treat it as unknown.

#### Scenario: Source language of a translated job
- **WHEN** the finalizer binds `language: "$job.source_language"` and the job's `translation` run succeeded with `{"source_language": "RU", "translated_text": "..."}`
- **THEN** its request has `inputs.language` `"ru"`

#### Scenario: Unknown source language
- **WHEN** the finalizer binds `language: "$job.source_language"` and the job has no `translation` run, or it failed, was skipped, or returned `source_language` null, empty or `"russian"`
- **THEN** its request has `inputs.language` `null` and finalization proceeds normally

#### Scenario: Not bound
- **WHEN** a finalizer's bindings do not include `$job.source_language`
- **THEN** its request `inputs` are unchanged from before this source existed
