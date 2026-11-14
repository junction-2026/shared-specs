## 1. Shared contract
- [ ] 1.1 Approve MODIFIED "ClaimLookup object" and ADDED cross-language requirements in `wikipedia-lookup-result`

## 2. backend (child `backend-wikipedia-cross-language`)
- [ ] 2.1 Number/date extraction and normalization on verbatim passages (no LLM, no translation)
- [ ] 2.2 `cross_language` and `cross_language_differences` on every ClaimLookup per the state rules
- [ ] 2.3 Unit and adapter tests (agree, no-values agree, discrepancy, gap, single wiki, neither found, cached)

## 3. frontend (child `frontend-wikipedia-cross-language`)
- [ ] 3.1 Read-only Wikipedia lookup section with per-wiki verbatim passages and the cross-language state
- [ ] 3.2 i18n strings for all locales, rendering-safety and gap-not-conflict tests
