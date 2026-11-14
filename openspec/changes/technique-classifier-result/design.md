# Design: technique-classifier-result

## Contract surface

| Element | Where clients see it | Classification | Evidence |
|---|---|---|---|
| AnalyzerRun `techniques` with TechniqueClassification `result` | `Job.analyzers[]`, `analyzer.succeeded` `data.analyzer.result` | shared-additive (new analyzer id, result is a service-defined object stored verbatim) | `analysis-jobs-api/spec.md:74` (result is the object verbatim), `analyzer-service-protocol/spec.md:65` (result conventions) |
| Failure codes `adapter_error`, `timeout`, `invalid_output`, `cancelled` | AnalyzerRun `error.code` | shared-additive (existing codes, existing meaning) | `analysis-jobs-api/spec.md:81` |
| Skip `dependency_failed` / `dependency_skipped` when `translation` did not succeed | AnalyzerRun `reason` | unchanged canonical behaviour | `analysis-jobs-api/spec.md:88` |
| LLM finalizer input (`llm.include`) | finalizer prompt | backend-local registry config | backend `analysis-finalizer` spec |

No existing object, member, status or error meaning changes; no client migration is
needed. No current client reads analyzer results (frontend @ 3e51ec4 has only the
health page). `grep -rn "techniques\|technique_classifier" openspec/specs` on
shared-specs @ 8324422 finds nothing, so the id and capability name are free.

## Offsets

Sentence `start`/`end` are half-open UTF-16 code-unit offsets (JavaScript string
indices). Resolution, in the backend:

1. Split `translated_text` into sentences keeping offsets; score them.
2. If `source_language` is `"en"`, search each reported sentence `text` in
   `Job.input.content`, left to right, each search starting at the previous match's
   `end`. If all are found, report those positions with `offsets_in: "original"`.
3. Otherwise report the positions in `translated_text` with
   `offsets_in: "translation"`.

Both cases guarantee `<string>.slice(start, end) === text`. The string is `Job.input.content`
for `"original"` and the `translated_text` member of the `translation` AnalyzerRun
result for `"translation"`.

## Backend-local (not in this change)

Model routing by `short_max_words`, the ML `/predict` batch protocol and response
validation, sentence splitting (`.`, `!`, `?`, newlines; fragments under 3 words
dropped), `max_sentences`, per-model settings, timeout, display-name texts, the LLM
description and the docs example are requirements of the backend task's local change.

## Risks

- Translator altering an English text makes offsets fall back to the translation;
  the client still has a correct slice. Acceptable.
- Short-model accuracy is moderate (macro F1 0.55): the spec requires clients to
  present detections as indicators.
