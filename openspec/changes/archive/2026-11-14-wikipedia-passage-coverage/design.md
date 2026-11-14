# Design: Wikipedia passage coverage label

## Context
Based on backend @ 0e6833bfa5f54cab43426bf15f74a65307afdfa0, frontend @ 4aab58091e8fa5edbe79f0d6f35f0fb24cec8ad8,
project @ 441ecbf96961128099af004da50a063f18b3345c, shared-specs @ 07b1fce6c316aa2ddf926ffab423dd721fb5b9b4.

- backend `internal/adapter/wikipedia.go:27` `wikiLookup` holds the WikiLookup members; `personalize`
  (`wikipedia.go:195`) recomputes `matched_entities`/`matched_numbers` per claim, also after cache hits, so the
  label is computed there too: cached and uncached answers get the same label for the same claim.
- `internal/finalizer/finalizer.go:121` `llmEntries` passes each opted-in AnalyzerRun's `result` verbatim to the
  LLM; new WikiLookup members therefore reach the finalizer without a protocol change. `normalize`
  (`finalizer.go:167`) drops every member except verdict/confidence/user_text; `internal/job/job.go:258`
  `FinalAssessment`; `internal/adapter/llm.go:26` `FinalizationSchema` has `additionalProperties: false`.
- The finalizer's `user_text` is free prose; a quote inside it cannot be verified deterministically. Hence a
  structured `wikipedia_quotes` member that the orchestrator verifies.
- frontend `src/api/types.ts:38` `FinalAssessment` has an index signature; no frontend code reads the `wikipedia`
  result. No frontend work is needed.
- `persistent-job-history` is archived (shared-specs @ 0fe09d0, backend SQLite store @ 402553a); it did not touch
  FinalAssessment, the protocol or wikipedia-lookup-result. Jobs it persisted before this change lack the new
  members; the contract defines both absences.
- Spec rebase (shared-specs `main` @ 07b1fce): canonical `analysis-jobs-api` gained "Job history persistence",
  "Persisted jobs in listing and cancel", "History retention", "Jobs interrupted by a restart", "Interrupted parts"
  and "Interrupted part timing" (`openspec/specs/analysis-jobs-api/spec.md:490-543`). None is MODIFIED here; the
  only MODIFIED requirement, "FinalAssessment object" (`spec.md:130-139`), is unchanged on `main` and the delta
  keeps its text verbatim plus `wikipedia_quotes`. The new ADDED requirement "Wikipedia quotes in persisted and
  interrupted jobs" ties the member to them: persisted verbatim (backend stores `finalization.result` as raw JSON,
  `internal/job/job.go:255`), never re-verified, absent when an interrupted finalization has `result: null`.

