## Context

- Canonical `analyzer-service-protocol/spec.md:22-34` defines binding sources: `$input`, `$input.source`, `$job.id`, `$analyzers.<id>` (dependency results only) and the job-wide `$job.analyzers`, `$job.coverage` (only on `after_all_analyzers_settled` analyzers).
- The finalizer runs with trigger `after_all_analyzers_settled` (backend `docs/examples/final_synthesis.yaml`) and has no `depends_on`, so it cannot bind `$analyzers.translation`. An HTTP finalizer can today only dig `source_language` out of `$job.analyzers` itself.
- Backend already normalizes the language for other adapters: `readSourceLanguage` (`internal/adapter/news_search.go:196`) lower-cases, trims and accepts only `^[a-z]{2}$`.
- `job-text-localization/spec.md:71` already declares the finalizer's `user_text` source language to be the translation run's `source_language` when it succeeded. This change makes the finalizer actually write in that language, so the localization contract becomes accurate; that spec is not modified.

## Decisions

1. **New binding source `$job.source_language`, not a new default input.** Binding sources are opt-in per configuration, so existing HTTP finalizers receive exactly the inputs they receive today. Alternative (always add `inputs.source_language`) rejected: it would change the request of every configured service.
2. **Value semantics.** The `source_language` member of the job's `translation` AnalyzerRun result when that run is `succeeded` and the value is a string that, trimmed and lower-cased, matches `^[a-z]{2}$`; that normalized string. Otherwise (no `translation` analyzer, run failed/skipped/not selected, value null, empty, not a string or not two letters) JSON `null`. The member is always present in `inputs` when bound (null, never omitted), so a service can rely on it.
3. **Restricted to `after_all_analyzers_settled`.** The translation run is only guaranteed settled then; a registry with the source on another trigger fails startup like `$job.analyzers` does. Analyzers that need the language earlier keep binding `$analyzers.translation` via `depends_on`.
4. **Fallback is the service's job.** `null` means "unknown"; a finalizer SHALL NOT fail because of it. The orchestrator does not fail or skip finalization on a null language.

## Compatibility classification

Grep of canonical specs for binding sources and finalizer inputs: `analyzer-service-protocol/spec.md:22` (Input binding sources), `:29-34` (Job-wide binding sources, scenario "Finalizer inputs"), `:8-12` (Analyzer request, default inputs). No other canonical spec names binding sources (`analysis-jobs-api`, `analysis-job-events`, `job-text-localization` only reference finalizer outputs).

| Change | Where | Class |
|---|---|---|
| New binding source `$job.source_language` | `analyzer-service-protocol/spec.md:29` | shared-additive (new opt-in input; unchanged when not bound) |
| Request body, default inputs, finalizer response, validation, normalization | `analyzer-service-protocol/spec.md:8,71,78,97` | unchanged |
| FinalAssessment / Job API | `analysis-jobs-api` | unchanged |

No breaking change; no client migration. Frontend is not affected.

## Risks

- A deployment's custom `prompt_file` does not mention `<source_language>`: the model may ignore it. Backend's default prompt is updated; custom prompts keep the previous behaviour (documented in backend README/example).
