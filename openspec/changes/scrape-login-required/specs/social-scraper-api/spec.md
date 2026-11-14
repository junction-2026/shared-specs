## ADDED Requirements

### Requirement: Login required error code
Scrape error codes SHALL include `login_required`: the platform refused an anonymous request for the requested profile or post, or answered with a login wall, so the content needs a logged-in session on the server side. `details.platform` SHALL be set. Clients SHALL NOT present `login_required` as a missing or private account or as a wait-and-retry condition.

#### Scenario: Anonymous Instagram refused
- **WHEN** `INSTAGRAM_SESSION_FILE` is not configured and Instagram answers 404 to the profile request for `https://www.instagram.com/nasa/`
- **THEN** the scrape fails with `error.code` `login_required`, `details.platform` `instagram` and `details.missing_settings` `["INSTAGRAM_SESSION_FILE"]`

#### Scenario: Instagram login wall
- **WHEN** Instagram redirects the request to `/accounts/login`, answers 401, or answers with a body flagging `"require_login": true` or `login_required`
- **THEN** the scrape fails with `error.code` `login_required` and `details.platform` `instagram`, not `rate_limited`

#### Scenario: Threads login wall
- **WHEN** Threads serves a page for `https://www.threads.net/@zuck` that carries no profile data but shows a login form, a link to `/login` or login-required flags
- **THEN** the scrape fails with `error.code` `login_required` and `details.platform` `threads`

#### Scenario: Passed through to the job
- **WHEN** a job's scrape fails with `login_required`
- **THEN** the job ends `failed` with `scrape.error.code` `login_required` and the scraper's `details`

### Requirement: Login required details
For `login_required`, `details.missing_settings` SHALL list the names, never values, of server settings that would fix the failure when they are known (Instagram without a session: `["INSTAGRAM_SESSION_FILE"]`) and MAY be omitted when none is known. `login_required` is distinct from `account_not_found`, `post_not_found`, `account_private`, `rate_limited` and `platform_not_configured`.

#### Scenario: Missing setting named
- **WHEN** `INSTAGRAM_SESSION_FILE` is not configured and an Instagram scrape fails with `login_required`
- **THEN** `details.missing_settings` is `["INSTAGRAM_SESSION_FILE"]` and contains no setting value

#### Scenario: No setting known
- **WHEN** a Threads scrape fails with `login_required` and the server supports no Threads session setting
- **THEN** `details.missing_settings` is absent or empty and `details.platform` is `threads`

## MODIFIED Requirements

### Requirement: Account and post error codes
Scrape error codes SHALL include `account_not_found` and `post_not_found` when the account or post does not exist or was deleted, and `account_private` when the account or post is not public. They SHALL be produced only when the platform's answer reliably means non-existence; an anonymous answer that cannot tell a missing account from a refused caller (Instagram without a session) SHALL be `login_required`.

#### Scenario: Private Instagram account
- **WHEN** a job scrapes a private Instagram profile
- **THEN** the scrape fails with `error.code` `account_private` and `details.platform` `instagram`

#### Scenario: Missing account
- **WHEN** a job scrapes `https://bsky.app/profile/does-not-exist.bsky.social`
- **THEN** the scrape fails with `error.code` `account_not_found`

#### Scenario: Missing Instagram account with a session
- **WHEN** `INSTAGRAM_SESSION_FILE` is configured and Instagram answers 404 for the profile
- **THEN** the scrape fails with `error.code` `account_not_found` and `details.platform` `instagram`

### Requirement: Rate limit and credential error codes
Scrape error codes SHALL include `rate_limited` (the platform throttled the scraper, for example HTTP 429; `details.retry_after_s` set when the wait is known; a login wall is `login_required`, not `rate_limited`) and `platform_not_configured` (credentials the platform needs are not configured, including X without `TWITTER_AUTH_TOKEN` and `TWITTER_CT0`; `details.missing_settings` lists the names, never values, of missing settings).

#### Scenario: X credentials missing
- **WHEN** `TWITTER_AUTH_TOKEN` is not set and a job scrapes `https://x.com/alice`
- **THEN** the scrape fails with `error.code` `platform_not_configured`, `details.platform` `twitter` and `details.missing_settings` containing `TWITTER_AUTH_TOKEN`

#### Scenario: Rate limited
- **WHEN** Instagram answers HTTP 429 with `Retry-After: 90`
- **THEN** the scrape fails with `error.code` `rate_limited` and `details.retry_after_s` 90

### Requirement: Upstream error codes
Scrape error codes SHALL include `upstream_error` (the platform answered with an error or with data that could not be parsed into the requested profile or post, and the answer is not a login wall), `upstream_timeout` (the platform did not answer within the scraper's upstream timeout) and `internal_error`.

#### Scenario: Unparseable page
- **WHEN** the Threads page contains neither any recognizable profile data nor login-wall markers
- **THEN** the scrape fails with `error.code` `upstream_error`, `details.platform` `threads` and a `message` naming the data that was missing
