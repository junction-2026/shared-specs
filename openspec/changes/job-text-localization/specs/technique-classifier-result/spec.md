## MODIFIED Requirements

### Requirement: Plain-language presentation
Clients that show a detected technique SHALL show `plain_language.name` and `definition` when present, a span's `why` next to (or on activation of) its highlight and `plain_language.why` for a Detection without spans, except as allowed by "Client localization of glossary texts". Without `plain_language`, clients SHALL fall back to their own localization by `name` or to `display` and `explanation`, without error. Clients SHALL NOT key, group or compare techniques by `plain_language.name`.

#### Scenario: Result from before plain-language support
- **WHEN** a client reads a stored TechniqueClassification whose Detections have no `plain_language` and whose spans have no `why`
- **THEN** it shows its own localization keyed by `name`, or `display` and `explanation`, and no `why`, without error

## ADDED Requirements

### Requirement: Client localization of glossary texts
When the client's interface language differs from the result's `explanation_language`, a client MAY show its own localization of a technique's name and definition keyed by the stable `name` (or an LLM finding's `label`), and its own `why` template containing the span `text` verbatim (no span text for a Detection without spans). It SHALL use `plain_language` (or the finding's `name` and `definition`) for an identifier it has no localization for, and SHALL NOT alter span `text`.

#### Scenario: Interface language differs from the explanation language
- **WHEN** `explanation_language` is `fr`, the interface language is `ar` and `Loaded_Language` has the span `"mensonges"`
- **THEN** the client may show its Arabic name and definition of `Loaded_Language` and an Arabic `why` containing `"mensonges"` verbatim

#### Scenario: Identifier without client localization
- **WHEN** the interface language differs from `explanation_language` and a Detection has a `name` the client has no localization for
- **THEN** the client shows `plain_language.name` and `plain_language.definition`
