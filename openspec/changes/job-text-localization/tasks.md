## 1. Shared contract
- [ ] 1.1 Approve new capability `job-text-localization` and MODIFIED technique-classifier-result "Plain-language presentation"

## 2. backend (child `backend-job-text-localization`)
- [ ] 2.1 Route `GET /api/v1/jobs/{id}/localization` with validation, 404/409/400 errors
- [ ] 2.2 Batched translation of `user_text` and LLM `explanation`s via the deployment's translation provider, timeout, no secrets in errors
- [ ] 2.3 Fixed translations of the orchestrator insufficient-evidence text for en, fr, ar, de, fi
- [ ] 2.4 Per (job, language) cache of successful texts; `unavailable` not cached; singleflight for concurrent requests
- [ ] 2.5 Tests: statuses, source-language rules, no job mutation / no events, cache, failure paths; README/API docs

## 3. frontend (children `frontend-result-localization`, `frontend-i18n-audit-rtl`)
- [ ] 3.1 Technique/LLM-label catalog keyed by stable ids in 5 languages; client-side why template; endpoint client
- [ ] 3.2 Localized explanation rendering with machine-translation / unavailable markers; original evidence verbatim and isolated
- [ ] 3.3 Static string audit and RTL of all other views
