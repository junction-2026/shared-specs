## Purpose
HTTP API of the social-media scraper service: given the URL of a public post or profile on a supported platform, it returns the author's profile, recent posting history and, for a post URL, the post and its comments, normalized across platforms, with typed errors for every way a scrape can fail.

## ADDED Requirements

### Requirement: Scraper endpoints and encoding
The scraper service SHALL serve `GET /health` and `POST /scrape` at the root of its base URL. Request and response bodies SHALL be JSON in UTF-8 with `Content-Type: application/json`. Timestamps SHALL be RFC 3339 strings in UTC with a `Z` suffix; durations SHALL be integer milliseconds in members ending with `_ms`.

#### Scenario: JSON response
- **WHEN** an authenticated client posts a valid body to `/scrape`
- **THEN** the response has `Content-Type: application/json` and `scraped_at` of the form `2026-11-14T10:00:00Z`

### Requirement: Scraper tolerant reader
Response objects of the scraper SHALL be read as "at least these members" and value lists (platforms, URL kinds, error codes, warning codes) as "includes" lists: clients MUST ignore unknown members and MUST NOT fail on unknown values. The service SHALL ignore unknown members in request bodies.

#### Scenario: Unknown request member ignored
- **WHEN** an authenticated client posts `{"url": "https://bsky.app/profile/alice.bsky.social", "lang": "en"}` to `/scrape`
- **THEN** the service ignores `lang` and scrapes the profile

### Requirement: Health endpoint
`GET /health` SHALL respond 200 with at least `{"status": "ok"}` without requiring authentication, and SHALL NOT contact any social-media platform.

#### Scenario: Health without token
- **WHEN** a client calls `GET /health` without an `Authorization` header
- **THEN** the status is 200 and the body has `status: ok`

### Requirement: Bearer authentication
`POST /scrape` SHALL require the header `Authorization: Bearer <token>` matching the service's configured token. A missing, malformed or wrong token SHALL yield 401 `unauthorized` with the header `WWW-Authenticate: Bearer`, before the body is read or any platform is contacted. The token and platform credentials MUST NOT appear in any response body, response header or log line.

#### Scenario: Missing token
- **WHEN** a client posts a valid body to `/scrape` without an `Authorization` header
- **THEN** the status is 401 with `error.code` `unauthorized` and the header `WWW-Authenticate: Bearer`

#### Scenario: Wrong token
- **WHEN** a client posts to `/scrape` with `Authorization: Bearer wrong`
- **THEN** the status is 401 with `error.code` `unauthorized`

### Requirement: Scrape request
`POST /scrape` SHALL accept `{"url": <string, required>, "max_posts": <integer 1–100, default 20>, "max_comments": <integer 0–200, default 50>}`. `url` MUST be an absolute `http` or `https` URL of at most 2048 characters.

#### Scenario: Defaults applied
- **WHEN** a client posts `{"url": "https://mastodon.social/@alice"}`
- **THEN** the service returns at most 20 posts and, since this is a profile URL, `comments: []`

### Requirement: Scrape request validation
A body that is not valid JSON SHALL yield 400 `invalid_request`. A missing or non-string `url`, a non-absolute or non-http(s) `url`, a `url` over 2048 characters, or `max_posts`/`max_comments` of the wrong type or out of range SHALL yield 422 `validation_failed` with `details.fields` mapping each offending member to a message.

#### Scenario: max_posts out of range
- **WHEN** a client posts `{"url": "https://bsky.app/profile/alice.bsky.social", "max_posts": 0}`
- **THEN** the status is 422 with `error.code` `validation_failed` and `error.details.fields` has the key `max_posts`

### Requirement: URL normalization before recognition
Before recognizing a URL the service SHALL ignore its query string and fragment and accept hosts with an optional `www.`, `m.` or `mobile.` prefix. A recognized URL has a `platform` and a `url_kind` of `profile` or `post`.

#### Scenario: Tracking parameters ignored
- **WHEN** a client posts `{"url": "https://mobile.x.com/alice/status/1790000000000000000?s=20"}` and X credentials are configured
- **THEN** the response has `platform: twitter`, `url_kind: post` and `post.id` `1790000000000000000`

