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
Before recognizing a URL the scraper SHALL ignore its query string and fragment and accept hosts with an optional `www.`, `m.` or `mobile.` prefix. A recognized URL has a `platform` and a `url_kind`; `url_kind` values include `profile`, `post` and `page`. Normalization applies to recognition only: a `web` page SHALL be fetched at the requested URL with its query string and without its fragment.

#### Scenario: Tracking parameters ignored
- **WHEN** a job is created with `{"scrape": {"url": "https://m.bsky.app/profile/alice.bsky.social/post/3kxyz?ref=share#top"}}`
- **THEN** the ScrapeResult has `platform: bluesky` and `url_kind: post` for the post with rkey `3kxyz` by `alice.bsky.social`

#### Scenario: Query string kept for pages
- **WHEN** a job scrapes `https://news.example.org/article.php?id=42#comments` as a `web` page
- **THEN** the provider is asked for `https://news.example.org/article.php?id=42` and the ScrapeResult `requested_url` is that URL

### Requirement: Bluesky and Mastodon URLs
The service SHALL recognize `bluesky` URLs `bsky.app/profile/<handle or DID>` (profile) and `bsky.app/profile/<handle or DID>/post/<rkey>` (post), and `mastodon` URLs `<instance>/@<user>` and `<instance>/users/<user>` (profile), `<instance>/@<user>/<status id>` and `<instance>/users/<user>/statuses/<status id>` (post) on any host other than `bsky.app` that serves the Mastodon REST API; no other host is excluded.

#### Scenario: Mastodon status
- **WHEN** a client scrapes `https://mastodon.social/@alice/112233445566778899`
- **THEN** the response has `platform: mastodon`, `url_kind: post` and `username: alice@mastodon.social`

#### Scenario: Bluesky host never probed as Mastodon
- **WHEN** a job is created with `{"scrape": {"url": "https://bsky.app/@alice"}}`
- **THEN** no Mastodon API request is made to `bsky.app` and the URL is scraped as a `web` page

### Requirement: Unsupported URLs
A URL SHALL fail the scrape with `unsupported_url`, before any request to a platform or to the page provider, when it is not an absolute `http` or `https` URL, cannot be parsed, contains userinfo, is longer than 2,000 characters, or names a local host (Local hosts not scraped). Every other URL is recognized: as `bluesky` or `mastodon` when it has their shape, otherwise as a `web` page. Other social networks SHALL get no platform-specific handling, error code or warning.

#### Scenario: Non-http scheme
- **WHEN** the scraper is given `ftp://example.com/a`
- **THEN** the scrape fails with `error.code` `unsupported_url` and no provider request is made

#### Scenario: Local and private hosts
- **WHEN** a job scrapes `http://127.0.0.1/admin`, `http://localhost/`, `http://10.0.0.5/x` or `http://[::1]/`
- **THEN** each scrape fails with `error.code` `unsupported_url` and no provider request is made

#### Scenario: Userinfo
- **WHEN** a job scrapes `https://user:secret@news.example.org/a`
- **THEN** the scrape fails with `error.code` `unsupported_url`, no provider request is made and the error `message` does not contain `secret`

#### Scenario: Too long
- **WHEN** a job scrapes an https URL of 2,001 characters
- **THEN** the scrape fails with `error.code` `unsupported_url`

#### Scenario: Unsupported social network post
- **WHEN** a job is created with `{"scrape": {"url": "https://x.com/alice/status/1790000000000000000"}}`
- **THEN** the URL is scraped as a `web` page, exactly as `https://example.com/alice/status/1790000000000000000` would be

#### Scenario: Unsupported site
- **WHEN** a job is created with `{"scrape": {"url": "https://example.com/some/article"}}`
- **THEN** the URL is scraped as a `web` page and the scrape does not fail with `unsupported_url`

#### Scenario: Facebook page not supported
- **WHEN** a job is created with `{"scrape": {"url": "https://www.facebook.com/examplenews"}}`
- **THEN** the URL is scraped as a `web` page with no Facebook-specific handling; a login wall fails with `login_required` (Web page login wall)

