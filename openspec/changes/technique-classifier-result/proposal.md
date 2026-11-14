# Proposal: Propaganda technique classifier result (`techniques`)

## Why

Parent feature junction-2026/project#15 planned a `techniques` analyzer (short/long
model by word count, `thresholds` map, `detected` list, per-sentence detections with
offsets). Parent feature junction-2026/project#16 amends that plan before any backend
code exists: the analyzer scores the English translation with the two NCI models
(`nci-technique` for documents, `nci-social` for short posts up to 128 model tokens),
returns **every** technique label with its score, the model, that model's cutoff and
an `above_cutoff` flag, keeps both result sets when both models run (no averaging),
and passes unfamiliar labels through. Where #16 conflicts with #15's draft, #16 wins.
The result reaches clients verbatim through `Job.analyzers[].result` and
`analyzer.succeeded` (`analysis-jobs-api/spec.md:74`), so its shape is an interface
between repositories. This change (still active, never archived) is rewritten in place.

Based on: backend @ 69f5c6d4f6b13bbb0e6027f0d2dfae5c02aff28e (`propaganda_detection`
adapter `internal/adapter/propaganda.go` incl. the `$analyzers.<id>` → `translated_text`
binding, `mistral_translation` result `translated_text`/`source_language`
`internal/adapter/translation.go:122-142`; no `techniques` code yet),
frontend @ 3e51ec4cc5fb43c4642a142f927e9a0d99c70231 (no job/analyzer client),
project @ 441ecbf96961128099af004da50a063f18b3345c (`full-e2e` only),
shared-specs @ 2dd0006dab4aa4c6cbfff866d86031b0376e9603 (active change
`technique-classifier-result` from #15).

## What Changes

- **technique-classifier-result** (new capability, amended before archive):
  - Analyzer id `techniques` (unchanged), category `propaganda`, `depends_on` `translation`;
    only the translation's `translated_text` is classified.
  - Result object TechniqueAnalysis: `words`, `results` (one ModelResult per model
    run: `model`, `cutoff`, `scores`), `latency_ms`.
  - TechniqueScore: `label`, `score`, `model`, `cutoff`, `above_cutoff`, `known`.
  - All 18 known labels present per ModelResult; unfamiliar labels kept (`known: false`).
  - Model values `nci-technique` / `nci-social`; which runs is decided by the text's
    length (rule below); both kept separately when both run.
  - Failure codes (existing canonical codes), credential-free errors, presentation rules.
- **Removed from #15's draft**: `model: short|long`, `threshold`, `thresholds`,
  `techniques` (TechniqueScore with `name`/`display`), `detected`, `max_score`,
  `sentences`, `offsets_in`, `sentences_truncated`, Detection/SentenceDetection objects,
  "unknown label is invalid_output".

Not changed: `analysis-jobs-api`, `analysis-job-events`, `analyzer-service-protocol`,
`api-conventions`. `propaganda_detection` is untouched.

## Decisions for approval

- **Routing rule (issue asks the planner to fix it).** The backend has no BERTweet
  tokenizer, so the 128-token limit is checked with a conservative word bound:
  `nci-social` runs when `words <= social_max_words` (default **80**: 80 words × ~1.5
  tokens/word + 2 special tokens ≤ 128); `nci-technique` runs when
  `words > social_max_words` **or** `words >= technique_min_words` (default **40**,
  "long enough to be a document"). So: < 40 words → social only; 40–80 → both;
  > 80 → technique only. Both bounds are backend registry config; the result echoes
  `words` and each model's `cutoff` so clients can see what happened.
- **Grouped result**: `results[]` holds one ModelResult per model run, in the order
  `nci-technique`, `nci-social`; every TechniqueScore also carries `model` and `cutoff`
  (as the issue requires) so a flattened list stays self-describing.
- **Score order**: the 18 known labels in the canonical order of the spec, then unknown
  labels in the order the model returned them. Clients sort for display.
- **Unfamiliar labels**: kept with `known: false` and `above_cutoff` computed the same way.
  A missing known label, a duplicate label or a score outside 0–1 is still `invalid_output`.
- **All-or-nothing run**: when both models are needed and either fails, `techniques`
  fails (no partial result), so a client never mistakes a single result for the full one.
- **Per-sentence detections and offsets dropped** (the issue leaves this to the planner):
  the NCI models score a whole text; sentence highlighting can return as a later additive
  member if a client needs it.
- **Cutoffs**: `nci-technique` 0.5, `nci-social` 0.3 by default, configurable per model in
  the registry and echoed as `cutoff`; `above_cutoff` is `score >= cutoff`.
- **No frontend or project task** (issue non-goals; no integration suite runs ML models).
  **One backend task** (adapter, registry validation, example, README, tests).

## Overlapping feature (junction-2026/project#15)

This rewrites #15's active, unarchived change. #15 has no backend code on main
(backend @ 69f5c6d has no `techniques`/`technique_classifier` code). If #15's backend
child `backend-technique-classifier` is still open, the orchestrator must supersede or
re-pin it to this revision: it would otherwise implement the removed shape. This plan's
backend child replaces it (same adapter name `technique_classifier`, new local change id).

## Impact

- backend: new `technique_classifier` adapter and registry keys,
  `docs/examples/technique_classifier.yaml`, README section, stub-service tests.
- frontend, project: no change. No existing client reads `techniques`.
