# social-scraper-api Specification

## Purpose
HTTP API of the social-media scraper service: given the URL of a public post or profile on a supported platform, it returns the author's profile, recent posting history and, for a post URL, the post and its comments, normalized across platforms, with typed errors for every way a scrape can fail.

## Requirements

### Requirement: Scraper endpoints and encoding
The scraper SHALL run inside the orchestrator and SHALL be reached only through jobs created with `scrape` (analysis-jobs-api); it SHALL NOT serve HTTP endpoints of its own. A ScrapeResult and a scrape error SHALL be JSON objects in UTF-8 as embedded in `Job.input.source.metadata.scrape` and `Job.scrape.error`. Timestamps SHALL be RFC 3339 strings in UTC with a `Z` suffix; durations SHALL be integer milliseconds in members ending with `_ms`.

#### Scenario: JSON response
- **WHEN** a job created with `scrape` for a Bluesky profile succeeds
- **THEN** its `input.source.metadata.scrape.scraped_at` has the form `2026-11-14T10:00:00Z` and `latency_ms` is an integer

#### Scenario: No standalone scraper endpoint
- **WHEN** a client calls `POST /scrape` or `GET /health` on the backend
- **THEN** the backend does not scrape (these are not routes of the backend)

### Requirement: Scraper tolerant reader
ScrapeResult and scrape error objects SHALL be read as "at least these members" and value lists (platforms, URL kinds, error codes, warning codes) as "includes" lists: clients MUST ignore unknown members and MUST NOT fail on unknown values. This includes values that the server no longer produces but that are still recorded on jobs created before a platform or error code was removed.

#### Scenario: Unknown request member ignored
- **WHEN** a job is created with `{"scrape": {"url": "https://bsky.app/profile/alice.bsky.social", "lang": "en"}}`
- **THEN** `lang` is ignored and the scraper scrapes the profile

#### Scenario: Unknown result member ignored
- **WHEN** a ScrapeResult embedded in `source.metadata.scrape` has a member `lang` a client does not know
- **THEN** the client ignores `lang` and reads the rest of the ScrapeResult

#### Scenario: Platform value no longer produced
- **WHEN** a client reads a job created before this revision whose `scrape.platform` is a value not in the current platform list
- **THEN** the client shows or ignores the value as an unknown platform and does not fail

### Requirement: Scrape request
A scrape SHALL take the ScrapeRequest of analysis-jobs-api, `{"url", "max_posts" (default 20), "max_comments" (default 50)}`, with defaults applied and already validated by `POST /api/v1/jobs`.

#### Scenario: Defaults applied
- **WHEN** a job is created with `{"scrape": {"url": "https://mastodon.social/@alice"}}`
- **THEN** the ScrapeResult has at most 20 `posts` and, since this is a profile URL, `comments: []`

### Requirement: URL normalization before recognition
Before recognizing a URL the scraper SHALL ignore its query string and fragment and accept hosts with an optional `www.`, `m.` or `mobile.` prefix. A recognized URL has a `platform` and a `url_kind` of `profile` or `post`.

#### Scenario: Tracking parameters ignored
- **WHEN** a job is created with `{"scrape": {"url": "https://m.bsky.app/profile/alice.bsky.social/post/3kxyz?ref=share#top"}}`
- **THEN** the ScrapeResult has `platform: bluesky` and `url_kind: post` for the post with rkey `3kxyz` by `alice.bsky.social`

### Requirement: Bluesky and Mastodon URLs
The service SHALL recognize `bluesky` URLs `bsky.app/profile/<handle or DID>` (profile) and `bsky.app/profile/<handle or DID>/post/<rkey>` (post), and `mastodon` URLs `<instance>/@<user>` and `<instance>/users/<user>` (profile), `<instance>/@<user>/<status id>` and `<instance>/users/<user>/statuses/<status id>` (post) on any host other than `bsky.app` that serves the Mastodon REST API; no other host is excluded.

#### Scenario: Mastodon status
- **WHEN** a client scrapes `https://mastodon.social/@alice/112233445566778899`
- **THEN** the response has `platform: mastodon`, `url_kind: post` and `username: alice@mastodon.social`

#### Scenario: Bluesky host never probed as Mastodon
- **WHEN** a job is created with `{"scrape": {"url": "https://bsky.app/@alice"}}`
- **THEN** the scrape fails with `error.code` `unsupported_url` and no Mastodon API request is made to `bsky.app`

### Requirement: Unsupported URLs
Any URL that is not recognized SHALL fail the scrape with `unsupported_url`, including URLs without a Bluesky or Mastodon URL shape, Bluesky paths that name no account or post (for example `bsky.app/search`) and hosts that do not serve the Mastodon REST API. URLs of other social networks SHALL get no platform-specific handling, error code, `details.platform` value or warning.

#### Scenario: Unsupported site
- **WHEN** a job is created with `{"scrape": {"url": "https://example.com/some/article"}}`
- **THEN** the scrape fails with `error.code` `unsupported_url`

#### Scenario: Unsupported social network post
- **WHEN** a job is created with `{"scrape": {"url": "https://x.com/alice/status/1790000000000000000"}}`
- **THEN** the scrape fails with `error.code` `unsupported_url`, exactly as for `https://example.com/alice/status/1790000000000000000`

#### Scenario: Facebook page not supported
- **WHEN** a job is created with `{"scrape": {"url": "https://www.facebook.com/examplenews"}}`
- **THEN** the scrape fails with `error.code` `unsupported_url`

### Requirement: ScrapeResult profile members
A successful scrape SHALL yield a ScrapeResult with at least: `platform` (includes `bluesky`, `mastodon`); `url_kind`; `username` (handle without a leading `@`; for Mastodon `<user>@<instance>`); `display_name`, `bio`, `profile_url` (string or null); `followers`, `following`, `post_count` (integer or null); `verified` (boolean or null); `scraped_at` (timestamp); `latency_ms` (integer). For `url_kind: post` the profile members describe the post's author.

