#!/usr/bin/env bash
set -euo pipefail

MODE="${1:?usage: renovate-automerge-gates.sh <evaluate|merge> <pr_number> <head_sha> <repo>}"
PR_NUMBER="${2:?}"
HEAD_SHA="${3:?}"
REPO="${4:?}"

REQUIRED_CHECKS=("Build code and test" "build_android" "build_ios" "guard_swiftpm_version")
IGNORE_CHECK_SUBSTR=("Socket" "SonarCloud" "smith" "cubic" "Renovate AI automerge")
CODERABBIT_LOGIN="coderabbitai[bot]"
POLL_SECONDS=30
MAX_WAIT_SECONDS=540

log() { echo "::notice::$*"; }
skip() { log "$1"; exit 2; }
fail() { echo "::error::$1"; exit 1; }

if [[ "${MODE}" != "evaluate" && "${MODE}" != "merge" ]]; then
  fail "Invalid mode: ${MODE}"
fi

PR_JSON="$(gh pr view "${PR_NUMBER}" --repo "${REPO}" --json state,isDraft,author,mergedAt,labels)"
PR_STATE="$(jq -r '.state' <<<"${PR_JSON}")"
PR_DRAFT="$(jq -r '.isDraft' <<<"${PR_JSON}")"
PR_AUTHOR="$(jq -r '.author.login' <<<"${PR_JSON}")"
MERGED_AT="$(jq -r '.mergedAt // empty' <<<"${PR_JSON}")"
PR_LABELS="$(jq -r '[.labels[].name] | join(",")' <<<"${PR_JSON}")"

if [[ "${PR_STATE}" != "OPEN" ]]; then
  skip "PR #${PR_NUMBER} is not open (${PR_STATE})"
fi

if [[ "${PR_DRAFT}" == "true" ]]; then
  skip "PR #${PR_NUMBER} is a draft"
fi

if [[ "${PR_AUTHOR}" != "renovate[bot]" && "${PR_AUTHOR}" != "app/renovate" ]]; then
  skip "PR #${PR_NUMBER} author is not Renovate (${PR_AUTHOR})"
fi

if [[ -n "${MERGED_AT}" && "${MERGED_AT}" != "null" ]]; then
  skip "PR #${PR_NUMBER} is already merged"
fi

