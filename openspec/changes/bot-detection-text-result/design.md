# Design: text-level `bot_detection` result

## Context
- backend `docs/examples/bot_detection.yaml` (@ fe6c2e6): analyzer `bot_detection`, category `bot_detection`,
  `enabled: false`, adapter `http_sync`, bindings `{content: $input, source: $input.source}`, result shape "not a
  shared contract".
- backend `config/risk_score/risk_score.yaml`: the `bot_detection` mapping (`author_score`, `author_posts`,
  `single_text_score`) is commented out by default.
- shared `manipulation-risk-score` reads `bot_detection` only through that deployment mapping.

## Decisions
1. **Reuse the id `bot_detection`.** The risk score (manipulation-risk-score/spec.md:9, :183) reads only the
   AnalyzerRun `bot_detection` through a deployment mapping. Keeping the id lets a deployment set
   `single_text_score: score` and get the `single_text` amplification basis with no formula or spec change. A new id
   would need a risk-score spec change (spec.md:9 names the analyzers it reads) and is out of the issue's scope.
   Because the result carries `scope`, a future account-level variant can use `scope: "account"` additively.
2. **Original text, no translation.** The model is multilingual; the analyzer has no `depends_on: [translation]`
   and sends `input.normalized_content`. A failed or skipped `translation` therefore does not skip it.
3. **`score` is always P(bot_or_generated).** The model's `LABEL_1` is bot / generated, `LABEL_0` human. With the
   model label `LABEL_1` and probability p: `label: bot_or_generated`, `score: p`; with `LABEL_0` and p:
   `label: human`, `score: 1 - p`. Clients never need to know model labels.
4. **Not a verdict, not propaganda.** The result is not read by the finalizer as propaganda evidence; the registry
   description (backend-local) states that one text is not an account verdict and the model sees the original text.
   The risk-score default configuration is not changed, so default risk scores stay identical (issue AC 7).
5. The detector service protocol (request body, accepted response forms) is backend-local: it is between the
   backend and an external service, not between repositories (common rule 13).

## Compatibility classification (every place that uses what this plan touches)
| Place | Evidence | Classification |
|---|---|---|
| AnalyzerRun `result` of `bot_detection` | analysis-jobs-api/spec.md:86 (result is the service object verbatim); no shared spec defined the `bot_detection` result before (backend example: "the result shape is not a shared contract") | shared-additive: a newly documented result object of an existing analyzer id |
| AnalyzerRun failure codes | analysis-jobs-api/spec.md:93 (`adapter_error`, `invalid_output`, `timeout`, `cancelled` already canonical) | unchanged: reuses existing codes |
| Risk-score reading of `bot_detection` | manipulation-risk-score/spec.md:9, :181-:197 (mapping, `single_text` basis) | unchanged: the mapping path `score` is a deployment choice; formula and defaults unchanged |
| Activity of `bot_detection` | analysis-job-events/spec.md:179-180 | unchanged |
| `GET /api/v1/analyzers` item | analysis-jobs-api/spec.md:197 | unchanged (`depends_on` of this analyzer is `[]`, a value, not a shape change) |

No shared-breaking change. No client migration is required: the frontend adds a marker that only appears for a
valid text-scope result.

## Risks
- The detector's exact wire shape is an assumption of the issue (label/score with `LABEL_1`). The backend adapter
  accepts the common Hugging Face forms and fails with `invalid_output` otherwise, so a mismatch is visible as a
  failed run, never as a wrong marker.