### Requirement: Bluesky and Mastodon URLs
The service SHALL recognize `bluesky` URLs `bsky.app/profile/<handle or DID>` (profile) and `bsky.app/profile/<handle or DID>/post/<rkey>` (post), and `mastodon` URLs `<instance>/@<user>` and `<instance>/users/<user>` (profile), `<instance>/@<user>/<status id>` and `<instance>/users/<user>/statuses/<status id>` (post) on any host that is not another listed platform and serves the Mastodon REST API.

#### Scenario: Mastodon status
- **WHEN** a client scrapes `https://mastodon.social/@alice/112233445566778899`
- **THEN** the response has `platform: mastodon`, `url_kind: post` and `username: alice@mastodon.social`

### Requirement: Instagram and Threads URLs
The service SHALL recognize `instagram` URLs `instagram.com/<user>` (profile), `instagram.com/p/<shortcode>` and `instagram.com/reel/<shortcode>` (post), and `threads` URLs `threads.net/@<user>` and `threads.com/@<user>` (profile) and `<threads host>/@<user>/post/<code>` (post).

#### Scenario: Instagram reel
- **WHEN** a client scrapes `https://www.instagram.com/reel/C1a2b3c4d5/`
- **THEN** the response has `platform: instagram` and `url_kind: post`

### Requirement: Facebook and X URLs
The service SHALL recognize `facebook` URLs `facebook.com/<page>` (page profile) and `facebook.com/<page>/posts/<id>` (post), public pages only, and `twitter` URLs `twitter.com/<user>` and `x.com/<user>` (profile) and `<host>/<user>/status/<id>` (post).

#### Scenario: Facebook page
- **WHEN** a client scrapes the public page `https://www.facebook.com/examplenews`
- **THEN** the response has `platform: facebook` and `url_kind: profile`

### Requirement: Unsupported URLs
Any URL that is not recognized, including platform paths that name no account or post (for example `x.com/explore`, `x.com/i/...`, `instagram.com/explore/...`) and hosts that do not serve the Mastodon REST API, SHALL yield 422 `unsupported_url`.

#### Scenario: Unsupported site
- **WHEN** a client posts `{"url": "https://example.com/some/article"}`
- **THEN** the status is 422 with `error.code` `unsupported_url`

### Requirement: ScrapeResult profile members
A successful scrape SHALL respond 200 with a ScrapeResult that has at least: `platform`; `url_kind`; `username` (handle without a leading `@`; for Mastodon `<user>@<instance>`); `display_name`, `bio`, `profile_url` (string or null); `followers`, `following`, `post_count` (integer or null when not exposed); `verified` (boolean or null when unknown); `scraped_at` (timestamp); `latency_ms` (integer). For `url_kind: post` the profile members describe the post's author.

#### Scenario: Unknown verification
- **WHEN** a Mastodon account is scraped
- **THEN** the ScrapeResult has `verified: null` unless the platform states it

