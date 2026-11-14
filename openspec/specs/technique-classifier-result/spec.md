# technique-classifier-result Specification

## Purpose
Result object of the propaganda technique classifier analyzer: per-technique scores for the 18 SemEval-2020 Task 11 techniques on a job's English text, the detected techniques and the sentences that carry them, as clients read it from the analysis job API and event stream.

## Requirements

### Requirement: Technique classifier analyzer
A deployment that offers technique classification SHALL register it as a regular, selectable analyzer with id `techniques`, category `propaganda` and `depends_on` including `translation`. Clients SHALL locate its result as the AnalyzerRun with `id` `techniques` and SHALL treat a missing, `skipped` or `failed` run as "no technique analysis available", not as "no techniques found".

#### Scenario: Translation failed
- **WHEN** `translation` is `failed`
- **THEN** `techniques` is `skipped` with reason `dependency_failed`, `result: null`, and no classifier request is sent

#### Scenario: Deployment without the analyzer
- **WHEN** the registry has no `techniques` analyzer
- **THEN** jobs have no AnalyzerRun with that id and clients show no technique analysis, without error

### Requirement: Technique names
Known technique names SHALL be these 18 strings: `Loaded_Language`, `Appeal_to_fear-prejudice`, `Exaggeration,Minimisation`, `Repetition`, `Flag-Waving`, `Name_Calling,Labeling`, `Reductio_ad_hitlerum`, `Black-and-White_Fallacy`, `Causal_Oversimplification`, `Whataboutism,Straw_Men,Red_Herring`, `Straw_Man`, `Red_Herring`, `Doubt`, `Appeal_to_Authority`, `Thought-terminating_Cliches`, `Bandwagon`, `Slogans`, `Obfuscation,Intentional_Vagueness,Confusion`. They are the known `label` values.

#### Scenario: Names are stable identifiers
- **WHEN** a client groups detections or scores by technique
- **THEN** it uses `name` (Detection) or `label` (TechniqueScore) as the key and `display` only as the shown name

### Requirement: TechniqueClassification object
When `techniques` has `succeeded`, its `result` SHALL be a TechniqueClassification with at least: `words` (integer), `results` (non-empty array of ModelResult, at most one per model, `nci-technique` before `nci-social`), `detected` and `summary` (a StrengthSummary), plus the members of the Span result members requirement and of the Plain-language result members requirement. It SHALL be the same in `analyzer.succeeded` and `GET /api/v1/jobs/{id}`. Clients SHALL ignore unknown members.

#### Scenario: Short text
- **WHEN** a job's English translation has 20 words and the defaults apply
- **THEN** `result.words` is 20 and `result.results` has one ModelResult with `model: "nci-social"` and `cutoff: 0.3`

#### Scenario: Both models ran
- **WHEN** both models classified the text
- **THEN** `results` has two entries, the first with `model: "nci-technique"` and the second with `model: "nci-social"`

#### Scenario: Result from before this change
- **WHEN** a client reads a `techniques` result stored before this change, which has `detected` but no `results` array
- **THEN** it shows the detected techniques as before and shows no per-model scores, without error

### Requirement: Model and words
`words` SHALL be the number of whitespace-separated words of the classified English text. `nci-social` (the short-post model, at most 128 model tokens) SHALL run when `words` is at most the deployment's short-post bound. `nci-technique` (the document model) SHALL run when `words` is at least the deployment's document minimum or above the short-post bound. The defaults SHALL be 80 words for the short-post bound and 40 words for the document minimum. Selection SHALL NOT depend on `input.source`.

#### Scenario: Short post
- **WHEN** the translated text has 39 words and the defaults apply
- **THEN** `results` has one ModelResult with `model: "nci-social"`

#### Scenario: Both models
- **WHEN** the translated text has 40 words, then 80 words, and the defaults apply
- **THEN** each `results` has a `nci-technique` and a `nci-social` ModelResult

#### Scenario: Long document
- **WHEN** the translated text has 81 words and the defaults apply
- **THEN** `results` has one ModelResult with `model: "nci-technique"`