- Active change `job-text-localization` (#45, on `main`) localizes only FinalAssessment `user_text` and LLM
  finding texts and requires quotations and Wikipedia passages to stay verbatim ("Original evidence stays
  verbatim"). `wikipedia_quotes` and `evidence_sentence` are such original evidence: never localized, and its
  JobLocalization `final_assessment` (`{"user_text": ...}`) is unaffected by the new member. No requirement overlap.

## Overlap with #47 (`wikipedia-cross-language`, plan @ a1e2de71e1ba87fcb725b71bcf20631d3dd949cd)
An approver let #47 run in parallel on `wikipedia-lookup-result` and `backend/analyzer-adapters`. Planned around it:
- **Disjoint requirements.** #47 MODIFIES "ClaimLookup object" and ADDS cross-language requirements; this change
  MODIFIES only "No verdict from Wikipedia lookup" (which #47 references but does not modify) and ADDS requirements
  with names #47 does not use. Neither delta rewrites a requirement the other modifies, so either archives cleanly
  first. This change does not rewrite "WikiLookup object" (its "at least" list stays valid), avoiding a second
  MODIFIED on the object family #47 extends.
- **Different objects, different questions.** #47 sets ClaimLookup members comparing two passages with each other;
  this change sets WikiLookup members comparing one passage with the claim. "Coverage is per WikiLookup" forbids
  either from changing the other and forbids presenting `conflicts` as a language-edition disagreement, consistent
  with #47's "Gap is not a conflict": a `gap` never makes a WikiLookup `conflicts`; its `no_page` entry is
  `no_coverage` and the found entry is labelled against the claim alone.
- **Number notions.** #47 normalizes locale notations (`1.500` = `1,500` = 1500) for passage-vs-passage sets; this
  change keeps the canonical digit-run definition of "Matched entities and numbers" for claim-vs-passage and is
  conservative instead: a digit run inside a grouped or decimal number is never a differing number (decision 8).
  Reusing #47's normalization would make this feature depend on an unapproved change and its backend child on
  another feature's code; the conservative rule gives no false `conflicts` from notation. A later change may switch
  coverage to #47's comparison values once both are canonical.
- **Backend code.** Both backend tasks edit `internal/adapter/wikipedia.go`. This feature keeps its logic in a new
  file (`internal/adapter/wikipedia_coverage.go`) and adds only the two struct members and one call in `personalize`,
  so the merge with #47's ClaimLookup-level code is mechanical. No frontend overlap: this feature has no frontend
  task; #47's frontend view does not read `coverage` and older readers ignore it.

## Decisions
1. **Label in the adapter, deterministic, no LLM.** Ordered rules (wikipedia-lookup-result "Wikipedia coverage
   rules") give exactly one label per entry and make tests table-driven.
2. **"Relation" is not compared.** No deterministic relation rule exists; a claim without a digit reaches at most
   `mentioned`. This settles the issue's open point conservatively (no false `aligned`).
3. **Numbers and dates are digit runs**, reusing the existing `matched_numbers` definition (wikipedia-lookup-result
   "Matched entities and numbers"). No word-number or date-format normalisation: "seventy" is not 70; for
   "2025-05-03" vs "3 May 2025" only the digit runs are compared. Kind: 4 digits = year, other = count. The rule is
   language-independent, which matters for the `{source}` wiki.
4. **Conservative `conflicts`.** A different number conflicts only when the claim has exactly one number of that
   kind, that number is absent from the sentence and the sentence contains a matched named entity. This prevents
   "voted 412 to 180" from conflicting with "630 members". False `conflicts` remain possible (an unrelated count in
   a sentence naming the entity), which is why the label is explicitly not a verdict and the finalizer reads
   `evidence_sentence`.
5. **Today's events.** "Today" cannot be detected without date parsing. The rules guarantee such a claim is
   `aligned` only if the passage carries all its numbers; typically it is `no_coverage` (no hit for the full-text
   query, or no entity) or `mentioned` (entity page without the numbers). "Claims about recent events" and the
   analyzer description state that this is not evidence of falsehood; `news_search` stays the place for reporting.
6. **Sentence splitting** by terminal punctuation followed by whitespace or end, and by line breaks; trimmed parts
   are substrings of `passage`, so evidence is verbatim by construction. Abbreviations ("e.g. ") may split early;
   accepted for determinism.
7. **Downgrade.** The backend checks that `evidence_sentence` is a substring of `passage` and satisfies the number
   condition before emitting `aligned`/`conflicts`, otherwise emits `mentioned`; consumers re-check and read a
   failed check as `mentioned` (no upgrade without a verifiable span).
8. **Grouped and decimal numbers are never `conflicts` evidence.** A digit run joined to another by `.`, `,`, `'`,
   NBSP or narrow NBSP is part of `1.500`/`1,500`/`2,5`; without locale parsing its value is unknown, so it never
   counts as the differing number X. Such a claim reaches `aligned` only when the same digit runs occur, otherwise
   `mentioned`.
9. **Quote enforcement by structure; drop, not fail.** The finalizer proposes `wikipedia_quotes`
   `{claim, language, quote}`; the orchestrator keeps only trimmed substrings of a found, non-`no_coverage` passage
   and copies `title`, `url`, `revision_id` and `coverage` itself (never from the finalizer). Invalid quotes are
   dropped instead of failing finalization (a wrong optional quote must not cost the user the verdict) and do not
   trigger the LLM reply retry. Rejected alternative: validating quotation marks in `user_text` (language-dependent,
   not deterministic). The prompt tells the LLM not to quote Wikipedia in `user_text` except text it also lists in
   `wikipedia_quotes`; that part is backend-local prompt behaviour and not enforceable by the orchestrator.

## Classification of interface changes
| Change | Canonical uses (file:line) | Class |
|---|---|---|
| WikiLookup `coverage`, `evidence_sentence` (ADDED requirements; the WikiLookup object requirement itself is not rewritten, its "at least" list stays valid) | wikipedia-lookup-result/spec.md:121 (WikiLookup object, "at least"), :128 (page members), :107 (WikipediaLookup: "Clients SHALL ignore unknown members") | shared-additive |
| "Standalone numbers" (ADDED) | new; refines only the new "Conflicting coverage" | shared-additive |
| "Coverage is per WikiLookup" (ADDED) | new; ClaimLookup (wikipedia-lookup-result/spec.md:114) unchanged; #47's proposed ClaimLookup members not referenced | shared-additive |
| "No verdict from Wikipedia lookup" extended to labels | wikipedia-lookup-result/spec.md:199 | shared-additive (same meaning, covers new member) |
| FinalAssessment `wikipedia_quotes` (MODIFIED "FinalAssessment object"; ADDED "Wikipedia quotes in the final assessment", "Wikipedia quote verification", "Wikipedia quotes for clients") | analysis-jobs-api/spec.md:130 (FinalAssessment "at least"), :105 (Finalization.result), :142 (orchestrator assessment, "at least"), :160 (JobSummary carries only `verdict`, unaffected); analysis-job-events `analysis.finalized` embeds Finalization | shared-additive |
| Finalizer response may include `wikipedia_quotes` (MODIFIED "Finalizer response", ADDED "Proposed Wikipedia quotes") | analyzer-service-protocol/spec.md:71, :78 (response validation unchanged: quotes never cause `invalid_output`) | shared-additive (optional member) |
| Finalizer input carries the labels (ADDED "Wikipedia labels in finalizer input") | analyzer-service-protocol/spec.md:29 (job-wide bindings); backend `finalizer.go:121` already passes results verbatim | shared-additive (states existing behaviour for the new members) |
| Normalization keeps verified `wikipedia_quotes` | analyzer-service-protocol/spec.md:97 ("drop every other member") | shared-additive: a member formerly dropped is now kept after verification; finalizers that never send it get `[]` |

No shared-breaking change: no member removed, renamed or retyped, no status or error code changed. Affected clients:
frontend (types tolerate unknown members; nothing to migrate), external `http_sync`/`http_async` finalizers (may
ignore the new member).

## Local (not in this change)
Go types and placement of the algorithm, the LLM JSON schema (`wikipedia_quotes` listed in `required` for strict
`json_schema` mode, as a possibly empty array), prompt text, `llm.description` wording, logging of dropped quotes
and tests are backend-local requirements of child `backend-wikipedia-coverage`.

## Risks
- Heuristic `conflicts` can be wrong; mitigated by decision 4 and the no-verdict rule.
- Digit-only comparison misses spelled-out numbers (`mentioned` instead of `aligned`): the safe direction.