CHANGED_FILES=()
PAGE=1
while true; do
  PAGE_JSON="$(
    gh api "repos/${REPO}/pulls/${PR_NUMBER}/files" -F per_page=100 -F page="${PAGE}" 2>/dev/null
  )" || fail "Failed to list changed files for PR #${PR_NUMBER}"
  mapfile -t PAGE_PATHS < <(jq -r '.[].path' <<<"${PAGE_JSON}")
  if [[ ${#PAGE_PATHS[@]} -eq 0 ]]; then
    break
  fi
  CHANGED_FILES+=("${PAGE_PATHS[@]}")
  if [[ ${#PAGE_PATHS[@]} -lt 100 ]]; then
    break
  fi
  PAGE=$((PAGE + 1))
done

if [[ ${#CHANGED_FILES[@]} -eq 0 ]]; then
  skip "PR #${PR_NUMBER} has no changed files"
fi

if [[ ",${PR_LABELS}," != *",github-actions,"* ]]; then
  skip "PR #${PR_NUMBER} is missing the github-actions label"
fi

SCOPE_OK=true
for file in "${CHANGED_FILES[@]}"; do
  [[ -z "${file}" ]] && continue
  if [[ "${file}" == .github/workflows/* ]]; then
    continue
  fi
  SCOPE_OK=false
  break
done

if [[ "${SCOPE_OK}" != "true" ]]; then
  skip "PR #${PR_NUMBER} is outside GitHub Actions automerge scope"
fi

ACTUAL_HEAD_SHA="$(gh pr view "${PR_NUMBER}" --repo "${REPO}" --json headRefOid -q .headRefOid)"
if [[ "${ACTUAL_HEAD_SHA}" != "${HEAD_SHA}" ]]; then
  skip "PR #${PR_NUMBER} head moved (${HEAD_SHA} -> ${ACTUAL_HEAD_SHA})"
fi

should_ignore_check() {
  local name="$1"
  for pattern in "${IGNORE_CHECK_SUBSTR[@]}"; do
    if [[ "${name}" == *"${pattern}"* ]]; then
      return 0
    fi
  done
  return 1
}

check_matches_required() {
  local check_name="$1"
  local required="$2"
  [[ "${check_name}" == "${required}" ]] && return 0
  [[ "${check_name}" == *"/ ${required}" ]] && return 0
  return 1
}

load_check_runs() {
  local output_file="$1"
  local sha="$2"
  if ! gh api "repos/${REPO}/commits/${sha}/check-runs" --paginate \
    --jq '.check_runs[] | [.id, .name, .status, (.conclusion // "")] | @tsv' >"${output_file}"; then
    fail "Failed to fetch check runs for ${sha}"
  fi
}

evaluate_required_checks_for_sha() {
  local target_sha="$1"
  local pending=false
  local failed=false
  local check_runs_file
  check_runs_file="$(mktemp)"
  trap 'rm -f "${check_runs_file}"' RETURN
  load_check_runs "${check_runs_file}" "${target_sha}"

  for required in "${REQUIRED_CHECKS[@]}"; do
    local found=false
    local latest_id=""
    local latest_status=""
    local latest_conclusion=""

    while IFS=$'\t' read -r id name status conclusion; do
      [[ -n "${id}" ]] || continue
      if should_ignore_check "${name}"; then
        continue
      fi
      if ! check_matches_required "${name}" "${required}"; then
        continue
      fi
      found=true
      if [[ -z "${latest_id}" || "${id}" -gt "${latest_id}" ]]; then
        latest_id="${id}"
        latest_status="${status}"
        latest_conclusion="${conclusion}"
      fi
    done <"${check_runs_file}"

    if [[ "${found}" != "true" ]]; then
      pending=true
      continue
    fi

    if [[ "${latest_status}" != "completed" ]]; then
      pending=true
    elif [[ "${latest_conclusion}" == "success" || "${latest_conclusion}" == "skipped" || "${latest_conclusion}" == "neutral" ]]; then
      :
    else
      echo "::error::Required check failed: ${required} (${latest_conclusion})"
      failed=true
    fi
  done

  if [[ "${failed}" == "true" ]]; then
    return 2
  fi
  if [[ "${pending}" == "true" ]]; then
    return 1
  fi
  return 0
}

wait_for_required_checks_on_sha() {
  local target_sha="$1"
  local label="$2"
  local start
  start="$(date +%s)"
  while true; do
    set +e
    evaluate_required_checks_for_sha "${target_sha}"
    local result=$?
    set -e
    if [[ "${result}" -eq 0 ]]; then
      log "All required checks passed on ${label} ${target_sha}"
      return 0
    fi
    if [[ "${result}" -eq 2 ]]; then
      fail "Required checks failed for PR #${PR_NUMBER} (${label} ${target_sha})"
    fi
    if (( $(date +%s) - start >= MAX_WAIT_SECONDS )); then
      skip "Timed out after ${MAX_WAIT_SECONDS}s waiting for required checks (${label}) on PR #${PR_NUMBER}"
    fi
    log "Waiting for required checks on ${label} ${target_sha}..."
    sleep "${POLL_SECONDS}"
  done
}

wait_for_pr_merge_commit_checks() {
  local start
  start="$(date +%s)"
  while true; do
    PR_PULL_JSON="$(gh api "repos/${REPO}/pulls/${PR_NUMBER}" --jq '{mergeable, merge_commit_sha}')"
    MERGEABLE="$(jq -r '.mergeable' <<<"${PR_PULL_JSON}")"
    MERGE_SHA="$(jq -r '.merge_commit_sha // empty' <<<"${PR_PULL_JSON}")"

    if [[ "${MERGEABLE}" == "false" ]]; then
      skip "PR #${PR_NUMBER} is not mergeable (conflicts or blocked)"
    fi

    if [[ -z "${MERGE_SHA}" ]]; then
      if (( $(date +%s) - start >= MAX_WAIT_SECONDS )); then
        skip "Timed out after ${MAX_WAIT_SECONDS}s waiting for merge test commit on PR #${PR_NUMBER}"
      fi
      log "Waiting for GitHub to compute merge test commit for PR #${PR_NUMBER}..."
      sleep "${POLL_SECONDS}"
      continue
    fi

    if [[ "${MERGE_SHA}" == "${HEAD_SHA}" ]]; then
      log "Merge test commit matches HEAD ${HEAD_SHA}; skipping duplicate check pass"
      return 0
    fi

    wait_for_required_checks_on_sha "${MERGE_SHA}" "merge"
    return 0
  done
}

get_coderabbit_review_state() {
  gh api "repos/${REPO}/pulls/${PR_NUMBER}/reviews" --paginate \
    | jq -r -s --arg sha "${HEAD_SHA}" --arg bot "${CODERABBIT_LOGIN}" '
      add
      | [.[]
          | select(
              .user.login == $bot
              and .commit_id == $sha
              and .state != "PENDING"
            )
        ]
      | sort_by(.submitted_at)
      | last
      | .state // ""'
}

wait_for_required_checks_on_sha "${HEAD_SHA}" "head"

wait_for_pr_merge_commit_checks

CODERABBIT_STATE="$(get_coderabbit_review_state)"
if [[ "${CODERABBIT_STATE}" == "CHANGES_REQUESTED" ]]; then
  skip "CodeRabbit requested changes on ${HEAD_SHA} for PR #${PR_NUMBER}"
fi

if [[ "${CODERABBIT_STATE}" != "APPROVED" ]]; then
  skip "CodeRabbit has not approved ${HEAD_SHA} for PR #${PR_NUMBER} (state: ${CODERABBIT_STATE:-none})"
fi

if [[ "${MODE}" == "evaluate" ]]; then
  log "All gates passed for PR #${PR_NUMBER} on ${HEAD_SHA}"
  exit 0
fi

log "Gates passed for PR #${PR_NUMBER}; merging"
gh pr merge "${PR_NUMBER}" --repo "${REPO}" --squash --delete-branch \
  --match-head-commit "${HEAD_SHA}"
gh pr comment "${PR_NUMBER}" --repo "${REPO}" \
  --body "AI review approved + CI green → auto-merged"
