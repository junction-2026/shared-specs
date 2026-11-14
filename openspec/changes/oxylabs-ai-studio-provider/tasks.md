# Tasks

## 1. Shared contract
- [ ] 1.1 Review and approve the `social-scraper-api` delta (provider/extraction values, run counting, configuration error, `details.provider_error_code`, consent/paywall login wall).

## 2. Backend (child `backend-ai-studio-provider`, local change `web-ai-studio-provider`)
- [ ] 2.1 `OXYLABS_API=ai_studio` with `OXYLABS_AI_STUDIO_API_KEY` and `OXYLABS_AI_STUDIO_URL`.
- [ ] 2.2 Run lifecycle (start, poll with backoff, data), cancellation and timeout.
- [ ] 2.3 JSON run with schema, mapping and sanitizing; `page_kind` handling.
- [ ] 2.4 Markdown fallback run; at most 2 runs; cache.
- [ ] 2.5 Stub-based tests; README settings table; existing provider tests unchanged.
