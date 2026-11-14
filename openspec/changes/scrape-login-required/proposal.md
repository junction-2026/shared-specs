# Proposal: scrape-login-required

Parent: junction-2026/project#19 — "Instagram and Threads scraping: honest login_required errors, Threads on threads.com".

Based on backend @ 4b3d394c7dd9a1ddea1f0c4cc96a37afd817ec23, frontend @ 3e51ec4cc5fb43c4642a142f927e9a0d99c70231, project @ 441ecbf96961128099af004da50a063f18b3345c, shared-specs @ 518903a3323a930a2dc357890e4f21df0a4641cb.

## Why
Without a logged-in session Instagram answers 404 for existing accounts and Threads serves a page without data. The scraper reports these as `account_not_found`, `rate_limited` or a generic `upstream_error`, so clients tell users that an existing account does not exist or that waiting will help. Clients need a distinct error code meaning "this platform refused an anonymous request; a login on the server side would fix it".

## What changes (shared contract, social-scraper-api)
- New scrape error code `login_required`: the platform refused an anonymous request or answered with a login wall; `details.platform` is set and `details.missing_settings` lists the names (never values) of server settings that would fix it when known (Instagram: `INSTAGRAM_SESSION_FILE`).
- `account_not_found` / `post_not_found` are produced only when the platform's answer can be trusted to mean non-existence; an anonymous Instagram 404 is `login_required`.
- `rate_limited` is reserved for throttling; a login wall is `login_required`.
- `upstream_error` is used for a Threads page only when it is neither data nor a login wall.
- The error-code requirements stay "includes" lists (tolerant reader). `login_required` flows to `Job.scrape.error.code` unchanged through analysis-jobs-api's pass-through of scraper codes (no change to that capability).

## Not in this change (backend-local, see child `backend-scrape-login-required`)
Go error constructor and internal HTTP status, Instagram 404/login-wall detection, Threads host `www.threads.com`, Threads login-wall markers, README, tests. Frontend: no work — the frontend currently has no scrape UI or error-code mapping (frontend @ 3e51ec4 has only the health check).

## Impact
Additive for clients (new value in an "includes" list). Behavioural change for some existing failure cases, classified in design.md.
