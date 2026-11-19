#!/usr/bin/env bash
# Evaluate Renovate automerge gates and dispatch the trusted merge workflow on main.
#
# Environment:
#   PR_NUMBER - Pull request number.
#   HEAD_SHA - Expected head commit SHA.
#   GITHUB_REPOSITORY - owner/repo for gh calls.
#   Merge workflow on main uses secrets.PERSONAL_ACCESS_TOKEN when configured.
set -euo pipefail

PR_NUMBER="${PR_NUMBER:?}"
HEAD_SHA="${HEAD_SHA:?}"
REPO="${GITHUB_REPOSITORY:?}"

set +e
bash .github/scripts/renovate-automerge-gates.sh evaluate \
  "${PR_NUMBER}" \
  "${HEAD_SHA}" \
  "${REPO}"
gate_result=$?
set -e
if [[ "${gate_result}" -eq 2 ]]; then
  exit 0
fi
if [[ "${gate_result}" -ne 0 ]]; then
  exit "${gate_result}"
fi
gh workflow run renovate-ai-automerge-merge.yml \
  --repo "${REPO}" \
  --ref main \
  -f "pr_number=${PR_NUMBER}" \
  -f "head_sha=${HEAD_SHA}"