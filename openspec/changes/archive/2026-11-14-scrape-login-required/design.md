# Design: scrape-login-required

Based on backend @ 4b3d394c7dd9a1ddea1f0c4cc96a37afd817ec23, frontend @ 3e51ec4cc5fb43c4642a142f927e9a0d99c70231, shared-specs @ 518903a3323a930a2dc357890e4f21df0a4641cb.

## Error object
`login_required` uses the existing scrape error envelope (social-scraper-api "Scrape error envelope"): `{"code": "login_required", "message": <human-readable, no credentials>, "details": {"platform": <platform>, "missing_settings": [<setting name>, ...] (optional)}}`. `missing_settings` has the same meaning and shape as for `platform_not_configured` (names only, never values). Instagram without a session sets `["INSTAGRAM_SESSION_FILE"]`. Threads sets `missing_settings` only if the backend supports a Threads session setting (optional in the parent issue); otherwise it omits it.

Difference to `platform_not_configured`: that code means the platform cannot be used at all without the setting (X). `login_required` means an anonymous request was tried and refused for this content; other URLs of the platform may still work anonymously.

## Uses of the changed codes in canonical shared specs (classification)
| Place | Use | Classification |
|---|---|---|
| openspec/specs/social-scraper-api/spec.md:16 (Scraper tolerant reader) | error codes are "includes" lists; clients must not fail on unknown values | basis for additive classification |
| openspec/specs/social-scraper-api/spec.md:126-135 (Account and post error codes) | `account_not_found` / `post_not_found` meaning narrowed: not produced for an anonymous refusal | shared-additive: a new code on a new condition (the platform refusing an anonymous request was previously mis-reported); the meaning of `account_not_found` ("does not exist") is unchanged and now reported more accurately |
| openspec/specs/social-scraper-api/spec.md:137-146 (Rate limit and credential error codes) | `rate_limited` no longer produced for a login wall | shared-additive: new code on a new, now-distinguished condition; `rate_limited` keeps its meaning (throttled) |
| openspec/specs/social-scraper-api/spec.md:148-153 (Upstream error codes) | Threads "no recognizable data" scenario narrowed to pages that are not a login wall | shared-additive, same reasoning |
| openspec/specs/analysis-jobs-api/spec.md:295 (Scrape failure) | `Scrape.error.code` includes the scraper's codes other than `internal_error`, passed through with `details` | unchanged; `login_required` passes through automatically. Not a scraper-unavailable case, so it is not mapped to `scraper_unavailable` |
| openspec/specs/analysis-jobs-api/spec.md:56-63 (Job status) | failed scrape ends the job `failed` | unchanged |
| openspec/specs/analysis-job-events/spec.md:111-112 | `scrape.failed` carries `data.scrape.error.code` | unchanged; `login_required` appears there like any scrape code |

No member is removed, renamed or retyped. No shared-breaking change.

### Affected clients
- frontend @ 3e51ec4: does not read `scrape.error.code` (no scrape UI yet; `src/` has only App and health). No migration needed. A future scrape UI should show `login_required` as "This platform needs a login on our side" rather than "account doesn't exist".
- project E2E (`full-e2e`): does not hit Instagram or Threads (tests use stubs only per parent AC 6). No migration.

## Not shared
- Fetch host of Threads (`www.threads.com` for both `threads.net` and `threads.com` URLs): backend runtime. URL recognition (social-scraper-api "Instagram and Threads URLs") is unchanged and still accepts both hosts. As a consequence Threads `profile_url` and `Post.url` values built by the backend use `https://www.threads.com`; these members are URL strings without a contracted host, so this is not a contract change.
- Login-wall detection heuristics, the legacy internal HTTP status (503) of the Go error value, an optional `THREADS_SESSION_FILE`: backend-local.
- No browser or browser automation (parent hard constraint): backend-local requirement.
