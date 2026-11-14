# Wikipedia cross-language agreement (junction-2026/project#47)

## Why
When a claim was looked up in the post-language Wikipedia and in English Wikipedia and both returned a passage, a
reader wants to know whether the two editions say the same thing about numbers and dates, without the system
averaging the two articles, translating one into the other, or issuing a verdict on the claim.

## What changes
- W2 (`wikipedia-claim-lookup`, junction-2026/project#29) is merged and archived: the canonical
  `wikipedia-lookup-result` capability on shared-specs `main` and `backend/internal/adapter/wikipedia.go` are the
  base. #46 (`wikipedia-passage-coverage`) and #45 (`job-text-localization`) are now archived too and canonical;
  no other feature's active change is modified or built on (`base_changes` is empty).
- `wikipedia-lookup-result` (additive only, see design.md):
  - MODIFIED "ClaimLookup object" (canonical text on main @ 80eea74 is unchanged since W2; this delta keeps every
    existing member and adds two new optional members `cross_language` and `cross_language_differences`).
  - ADDED "Missing cross-language members", "Cross-language state", "Cross-language gap", "Cross-language agree and
    discrepancy", "Cross-language comparison values", "Date comparison values", "Number comparison values",
    "Cross-language differences", "Compared value object", "Cross-language comparison is deterministic",
    "Cross-language rendering" and "Gap is not a conflict".
- The term `conflicts` is now canonical (from #46): a per-WikiLookup `coverage` label that compares one passage with
  the claim ("Conflicting coverage", "Coverage is per WikiLookup"). This change compares the two passages with each
  other (`discrepancy`), never reads or changes `coverage`, and states that neither `gap` nor `discrepancy` is
  presented or counted as `coverage: "conflicts"`.

Interface only (common rule 13): number/date recognition tables, locale number parsing, code layout and tests are
backend-local; the display, layout, strings and accessibility are frontend-local.

## Impact
- Shared capability modified: `wikipedia-lookup-result` (additive). No endpoint, status, error code or other object
  changes. The finalizer receives the `wikipedia` result unchanged ("Wikipedia labels in finalizer input"), so it
  also sees the new members; that needs no change.
- backend: compute `cross_language` / `cross_language_differences` per ClaimLookup in the `wikipedia` adapter, tests.
- frontend: no Wikipedia result display exists yet; the frontend task adds a read-only Wikipedia lookup section
  (per claim, each wiki's passage verbatim and separate, its `coverage` label) that shows the cross-language state.
- project: no new integration suite; repo-ci of backend and frontend cover the change.

Based on backend @ d03c1cc4ce1f941ef37a4b715c2de081ac65f379, frontend @ d89fc94d738759e936810e659df7f798a337bd4c,
project @ 441ecbf96961128099af004da50a063f18b3345c, shared-specs @ 80eea74d1a67f7e07075f91415415fbd3dba7444.
