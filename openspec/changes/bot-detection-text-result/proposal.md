# Text-level bot / generated-text result of `bot_detection` (junction-2026/project#73)

Based on backend @ fe6c2e621680b87d7afa598e60b9e7fe9e44f0c5, frontend @ 60dc985dee63c01e743a53cbc02ccd049604e83c,
project @ 441ecbf96961128099af004da50a063f18b3345c, shared-specs @ 18e157ddd9d020aeb9af984d337bf47f5c970659
(no active shared change on main; this change neither modifies nor builds on another feature's change).

## Why
The bot-detector service is today only an undocumented, disabled, account-level example (`bot_detection`, adapter
`http_sync`, backend `docs/examples/bot_detection.yaml`). Nothing answers "does this one text look human-written or
bot / generated?". Readers need that small, honest signal, computed by the multilingual model on the original text,
and clearly not an account verdict and not a propaganda detector.

## What changes
- New shared capability `bot-detection-result` (ADDED requirements): the analyzer `bot_detection` (category
  `bot_detection`, no dependency on `translation`) classifies the job's original `normalized_content`; when it succeeds its
  `result` is a TextBotDetection object with at least `label` (`human` | `bot_or_generated`), `score`
  (P(bot_or_generated), 0..1) and `scope: "text"`. Failure codes, client tolerance (missing / skipped / failed /
  unknown scope or label = "no text-origin signal") and the analyzer's description semantics are specified.
- Decision: the analyzer id `bot_detection` is reused (not a new id), so the existing Manipulation Risk Score
  `bot_detection.single_text_score` deployment mapping can read the new result with the path `score`; the risk-score
  formula, its spec and its default configuration are unchanged.
- No change to `analysis-jobs-api`, `analysis-job-events`, `manipulation-risk-score`, `technique-classifier-result`
  or the propaganda analyzer. All of it is additive (see design.md).

## Out of scope (local to the owning repository)
- backend: the `bot_detection` text adapter, the request/response protocol of the detector service, label mapping,
  validation, registry example, README, risk-config comment, tests.
- frontend: the marker next to the confidence in the Results verdict card, its tooltip / aria text, i18n, tests.

## Impact
- Clients that ignore unknown members (api-conventions) are unaffected. A deployment that still runs the old
  account-level `http_sync` entry returns a result without `scope: "text"`; clients show no marker for it.
- Children: `backend-bot-text` (backend), `frontend-bot-text-marker` (frontend); independent, both build on this
  contract only.
