## MODIFIED Requirements

### Requirement: TechniqueClassification object
When `techniques` has `succeeded`, its `result` SHALL be a TechniqueClassification with at least: `words` (integer), `results` (non-empty array of ModelResult, at most one per model, `nci-technique` before `nci-social`) and `detected`, plus the members of the Span result members requirement and of the Plain-language result members requirement. It SHALL be the same in `analyzer.succeeded` and `GET /api/v1/jobs/{id}`. Clients SHALL ignore unknown members.

#### Scenario: Short text
- **WHEN** a job's English translation has 20 words and the defaults apply
- **THEN** `result.words` is 20 and `result.results` has one ModelResult with `model: "nci-social"` and `cutoff: 0.3`

#### Scenario: Both models ran
- **WHEN** both models classified the text
- **THEN** `results` has two entries, the first with `model: "nci-technique"` and the second with `model: "nci-social"`

#### Scenario: Result from before this change
- **WHEN** a client reads a `techniques` result stored before this change, which has `detected` but no `results` array
- **THEN** it shows the detected techniques as before and shows no per-model scores, without error

### Requirement: Detection object
A Detection SHALL have at least `name`, `display`, `explanation` (non-empty one-line English string), `models` (non-empty array of the `model` values of the ModelResults in which it is above cutoff, in `results` order), `spans` (array of TechniqueSpan, possibly empty) and `plain_language` (a PlainLanguage object). `name` stays the stable English identifier of the Technique names requirement and is never localized. A Detection carries no score of its own; clients read scores from `results`.

#### Scenario: Detection members
- **WHEN** `Doubt` is above cutoff only in the `nci-technique` ModelResult
- **THEN** its Detection has `name: "Doubt"`, a non-empty `display` and `explanation`, `models: ["nci-technique"]`, a `spans` array and a `plain_language` object

### Requirement: TechniqueSpan object
A TechniqueSpan SHALL have at least `technique` (the `name` of the Detection that holds it), `text` (string, non-empty), `start`, `end` (integers) and `why` (string, see Plain-language why). Offsets SHALL never refer to the translation.

#### Scenario: Span member values
- **WHEN** a Detection with `name: "Doubt"` holds a span
- **THEN** the span has `technique: "Doubt"`, a non-empty `text` and a non-empty `why` that contains `text`

### Requirement: Technique score presentation
Span `text`, `label`, `display`, `explanation` and every member of `plain_language` and TechniqueSpan `why` come from untrusted content, model output or a template filled with untrusted content; clients SHALL render them as plain text without HTML or Markdown interpretation. Clients SHALL present detections as indicators of a technique on the English translation, not as proof of propaganda, and SHALL treat several techniques at once as normal.

#### Scenario: Markup in a label
- **WHEN** an unfamiliar `label` is `<b>LIES</b>`
- **THEN** a client that shows it shows those characters literally

#### Scenario: Several techniques at once
- **WHEN** `Loaded_Language` and `Flag-Waving` are both in `detected`
- **THEN** a client shows both as indicated techniques

#### Scenario: Markup quoted in why
- **WHEN** a span `text` is `<b>LYING</b>` and its `why` quotes it
- **THEN** a client shows the `<b>` characters literally

## ADDED Requirements

### Requirement: Plain-language result members
A succeeded TechniqueClassification SHALL also have at least `explanation_language` (non-empty string, the language of every `plain_language` member and span `why`) and `glossary_version` (non-empty string identifying the fixed glossary edition that produced them). `explanation_language` SHALL be the `translation` result's `source_language` when the deployment's glossary has that language, and `en` otherwise (including a missing `source_language`). Values of `explanation_language` include `en`.

#### Scenario: Supported language
- **WHEN** `translation` reports `source_language: "de"` and the glossary has German
- **THEN** `result.explanation_language` is `de` and every `plain_language` and span `why` is German

#### Scenario: Unsupported language falls back to English
- **WHEN** `translation` reports a `source_language` the glossary does not have
- **THEN** `result.explanation_language` is `en`, `plain_language.name` and `definition` are the English glossary entries, and the result is otherwise unchanged

