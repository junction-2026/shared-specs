## 1. Shared contract
- [ ] 1.1 Review and approve `country-association`, `propaganda-map-api` and `analysis-jobs-api` deltas
- [ ] 1.2 Publish to shared-specs main without archive

## 2. backend (local change backend-ai-country-association)
- [ ] 2.1 Country association LLM step, ISO table, config, isolation, cancellation/interruption
- [ ] 2.2 Persist `Job.country_association`; serialize in GET job and events
- [ ] 2.3 Multi-country map storage, aggregates, lists and MapAnalysis members
- [ ] 2.4 Backfill of stored jobs (batched, retried) and map re-derivation
- [ ] 2.5 Tests: single, several, no country, failure/invalid output, backfill, multi-country map

## 3. frontend (local change frontend-multi-country-map)
- [ ] 3.1 Read `countries`, nullable `outlet`, empty `source.url`
- [ ] 3.2 Map wording per "Map country meaning" in every locale
- [ ] 3.3 Panel items for pasted text and multi-country analyses; tests