#### Scenario: Platform does not matter
- **WHEN** two jobs have the same text, one with `source.platform: "x"` and one without `source`
- **THEN** both results have the same `results[].model` values, scores and `detected` names

### Requirement: Technique classifier failures
`techniques` SHALL be `failed` with `result: null` and an `error.code` that includes: `invalid_output` when a model response misses a known label, repeats a label, has a missing or empty label, has a score outside 0 to 1 or is not readable as label scores; `adapter_error` for a non-2xx answer, a connection error or an unreadable translation result; `timeout` when its timeout elapses; `cancelled` on job cancellation. It SHALL NOT fail the job or other analyzers or affect `propaganda_detection`.

#### Scenario: Unnamed labels
- **WHEN** a model answers with labels `LABEL_0` to `LABEL_17` only
- **THEN** `techniques` is `failed` with `error.code: invalid_output` (known labels missing) and the job ends `completed`

#### Scenario: No fallback model
- **WHEN** only `nci-technique` is selected and its service answers HTTP 503
- **THEN** `techniques` is `failed` with `error.code: adapter_error` and the `nci-social` service received no classification request

### Requirement: Technique classifier errors hide credentials
`error.message` of a failed `techniques` run and every member of its result MUST NOT contain credentials: no configured header value (such as `Authorization`) and no token, even when the classifier echoes them.

#### Scenario: Service echoes the token
- **WHEN** the classifier answers HTTP 401 with a body that repeats the bearer token
- **THEN** `error.message` does not contain the token

### Requirement: Span result members
A succeeded TechniqueClassification SHALL also have at least `span_method` (values include `sentence` and `phrase`), `span_status` (values include `ok`, `failed` and `timeout`) and `spans_truncated` (boolean), the same in `analyzer.succeeded` and `GET /api/v1/jobs/{id}`.

#### Scenario: Span members present
- **WHEN** `techniques` has `succeeded` for an English job
- **THEN** `result.span_method` is `sentence` and `result.span_status` and `result.spans_truncated` are present

### Requirement: Span status
`span_status` SHALL be `ok` when the span step completed or was not needed, `failed` or `timeout` as defined in "Span failures keep the classification". Clients SHALL treat an unknown `span_status` value like `failed`, and a result without `span_status` (produced before span support) as having no span analysis.

#### Scenario: Result from before span support
- **WHEN** a client reads a stored TechniqueClassification that has no `span_status` and Detections without `spans`
- **THEN** it shows the detected techniques without highlights and without error

### Requirement: Detected techniques keep empty spans
A technique SHALL NOT be removed from `detected` because it has no span, and no paraphrased or translated text SHALL be substituted as its span.

#### Scenario: Detected technique without span
- **WHEN** `Doubt` is above cutoff in a ModelResult and no span is accepted for it
- **THEN** `Doubt` is in `detected` with `spans: []`

### Requirement: Span highlighting presentation
Clients that highlight techniques in the user's text SHALL highlight the `[start, end)` ranges of `detected[].spans` in `Job.input.content` rendered as plain text, and SHALL list a detected technique whose `spans` is empty or missing without a highlight. Clients SHALL NOT present any part of the translation, including `sentences[].text` of results stored before this change, as the user's words.

#### Scenario: Markup in highlighted content
- **WHEN** `Job.input.content` is `"<i>They</i> are LYING"` and a span covers `"LYING"`
- **THEN** a client shows `<i>They</i>` literally and highlights only `LYING`

### Requirement: TechniqueSpan object
A TechniqueSpan SHALL have at least `technique` (the `name` of the Detection that holds it), `text` (string, non-empty), `start`, `end` (integers) and `why` (string, see Plain-language why). Offsets SHALL never refer to the translation.

#### Scenario: Span member values
- **WHEN** a Detection with `name: "Doubt"` holds a span
- **THEN** the span has `technique: "Doubt"`, a non-empty `text` and a non-empty `why` that contains `text`

### Requirement: Span offsets
`start` and `end` SHALL be half-open UTF-16 code-unit offsets into `Job.input.content` such that `Job.input.content.slice(start, end)` equals `text`, compared on the characters as submitted: not `normalized_content`, not trimmed and not case-folded.