### Requirement: PlainLanguage object
A PlainLanguage object SHALL have at least `name` (non-empty string: the glossary's name of the technique in `explanation_language`), `definition` (non-empty string: the glossary's one-line definition of the technique in `explanation_language`) and `why` (non-empty string of one or two sentences, see Plain-language why).

#### Scenario: English loaded language
- **WHEN** `Loaded_Language` is detected and `explanation_language` is `en`
- **THEN** its `plain_language.name` and `definition` are the English glossary entries for `Loaded_Language` (for example a definition saying the words carry a strong emotional push)

### Requirement: Fixed glossary
`plain_language.name` and `plain_language.definition` SHALL be taken from a fixed glossary that the deployment ships, keyed by technique `name` and language, and SHALL NOT be generated, reworded or translated per request by an LLM or any other model. Two results with the same `glossary_version`, `explanation_language` and technique `name` SHALL have the same `plain_language.name` and `definition`. A change of any glossary wording SHALL change `glossary_version`.

#### Scenario: Same wording across jobs
- **WHEN** two German jobs both detect `Doubt` with the same `glossary_version`
- **THEN** both have identical `plain_language.name` and `plain_language.definition` for `Doubt`

#### Scenario: No LLM call for definitions
- **WHEN** a job detects three techniques and `span_method` is `sentence`
- **THEN** no LLM request is sent by `techniques` to produce names, definitions or `why`

### Requirement: Plain-language why
`why` SHALL be one or two sentences built from a fixed template of the glossary in `explanation_language`, and SHALL contain no text other than the template, the technique's `plain_language.name` and, for a span, the span `text`. It SHALL NOT state any fact about the world, any score or any claim about the author's intent.

#### Scenario: Template only
- **WHEN** `Flag-Waving` has a span `"Real patriots vote no"` and `explanation_language` is `en`
- **THEN** the span's `why` consists of the English template, the glossary name of `Flag-Waving` and `"Real patriots vote no"`, and nothing else

### Requirement: Span why quotes the span
A TechniqueSpan's `why` SHALL contain its `text` verbatim (unchanged characters, not trimmed, not translated) as a quotation. A Detection's `plain_language.why` SHALL equal the `why` of its first span when `spans` is non-empty.

#### Scenario: Why quotes the span
- **WHEN** `Loaded_Language` has spans `"LÜGEN euch"` (first) and `"Verräter"` and `explanation_language` is `de`
- **THEN** each span's `why` is German and contains its own `text` verbatim, and `plain_language.why` equals the `why` of the `"LÜGEN euch"` span

### Requirement: Why without a span
When a Detection's `spans` is empty (no span accepted, or the span step failed or timed out), its `plain_language.why` SHALL state that the technique was indicated by the score of the whole text and that no specific phrase was located, and SHALL quote no text.

#### Scenario: No span located
- **WHEN** `Doubt` is in `detected` with `spans: []` and `explanation_language` is `en`
- **THEN** `plain_language.why` is an English sentence saying the label came from the score of the whole text and no phrase was located, and it contains no quotation from the content

#### Scenario: Span step failed
- **WHEN** `span_status` is `failed`
- **THEN** every Detection's `plain_language.why` is the no-phrase-located sentence

### Requirement: Plain-language presentation
Clients that show a detected technique SHALL show `plain_language.name` and `plain_language.definition` when present, and SHALL show a span's `why` next to (or on activation of) its highlight and `plain_language.why` for a Detection without spans. For a result without `plain_language` (stored before this change), clients SHALL fall back to `display` and `explanation` without error. Clients SHALL NOT key, group or compare techniques by `plain_language.name`.

#### Scenario: Result from before plain-language support
- **WHEN** a client reads a stored TechniqueClassification whose Detections have no `plain_language` and whose spans have no `why`
- **THEN** it shows `display` and `explanation` as before and no `why`, without error
