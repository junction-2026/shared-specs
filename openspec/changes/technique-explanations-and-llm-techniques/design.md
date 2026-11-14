## Context

`techniques` (technique-classifier-result) returns `detected[]` Detections with `name`, `display`, English `explanation`, `models` and `spans` (TechniqueSpans in `Job.input.content`). The backend's built-in English names and explanations live in `backend/internal/adapter/technique_names.go`. Analyzers are configured per deployment in a YAML registry (`backend/docs/examples/technique_classifier.yaml`); the finalizer receives each opted-in analyzer's configured `llm.description` and result (`backend/internal/finalizer/finalizer.go` `llmEntries`). The frontend reads `detected[].display`, `explanation` and `spans` in `frontend/src/job/JobView.tsx`.

## Goals / Non-Goals

Goals: localized, deterministic definition and justification for each detected technique; a separate, clearly weaker LLM detector for three non-SemEval weaknesses; concurrent backend and frontend implementation from this contract.

Non-goals: changing NCI models, cutoffs, routing or span rules; LLM definitions per request; mapping LLM labels onto SemEval labels; fact-checking.

## Decisions

1. **Localized members go under `plain_language`, not `name`.** `Detection.name` is the stable English key (spec "Technique names" scenario "Names are stable identifiers"; `TechniqueSpan.technique` refers to it). Reusing it for a translated name would be breaking. `plain_language: {name, definition, why}` mirrors the issue's member names inside a new object.
2. **Glossary is a backend artifact with a version.** The result carries `glossary_version` so a stored result can be traced to the exact wording. Supported languages are a backend-local list; the contract only says `explanation_language` is the translation's `source_language` when the glossary supports it, else `en`.
3. **`why` is a template.** It quotes the span text verbatim and adds only the localized technique name, so it cannot carry a claim about the world. Per-span `why` lets clients show the sentence next to each highlight; `plain_language.why` is the first span's sentence or the document-score sentence.
4. **T4 is a separate analyzer (`llm_techniques`), not members of `techniques`.** `techniques` is all-or-nothing on NCI model failures (requirement "No partial technique result") and depends on the translation for classification; a separate analyzer keeps LLM findings apart from model labels (as the issue demands), fails independently, is separately selectable and gets its own finalizer description saying it is weaker. It depends on `translation` only for `source_language` (glossary language); it analyzes the original text.
5. **Headline only for direct input.** See proposal: scraped `source.title` is a display name (`analysis-jobs-api/spec.md:288`).
6. **Findings without an accepted span are dropped.** Unlike model labels there is no document score backing an LLM label, so a finding is evidence only through its quoted span.
7. **Closed label set.** The analyzer emits only the three labels. Clients still ignore findings whose `label` they do not know (tolerant reader), so a later fourth label is additive.

## Classification of affected uses (shared-specs @ 6d1e0c05)

| Object / endpoint | Uses (file:line) | Change | Class |
|---|---|---|---|
| TechniqueClassification | `technique-classifier-result/spec.md:26` (defined, "at least", clients ignore unknown members); delivered in `analysis-jobs-api` AnalyzerRun `result` and `analysis-job-events` `analyzer.succeeded` | new members `explanation_language`, `glossary_version` | shared-additive |
| Detection | `technique-classifier-result/spec.md:256` (only use; "at least") | new member `plain_language` | shared-additive |
| TechniqueSpan | `technique-classifier-result/spec.md:106` (only use; "at least") | new member `why` | shared-additive |
| Technique score presentation | `technique-classifier-result/spec.md:263` | plain-text rule extended to new strings | shared-additive (client rule) |
| `GET /api/v1/analyzers`, `Job.analyzers` | `analysis-jobs-api/spec.md:180`, `:66`, `:29` (selection) | a deployment may list a new analyzer id `llm_techniques`; clients already handle arbitrary ids | shared-additive (new analyzer) |
| `input.source.title` | `analysis-jobs-api/spec.md:9`, `:288` | read only; meaning unchanged | none |
| Finalizer input | backend-internal (`analysis-finalizer` local spec) | description of the new analyzer | not shared |

No existing "exactly" clause is touched. The "Score list order" clause ("exactly one TechniqueScore per known label") is unchanged and remains required for indexing.

No shared-breaking change; no client migration needed. Frontend at 1abe19a ignores unknown members and finds runs by id; it keeps working unchanged until its child adds rendering.

## Risks / Trade-offs

- Glossary translation quality: fixed artifact reviewed in the backend PR; unsupported languages fall back to English (`explanation_language: "en"`), so clients can label it.
- LLM span hallucination: exact-substring acceptance, no repair; unmatched findings dropped.
- Long sentence spans make `why` long: accepted, since the issue requires a verbatim quote.
- UI overlap of model and LLM highlights: clients show the two groups separately.
