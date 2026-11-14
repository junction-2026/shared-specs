## Why

The `techniques` analyzer shows which phrase carries a technique, with an English `display` and one-line `explanation`, but not what the technique means or why this phrase is an instance of it in the language of the post (junction-2026/project#27, item T2). Three weaknesses that the 18 SemEval-2020 labels do not cover (evidence-certainty mismatch, misleading headline, statistical cherry-picking) are not detected at all (item T4).

Based on backend @ 1574bd306c06df424375d2a464fd0e57b229659a, frontend @ 1abe19a7fa41cea9a083eebc699f328dc58e904a, project @ 441ecbf96961128099af004da50a063f18b3345c, shared-specs @ 6d1e0c05eeee99ea3099ca5c00e6e8a7c8e16dad.

## What Changes

- `technique-classifier-result` (additive): a succeeded TechniqueClassification gains `explanation_language` and `glossary_version`; each Detection gains `plain_language` `{name, definition, why}` in that language; each TechniqueSpan gains `why`. `name` and `definition` come from a fixed, versioned glossary (not from an LLM per request); `why` is a fixed template that quotes the accepted span verbatim, or states that the label came from the document score and no phrase was located. The existing `name`, `display` and `explanation` keep their meaning (`name` stays the stable English identifier, so the localized name is `plain_language.name`).
- New capability `llm-technique-result`: an optional, selectable analyzer `llm_techniques` (category `propaganda`) whose LLM looks only for the closed set `evidence_certainty_mismatch`, `misleading_headline`, `statistical_cherry_picking` in the original text and, when the job has a distinct headline, in `input.source.title`. Each finding has `label`, a localized `name` and `definition`, `explanation` (one sentence), `confidence`, `source: "llm"` and a span that is an exact substring of the content or the title. Findings are never merged into `techniques.detected` and never mapped onto SemEval labels.
- No removed or renamed member, no changed meaning, no new error code on an existing condition. Results stored before this change still render.

### Decision that corrects an assumption of the issue

The issue names "a scrape that separated a title from the body" as the source of a headline. At shared-specs 6d1e0c05, `openspec/specs/analysis-jobs-api/spec.md:288` sets a scraped job's `source.title` to the account's `display_name`, not a headline, and only Bluesky and Mastodon posts (which have no headline) are scraped. This plan therefore checks the title only for jobs created with `input` (no `scrape`) whose `source.title` is non-empty and differs from the content. Scraped jobs never get a `misleading_headline` finding until a scraper produces real headlines (a later change).

## Capabilities

### New Capabilities

- `llm-technique-result`: the `llm_techniques` analyzer and its LlmTechniqueResult object.

### Modified Capabilities

- `technique-classifier-result`: plain-language members on TechniqueClassification, Detection and TechniqueSpan; presentation rules for them.

## Impact

- backend: versioned glossary artifact (18 SemEval techniques + 3 LLM labels, names, definitions and `why` templates per supported language), result members, new `llm_techniques` adapter with exact-substring checking, example registry config, finalizer description marking LLM labels as weaker.
- frontend: show `plain_language.name`, `definition` and `why` next to highlights; show `llm_techniques` findings as a separate, weaker group, title spans highlighted in the shown title.
- project: no change; `full-e2e` is still a placeholder.
