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
- The term "conflict" was not defined in any canonical spec; this change does not introduce a conflict concept.
  It defines `discrepancy` (values differ) and states that `gap` is neither a discrepancy nor a conflict.

Interface only (common rule 13): number/date recognition tables, locale number parsing, code layout and tests are
backend-local; the display, layout, strings and accessibility are frontend-local.

## Impact
- Shared capability modified: `wikipedia-lookup-result` (additive). No endpoint, status, error code or other object changes.
- backend: compute `cross_language` / `cross_language_differences` per ClaimLookup in the `wikipedia` adapter, tests.
- frontend: no Wikipedia result display exists yet; the frontend task adds a read-only Wikipedia lookup section
  (per claim, each wiki's passage verbatim and separate) that shows the cross-language state.
- project: no new integration suite; repo-ci of backend and frontend cover the change.

Based on backend @ 2ee817ed318928e5ecb2d6ce9aab822a7cc99f16, frontend @ 530723a5ee7c097b107eb9b9eb4258ec027f5663,
project @ 441ecbf96961128099af004da50a063f18b3345c, shared-specs @ b4a04a191450549e9d263166bd8cc2904044cff6.
