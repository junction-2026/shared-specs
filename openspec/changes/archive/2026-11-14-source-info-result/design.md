# Design: source-info-result

## Contract surface

| Element | Where clients see it | Classification | Evidence |
|---|---|---|---|
| AnalyzerRun `source_info` with SourceInfo `result` | `Job.analyzers[]`, `analyzer.succeeded` `data.analyzer.result` | shared-additive (new analyzer id; result is stored verbatim) | `analysis-jobs-api/spec.md:74` (result verbatim), `analysis-jobs-api/spec.md:67` (one AnalyzerRun per registry analyzer) |
| Skip reason `no_sources` | AnalyzerRun `reason` | shared-additive (new reason on a new condition; reason list is "values include") | `analysis-jobs-api/spec.md:81`; precedent `news-search-result/spec.md` "Nothing to search" |
| Skip `dependency_failed` / `dependency_skipped` when `news_search` did not succeed | AnalyzerRun `reason` | unchanged canonical behaviour | `analysis-jobs-api/spec.md:81,88-92` |
| Failure codes `adapter_error`, `cancelled` | AnalyzerRun `error.code` | unchanged (existing codes, existing meaning) | `analysis-jobs-api/spec.md:81` |
| `news_search` Article (`url`, `domain`) | read by the backend only | unchanged; consumed | `news-search-result/spec.md` "Article object" |
| `input.source.url` | Input object | unchanged; consumed | `analysis-jobs-api/spec.md:9` |
| Selection closure (`analyzers: ["source_info"]` selects `news_search`, `topic_extraction`) | job creation | unchanged canonical behaviour | `analysis-jobs-api/spec.md:30` |

No existing object, member, status or error meaning changes; no client migration.
`grep -rn "source_info\|no_sources\|outlet" openspec/specs` on shared-specs @ 518903a
finds nothing, so the id, reason and capability name are free. There are no active
shared changes on 518903a.

## Tolerant reader and the one "exactly"

All objects are "at least". `articles` has *exactly one* SourceArticle per
`news_search` Article in the same order: this alignment is what lets a client join
`source_info.articles[i]` to `news_search.articles[i]`; it is required, not a
closed-object rule.

## Matching

1. `url.Parse`; host = `Hostname()` (no port), lower-cased, trailing `.` removed, one
   leading `www.` removed. No host or parse error → unmatched, `domain: null`.
2. Exact lookup in host map built from every outlet's `hosts` and `domains` →
   `match: "host"`.
3. `publicsuffix.EffectiveTLDPlusOne(host)` looked up in the domain map built from
   `domains` → `match: "domain"`. Error (e.g. host is a public suffix or an IP) →
   unmatched.

## Backend-local (not in this change)

Loading `execution.outlets_file` once at startup, header and duplicate/empty-domain
validation with row numbers, the refusal to start when an enabled entry's file is
missing or invalid, the Dockerfile `COPY`, registry keys and bindings, the LLM
description and the docs example are requirements of the backend task's local change.

## Risks

- ~65% `bias: unknown`, ~45% no country: the spec requires clients to show these as
  "not rated". Acceptable.
- Leaning data used as truth signal: the rendering requirement and LLM description
  forbid it.
