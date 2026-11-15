## Why

junction-2026/project#75: an analysis is placed on the Explore propaganda map only when its page outlet (or the outlet table match of its URL) has a country. Analyses of pasted text, unknown outlets or e.g. US-related content get no country and cannot be found on the map. The canonical rule "No inferred country" forbids anything else.

## What Changes

- New capability `country-association`: an LLM step of the orchestrator runs once per job with detected propaganda after the analyzers settle (concurrently with finalization) and returns zero, one or several ISO 3166-1 alpha-2 countries from the original input and the analysis result. Failure, timeout or invalid output never fails the job. Stored done public jobs with detected propaganda are backfilled in bounded, retried batches.
- `analysis-jobs-api`: new Job member `country_association` (CountryAssociation or null). Additive.
- `propaganda-map-api`: a job's map country becomes a list of map countries (outlet country first, then the associated countries); an analysis is counted in every CountryAggregate of its countries and listed under each country; MapAnalysis gains `countries` (MapCountry with `basis`), `outlet` may be null and `source.url` may be `""`; top-level `analyses` is the number of distinct map analyses; "Map country meaning" reworded. **BREAKING** (meaning changes, see design.md): `outlet` nullable, `source.url` empty, sum of aggregates may exceed `analyses`.
- Removed: propaganda-map-api "No inferred country".

## Capabilities

### New Capabilities
- `country-association`: AI country association of an analysis job, its object, isolation, timing and backfill.

### Modified Capabilities
- `propaganda-map-api`: multi-country map analyses.
- `analysis-jobs-api`: `Job.country_association` member.

## Impact

- backend: new LLM country association step and ISO country table, job persistence of `country_association`, multi-country map storage and queries, map backfill, API serialization.
- frontend: propaganda map wording, multi-country MapAnalysis reading and panel items, pasted-text items without outlet/URL; optional display of `country_association` on the job page is not required.

Based on backend @ fe6c2e621680b87d7afa598e60b9e7fe9e44f0c5, frontend @ 8eba4940ccaf855b41d488d8f385f4133c95f501, project @ 441ecbf96961128099af004da50a063f18b3345c, shared-specs @ 92a5491bf6c142f2322523c4a24e41a5b04d4946.
