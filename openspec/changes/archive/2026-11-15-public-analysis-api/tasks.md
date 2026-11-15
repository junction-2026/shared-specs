# Tasks: public-analysis-api

## 1. Shared contract
- [x] 1.1 Write capability `public-analysis-api` (endpoints, PublicAnalysis object, composition, errors, rate limit).
- [x] 1.2 Classify compatibility against analysis-jobs-api, api-conventions and the result capabilities (design.md).

## 2. backend (child `backend-public-analysis-api`)
- [ ] 2.1 Route `POST /api/v1/public/analyses` and `GET /api/v1/public/analyses/{id}` with method handling.
- [ ] 2.2 Request validation and precedence (429, 413, 400 `invalid_request`, 422, 400 `missing_content`, 503).
- [ ] 2.3 Content composition and `input.source.metadata.public_api`; create via the existing engine.
- [ ] 2.4 Job to PublicAnalysis mapping (result, techniques, bot_signal, evidence, error, share_url).
- [ ] 2.5 Global token-bucket rate limits per endpoint with configuration; public base URL configuration.
- [ ] 2.6 Tests for every scenario of the capability; README/docs for integrators.
