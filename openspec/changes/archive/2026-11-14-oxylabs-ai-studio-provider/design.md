# Design: Oxylabs AI Studio page provider

## Context
Canonical `social-scraper-api` (shared-specs @ ec63dcf) describes one Oxylabs page provider fetching HTML. The backend (ad7c2b2, `internal/socialscraper/web`, `internal/socialscraper/config.go`) supports `OXYLABS_API` = `web_api` | `web_scraper_api`. AI Studio (`https://api-aistudio.oxylabs.io`) is asynchronous (start run, poll, fetch data) and returns either AI-extracted JSON for a schema or Markdown, never HTML.

## Decisions
1. **Provider value.** A ScrapeResult produced by AI Studio has `provider: "oxylabs_ai_studio"`; HTML providers keep `"oxylabs"`. Clients already treat `provider` as an "includes" list.
2. **Extraction values.** `ai_studio_json` for the primary JSON run; the Markdown run reuses `markdown_fallback` because the text is produced the same way (Markdown with syntax removed).
3. **Request counting.** `oxylabs_requests` counts runs started (`POST /scrape`), not polls or data fetches. Max 2 (JSON, then Markdown). Cache hits keep `0`.
4. **Rendering.** AI Studio runs always use `render_javascript: true`, so `rendered: true` for every fresh AI Studio result.
5. **Error details.** A failed run maps to `upstream_error` with the new optional `details.provider_error_code` (string, the provider's `error_code`). Never contains credentials.
6. **Metadata.** AI Studio metadata goes into the existing members (`title`, `site_name`, `author`, `description`, `lang`, `canonical_url`, `published_at`). The model's `lang` is accepted only as a two-letter code; `host`/`domain` are always computed by the server from `final_url`. All strings are sanitized server-side (backend-local requirement).
7. **Login/consent walls.** The model's `page_kind` replaces the HTML login-wall detector for AI Studio results: `login_wall` → `login_required`; `consent_or_paywall` with text shorter than the minimum → `login_required` (message says consent or paywall).

## Compatibility classification
Every place the touched objects are used, grep of `openspec/specs` at ec63dcf:

| Change | Evidence | Class |
|---|---|---|
| `provider` value `oxylabs_ai_studio` | social-scraper-api/spec.md:247 ("values include `oxylabs`"), :218 scenario | shared-additive (new value in an includes list; tolerant reader :19-20) |
| `extraction` value `ai_studio_json` | social-scraper-api/spec.md:247, :265 | shared-additive |
| `oxylabs_requests` counts runs for AI Studio | social-scraper-api/spec.md:247, :251, :276, :283 | shared-additive (same type and meaning "requests that cost provider credits"; HTML providers unchanged) |
| Rendering/retries scoped to HTML providers | social-scraper-api/spec.md:272 | shared-additive (behaviour for existing providers unchanged; new provider has its own rule) |
| `missing_settings` may name `OXYLABS_AI_STUDIO_API_KEY` | social-scraper-api/spec.md:175, :294; analysis-jobs-api/spec.md:310 | shared-additive (new setting name in a list of names) |
| `details.provider_error_code` | social-scraper-api/spec.md:131 (details is an open object), :301 | shared-additive (new optional member) |
| `login_required` on consent/paywall | social-scraper-api/spec.md:316; analysis-jobs-api/spec.md:306, :314 | shared-additive (existing code on a new condition, only with the new provider) |

No shared-breaking change. No other spec (source-info-result, analysis-jobs-api) references `provider`, `extraction` or `oxylabs_requests`. Existing "exactly" wording in touched requirements ("exactly two provider requests") is a test-observable count, kept, and scoped to HTML providers.

## Client migration
None. Frontend at 6bc108a does not read these members. Jobs recorded before this change keep their values.

## Risks
- AI output is untrusted: mitigated by backend sanitizing (types, control/zero-width characters, 500-char metadata cap) and local host/domain computation.
- Longer worst case: 2 runs each bounded by `WEB_TIMEOUT_SECONDS` (default 150 s) fit the 360 s job scrape timeout.
