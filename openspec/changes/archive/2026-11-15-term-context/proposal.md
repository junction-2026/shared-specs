# Term context from sources (junction-2026/project#49)

## Why
A post can use loaded or unfamiliar terms whose meaning the reader cannot judge, and no analyzer says what a term
means. The user needs, per such term, how the post uses it, what the encyclopedia says and how news snippets use it,
each as a verbatim quote from a source the user can open, never a model-written definition.

## What changes
- New shared capability `term-context-result` (additive): a new selectable analyzer `term_context` (category
  `coverage`, `depends_on` `topic_extraction`, `translation`, `news_search`) whose result lists one TermContext per
  kept term with `term`, `in_post`, `encyclopedia` (verbatim lead quote of the term's own Wikipedia page with a
  revision permalink, or the literal `"no_coverage"`), `elsewhere` (verbatim `news_search` snippets that contain the
  term, with their article url) and `sense` (`same`, `differs`, `unknown`), plus `differs_from` naming the quotes
  that differ so that they are reachable.
- Term selection: candidates are the Claim `entities` of `topic_extraction` and words or phrases of the post. One
  LLM call picks the loaded or unfamiliar ones; the backend keeps only picks that occur verbatim in the post. No
  term list or dictionary. The model never writes a definition, a tribe or camp name, or a verdict: its output is
  only substrings of the post (selection) and the `same`/`differs` relation between given quotes (comparison).
- The `wikipedia` analyzer and `wikipedia-lookup-result` are NOT changed: `term_context` does its own title lookup
  in one wiki (the post's language). The claim lookup's rules (title/full-text modes, two wikis, passages and, since
  #46 `wikipedia-passage-coverage` was archived, per-WikiLookup `coverage` labels) do not fit a term's own page, and
  #47 `wikipedia-cross-language` (archived on main @ 4bc8742) added cross-language comparison to that capability. The backend may share code and
  cache with the `wikipedia` adapter.
- analysis-jobs-api "Wikipedia quotes for clients" (canonical since #46 was archived) says clients present only
  FinalAssessment `wikipedia_quotes` as quotations from Wikipedia. This change modifies it so that `term_context`
  EncyclopediaQuote objects may also be presented as Wikipedia quotations, while the final assessment still shows
  only `wikipedia_quotes`.
- `news_search` is NOT changed and no extra news search is sent: `elsewhere` reuses its Article snippets, so the
  Serper quota is unaffected.
- Not shared (common rule 13): LLM prompts, sentence segmentation heuristics, Wikipedia cache, registry config,
  progress activity (backend local change); term cards, layout, i18n labels and RTL isolation (frontend local
  change).

## Impact
- Shared capabilities: `term-context-result` (new); `analysis-jobs-api` (one requirement modified, additive:
  "Wikipedia quotes for clients"). analysis-job-events, topic-extraction-result, wikipedia-lookup-result,
  news-search-result and job-text-localization are unchanged.
- backend: new `term_context` adapter and registry entry; at most two LLM calls per job (selection, comparison),
  each with the usual single reply retry; at most two Wikipedia requests per kept term, cached.
- frontend: renders the result as term cards in plain text, links only per the rendering rule.
- project: no new integration suite (`full-e2e` is still a placeholder); repo-ci gates the work.
- Canonical `job-text-localization` (#45, archived): "Localization does not re-run analysis" and "Original evidence
  stays verbatim" already treat these quotes as original source material; `term`, `in_post`, `quote` and `snippet`
  are never translated and no LocalizedText is added. No change to that capability.
- No base changes: the plan builds only on canonical specs; no other feature's active change is edited.

Based on backend @ e8c46a1e6e4ab169e6376c5da627d0c71ae0b2ba, frontend @ ae2bfa4d745ddce44e7df7d2a86f2edfd4eba14d,
project @ 441ecbf96961128099af004da50a063f18b3345c, shared-specs @ 1e0221572c2e6eb4d4f9a1caf857116d54c3bb56.

Feature #53 `job-visibility` (archived on main @ a2387ba) changed other analysis-jobs-api requirements (Create job,
Create job validation, Job object, List jobs, Persisted jobs in listing and cancel) and added Job visibility, Listing
excludes non-public jobs and Unlisted jobs by id. This change keeps all of them as they are on main and modifies only
"Wikipedia quotes for clients", whose canonical text is unchanged since 5981c9fd. `term_context` results follow the
job's `public` flag like every other AnalyzerRun; nothing in this change depends on it. #60
`russian-localization-language` (archived @ 29080f5) added `ru` to job-text-localization; TermContext strings stay
untranslated in every language, `ru` included.
