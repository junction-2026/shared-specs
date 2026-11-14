# Wikipedia cross-language agreement (junction-2026/project#47)

## Why
When a claim was looked up in the post-language Wikipedia and in English Wikipedia and both returned a passage, a
reader wants to know whether the two editions say the same thing about numbers and dates, without the system
averaging the two articles, translating one into the other, or issuing a verdict on the claim.

## What changes
- W2 (`wikipedia-claim-lookup`, junction-2026/project#29) is already merged and archived: the canonical
  `wikipedia-lookup-result` capability on shared-specs `main` and `backend/internal/adapter/wikipedia.go` are the
  base. No active change is modified; this change builds on the canonical spec only.
- `wikipedia-lookup-result` (additive only, see design.md):
  - MODIFIED "ClaimLookup object": two new optional members `cross_language` and `cross_language_differences`.
  - ADDED "Missing cross-language members", "Cross-language state", "Cross-language gap", "Cross-language agree and discrepancy", "Cross-language comparison values", "Date comparison values", "Number comparison values", "Cross-language differences", "Compared value object",
    "Cross-language comparison is deterministic", "Cross-language rendering" and "Gap is not a conflict".
- The term "conflicts" is not defined in any canonical spec on `main`. The parallel feature junction-2026/project#46
  (`wikipedia-passage-coverage`, still planning) proposes it as a per-WikiLookup `coverage` label (passage vs. claim).
  This change does not introduce or depend on it: it defines `discrepancy` (the two passages' values differ, a
  ClaimLookup-level comparison of passage vs. passage) and states that `gap` is neither a discrepancy nor a conflict.

Interface only (common rule 13): number/date recognition tables, locale number parsing, code layout and tests are
backend-local; the display, layout, strings and accessibility are frontend-local.

## Impact
- Shared capability modified: `wikipedia-lookup-result` (additive). No endpoint, status, error code or other object changes.
- backend: compute `cross_language` / `cross_language_differences` per ClaimLookup in the `wikipedia` adapter, tests.
- frontend: no Wikipedia result display exists yet; the frontend task adds a read-only Wikipedia lookup section
  (per claim, each wiki's passage verbatim and separate) that shows the cross-language state.
- project: no new integration suite; repo-ci of backend and frontend cover the change.

Based on backend @ 402553adaf40e950db2f9cd0846d408ab2e79a31, frontend @ 1a14ae98aebb4160df059a3cff5e192186797c90,
project @ 441ecbf96961128099af004da50a063f18b3345c, shared-specs @ 07b1fce6c316aa2ddf926ffab423dd721fb5b9b4.
