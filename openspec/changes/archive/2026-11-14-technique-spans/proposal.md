# Proposal: technique-spans

Parent: junction-2026/project#17. Based on backend @ 4b3d394c7dd9a1ddea1f0c4cc96a37afd817ec23,
frontend @ 3e51ec4cc5fb43c4642a142f927e9a0d99c70231, project @ 441ecbf96961128099af004da50a063f18b3345c,
shared-specs @ 518903a3323a930a2dc357890e4f21df0a4641cb.

## Why

The `techniques` analyzer scores the English translation of a job's text. Its `sentences[]`
point into the user's original text only for English input whose sentences are found
verbatim (`offsets_in: original`); for every other language the highlights live in the
machine translation. Users need to see which phrases of the text they actually submitted
carry each detected technique.

## What changes

- Each Detection in `detected` gains `spans`: a list of TechniqueSpan
  (`technique`, `text`, `start`, `end`), half-open UTF-16 offsets into `Job.input.content`
  with `content.slice(start, end) === text` on the submitted characters.
- English input (`source_language: "en"`): spans are whole sentences of the original text
  scored by a sentence-level classifier (`nci-social`), kept for each detected technique
  at or above the sentence model's threshold.
- Any other language: an LLM proposes candidate phrases per detected technique; only
  candidates that occur verbatim in `Job.input.content` become spans. No fuzzy matching.
- A detected technique with no accepted span stays in `detected` with `spans: []`.
- New result members `span_method`, `span_status`, `spans_truncated` tell clients how
  spans were produced and whether the span step failed. A failed or timed-out span step
  leaves `techniques` `succeeded` with all span lists empty.
- Presentation: clients highlight spans in the original text rendered as plain text and
  never present the translation as the user's words.

All changes are additive to `technique-classifier-result` (new optional members; see
design.md). No change to technique names, document scoring or thresholds.

## Impact

- Shared capability: `technique-classifier-result` (modified).
- backend: span step inside the `technique_classifier` adapter (sentence model client,
  LLM phrase task, substring validation, offsets, failure isolation).
- frontend: job result view highlighting spans in the original text.
- project: no change (the `full-e2e` suite is still a placeholder).
