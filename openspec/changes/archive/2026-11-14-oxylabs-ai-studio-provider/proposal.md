# Oxylabs AI Studio page provider

Parent: junction-2026/project#34. Based on backend @ ad7c2b2d5a77e65c1c557b076a79725f9e72c1d6, frontend @ 6bc108a25fc0cc215966b06a5b713f9275f40066, project @ 441ecbf96961128099af004da50a063f18b3345c, shared-specs @ ec63dcf9de7f54316d31a827c4428b9d0b98d55a.

## Why
The team's Oxylabs plan is AI Studio. Its key is rejected (HTTP 401) by the Oxylabs Web API, so every `web` scrape currently fails with `upstream_error`. The backend gets a third page provider, `OXYLABS_API=ai_studio`, that runs the AI Studio AI Scraper. Its output reaches clients through the ScrapeResult embedded in `Job.input.source.metadata.scrape` and through scrape errors, so the values clients can see are part of the shared contract.

## What Changes
All changes are additive to `social-scraper-api`:
- `provider` gains the value `oxylabs_ai_studio`; `extraction` gains `ai_studio_json` (`markdown_fallback` is reused for AI Studio's Markdown run).
- `oxylabs_requests` counts AI Studio *runs* (started scrapes), not status polls; at most 2 per scrape.
- `platform_not_configured` names `OXYLABS_AI_STUDIO_API_KEY` when `ai_studio` is selected without a key.
- Scrape errors of a failed AI Studio run carry the provider's code in the new optional `details.provider_error_code`.
- `login_required` is also produced when AI Studio classifies the page as a login wall, or as a consent/paywall page with too little text.
- The rendering-and-retries rule (unrendered fetch first, at most 3 requests) is scoped to the HTML providers `web_api` and `web_scraper_api`; AI Studio always renders.

Not in the shared contract (backend-local): environment settings, request/poll protocol to AI Studio, JSON schema sent, sanitizing of model output, polling intervals, README, tests.

## Impact
- Backend: new provider in `internal/socialscraper/web` (local change `web-ai-studio-provider`).
- Frontend: none. It does not read `provider`, `extraction` or `oxylabs_requests` (grep at 6bc108a), and tolerant-reader rules already cover new values.
- `web_api` stays the default; deployments that do not set `OXYLABS_API=ai_studio` see no change.