### Requirement: ScrapeResult profile members
A successful scrape SHALL yield a ScrapeResult with at least: `platform` (includes `bluesky`, `mastodon`, `web`); `url_kind`; `username` (handle without a leading `@`; for Mastodon `<user>@<instance>`; null for `page`); `display_name`, `bio`, `profile_url` (string or null); `followers`, `following`, `post_count` (integer or null); `verified` (boolean or null); `scraped_at` (timestamp); `latency_ms` (integer). For `post` they describe the post's author; for `page` see Page profile members.

#### Scenario: Unknown verification
- **WHEN** a Mastodon account is scraped
- **THEN** the ScrapeResult has `verified: null` unless the platform states it

#### Scenario: Supported platform values
- **WHEN** any scrape succeeds
- **THEN** the ScrapeResult `platform` is `bluesky`, `mastodon` or `web`

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
Scrape error codes SHALL include `unsupported_url` (a URL that cannot be scraped, Unsupported URLs).

#### Scenario: Facebook personal profile
- **WHEN** a job is created with `{"scrape": {"url": "https://www.facebook.com/profile.php?id=100000000000001"}}`
- **THEN** the URL is scraped as a `web` page and the scrape does not fail with `unsupported_url` or `unsupported_account_type` (no longer produced)

#### Scenario: Malformed URL
- **WHEN** the scraper is given `https://exa mple.com/a`
- **THEN** the scrape fails with `error.code` `unsupported_url`

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

### Requirement: Page profile members
For `url_kind: page`, every profile member of the ScrapeResult (`username`, `display_name`, `bio`, `profile_url`, `followers`, `following`, `post_count`, `verified`) SHALL be null; the page author is in `author` (Web page metadata members).

#### Scenario: Page has no profile
- **WHEN** a `web` page scrape succeeds
- **THEN** the ScrapeResult has `username: null`, `display_name: null`, `followers: null` and `verified: null`

### Requirement: Local hosts not scraped
A URL whose host is `localhost`, a name ending in `.localhost`, or an IP literal in a private, loopback, link-local or unspecified range (IPv4 `10/8`, `172.16/12`, `192.168/16`, `127/8`, `169.254/16`, `0/8`; IPv6 `::1`, `::`, `fc00::/7`, `fe80::/10`, and IPv4-mapped forms of those IPv4 ranges) SHALL fail with `unsupported_url` without any provider request. Public IP literals are scraped as `web` pages.

#### Scenario: IPv4-mapped loopback
- **WHEN** a job scrapes `http://[::ffff:127.0.0.1]/`
- **THEN** the scrape fails with `error.code` `unsupported_url` and no provider request is made

### Requirement: Mastodon probe fallback
A URL with a Mastodon shape whose host does not serve the Mastodon REST API SHALL be scraped as a `web` page in the same scrape instead of failing with `unsupported_url`. Mastodon errors from a host that does serve the API (for example `account_not_found`) are kept.

#### Scenario: Blog profile that is not Mastodon
- **WHEN** a job scrapes `https://blog.example.com/@alice` and `blog.example.com` does not serve the Mastodon REST API
- **THEN** the URL is scraped as a `web` page and a successful ScrapeResult has `platform: web` and `url_kind: page`

### Requirement: Web page fallback
Every URL that passes the checks of Unsupported URLs and is not a Bluesky or Mastodon URL SHALL be recognized as `platform: web`, `url_kind: page` and scraped by fetching the page through the server's page provider (Oxylabs). A `web` scrape makes no request to the target site from the server itself.

#### Scenario: News article
- **WHEN** a job scrapes `https://www.dw.com/en/some-article/a-12345678` on a server with the page provider configured
- **THEN** the ScrapeResult has `platform: web`, `url_kind: page` and `provider: oxylabs`

#### Scenario: Bluesky still a platform
- **WHEN** a job scrapes `https://bsky.app/profile/alice.bsky.social/post/3kxyz`
- **THEN** the ScrapeResult has `platform: bluesky` and no provider request is made

### Requirement: Web page result members
A ScrapeResult with `url_kind: page` SHALL have, besides the profile members, at least: `text` (string, Web page text); `requested_url` (the fetched URL); `final_url` (URL after redirects when the provider reports it, else `requested_url`); `host` (lower-case host of `final_url` without `www.`); `domain` (registered domain of `host` per the public suffix list, or null for an IP host); `posts: []`, `post: null`, `comments: []`, `warnings` (default `[]`).

