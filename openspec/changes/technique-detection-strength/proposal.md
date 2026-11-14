# Proposal: technique-detection-strength

Parent: junction-2026/project#31. Based on backend @ 10ac227cb99faad73a75dbcbcd12c20425f7d7ef,
frontend @ d590b927aa520e3533978fd67d85fb6cdf691aaf, project @ 441ecbf96961128099af004da50a063f18b3345c,
shared-specs @ 18def034782c3f2db61a163a886af7863c9c34c4.

## Why

The `techniques` analyzer lists every known technique above cutoff in `detected[]`. A borderline score just
above a cutoff, with no phrase located in the text, looks the same to readers (and to the LLM finalizer) as a
high-scoring, located detection. On 2026-11-14 a harmless 51-word announcement got six span-less, borderline
detections and the verdict `uncertain`, although the finalizer's own text said it looked normal. Clients and the
finalizer need to tell strong detections from weak hints, and the verdict meanings need to say that weak hints
alone do not make a result `uncertain`.

## What changes

- Each Detection in `detected` gains `margin` (highest `score - cutoff` across the models that detected it,
  rounded to 2 decimals), `located` (`true` when it has at least one span) and `strength` (`strong` when
  `located` or `margin >= strong_margin`, otherwise `weak`; `strong_margin` is a deployment setting, default
  0.15).
- TechniqueClassification gains `summary: {strong, weak}`, the counts of strong and weak Detections.
- Additive only: results stored before this change have none of these members and clients keep rendering them.
- Verdict values (analysis-jobs-api): the meaning of `detected`, `not_detected` and `uncertain` is restated in
  terms of strong signals: `not_detected` when no strong signal was found (weak hints only lower confidence),
  `uncertain` when strong signals disagree, a decisive applicable analyzer is unavailable, or there is no
  evidence. The value set and client fallback are unchanged.

Backend-internal parts (registry key `execution.strong_margin`, the `llm.description` of the technique
classifier, the rewritten finalizer prompt and their tests) are written in the backend's local OpenSpec change,
not here (shared specs hold interfaces only).

## Capabilities

### Modified Capabilities
- `technique-classifier-result`: Detection strength members, `summary`, strength rule, compatibility.
- `analysis-jobs-api`: Verdict values requirement restated (meanings only).

## Impact

- backend: `internal/adapter/technique.go` computes the new members; finalizer prompt and registry are local.
- frontend: none required. `src/job/api.ts` types Detection with optional members and `JobView.tsx` keeps only
  entries with a string `name`; unknown members are ignored and the verdict is not rendered today.
- project: no new integration suite.
