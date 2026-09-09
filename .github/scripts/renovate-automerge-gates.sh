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
MAX_WAIT_SECONDS=1800

log() { echo "::notice::$*"; }
skip() { log "$1"; exit 2; }
fail() { echo "::error::$1"; exit 1; }

if [[ "${MODE}" != "evaluate" && "${MODE}" != "merge" ]]; then
  fail "Invalid mode: ${MODE}"
fi

PR_JSON="$(gh pr view "${PR_NUMBER}" --repo "${REPO}" --json state,isDraft,author,mergedAt,labels,files)"
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

mapfile -t CHANGED_FILES < <(jq -r '.files[].path' <<<"${PR_JSON}")
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

fetch_check_runs() {
  gh api "repos/${REPO}/commits/${HEAD_SHA}/check-runs" --paginate \
    --jq '.check_runs[] | [.id, .name, .status, (.conclusion // "")] | @tsv'
}

evaluate_required_checks() {
  local pending=false
  local failed=false

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
    done < <(fetch_check_runs)

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

wait_for_required_checks() {
  local start
  start="$(date +%s)"
  while true; do
    set +e
    evaluate_required_checks
    local result=$?
    set -e
    if [[ "${result}" -eq 0 ]]; then
      log "All required checks passed on ${HEAD_SHA}"
      return 0
    fi
    if [[ "${result}" -eq 2 ]]; then
      fail "Required checks failed for PR #${PR_NUMBER}"
    fi
    if (( $(date +%s) - start >= MAX_WAIT_SECONDS )); then
      skip "Timed out after ${MAX_WAIT_SECONDS}s waiting for required checks on PR #${PR_NUMBER}"
    fi
    log "Waiting for required checks on ${HEAD_SHA}..."
    sleep "${POLL_SECONDS}"
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

wait_for_required_checks

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