#### Scenario: Domain fields
- **WHEN** a page is fetched from `https://www.bbc.co.uk/news/articles/abc`
- **THEN** the ScrapeResult has `host: "bbc.co.uk"` and `domain: "bbc.co.uk"`

### Requirement: Web page metadata members
A `page` ScrapeResult SHALL have at least: `site_name`, `title`, `description`, `author` (string or null, from the page's structured data, Open Graph or HTML meta tags); `lang` (language tag such as `en-US`, or null); `canonical_url` (absolute http(s) URL the page declares canonical, or null); `published_at` (UTC timestamp, null when absent or unparseable); `word_count` (integer, whitespace-separated words of `text`).

#### Scenario: Article metadata
- **WHEN** the provider returns an article page whose JSON-LD has `headline` `Election results`, `author.name` `Jane Doe`, `datePublished` `2026-11-13T08:30:00+01:00`, whose `og:site_name` is `DW` and whose `<html lang>` is `en`
- **THEN** the ScrapeResult has `title: "Election results"`, `author: "Jane Doe"`, `published_at: "2026-11-13T07:30:00Z"`, `site_name: "DW"` and `lang: "en"`

#### Scenario: Unparseable date
- **WHEN** the page declares `article:published_time` `yesterday`
- **THEN** the ScrapeResult has `published_at: null` and the scrape succeeds

#### Scenario: Locale as language
- **WHEN** the page has no `<html lang>` and `og:locale` `de_DE`
- **THEN** the ScrapeResult has `lang: "de-DE"`

### Requirement: Web page fetch members
A `page` ScrapeResult SHALL have at least: `truncated` (boolean); `extraction` (values include `trafilatura` and `markdown_fallback`); `rendered` (boolean, true when fetched with JavaScript rendering); `cached` (boolean, true when served from the server's page cache); `provider` (values include `oxylabs`); `oxylabs_requests` (integer, requests sent to the provider for this scrape, `0` when `cached`).

#### Scenario: Fetch members of a fresh scrape
- **WHEN** a page is scraped for the first time and one unrendered fetch yields its text
- **THEN** the ScrapeResult has `rendered: false`, `cached: false`, `provider: "oxylabs"`, `oxylabs_requests: 1` and `extraction: "trafilatura"`

### Requirement: Web page text
`text` SHALL be the page's main content as plain text: paragraphs kept; navigation, footers, comments and other boilerplate removed; entities decoded; paragraph boundaries as `\n`; trimmed. `text` SHALL be at most 20,000 characters: a longer text is cut at the last whitespace at or before character 20,000 with `truncated: true`, otherwise `truncated: false`.

#### Scenario: Boilerplate removed
- **WHEN** the provider returns an article page with a navigation menu `Home World Business` and a footer `© 2026 Example Media`
- **THEN** `text` contains the article paragraphs and contains neither `Home World Business` nor `© 2026 Example Media`

#### Scenario: Long article
- **WHEN** the main content has 35,000 characters
- **THEN** `text` has at most 20,000 characters, ends at a word boundary, and `truncated` is `true`

### Requirement: Web page Markdown fallback
When the main content extracted from the HTML is shorter than the server's minimum text length (default 300 characters) even after a rendered fetch, and the provider's Markdown version of the page has more text, `text` SHALL be that Markdown with its syntax removed and `extraction` SHALL be `markdown_fallback`; otherwise `extraction` is `trafilatura`.

#### Scenario: Markdown fallback
- **WHEN** no main content can be extracted from the HTML even after a rendered fetch, and the provider's Markdown has 800 characters of text
- **THEN** the scrape succeeds with `extraction: "markdown_fallback"` and `text` without Markdown syntax such as `#`, `**` or `[label](url)` link targets

### Requirement: Web page rendering and retries
A `web` scrape SHALL first fetch the page without JavaScript rendering; if the main content extracted from it is shorter than the minimum text length, it SHALL fetch once more with rendering and use that answer (`rendered: true`). A provider answer HTTP 429 or 5xx SHALL be retried at most once per scrape; there SHALL be no other retries, so a scrape sends at most 3 provider requests.

#### Scenario: Rendering retry
- **WHEN** the provider returns a JavaScript shell without article text for the unrendered fetch and the full article for the rendered fetch
- **THEN** exactly two provider requests are sent, the ScrapeResult has `rendered: true`, `oxylabs_requests: 2` and the full article `text`

#### Scenario: No rendering needed
- **WHEN** the unrendered fetch yields 1,500 characters of main content
- **THEN** exactly one provider request is sent and the ScrapeResult has `rendered: false` and `oxylabs_requests: 1`

### Requirement: Web page cache
A successful `web` result SHALL be cached in memory, keyed by the normalized requested URL, for the server's cache lifetime (default 1 hour). A scrape of a cached URL within that time SHALL send no provider request and return the cached result with `cached: true`, `oxylabs_requests: 0` and a new `scraped_at` and `latency_ms`. Failed scrapes SHALL NOT be cached.

#### Scenario: Cached page
- **WHEN** the same page URL is scraped twice within the cache lifetime and the first scrape succeeded
- **THEN** the second scrape sends no provider request and has `cached: true` and `oxylabs_requests: 0`

#### Scenario: Failure not cached
- **WHEN** a page scrape failed with `upstream_timeout` and the same URL is scraped again
- **THEN** the second scrape sends a provider request

### Requirement: Web page configuration error
A `web` scrape SHALL fail with `platform_not_configured`, `details.platform` `web` and `details.missing_settings` naming the missing provider settings, before any provider request, when the provider credentials are not configured: `OXYLABS_WEB_API_KEY` for the default Oxylabs Web API, `OXYLABS_USERNAME` and/or `OXYLABS_PASSWORD` for the Oxylabs Web Scraper API.

#### Scenario: Provider not configured
- **WHEN** `OXYLABS_WEB_API_KEY` is not set and a job scrapes `https://www.dw.com/en/some-article/a-12345678`
- **THEN** the scrape fails with `error.code` `platform_not_configured`, `details.platform` `web` and `details.missing_settings` containing `OXYLABS_WEB_API_KEY`, and no provider request is made

### Requirement: Web page error codes
A failed `web` scrape SHALL set `details.platform` `web` and use: `upstream_error` when the provider reports the target failed or blocked (`details.target_status` set when known), rejects the request, or answers unreadable data; `rate_limited` when still throttled after the retry (`details.retry_after_s` when known); `upstream_timeout` on no answer within the upstream timeout; `no_text_content` when neither HTML nor Markdown has text. No error SHALL contain a provider credential.

#### Scenario: Target blocked
- **WHEN** the provider reports that the target answered HTTP 403
- **THEN** the scrape fails with `error.code` `upstream_error`, `details.platform` `web`, `details.target_status` 403 and a `message` saying the page refused the request

#### Scenario: Empty page
- **WHEN** the provider returns a page whose HTML and Markdown contain no text
- **THEN** the scrape fails with `error.code` `no_text_content` and `details.platform` `web`

#### Scenario: Credentials never returned
- **WHEN** the provider rejects the configured API key with HTTP 401
- **THEN** the scrape fails with `error.code` `upstream_error` and neither `message` nor `details` contains the key

### Requirement: Web page login wall
A `web` scrape SHALL fail with `login_required` and `details.platform` `web`, without `details.missing_settings`, when the main text is shorter than the minimum text length after the rendered fetch and the page shows a login wall: a password input, a log-in or sign-in form as main content, or a final URL path `/login`, `/signin` or `/accounts/login` (or below them). The server does not bypass login walls.

#### Scenario: Social network login wall
- **WHEN** a job scrapes `https://www.instagram.com/nasa/` and the provider returns a page with a password input and almost no other text
- **THEN** the scrape fails with `error.code` `login_required`, `details.platform` `web` and no `details.missing_settings`

#### Scenario: Short page without login wall
- **WHEN** the rendered page has 120 characters of main text and no login-wall marker, and its Markdown has no more text
- **THEN** the scrape succeeds with that `text`

#### Scenario: Not a retry condition
- **WHEN** a client shows a job whose scrape failed with `login_required`
- **THEN** it does not present it as a missing page or as a wait-and-retry condition
