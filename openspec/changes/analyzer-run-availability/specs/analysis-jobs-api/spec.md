## ADDED Requirements

### Requirement: AnalyzerRun availability
The AnalyzerRun object SHALL additionally have `availability` (string or null) and `note` (string or null). `availability` values include `ran` (produced a result), `not_applicable` (nothing to check in this input, or not requested) and `unavailable` (failed, cancelled or not set up). Both SHALL be null while the run is `pending` or `running`; a `succeeded` run SHALL have `ran` and `note: null`. Existing AnalyzerRun members keep their meaning.

#### Scenario: Unsettled run
- **WHEN** an analyzer is `running`
- **THEN** its AnalyzerRun has `availability: null` and `note: null`

#### Scenario: Succeeded run availability
- **WHEN** an analyzer has `succeeded`
- **THEN** its AnalyzerRun has `availability: ran` and `note: null`

### Requirement: Availability note text
`note` SHALL be a short fixed English sentence intended for display. Clients SHALL NOT parse it, and its wording may change without a contract change. Clients SHALL treat an unknown `availability` value like `unavailable`.

#### Scenario: Unknown availability value
- **WHEN** a client receives an AnalyzerRun with an `availability` value it does not know
- **THEN** it presents the run as unavailable

### Requirement: Nothing-to-check skips
A `skipped` run SHALL have `availability: not_applicable` and this `note`, by `reason`:
- `no_checkable_claims`: "Not run: the text contains no specific factual claims to check."
- `no_searchable_topics`: "Not run: the text names no concrete topics or events to search news coverage for."
- `no_sources`: "Not run: there were no news articles or page URL to look up."

#### Scenario: No checkable claims
- **WHEN** `fact_check` is `skipped` with `no_checkable_claims`
- **THEN** it has `availability: not_applicable`, `note` "Not run: the text contains no specific factual claims to check." and still `reason: no_checkable_claims`

### Requirement: Input and selection skips
A `skipped` run SHALL have `availability: not_applicable` and this `note`, by `reason`:
- `not_applicable`: "Not run: this analyzer does not apply to this kind of input."
- `not_selected` or `disabled`: "Not run: this analyzer was not requested for this job."

#### Scenario: Not selected
- **WHEN** a job was created with `"analyzers": ["claims"]` and `legacy` is `skipped` with `not_selected`
- **THEN** `legacy` has `availability: not_applicable` and `note` "Not run: this analyzer was not requested for this job."

### Requirement: Unavailable runs
A `failed` run with any `error.code`, and a `skipped` run whose reason is `dependency_failed`, `cancelled`, `input_unavailable` or any reason not listed in "Nothing-to-check skips", "Input and selection skips" or "Dependency-skipped availability", SHALL have `availability: unavailable` and `note` "Unavailable: the analyzer failed or is not set up, so its result is missing."

#### Scenario: Failed dependency
- **WHEN** `news_search` is `failed` with `error.code: adapter_error` and `source_info` is `skipped` with `dependency_failed`
- **THEN** both have `availability: unavailable` and the unavailable note

#### Scenario: Unknown reason
- **WHEN** an analyzer is `skipped` with a reason not listed in this spec
- **THEN** it has `availability: unavailable`

### Requirement: Dependency-skipped availability
A run `skipped` with `dependency_skipped` SHALL take the `availability` and `note` of its root skip: the first id in its `depends_on` whose run is `skipped`, followed again while that run's reason is `dependency_skipped`. After 8 steps, or when no skipped dependency exists, it SHALL be `unavailable` with the unavailable note.

#### Scenario: No checkable content
- **WHEN** `topic_extraction` succeeded with no topics and no claims, `fact_check` is `skipped` with `no_checkable_claims`, `news_search` is `skipped` with `no_searchable_topics` and `source_info` (depending on `news_search`) is `skipped` with `dependency_skipped`
- **THEN** `GET /api/v1/jobs/{id}` shows `availability: not_applicable` for all three, `source_info.note` equals `news_search.note`, and every run keeps its `status` and `reason`

### Requirement: Availability stability
`availability` and `note` SHALL be set when the run settles and SHALL then never change. They SHALL be identical wherever the AnalyzerRun appears: `Job.analyzers` of every endpoint returning a Job, `data.analyzer` of `analyzer.*` events and the `$job.analyzers` binding.

#### Scenario: Same values in the event
- **WHEN** `fact_check` settles as `skipped` with `no_checkable_claims`
- **THEN** the `analyzer.skipped` event's `data.analyzer` has the same `availability` and `note` as the run in `GET /api/v1/jobs/{id}`