#### Scenario: Characters outside the BMP
- **WHEN** `Job.input.content` is `"😡 They are LYING to you."` and the sentence `"They are LYING to you."` is a span
- **THEN** the span has `start: 3`, `end: 25`, because the emoji is two UTF-16 code units followed by a space

### Requirement: Span ordering and overlap
Spans of one Detection SHALL be ordered by `start`, then `end`, and no two of them SHALL have the same `start` and `end`. Spans of different techniques MAY overlap or coincide.

#### Scenario: Overlapping techniques
- **WHEN** the same sentence carries `Loaded_Language` and `Doubt`
- **THEN** both Detections hold a span with the same `start`, `end` and `text`, each with its own `technique`

### Requirement: Span method
`span_method` SHALL be `sentence` when the `translation` result's `source_language` is `en`, and `phrase` for any other or missing `source_language`. When `detected` is empty, no span request SHALL be sent and `span_status` SHALL be `ok`.

#### Scenario: Nothing detected
- **WHEN** `detected` is empty for a German job
- **THEN** `span_method` is `phrase`, `span_status` is `ok` and no span model or LLM request is sent

### Requirement: Sentence spans for English input
When `span_method` is `sentence`, the deployment SHALL split `Job.input.content` into sentences and score them with its sentence-level technique model (`nci-social`), independent of which models produced `results` and of `words`. For each Detection in `detected`, every scored sentence whose sentence-model score for that technique is at or above the sentence model's effective threshold for it SHALL be a span whose `text` is the sentence.

#### Scenario: English job
- **WHEN** an English job with content `"Wake up. They are LYING to you."` has `Loaded_Language` in `detected`, the sentence model scores `"They are LYING to you."` above its `Loaded_Language` threshold and `"Wake up."` below it
- **THEN** `Loaded_Language` has one span `{technique: "Loaded_Language", text: "They are LYING to you.", start: 9, end: 31}`

### Requirement: Sentence spans only for detected techniques
Sentence-model scores of techniques not in `detected` SHALL produce no span and SHALL NOT change `detected`. `spans_truncated` SHALL be `true` when sentences beyond the deployment's span sentence limit were not scored.

#### Scenario: Sentence above cutoff for an undetected technique
- **WHEN** the sentence model scores a sentence above its `Doubt` threshold but `Doubt` is not in `detected`
- **THEN** no span with `technique: "Doubt"` exists and `Doubt` is not added to `detected`

### Requirement: Phrase spans for other languages
When `span_method` is `phrase`, the deployment SHALL ask an LLM for candidate phrases of `Job.input.content` for each technique in `detected`. A candidate SHALL be accepted only if it is non-empty and occurs in `Job.input.content` as an exact, case-sensitive substring; its span SHALL be its leftmost occurrence, with `text` the candidate unchanged.

#### Scenario: Translated candidate rejected
- **WHEN** a German job's content is `"Sie LÜGEN euch an."` and the LLM returns `"They are LYING"` and `"LÜGEN euch"` for `Loaded_Language`
- **THEN** `Loaded_Language` has one span `{text: "LÜGEN euch", start: 4, end: 14}`

#### Scenario: Repeated phrase
- **WHEN** an accepted candidate occurs twice in the content
- **THEN** its span is the first occurrence

### Requirement: Phrase candidate rejection
Candidates that are not exact substrings SHALL be rejected without fuzzy matching, trimming, normalization, translation or repair. Candidates for techniques not in `detected` SHALL be ignored. `spans_truncated` SHALL be `true` when candidates beyond the deployment's per-technique limit were dropped.

#### Scenario: All candidates rejected
- **WHEN** every candidate for `Doubt` differs from the content (for example in case or whitespace)
- **THEN** `Doubt` stays in `detected` with `spans: []` and `span_status` is `ok`

### Requirement: Span failures keep the classification
A failure of the span step SHALL NOT change the AnalyzerRun status, `results` or `detected` membership. When the sentence model or the LLM answers non-2xx, cannot be reached or gives an unreadable answer, `span_status` SHALL be `failed`; when the span step's own deadline elapses it SHALL be `timeout`; in both cases every `detected[].spans` SHALL be `[]`. The `timeout` failure of the whole run applies only when the analyzer's overall timeout elapses.

