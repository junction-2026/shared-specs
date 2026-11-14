## 1. Shared contract
- [ ] 1.1 Approve the new capability `propaganda-map-api` (ADDED requirements only)

## 2. backend (child `backend-propaganda-map`)
- [ ] 2.1 Derive map country and technique set when a job is done; persist them (SQLite migration + backfill of stored jobs; in-memory store derives from the working set)
- [ ] 2.2 `GET /api/v1/map/countries` and `GET /api/v1/map/countries/{country_code}/analyses` per the spec
- [ ] 2.3 Store, derivation and HTTP tests (eligibility, fallback outlet match, ordering, pagination, errors, listing exclusion, retention, restart)

## 3. frontend (child `frontend-propaganda-map`)
- [ ] 3.1 API client and tolerant types for both endpoints
- [ ] 3.2 Global propaganda map on `/explore` without `job`: sequential shading, legend, tooltip, country panel with paged list, loading/empty/error states, keyboard/touch access
- [ ] 3.3 `/explore?job=<id>` unchanged; i18n for every locale; component tests
