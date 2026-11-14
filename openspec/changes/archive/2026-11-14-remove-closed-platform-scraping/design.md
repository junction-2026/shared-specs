## Context

Canonical `social-scraper-api` (shared-specs @ 2bda20a) lists five platforms and has requirements that apply only to Instagram, Threads and X. The backend (@ 34e1c51) implements them in `internal/socialscraper/{instagram,threads,x}`, keeps a `listedHosts` set in `internal/socialscraper/urls.go` (`bsky.app`, `instagram.com`, `threads.net`, `threads.com`, `facebook.com`, `fb.com`, `fb.watch`, `twitter.com`, `x.com`) that is never probed as a Mastodon instance, and registers the modules in `cmd/orchestrator/scraper.go`.

## Decisions

### D1: Only `bsky.app` stays excluded from Mastodon recognition

The issue leaves to the planner whether the hosts of removed platforms stay excluded from Mastodon probing. Decision: they do not. The only host excluded from Mastodon recognition is `bsky.app`, because it is a supported platform. Every other host, `instagram.com`, `threads.net`, `threads.com`, `facebook.com`, `fb.com`, `fb.watch`, `twitter.com` and `x.com` included, goes through the same rules as an unknown host:

- A path without a Mastodon shape (`/@<user>`, `/@<user>/<digits>`, `/users/<user>`, `/users/<user>/statuses/<digits>`) fails with `unsupported_url` and no network request. This covers nearly all real links to the removed platforms: `x.com/<user>`, `x.com/<user>/status/<id>`, `instagram.com/<user>`, `instagram.com/p/<code>`, `instagram.com/reel/<code>`, `facebook.com/<page>`, `facebook.com/profile.php?id=…`, `fb.watch/<id>/`.
- A path with a Mastodon shape (in practice `threads.net/@<user>` and `threads.com/@<user>`) is probed as a Mastodon instance, like `example.com/@alice` is today. The outcome is whatever the generic Mastodon rules give for that host's answer, usually `unsupported_url` (redirect or non-JSON answer).

Why: this meets the acceptance criterion "no platform-specific code path, error or warning", and it removes a host list that would otherwise have to be maintained. Keeping a deny-list "because those hosts cannot serve the Mastodon API" would be platform-specific code for platforms we no longer support. The cost is one outbound request for Mastodon-shaped Threads links. That request is already bounded by the Mastodon host-safety rules (no redirects, https only, same host).

Rejected alternative: keep the removed hosts in a "known non-Mastodon hosts" list. It would make Threads links fail without a request, but it keeps platform-specific code that the issue asks to remove.

### D2: `login_required` removed, `platform_not_configured` kept generic

`login_required` was produced only by the Instagram and Threads modules (backend `errors.go` `LoginRequired` callers at 34e1c51: `instagram/instagram.go:176,178`, `threads/threads.go:345`). Its two requirements are removed. `platform_not_configured` is also produced by the backend core for a recognized platform without a registered module (`internal/socialscraper/scraper.go:38`), so it stays in the error-code list without the X example. Both lists are "includes" lists: clients already handle unknown and missing codes.

### D3: No change to request or response shapes

No member is added, removed or renamed. `platform` keeps its type (string) and its "includes" semantics. The change only narrows which values the server produces and which URLs it recognizes.

## Compatibility classification

Usages found with `grep -rn` in canonical shared specs @ 2bda20a:

| Item | Where used | Change | Class |
|---|---|---|---|
| `ScrapeResult.platform` value list | `social-scraper-api/spec.md:70`; mirrored by `Scrape.platform` (`analysis-jobs-api/spec.md:263`) and `Job.input.source.platform` (`analysis-jobs-api/spec.md:288`) | `instagram`, `threads`, `twitter` no longer produced | shared-breaking (an existing case changes outcome), wire-compatible under the tolerant-reader rule `social-scraper-api/spec.md:20` |
| Recognition of Instagram/Threads/X URLs | `social-scraper-api/spec.md:41-42,51-56,159-164` | those URLs now fail with `unsupported_url` (or the generic Mastodon outcome, D1) | shared-breaking: an existing case changes status |
| Facebook / removed-host exclusion from Mastodon probing | `social-scraper-api/spec.md:45,59` | exclusion limited to `bsky.app` | shared-breaking for Mastodon-shaped paths on those hosts only (D1) |
| `login_required` error code | `social-scraper-api/spec.md:127,142,166-194`; passed through by `analysis-jobs-api/spec.md:295` ("the scraper's error codes") | no longer produced | shared-breaking (removed value), wire-compatible: `Scrape.error.code` is an "includes" list |
| `platform_not_configured` error code | `social-scraper-api/spec.md:142-146,186` | kept, generic description, X example dropped | no wire change |
| `details.missing_settings` | `social-scraper-api/spec.md:142,171,186-194` | stays defined for `platform_not_configured` only | no wire change |
| Scenarios in `analysis-jobs-api` | `analysis-jobs-api/spec.md:298-303` | rewritten to Mastodon and an X URL failing with `unsupported_url` | scenario-only |
| `analysis-jobs-api/spec.md:237,245` (`https://x.com/alice` in request validation scenarios) | validation only, independent of platform support | unchanged | none |
| `analysis-job-events` (`spec.md:104-105`, Bluesky only) | — | unchanged | none |

Affected clients and migration:

- **frontend** @ 1abe19a: `grep -rniE "instagram|twitter|threads|login_required|platform_not_configured|missing_settings|scrape" frontend/src` finds nothing. It shows no scrape platform or scrape error code specially. No migration.
- **project** @ 441ecbf: no scraping test (the `full-e2e` suite is a placeholder). No migration.
- **Jobs created before the change** keep the `platform` and `scrape.error.code` they were given (for example `twitter` or `login_required`). Clients read them under the tolerant-reader rule. No data migration.

## Risks / Trade-offs

- [Threads links are probed as Mastodon] → bounded by the existing Mastodon host-safety rules. The answer is usually a redirect or HTML, which is `unsupported_url`. An unusual answer (for example 403) gives the same code it would for any other host.
- [Users lose X/Instagram/Threads scraping] → intended. The `unsupported_url` message stays generic.
