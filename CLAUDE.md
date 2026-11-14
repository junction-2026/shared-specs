# Working in this repository

- OpenSpec is mandatory: every change carries `openspec/changes/<id>/` (proposal, tasks, delta specs).
- A delta spec that creates a capability starts with `## Purpose` (50+ characters).
- Run `scripts/validate-openspec.sh` before pushing; `repo-ci` runs it on every PR.
- Never push to the default branch; the Junction orchestrator merges validated feature groups.
