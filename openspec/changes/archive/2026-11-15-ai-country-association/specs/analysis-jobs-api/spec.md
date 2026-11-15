## ADDED Requirements

### Requirement: Job country association member
The Job object SHALL also have `country_association`: the job's CountryAssociation (country-association "CountryAssociation object"), or null until the step has settled (country-association "Country association before done"). It SHALL be the same in `GET /api/v1/jobs/{id}` and in every event's `data.job`. Clients SHALL treat a missing `country_association` member like `country_association: null`. `GET /api/v1/jobs` JobSummary items are unchanged.

#### Scenario: Running job
- **WHEN** a client reads a job whose `techniques` run is still `running`
- **THEN** it has `country_association: null`

#### Scenario: Completed job
- **WHEN** a job with detected propaganda has completed in a deployment with a country association model
- **THEN** `GET /api/v1/jobs/{id}` returns it with a non-null `country_association` whose `status` is `succeeded` or `failed`
