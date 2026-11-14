# Design: Wikipedia passage coverage label

## Context
Based on backend @ 2ee817ed318928e5ecb2d6ce9aab822a7cc99f16, frontend @ 530723a5ee7c097b107eb9b9eb4258ec027f5663,
project @ 441ecbf96961128099af004da50a063f18b3345c, shared-specs @ b4a04a191450549e9d263166bd8cc2904044cff6.

- backend `internal/adapter/wikipedia.go:27` `wikiLookup` holds the WikiLookup members; `personalize`
  (`wikipedia.go:195`) recomputes `matched_entities`/`matched_numbers` per claim, also after cache hits, so the
  label is computed there too: cached and uncached answers get the same label for the same claim.
- `internal/finalizer/finalizer.go:121` `llmEntries` passes each opted-in AnalyzerRun's `result` verbatim to the
  LLM; new WikiLookup members therefore reach the finalizer without a protocol change. `normalize`
  (`finalizer.go:180`) drops every member except verdict/confidence/user_text; `internal/job/job.go:255`
  `FinalAssessment`; `internal/adapter/llm.go:26` `FinalizationSchema` has `additionalProperties: false`.
- The finalizer's `user_text` is free prose; a quote inside it cannot be verified deterministically. Hence a
  structured `wikipedia_quotes` member that the orchestrator verifies.
- frontend `src/api/types.ts:38` `FinalAssessment` has an index signature; no frontend code reads the `wikipedia`
  result. No frontend work is needed.
- Overlap: the only active shared change, `persistent-job-history`, adds other requirements to analysis-jobs-api
  and analysis-job-events; it does not touch FinalAssessment, the protocol or wikipedia-lookup-result. Jobs it
  persists from before this change lack the new members; the contract defines both absences.

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
8. **Quote enforcement by structure; drop, not fail.** The finalizer proposes `wikipedia_quotes`
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