#### Scenario: LLM times out
- **WHEN** a German job has `Doubt` in `detected` and the span LLM does not answer before the span deadline
- **THEN** `techniques` is `succeeded`, `span_status` is `timeout` and `Doubt` is in `detected` with `spans: []`

#### Scenario: Sentence model error
- **WHEN** the sentence model answers HTTP 503 for an English job
- **THEN** `techniques` is `succeeded` with `span_status: failed`, every `detected[].spans` empty and the same `results` and `detected` names as without span support

### Requirement: English translation only
Every classification request of the `techniques` analyzer to `nci-technique` or `nci-social` SHALL carry only the `translated_text` of the `translation` result and SHALL NOT carry `Job.input.content` or any other original-language text. The span step is governed by the span requirements: it sends sentences of `Job.input.content` to the sentence model only when `span_method` is `sentence` (`source_language` `en`).

#### Scenario: Non-English job
- **WHEN** a job's content is German and `translation` succeeds with an English `translated_text`
- **THEN** every request to `nci-technique` and `nci-social` carries only English text from `translated_text` and none carries the German content

### Requirement: ModelResult object
A ModelResult SHALL have at least `model` (values include `nci-technique` and `nci-social`), `cutoff` (number 0 to 1, the cutoff the deployment configured for that model when the job ran), `scores` (array of TechniqueScore) and `latency_ms` (number or null, as reported by the model service). Scores below the cutoff SHALL be present.

#### Scenario: Below-cutoff scores kept
- **WHEN** every label scores below the cutoff
- **THEN** `scores` still has an entry for each of the 18 known labels, each with `above_cutoff: false`

### Requirement: Score list order
`scores` SHALL hold exactly one TechniqueScore per known label (so a client indexing by `label` never sees two scores for one label from one model), in the order of the Technique names requirement, followed by one TechniqueScore for each other label the model returned, in the model's order. Clients sort for display.

#### Scenario: Known labels first
- **WHEN** a model returns `Appeal_to_Pity` before the 18 known labels
- **THEN** `scores` starts with `Loaded_Language` and ends with `Appeal_to_Pity`

