# Design: term-context

## Decisions

### D1. New analyzer instead of a `wikipedia` "term mode"
The issue suggests extending W1 (`wikipedia`) so a term can be looked up as its own page. Two active plans already
modify `wikipedia-lookup-result` (#46 `wikipedia-passage-coverage`, #47 `wikipedia-cross-language`); a third delta on
the same capability would conflict. The term lookup also has different rules (exact title or redirect only, one
wiki, a lead *sentence*, `no_coverage`) from the claim lookup (title/full-text modes, two wikis, passages). A new
analyzer `term_context` with its own capability keeps both contracts simple and independent. The backend may reuse
the `wikipedia` adapter's HTTP client, rate limiting and persistent cache internally (backend local).

### D2. Term selection (issue AC5: "selection rule to be settled in planning")
Claim `entities` are named people, organisations, places and numbers (topic-extraction-result "What counts as a
claim"), so loaded words such as pejorative labels or coined slogans are usually not entities. Candidates are
therefore the entities and words or phrases of the post. A model judges "loaded or unfamiliar" against the written
criteria in "Term candidates and selection"; there is no dictionary (non-goal). The model's selection output is
used only as strings to locate in the post; the backend keeps a pick only when it occurs verbatim (case-insensitive,
letter/digit boundaries) and takes `term` from the post. Persons, numbers and dates are excluded to keep the
feature about terms, not people.

### D3. `sense` via an LLM judging quotes only
`unknown` is decided by rule (no other quote). For other terms one LLM request compares only `term`, `in_post`,
the encyclopedia `quote` and the `snippet`s (issue assumption: inputs limited to the quotes). Its output is an enum
plus QuoteRefs; `differs_from` makes every differing quote reachable (issue AC4). No model text is shown.

### D4. `encyclopedia` is an object or the literal `"no_coverage"`
Follows issue AC2 literally. Clients treat any non-object value like `"no_coverage"`, so a later status object
or new string is not breaking.

### D5. One wiki, no extra news search
Quota risk from the issue: at most one title request plus one search request per kept term (cached, max 5 terms),
in the post's language wiki only; `elsewhere` reuses `news_search` snippets, so Serper usage is unchanged. An
English fallback for missing pages can be added later as an additive change.

### D6. Dependency on `news_search`
`term_context` depends on `news_search` so its snippets are available. Consequence: when `news_search` is skipped
(`no_searchable_topics`) or failed, `term_context` is skipped (analysis-jobs-api "Dependency and timeout
semantics"), and a deployment needs `news_search` enabled to run it. Accepted: a post with no searchable topic
rarely yields terms with comparable quotes, and "Dependency-skipped availability" gives a correct note.

## Compatibility classification

Grep of canonical specs (shared-specs @ 07b1fce6) for every object this change touches:

| Object / place | Evidence | Change | Class |
|---|---|---|---|
| New analyzer id `term_context` in AnalyzerRun list | analysis-jobs-api/spec.md:74 (AnalyzerRun object), :66 (Job analyzer list), :181 (List analyzers) | new AnalyzerRun / registry item on deployments that enable it | shared-additive (new endpoint-equivalent object; clients already ignore analyzers they do not know) |
| Skip/failure reasons and availability | analysis-jobs-api/spec.md:81, :88, :387, :398 | reuses existing reasons and codes only; no new skip reason | none |
| `topic_extraction` Claim `entities` | topic-extraction-result/spec.md:106, :113 | read only | none |
| `news_search` Article `snippet`, `url`, `title`, `domain` | news-search-result/spec.md:237 | read only; no extra searches | none |
| `wikipedia` analyzer / WikipediaLookup | wikipedia-lookup-result/spec.md (whole) | not touched | none |
| LLM reply retry rules | analysis-jobs-api/spec.md:422-468 | referenced, not modified | none |
| job-text-localization (active change #45) | changes/job-text-localization/specs/job-text-localization/spec.md "Localization does not re-run analysis", "Original evidence stays verbatim" | TermContext strings are original evidence and are never translated; no new LocalizedText | none |

No shared-breaking change: no member removed, renamed or retyped, no status of an existing case changed. No
client migration is needed; clients that do not know `term_context` show it at most as a generic analyzer row.

## Not shared (common rule 13)
- backend: prompts for selection and comparison, sentence and lead-sentence segmentation code, cache storage and
  TTL, config keys and defaults wiring, progress activity facts, finalizer handling.
- frontend: term card layout, i18n labels in all UI locales, RTL isolation of quotes, placement in the results view.

## Risks
- Matching across languages: `term` is located in the post as written; snippets in another language rarely
  contain it, so `elsewhere` is mostly same-language. Accepted (no translation of quotes, by design).
- Disambiguation: returned as `no_coverage` rather than guessing a sense.
- Model selection quality is non-deterministic; tests use a stubbed LLM, and the verbatim filter guarantees AC1.
