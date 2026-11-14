# api-conventions Specification

## Purpose
Cross-cutting conventions shared by every HTTP and WebSocket interface of the analysis orchestrator: base path, encoding, timestamps, the error envelope, pagination and tolerant-reader compatibility rules.

## Requirements

### Requirement: Base path and encoding
The orchestrator SHALL serve every API endpoint under the base path `/api/v1`. Request and response bodies SHALL be JSON encoded as UTF-8 with `Content-Type: application/json`. Identifiers (job ids, analyzer ids) SHALL be opaque strings; clients MUST NOT parse them.

#### Scenario: JSON response
- **WHEN** a client calls any `/api/v1` endpoint that returns a body
- **THEN** the response has `Content-Type: application/json` and a UTF-8 JSON body

### Requirement: Timestamps and durations
Timestamps SHALL be RFC 3339 strings in UTC with a `Z` suffix; fractional seconds are allowed. Durations SHALL be integer milliseconds in members whose names end with `_ms`.

#### Scenario: Timestamp format
- **WHEN** a response contains `created_at`
- **THEN** its value has the form `2026-11-14T10:00:00Z` or `2026-11-14T10:00:00.123Z`

### Requirement: Error envelope
Every error response (HTTP status 4xx or 5xx) SHALL have the body `{"error": {"code": <string>, "message": <string>, "details": <object, optional>}}`. `code` is a stable machine-readable snake_case identifier. `message` is human-readable and MUST NOT be parsed by clients. Messages MUST NOT contain stack traces, credentials or analyzer endpoint URLs.

#### Scenario: Unknown job
- **WHEN** a client requests `GET /api/v1/jobs/does-not-exist`
- **THEN** the status is 404 and the body is `{"error": {"code": "not_found", "message": "..."}}`

### Requirement: Common error codes
Every endpoint SHALL use these error codes for these cases; they include: `invalid_request` (400, body is not valid JSON or a query parameter is malformed), `validation_failed` (422, valid JSON violating the endpoint schema, with `details.fields` mapping each offending member path to a message), `not_found` (404), `method_not_allowed` (405), `payload_too_large` (413) and `internal_error` (500). Endpoints MAY define further codes.

#### Scenario: Malformed JSON
- **WHEN** a client posts `{"input":` to `/api/v1/jobs`
- **THEN** the status is 400 with `error.code` `invalid_request`

#### Scenario: Schema violation
- **WHEN** a client posts `{"input": {"content": 5}}` to `/api/v1/jobs`
- **THEN** the status is 422 with `error.code` `validation_failed` and `error.details.fields` has the key `input.content`

### Requirement: Cursor pagination
List endpoints SHALL accept the query parameters `limit` (integer 1–100, default 20) and `cursor` (opaque string from a previous response) and SHALL return `{"items": [...], "next_cursor": <string or null>}`, with `next_cursor` `null` when no further items exist. A `limit` outside 1–100 or an undecodable cursor SHALL yield 400 `invalid_request`.

#### Scenario: Last page
- **WHEN** a client lists jobs and fewer than `limit` items remain
- **THEN** the response has `next_cursor: null`

#### Scenario: Limit out of range
- **WHEN** a client lists jobs with `limit=500`
- **THEN** the status is 400 with `error.code` `invalid_request`

### Requirement: Tolerant reader for objects
Every response object and event payload SHALL be read as "at least these members": the server MAY add optional members and clients MUST ignore members they do not know. Request bodies SHALL ignore unknown members. Removing or renaming a member, changing its type or meaning, or changing the HTTP status of an existing case is breaking and requires a new shared spec revision.

#### Scenario: Unknown member in a response
- **WHEN** a later backend adds a member `language` to the Job object
- **THEN** existing clients keep working and ignore `language`

#### Scenario: Unknown member in a request
- **WHEN** a client sends `{"input": {"content": "x"}, "priority": 1}` to `POST /api/v1/jobs`
- **THEN** the server ignores `priority` and creates the job

### Requirement: Tolerant reader for enumerations
Lists of statuses, reasons, error codes, limitation kinds and event types SHALL be "includes" lists: the server MAY add values. Clients MUST NOT fail on an unknown value; they SHALL treat an unknown job status according to the job's `done` member and ignore unknown event types.

#### Scenario: New event type
- **WHEN** a later backend emits an event with `type` `analyzer.progress`
- **THEN** an existing client ignores it and keeps processing later events
