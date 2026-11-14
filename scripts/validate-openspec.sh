#!/usr/bin/env bash
# validate-openspec.sh: validates canonical specs and every active local
# change with the PINNED OpenSpec CLI, then dry-runs the archive the
# orchestrator performs at integration time. Emits structured artifacts.
# Verified against @fission-ai/openspec 1.16.1.
set -euo pipefail
OPENSPEC_VERSION="${OPENSPEC_VERSION:?pin the OpenSpec CLI version}"
export OPENSPEC_TELEMETRY=0 DO_NOT_TRACK=1 OPENSPEC_NO_UPDATE_CHECK=1 CI=1 NO_COLOR=1
if command -v openspec >/dev/null 2>&1 && [ "$(openspec --version)" = "${OPENSPEC_VERSION}" ]; then
  OS=(openspec)
else
  OS=(npx -y "@fission-ai/openspec@${OPENSPEC_VERSION}")
fi
mkdir -p artifacts
"${OS[@]}" validate --all --strict --no-interactive --json > artifacts/openspec-validation.json || {
  cat artifacts/openspec-validation.json
  exit 1
}

# Archive dry-run: archiving a change that creates a capability without a
# "## Purpose" in its delta leaves a placeholder that fails strict validation.
# Catch that here instead of at candidate assembly.
changes=()
if [ -d openspec/changes ]; then
  for d in openspec/changes/*/; do
    id="$(basename "$d")"
    [ "$id" = archive ] && continue
    [ -f "$d/proposal.md" ] && changes+=("$id")
  done
fi
if [ "${#changes[@]}" -gt 0 ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  cp -R openspec "$tmp/openspec"
  for id in "${changes[@]}"; do
    (cd "$tmp" && "${OS[@]}" archive "$id" --yes > /dev/null) || { echo "::error::openspec archive dry-run failed for $id"; exit 1; }
  done
  (cd "$tmp" && "${OS[@]}" validate --all --strict --no-interactive --json) > artifacts/openspec-archive-dry-run.json || {
    cat artifacts/openspec-archive-dry-run.json
    echo "::error::specs are invalid after archiving (a new capability needs a '## Purpose' of 50+ characters in its delta spec)"
    exit 1
  }
fi

# Every PR must carry at least one active change (no OpenSpec bypass), except the
# bot's spec-finalization (integration/*) and shared archive (archive/*) PRs, and
# a standalone change Junction labeled junction:no-spec. Junction applies that
# label only after its own no-spec verdict and removes it from any other PR;
# its merge gate never trusts the label. OpenSpec files the PR does touch are
# still validated strictly above.
no_spec_label() {
  [ -n "${GITHUB_EVENT_PATH:-}" ] && [ -f "$GITHUB_EVENT_PATH" ] || return 1
  if ! command -v jq >/dev/null 2>&1; then
    echo "::warning::jq not found: the junction:no-spec label is not read"
    return 1
  fi
  # The PR's current labels only: an unlabeled event also names the removed label (.label).
  jq -e '.pull_request.labels[]?.name | select(. == "junction:no-spec")' "$GITHUB_EVENT_PATH" >/dev/null
}
if [ "${GITHUB_EVENT_NAME:-}" = "pull_request" ] && [[ "${GITHUB_HEAD_REF:-}" != integration/* ]] && [[ "${GITHUB_HEAD_REF:-}" != archive/* ]]; then
  if no_spec_label; then
    echo "standalone change labeled junction:no-spec: no OpenSpec change required"
  elif ! git diff --name-only "origin/${GITHUB_BASE_REF}...HEAD" | grep -q '^openspec/changes/[^/]*/proposal.md$'; then
    echo "::error::PR has no OpenSpec change (openspec/changes/<id>/proposal.md)"
    exit 1
  fi
fi
