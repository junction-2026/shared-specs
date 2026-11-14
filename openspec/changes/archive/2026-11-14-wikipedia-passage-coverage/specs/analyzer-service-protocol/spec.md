## ADDED Requirements

### Requirement: Proposed Wikipedia quotes
A finalizer MAY return `wikipedia_quotes`, an array of objects with at least `claim`, `language` and `quote` (strings), as proposals that the orchestrator verifies (analysis-jobs-api "Wikipedia quote verification"). The orchestrator SHALL store `[]` when the member is absent or not an array, SHALL drop entries that are not objects with string `claim`, `language` and `quote`, and SHALL NOT fail finalization because of `wikipedia_quotes`.

#### Scenario: Malformed quotes ignored
- **WHEN** the finalizer returns `{"verdict": "not_detected", "user_text": "...", "wikipedia_quotes": "see Wikipedia"}`
- **THEN** finalization is `completed` with `wikipedia_quotes: []`

### Requirement: Wikipedia labels in finalizer input
The finalizer's input SHALL carry the job's `wikipedia` AnalyzerRun result unchanged when the finalizer receives that run (for the `llm` adapter, when `wikipedia` is opted in to LLM input), including each WikiLookup's `coverage`, `evidence_sentence` and `passage`.

#### Scenario: Labels reach the LLM finalizer
- **WHEN** `wikipedia` succeeded, is opted in to LLM input and a WikiLookup has `coverage: "conflicts"`
- **THEN** the finalizer's input contains that WikiLookup with its `coverage`, `evidence_sentence` and `passage`

## MODIFIED Requirements

### Requirement: Finalizer response
For every adapter the finalizer output SHALL be a JSON object with at least `verdict` and `user_text` and optionally `confidence` and `wikipedia_quotes`, as defined for FinalAssessment (analysis-jobs-api). For `http_sync` and `http_async` the output is the result object; for `llm` it is the JSON object decoded from the model's reply.

#### Scenario: Minimal valid response
- **WHEN** the finalizer returns `{"verdict": "not_detected", "user_text": "No signs of propaganda were found."}`
- **THEN** the stored result has `confidence: null`, `usage: null`, `produced_by: finalizer` and `wikipedia_quotes: []`

### Requirement: Finalizer output normalization
The orchestrator SHALL store `verdict`, `confidence` and `user_text` unchanged (an absent or null `confidence` as null), set `produced_by: finalizer`, set `usage` to the token usage reported by the adapter (null when none), set `wikipedia_quotes` to the verified quotes (see "Proposed Wikipedia quotes") and drop every other member of the output. It SHALL NOT compute or adjust the verdict or confidence.

#### Scenario: Extra members dropped
- **WHEN** the finalizer returns `{"verdict": "detected", "confidence": 0.9, "user_text": "...", "reasoning": "..."}`
- **THEN** the stored result has no `reasoning` member

#### Scenario: Output member named usage
- **WHEN** an `http_sync` finalizer returns `{"verdict": "detected", "user_text": "...", "usage": {"total_tokens": 1}}`
- **THEN** the stored result has `usage: null`, because `usage` is set only from the adapter's report
