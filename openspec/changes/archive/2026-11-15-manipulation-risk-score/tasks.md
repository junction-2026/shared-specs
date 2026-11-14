## 1. Shared contract
- [ ] 1.1 Approve the new capability `manipulation-risk-score` and the additive ADDED requirements of `analysis-jobs-api` (Job risk member) and `analysis-job-events` (Risk score with the settle barrier)

## 2. backend (child `backend-risk-score`)
- [ ] 2.1 Risk configuration (defaults of the spec, validation at start-up) and bot-detector result mapping
- [ ] 2.2 Deterministic RiskScore computation at the settle barrier; `Job.risk` and `data.risk` on `analysis.ready_for_finalization`; persistence
- [ ] 2.3 Unit tests for every scenario of the spec, engine/event tests, persistence round trip

## 3. frontend (child `frontend-risk-score`)
- [ ] 3.1 Tolerant `RiskScore` types and reader
- [ ] 3.2 Risk Score section at the top of the Results screen: headline, band colour, info tooltip, dimension bars, technique list, drivers, collapsible caveats, missing-input notes
- [ ] 3.3 Catalog texts for every locale; component tests
