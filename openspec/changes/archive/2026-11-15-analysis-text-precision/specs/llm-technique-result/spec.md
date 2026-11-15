## MODIFIED Requirements

### Requirement: LLM technique labels
The analyzer SHALL look only for, and emit only, these labels: `evidence_certainty_mismatch` (a contested, causal or sweeping claim is presented as certain without evidence; see "Evidence certainty mismatch scope"), `misleading_headline` (the headline states or implies something the body does not support) and `statistical_cherry_picking` (numbers are selected to support a conclusion the fuller data would not).

#### Scenario: Unknown label from the LLM
- **WHEN** the LLM answers with a finding labelled `fabricated_authority`
- **THEN** the finding is dropped

### Requirement: LLM finding filtering
Findings whose `confidence` is below the deployment's minimum confidence (default 0.6) or outside 0 to 1 SHALL be dropped. At most the deployment's per-label limit (default 5) findings per label SHALL be kept, highest `confidence` first; dropping beyond it sets `truncated: true`.

#### Scenario: Low confidence dropped
- **WHEN** the LLM rates an `evidence_certainty_mismatch` finding with confidence 0.5 and the default minimum applies
- **THEN** that finding is not in `findings`

#### Scenario: Default minimum kept
- **WHEN** the LLM rates an `evidence_certainty_mismatch` finding with confidence 0.6 and the default minimum applies
- **THEN** that finding is in `findings`

## ADDED Requirements

### Requirement: Evidence certainty mismatch scope
The analyzer SHALL ask for `evidence_certainty_mismatch` only where the text presents a contested, causal or sweeping claim as certain ("proves", "definitely", "everyone knows", "there is no doubt", "the real reason is") while giving no evidence or only an anecdote. Reporting events, figures or statements attributed to a named source, quoting someone's certainty, and the ordinary declarative style of news reports SHALL NOT be described to the LLM as a mismatch.

#### Scenario: Attributed news sentence
- **WHEN** the analyzer is asked about "The ministry said 40 people were killed in the strike on Tuesday."
- **THEN** the LLM request's instructions define this kind of attributed reporting as not an `evidence_certainty_mismatch`

#### Scenario: Unsupported certainty
- **WHEN** the analyzer is asked about "This definitely proves the vaccine was designed to harm us."
- **THEN** the LLM request's instructions define this kind of claim as an `evidence_certainty_mismatch`
