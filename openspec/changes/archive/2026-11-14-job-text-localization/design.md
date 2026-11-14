# Design: job text localization

## Context
Based on backend @ 402553ad, frontend @ 1a14ae98, shared-specs @ b4a04a19, project @ 441ecbf9. (Backend changes since
2ee817ed are the #43 SQLite job store only; frontend changes since 530723a5 are the VEIL brand restore only; the
text-source table below is unaffected.)

Where each user-visible result text comes from today (backend @ 402553ad):

| Text | Source | Language today | Class |
|---|---|---|---|
| Verdict, confidence, availability, detection strength, status, analyzer ids, activity `key` | enums / stable ids | n/a | A: frontend catalog |
| Technique `name`, LLM `label` | stable ids (technique-classifier-result/spec.md:19-21, llm-technique-result/spec.md:19) | n/a | A: frontend catalog |
| `plain_language.name`, `definition`, span/detection `why` | fixed glossary (technique_glossary.yaml, langs en fi sv de fr es ru uk; no ar) | content `source_language`, else en (technique-classifier-result/spec.md:286) | A: frontend catalog keyed by `name` + client-side why template (spec.md:315: why = template + name + span text only) |
| Activity `text`/`detail` | fixed English (analysis-job-events/spec.md:175) | en | A: already localized by `key`/`params` (spec.md:182) |
| Availability `note` | fixed English (analysis-jobs-api/spec.md:360) | en | A: frontend localizes by availability/reason |
| `finalization.result.user_text` (finalizer) | LLM, prompt "in the language of the content" (backend config/finalizer/prompt.md:36) | content | B: new endpoint |
| `user_text` produced_by orchestrator | fixed English (backend internal/finalizer/finalizer.go:25) | en | B: new endpoint, fixed table |
| LLM finding `explanation` | LLM in `explanation_language` (llm-technique-result/spec.md:55) | content/en | B: new endpoint |
| Input content, span `text`, claims, topics, news headlines, fact-check reviews, Wikipedia passages | source material | original | C: verbatim, `dir`-isolated |
| Wikipedia `cross_language` (if #47 ships) | enum (plan/47 wikipedia-lookup-result) | n/a | A: frontend catalog, owned by #47's frontend task |
| Wikipedia compared value `text` (if #47 ships) | verbatim substring of a passage | original | C: verbatim |
| Ask Stiriri thread | frontend mock (frontend src/views/AskView.tsx:7), no backend | catalog | A: frontend catalog |

No existing request parameter, header or endpoint selects a presentation language (grep of the canonical specs for
`locale`, `lang`, `Accept-Language`: only content/search languages). The smallest additive mechanism that also works
for already completed analyses is a read-only sub-resource of the job.

## Decisions
1. **Separate read endpoint, not a job option.** A create-time option cannot serve a language switch on a finished
   job. `GET /jobs/{id}/localization?language=` is idempotent, needs no body and leaves the Job untouched, so the
   analysis is never re-run and existing clients never see a difference.
2. **Only model-written presentation texts.** Glossary texts and enums are localized by the client from stable ids
   (deterministic, offline, consistent terminology across pages). The endpoint covers what the client cannot
   rebuild: finalizer `user_text` and LLM `explanation`s. Source material is never translated (issue class C).
3. **Per-text status instead of an error.** A missing or failing provider yields 200 with `unavailable` texts so the
   page renders the original with an honest marker; nothing pretends to be localized (issue §6).
4. **Stable while running.** Cache per (job, language) of successful texts; `unavailable` is not cached. Persisting
   the cache is a backend-local choice (not required).
5. **Supported set "includes" en, fr, ar, de, fi** (tolerant enumeration): the UI's locales. The backend may add more.
6. **Client-side technique localization is permitted explicitly** by modifying "Plain-language presentation", which
   today obliges clients to show `plain_language` (the very cause of French names on an Arabic page).
7. Job must be `done` (409 `job_not_finished` otherwise): texts are settled only then, so the cache can never hold a
   stale text. The frontend requests the localization only after the job is done.

## Compatibility classification

| Item | Where used (canonical) | Change | Class |
|---|---|---|---|
| `GET /api/v1/jobs/{id}/localization` | new | new endpoint | shared-additive |
| `job_not_finished` (409), `unsupported_language` (400) | new conditions on the new endpoint; common codes api-conventions/spec.md:33 | new codes on new conditions | shared-additive |
| JobLocalization, LlmFindingLocalization, LocalizedText | new objects, used only by the new endpoint | new | shared-additive |
| Job, FinalAssessment (analysis-jobs-api/spec.md:44, :131), events (analysis-job-events) | unchanged | none | — |
| TechniqueClassification / Detection / PlainLanguage (technique-classifier-result/spec.md:27, :256, :297) | server output unchanged | none | — |
| "Plain-language presentation" (technique-classifier-result/spec.md:339) | client obligation; referenced by analysis-job-events TechniquePreview (spec.md:307) for verbatim server-side copying only | MODIFIED to defer to the ADDED "Client localization of glossary texts" (client MAY localize by `name`/`label` when UI language ≠ `explanation_language`; still SHALL fall back to `plain_language`) | shared-additive (no server change, no client must change; existing clients stay conformant) |
| LlmTechniqueFinding `name`/`definition`/`explanation` (llm-technique-result/spec.md:47-58, :142) | server output unchanged; rendering rule (plain text) unchanged | none | — |

No shared-breaking change; no client migration required. Old frontends ignore the new endpoint.

## Overlap with active changes
`persistent-job-history` (active, not implemented on main) adds requirements to `analysis-jobs-api` and
`analysis-job-events`. This change modifies neither; a persisted done job is localized like any other.
`base_changes` is empty.

Since #43's backend store is merged (backend @ 402553ad), the backend task looks jobs up through the job store, not
an in-memory map; the per-(job, language) localization cache stays in memory (spec allows a different wording after
restart) and is not added to the SQLite schema, so it does not touch #43's `job-store` capability.

`wikipedia-cross-language` (junction-2026/project#47, plan/47 @ 0a6e0c7d, awaiting approval) modifies only
`wikipedia-lookup-result`: no shared capability in common, no contradiction. It adds no model-written text, so the
localization endpoint has nothing to cover for it. Its frontend task (`wikipedia-lookup-view`) owns the Wikipedia
section and its strings; this feature's frontend tasks only extend the key-completeness test, which then also
gates that section's strings in all five locales. Both features add keys to the same locale catalogs
(`frontend/src/i18n/locales/*`): the second to merge rebases (additive key sets, no shared keys). The backend task
of this feature does not change `internal/adapter/wikipedia*.go`.

## Risks
- Translation latency on first request (one provider call per job/language, all texts batched): the client shows the
  original with a "translating" marker until the answer arrives.
- Model translation quality for Arabic/Finnish: provider choice and prompt are backend-local; texts are labelled
  machine-translated.