#### Scenario: Unknown verification
- **WHEN** a Mastodon account is scraped
- **THEN** the ScrapeResult has `verified: null` unless the platform states it

#### Scenario: Supported platform values
- **WHEN** any scrape succeeds
- **THEN** the ScrapeResult `platform` is `bluesky` or `mastodon`

### Requirement: ScrapeResult content members
A ScrapeResult SHALL also have at least: `posts` (array of Post, the author's own recent posts, newest first, at most `max_posts`); `post` (the Post the URL names when `url_kind` is `post`, otherwise null); `comments` (array of Comment on that post, oldest first, at most `max_comments`; `[]` for `url_kind: profile`); `warnings` (array of `{"code", "message"}`, default `[]`).

#### Scenario: Profile scrape
- **WHEN** a job is created with `{"scrape": {"url": "https://bsky.app/profile/alice.bsky.social", "max_posts": 5}}` for an account with 40 posts
- **THEN** the ScrapeResult has `platform: bluesky`, `url_kind: profile`, `username: alice.bsky.social`, `post: null`, `comments: []` and 5 `posts`, newest first

#### Scenario: Post scrape
- **WHEN** a job is created with the URL of a Mastodon status that has 3 replies
- **THEN** the ScrapeResult has `url_kind: post`, `post` set to that status, 3 `comments` oldest first and the author's recent `posts`

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

### Requirement: Scrape error envelope
A failed scrape SHALL yield an error object with at least `{"code": <string>, "message": <string>, "details": <object, optional>}`; `details.platform` SHALL be set whenever the platform is known. `message` is human-readable and MUST NOT contain stack traces, tokens, cookies or other credentials. An unexpected internal failure, including a panic in a platform module, SHALL yield `internal_error` and SHALL NOT crash the orchestrator.

#### Scenario: Unexpected exception
- **WHEN** a platform module panics during a scrape
- **THEN** the scrape fails with `internal_error` (surfaced to clients as analysis-jobs-api `scraper_unavailable`), the message contains no stack trace and the orchestrator keeps serving

### Requirement: Request error codes
Scrape error codes SHALL include `unsupported_url` (not a recognized post or profile URL, Unsupported URLs).

#### Scenario: Facebook personal profile
- **WHEN** a job is created with `{"scrape": {"url": "https://www.facebook.com/profile.php?id=100000000000001"}}`
- **THEN** the scrape fails with `error.code` `unsupported_url`, not `unsupported_account_type` (no longer produced)

### Requirement: Partial scrape results and warnings
When the requested profile or post was scraped but secondary data was not (comments, part of the history, or members the platform omitted), the scrape SHALL succeed, set those members to `[]` or null, and add a warning. Warning codes include `comments_unavailable`, `history_unavailable`, `history_truncated`, `partial_parse`. A missing key in platform data SHALL NOT cause `internal_error`.

#### Scenario: Unparseable history item
- **WHEN** a Mastodon instance returns the profile and an account status list in which one item cannot be parsed
- **THEN** the scrape succeeds with the parseable `posts` and a warning with code `partial_parse`

#### Scenario: Comments not available
- **WHEN** a Mastodon instance returns the requested status but its replies cannot be fetched
- **THEN** the scrape succeeds with `comments: []` and a warning with code `comments_unavailable`

### Requirement: Missing and private content error codes
Scrape error codes SHALL include `account_not_found` and `post_not_found` when the account or post does not exist or was deleted, and `account_private` when the account or post is not public. They SHALL be produced only when the platform's answer reliably means non-existence or non-public content.

#### Scenario: Private Mastodon account
- **WHEN** a job scrapes a Mastodon profile whose instance refuses the account lookup with HTTP 401 or 403
- **THEN** the scrape fails with `error.code` `account_private` and `details.platform` `mastodon`

#### Scenario: Missing account
- **WHEN** a job scrapes `https://bsky.app/profile/does-not-exist.bsky.social`
- **THEN** the scrape fails with `error.code` `account_not_found`

#### Scenario: Missing Mastodon status
- **WHEN** a Mastodon instance answers the status request with HTTP 404 and a JSON body
- **THEN** the scrape fails with `error.code` `post_not_found` and `details.platform` `mastodon`

### Requirement: Rate limit and configuration error codes
Scrape error codes SHALL include `rate_limited` (the platform throttled the scraper, for example HTTP 429; `details.retry_after_s` set when the wait is known) and `platform_not_configured` (a recognized platform has no scraper module on this server or needs credentials that are not configured; `details.missing_settings`, when present, lists the names, never values, of missing settings). Bluesky and Mastodon need no credentials.

#### Scenario: Rate limited
- **WHEN** a Mastodon instance answers HTTP 429 with `Retry-After: 90`
- **THEN** the scrape fails with `error.code` `rate_limited`, `details.platform` `mastodon` and `details.retry_after_s` 90

#### Scenario: No credentials needed
- **WHEN** a job scrapes a public Bluesky or Mastodon URL on a server with no platform credentials configured
- **THEN** the scrape does not fail with `platform_not_configured`

### Requirement: Upstream and internal error codes
Scrape error codes SHALL include `upstream_error` (the platform answered with an error or with data that could not be parsed into the requested profile or post), `upstream_timeout` (the platform did not answer within the scraper's upstream timeout) and `internal_error`.

#### Scenario: Unparseable answer
- **WHEN** a Mastodon instance answers the status request with JSON that has no `account`
- **THEN** the scrape fails with `error.code` `upstream_error`, `details.platform` `mastodon` and a human-readable `message`