### Requirement: TechniqueScore object
A TechniqueScore SHALL have at least `label` (string), `display` (non-empty string: the built-in display name of a known label, otherwise the label itself), `score` (number 0 to 1, the model's confidence in that technique on the English translation; scores are independent and need not sum to 1), `model` and `cutoff` (equal to those of its ModelResult), `above_cutoff` (boolean, `true` when `score >= cutoff` and `false` otherwise) and `known` (boolean, `true` for the 18 known labels).

#### Scenario: Equality counts
- **WHEN** the `nci-social` cutoff is 0.3 and `Loaded_Language` scores 0.3
- **THEN** its TechniqueScore has `above_cutoff: true`

#### Scenario: Just below the cutoff
- **WHEN** the `nci-technique` cutoff is 0.5 and `Doubt` scores 0.49
- **THEN** its TechniqueScore is present with `score: 0.49` and `above_cutoff: false`

#### Scenario: Same score, different cutoffs
- **WHEN** both models ran with cutoffs 0.5 (`nci-technique`) and 0.3 (`nci-social`) and `Loaded_Language` scores 0.4 from both
- **THEN** it has `above_cutoff: false` in the `nci-technique` ModelResult and `above_cutoff: true` in the `nci-social` ModelResult

### Requirement: Unfamiliar labels
A label returned by a model that is not one of the 18 known labels SHALL be kept as a TechniqueScore with `known: false` and `above_cutoff` evaluated against that model's cutoff; it SHALL NOT make the run fail and SHALL NOT appear in `detected`. Clients SHALL key scores by `label` and SHALL accept labels outside the known list.

#### Scenario: Extra label
- **WHEN** a model returns the 18 known labels plus `Appeal_to_Pity` with score 0.7
- **THEN** the run succeeds, that model's ModelResult has 19 scores, the last with `label: "Appeal_to_Pity"`, `display: "Appeal_to_Pity"`, `known: false`, `score: 0.7` and `above_cutoff: true`, and `detected` has no `Appeal_to_Pity` entry

### Requirement: Separate model results
When both models run, both ModelResults SHALL be kept separately. The analyzer SHALL NOT average, merge or otherwise combine their scores into one score, and clients SHALL NOT compare or combine scores across models.

#### Scenario: No averaging
- **WHEN** both models ran and `Doubt` scored 0.6 from `nci-technique` and 0.2 from `nci-social`
- **THEN** the `nci-technique` ModelResult has `Doubt` with `score: 0.6`, the `nci-social` ModelResult has `Doubt` with `score: 0.2`, and no other `Doubt` score appears in the result

### Requirement: Default cutoffs
Unless the deployment configures other values, `cutoff` SHALL be 0.5 for `nci-technique` and 0.3 for `nci-social`. A changed configuration SHALL be visible in `cutoff` of every result produced after the change.

#### Scenario: Configured cutoff
- **WHEN** the deployment sets the `nci-technique` cutoff to 0.6
- **THEN** new `nci-technique` ModelResults have `cutoff: 0.6` and every `above_cutoff` in them is evaluated against 0.6

### Requirement: No partial technique result
When two models are selected and either fails, `techniques` SHALL be `failed` with that model's error and `result: null`. A succeeded result SHALL contain a ModelResult for every model the routing selected.

#### Scenario: One of two models fails
- **WHEN** both models are selected and the `nci-social` service answers HTTP 503
- **THEN** `techniques` is `failed` with `error.code: adapter_error` and `result: null`

### Requirement: Detected techniques by cutoff
`detected` SHALL list a Detection for each known technique name that has `above_cutoff: true` in at least one ModelResult, in the order of the Technique names requirement, and SHALL be empty when there is none. Unfamiliar labels SHALL NOT appear in `detected`.

#### Scenario: Above cutoff in one model only
- **WHEN** both models ran with default cutoffs and `Loaded_Language` scores 0.4 from both
- **THEN** `detected` has `Loaded_Language` with `models: ["nci-social"]`

#### Scenario: Above cutoff in both models
- **WHEN** `Doubt` is above cutoff in both ModelResults
- **THEN** `detected` has one `Doubt` entry with `models: ["nci-technique", "nci-social"]`

#### Scenario: Nothing above cutoff
- **WHEN** no known label is above cutoff in any ModelResult
- **THEN** `detected` is an empty array and every score is still present in `results`

### Requirement: Detection object
A Detection SHALL have at least `name`, `display`, `explanation` (non-empty one-line English string), `models` (non-empty array of the `model` values of the ModelResults in which it is above cutoff, in `results` order), `spans` (array of TechniqueSpan, possibly empty) and `plain_language` (a PlainLanguage object). `name` stays the stable English identifier of the Technique names requirement and is never localized. A Detection carries no score of its own; clients read scores from `results`.

#### Scenario: Detection members
- **WHEN** `Doubt` is above cutoff only in the `nci-technique` ModelResult
- **THEN** its Detection has `name: "Doubt"`, a non-empty `display` and `explanation`, `models: ["nci-technique"]`, a `spans` array and a `plain_language` object

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

### Requirement: Technique score interpretation
Clients that show scores SHALL NOT present a below-cutoff score as a detected technique, SHALL NOT present `score` as a calibrated probability and SHALL NOT compare or combine scores across models.

#### Scenario: Below-cutoff score shown
- **WHEN** a client lists `Doubt` with `score: 0.2` and `above_cutoff: false`
- **THEN** it does not mark `Doubt` as an indicated technique

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

### Requirement: Detection strength members
Besides the members of the Detection object requirement, a Detection SHALL have at least `margin` (number, derived from the scores in `results`; it is not a score of its own), `located` (boolean) and `strength` (string; values include `strong` and `weak`), as defined by the Detection strength requirement, the same in `analyzer.succeeded` and `GET /api/v1/jobs/{id}`.

#### Scenario: Strength members present
- **WHEN** `techniques` succeeds with `Doubt` in `detected`
- **THEN** the `Doubt` Detection has `margin`, `located` and `strength` in both the event and the job response

### Requirement: Detection strength
For each Detection, `margin` SHALL be the highest `score - cutoff` of its `name` across the ModelResults listed in its `models`, rounded half away from zero to 2 decimals (so `margin >= 0`). `located` SHALL be `true` exactly when its final `spans`, after the span step, has at least one entry. `strength` SHALL be `strong` when `located` is `true` or the rounded `margin` is at least the deployment's strong margin, and `weak` otherwise.

#### Scenario: Borderline and clear detections without spans
- **WHEN** a short post's `nci-social` ModelResult (cutoff 0.4) has `Bandwagon` 0.44, the `nci-technique` ModelResult (cutoff 0.5) has `Loaded_Language` 0.70, the strong margin is 0.15 and neither has a span
- **THEN** `Bandwagon` has `margin: 0.04`, `located: false`, `strength: "weak"` and `Loaded_Language` has `margin: 0.2`, `located: false`, `strength: "strong"`

#### Scenario: Located detection is strong
- **WHEN** `Doubt` scores 0.31 with cutoff 0.3 and has one span
- **THEN** its Detection has `margin: 0.01`, `located: true` and `strength: "strong"`

#### Scenario: Highest margin across models
- **WHEN** `Doubt` is above cutoff in both models, 0.55 with cutoff 0.5 and 0.5 with cutoff 0.3
- **THEN** its `margin` is 0.2

#### Scenario: Margin equal to the strong margin
- **WHEN** `Slogans` scores 0.65 with cutoff 0.5, has no span and the strong margin is 0.15
- **THEN** its `margin` is 0.15 and `strength` is `strong`

#### Scenario: Span step failed
- **WHEN** `span_status` is `failed` and `Flag-Waving` has margin 0.05
- **THEN** `Flag-Waving` has `spans: []`, `located: false` and `strength: "weak"`

### Requirement: Strong margin setting
Unless the deployment configures another value, the strong margin SHALL be 0.15. A changed strong margin SHALL apply to results produced after the change and SHALL NOT change stored results.

#### Scenario: Configured strong margin
- **WHEN** the deployment sets the strong margin to 0.05 and `Bandwagon` has margin 0.06 and no span
- **THEN** new results have `Bandwagon` with `strength: "strong"`, and results stored earlier keep their `strength`

### Requirement: StrengthSummary object
A StrengthSummary SHALL have at least `strong` and `weak` (non-negative integers): the number of Detections in `detected` with `strength` `strong` and `weak` respectively. Their sum SHALL equal the length of `detected`.

#### Scenario: Nothing detected
- **WHEN** `detected` is empty
- **THEN** `summary` is `{"strong": 0, "weak": 0}`

#### Scenario: Mixed detections
- **WHEN** `detected` has `Loaded_Language` (`strong`) and `Bandwagon` (`weak`)
- **THEN** `summary` has `strong: 1` and `weak: 1`

### Requirement: Detection strength interpretation
A `weak` Detection is a hint at most (a borderline score with no phrase located), not evidence of propaganda on its own. Clients that show strength SHALL present a `weak` Detection as weaker than a `strong` one and SHALL NOT present `margin` as a probability. Clients SHALL treat an unknown `strength` value as no strength information.

#### Scenario: Unknown strength value
- **WHEN** a client receives a Detection with `strength: "moderate"`
- **THEN** it shows the Detection without a strength indicator, without error

### Requirement: Results without strength
Clients SHALL accept TechniqueClassifications without `summary` and Detections without `margin`, `located` or `strength`, as stored before this change. They SHALL show such Detections as before, with no strength indicator, and SHALL NOT derive a strength for them.

#### Scenario: Result from before strength support
- **WHEN** a client reads a stored `techniques` result whose Detections have `name`, `display`, `explanation`, `models` and `spans` but no `strength`, and no `summary`
- **THEN** it lists the detected techniques and their highlights as before, without a strength indicator and without error
