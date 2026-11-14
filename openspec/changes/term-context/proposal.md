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
  in one wiki (the post's language). This keeps the change independent of the active plans that modify
  `wikipedia-lookup-result` (#46 `wikipedia-passage-coverage`, #47 `wikipedia-cross-language`). The backend may
  share code and cache with the `wikipedia` adapter.
- `news_search` is NOT changed and no extra news search is sent: `elsewhere` reuses its Article snippets, so the
  Serper quota is unaffected.
- Not shared (common rule 13): LLM prompts, sentence segmentation heuristics, Wikipedia cache, registry config,
  progress activity (backend local change); term cards, layout, i18n labels and RTL isolation (frontend local
  change).

## Impact
- Shared capabilities: `term-context-result` (new). No existing requirement is modified; analysis-jobs-api,
  analysis-job-events, topic-extraction-result, wikipedia-lookup-result and news-search-result are unchanged.
- backend: new `term_context` adapter and registry entry; at most two LLM calls per job (selection, comparison),
  each with the usual single reply retry; at most two Wikipedia requests per kept term, cached.
- frontend: renders the result as term cards in plain text, links only per the rendering rule.
- project: no new integration suite (`full-e2e` is still a placeholder); repo-ci gates the work.
- Active change `job-text-localization` (#45): its "Localization does not re-run analysis" and "Original evidence
  stays verbatim" already treat these quotes as original source material; `term`, `in_post`, `quote` and
  `snippet` are never translated. No interaction with its API; not a base change.

Based on backend @ 0e6833bfa5f54cab43426bf15f74a65307afdfa0, frontend @ 1a14ae98aebb4160df059a3cff5e192186797c90,
project @ 441ecbf96961128099af004da50a063f18b3345c, shared-specs @ 07b1fce6c316aa2ddf926ffab423dd721fb5b9b4.
