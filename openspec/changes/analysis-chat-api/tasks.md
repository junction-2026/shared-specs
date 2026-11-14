## 1. Shared contract
- [ ] 1.1 Approve new capability `analysis-chat-api` (`POST /api/v1/jobs/{id}/chat`)

## 2. backend (child `backend-analysis-chat`)
- [ ] 2.1 Route, ChatRequest validation (422 paths), eligibility 404/409 `job_not_completed`
- [ ] 2.2 OpenAI-compatible upstream client: config/secret, timeout → 504, failures → 503, no secrets/URL in errors or logs
- [ ] 2.3 VEIL persona system prompt, grounding builder with size caps, language hint, history window, reply cap
- [ ] 2.4 Per-job rate limit, one in-flight per job, global concurrency cap → 429 with Retry-After
- [ ] 2.5 Tests with a fake upstream server; README (config, container networking, key rotation note)

## 3. frontend (child `frontend-ask-veil-chat`)
- [ ] 3.1 `postJobChat` client + tolerant types + error copy for the new codes
- [ ] 3.2 `/jobs/:id/ask` real chat (context bar, thread, composer, loading, errors with retry, disabled states); Results link
- [ ] 3.3 nginx chat proxy location with 120 s read timeout
- [ ] 3.4 i18n en/de/fr/fi/ar/ru (only `ask.ts` namespace files), mock list, tests