### Requirement: ScrapeResult content members
A ScrapeResult SHALL also have at least: `posts` (array of Post, the author's own recent posts, newest first, at most `max_posts`); `post` (the Post the URL names when `url_kind` is `post`, otherwise null); `comments` (array of Comment on that post, oldest first, at most `max_comments`; `[]` for `url_kind: profile`); `warnings` (array of `{"code", "message"}`, default `[]`).

#### Scenario: Profile scrape
- **WHEN** a client posts `{"url": "https://bsky.app/profile/alice.bsky.social", "max_posts": 5}` for an account with 40 posts
- **THEN** the response has `platform: bluesky`, `url_kind: profile`, `username: alice.bsky.social`, `post: null`, `comments: []` and 5 `posts`, newest first

#### Scenario: Post scrape
- **WHEN** a client posts the URL of a Mastodon status that has 3 replies
- **THEN** the response has `url_kind: post`, `post` set to that status, 3 `comments` oldest first and the author's recent `posts`

### Requirement: Post and Comment objects
A Post SHALL have at least: `id` (string, platform id), `text` (plain text, `""` when the post has no text), `created_at` (timestamp or null), `url` (string or null), and `likes`, `replies`, `reposts` (integer or null when not exposed). A Comment SHALL have at least the Post members plus `author` (`{"username", "display_name"}`, `display_name` string or null) and `in_reply_to_id` (id of the post or comment it answers, or null when unknown).

#### Scenario: Counter not exposed
- **WHEN** a platform does not expose repost counts for a post
- **THEN** that Post has `reposts: null`, not `0`

### Requirement: Plain-text normalization
`text` of every Post and Comment and the profile `bio` SHALL be plain text: HTML markup removed (for example Mastodon `content`), HTML entities decoded, `<br>` and paragraph boundaries turned into `\n`, and leading and trailing whitespace trimmed. Link text SHALL be kept.

#### Scenario: Mastodon HTML stripped
- **WHEN** a Mastodon status has content `<p>Hello &amp; <a href="https://x.y">welcome</a></p><p>Bye</p>`
- **THEN** the Post `text` is `Hello & welcome\nBye`

### Requirement: Partial results and warnings
When the requested profile or post was scraped but secondary data was not (comments, part of the history, or members the platform omitted), the service SHALL respond 200, set those members to `[]` or null, and add a warning. Warning codes include `comments_unavailable`, `history_unavailable`, `history_truncated`, `partial_parse`. A missing key in platform data SHALL NOT cause a 500.

#### Scenario: Threads structure changed
- **WHEN** the Threads page data lacks the follower count key but contains the profile and posts
- **THEN** the response is 200 with `followers: null` and a warning with code `partial_parse`

#### Scenario: Comments not available
- **WHEN** Instagram returns a post but refuses its comments without login
- **THEN** the response is 200 with `comments: []` and a warning with code `comments_unavailable`

### Requirement: Scrape error envelope
Every error response SHALL have the body `{"error": {"code": <string>, "message": <string>, "details": <object, optional>}}`; `details.platform` SHALL be set whenever the platform is known. `message` is human-readable and MUST NOT contain stack traces, tokens, cookies or other credentials. An unexpected internal failure SHALL yield 500 `internal_error` with this envelope.

#### Scenario: Unexpected exception
- **WHEN** a platform module raises an unexpected exception
- **THEN** the status is 500 with `error.code` `internal_error` and the body contains no stack trace

### Requirement: Request error codes
`POST /scrape` error codes SHALL include `unauthorized` (401), `invalid_request` (400), `validation_failed` (422), `unsupported_url` (422, not a recognized post or profile URL) and `unsupported_account_type` (422, an account type that is not scraped, including Facebook personal profiles with `details.account_type` `personal_profile`).

#### Scenario: Facebook personal profile
- **WHEN** a client scrapes `https://www.facebook.com/profile.php?id=100000000000001`
- **THEN** the status is 422 with `error.code` `unsupported_account_type` and `details.account_type` `personal_profile`

### Requirement: Account and post error codes
`POST /scrape` error codes SHALL include `account_not_found` (404) and `post_not_found` (404) when the account or post does not exist or was deleted, and `account_private` (403) when the account or post is not public.

#### Scenario: Private Instagram account
- **WHEN** a client scrapes a private Instagram profile
- **THEN** the status is 403 with `error.code` `account_private` and `details.platform` `instagram`

#### Scenario: Missing account
- **WHEN** a client scrapes `https://bsky.app/profile/does-not-exist.bsky.social`
- **THEN** the status is 404 with `error.code` `account_not_found`

### Requirement: Rate limit and credential error codes
`POST /scrape` error codes SHALL include `rate_limited` (429, the platform throttled the service; `Retry-After` header and `details.retry_after_s` set when the wait is known) and `platform_not_configured` (503, credentials the platform needs are not configured, including X without `TWITTER_AUTH_TOKEN` and `TWITTER_CT0`; `details.missing_settings` lists the names, never values, of missing settings).

#### Scenario: X credentials missing
- **WHEN** `TWITTER_AUTH_TOKEN` is not set and a client scrapes `https://x.com/alice`
- **THEN** the status is 503 with `error.code` `platform_not_configured`, `details.platform` `twitter` and `details.missing_settings` containing `TWITTER_AUTH_TOKEN`

#### Scenario: Rate limited
- **WHEN** Instagram throttles the service
- **THEN** the status is 429 with `error.code` `rate_limited`

### Requirement: Upstream error codes
`POST /scrape` error codes SHALL include `upstream_error` (502, the platform answered with an error or with data that could not be parsed into the requested profile or post), `upstream_timeout` (504, the platform did not answer in time) and `internal_error` (500).

#### Scenario: Unparseable page
- **WHEN** the Threads page no longer contains any recognizable profile data
- **THEN** the status is 502 with `error.code` `upstream_error` and `details.platform` `threads`
