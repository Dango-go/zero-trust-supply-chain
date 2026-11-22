#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASELINE="${1:-${ROOT_DIR}/security/repo-baseline.json}"

if [[ ! -f "${BASELINE}" ]]; then
  echo "::error::Baseline file not found: ${BASELINE}"
  exit 1
fi

for cmd in jq gh; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "::error::Required command '${cmd}' is not installed."
    exit 1
  fi
done

# Resolve owner/repo from GITHUB_REPOSITORY or git remote
REPO="${GITHUB_REPOSITORY:-}"
if [[ -z "${REPO}" ]]; then
  REMOTE_URL="$(git -C "${ROOT_DIR}" remote get-url origin 2>/dev/null || true)"
  if [[ -n "${REMOTE_URL}" ]]; then
    REPO="$(sed -E 's#(git@github\.com:|https://github\.com/)##; s#\.git$##' <<<"${REMOTE_URL}")"
  fi
fi

if [[ -z "${REPO}" ]]; then
  REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
fi
if [[ -z "${REPO}" ]]; then
  echo "::error::Unable to determine GitHub repository (set GITHUB_REPOSITORY)."
  exit 1
fi

# if local start - gh auth login
export GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
DRIFT=0

ok()    { echo "[OK]    $*"; }
drift() { echo "[DRIFT] $*"; DRIFT=1; }
warn()  { echo "[WARN]  $*"; }

echo "==> Auditing GitHub repository '${REPO}' against ${BASELINE}"


# 1. Branch Protection / Rules for 'main'
BP_JSON=""
if BP_JSON="$(gh api "repos/${REPO}/branches/main/protection" 2>/dev/null)"; then
  exp_enforce_admins="$(jq -r '.branch_protection.main.enforce_admins' "${BASELINE}")"
  act_enforce_admins="$(jq -r '.enforce_admins.enabled // false' <<<"${BP_JSON}")"
  if [[ "${act_enforce_admins}" == "${exp_enforce_admins}" ]]; then
    ok "main.enforce_admins == ${exp_enforce_admins}"
  else
    drift "main.enforce_admins expected '${exp_enforce_admins}', got '${act_enforce_admins}'"
  fi

  exp_force_push="$(jq -r '.branch_protection.main.allow_force_pushes' "${BASELINE}")"
  act_force_push="$(jq -r '.allow_force_pushes.enabled // false' <<<"${BP_JSON}")"
  if [[ "${act_force_push}" == "${exp_force_push}" ]]; then
    ok "main.allow_force_pushes == ${exp_force_push}"
  else
    drift "main.allow_force_pushes expected '${exp_force_push}', got '${act_force_push}'"
  fi

  exp_deletions="$(jq -r '.branch_protection.main.allow_deletions' "${BASELINE}")"
  act_deletions="$(jq -r '.allow_deletions.enabled // false' <<<"${BP_JSON}")"
  if [[ "${act_deletions}" == "${exp_deletions}" ]]; then
    ok "main.allow_deletions == ${exp_deletions}"
  else
    drift "main.allow_deletions expected '${exp_deletions}', got '${act_deletions}'"
  fi

  exp_linear="$(jq -r '.branch_protection.main.required_linear_history' "${BASELINE}")"
  act_linear="$(jq -r '.required_linear_history.enabled // false' <<<"${BP_JSON}")"
  if [[ "${act_linear}" == "${exp_linear}" ]]; then
    ok "main.required_linear_history == ${exp_linear}"
  else
    drift "main.required_linear_history expected '${exp_linear}', got '${act_linear}'"
  fi

  exp_reviews="$(jq -r '.branch_protection.main.required_pull_request_reviews.required_approving_review_count' "${BASELINE}")"
  act_reviews="$(jq -r '.required_pull_request_reviews.required_approving_review_count // 0' <<<"${BP_JSON}")"
  if [[ "${act_reviews}" -ge "${exp_reviews}" ]]; then
    ok "main.required_approving_review_count (${act_reviews} >= ${exp_reviews})"
  else
    drift "main.required_approving_review_count expected >= ${exp_reviews}, got ${act_reviews}"
  fi

  exp_codeowner="$(jq -r '.branch_protection.main.required_pull_request_reviews.require_code_owner_reviews' "${BASELINE}")"
  act_codeowner="$(jq -r '.required_pull_request_reviews.require_code_owner_reviews // false' <<<"${BP_JSON}")"
  if [[ "${act_codeowner}" == "${exp_codeowner}" ]]; then
    ok "main.require_code_owner_reviews == ${exp_codeowner}"
  else
    drift "main.require_code_owner_reviews expected '${exp_codeowner}', got '${act_codeowner}'"
  fi

  exp_strict="$(jq -r '.branch_protection.main.required_status_checks.strict' "${BASELINE}")"
  act_strict="$(jq -r '.required_status_checks.strict // false' <<<"${BP_JSON}")"
  if [[ "${act_strict}" == "${exp_strict}" ]]; then
    ok "main.required_status_checks.strict == ${exp_strict}"
  else
    drift "main.required_status_checks.strict expected '${exp_strict}', got '${act_strict}'"
  fi

  while IFS= read -r ctx; do
    if jq -e --arg c "${ctx}" '(.required_status_checks.contexts // []) | index($c) != null' <<<"${BP_JSON}" >/dev/null; then
      ok "main.required_status_checks contains '${ctx}'"
    else
      drift "main.required_status_checks missing '${ctx}'"
    fi
  done < <(jq -r '.branch_protection.main.required_status_checks.contexts[]' "${BASELINE}")
else
  # Fallback to Repository Rules API (Rulesets)
  if RULES_JSON="$(gh api "repos/${REPO}/rules/branches/main" 2>/dev/null)" && [[ "$(jq 'length' <<<"${RULES_JSON}")" -gt 0 ]]; then
    ok "main branch protected via Repository Rulesets ($(jq 'length' <<<"${RULES_JSON}") active rules)"
  else
    drift "No branch protection or active ruleset found for 'main' (or insufficient token permissions)"
  fi
fi


# 2. Tag Protection Ruleset ('v*')
if RULESETS_JSON="$(gh api "repos/${REPO}/rulesets" 2>/dev/null)"; then
  if jq -e '.[] | select(.target == "tag" and .enforcement == "active")' <<<"${RULESETS_JSON}" >/dev/null; then
    ok "Active tag ruleset found"
  else
    drift "No active tag ruleset protecting release tags (v*) found"
  fi
else
  warn "Unable to query repos/${REPO}/rulesets (check token scope: administration:read)"
fi


# 3. Release Environment Protection ('release')
EXP_REVIEWERS="$(jq -r '.environments.release.required_reviewers' "${BASELINE}")"
if ENV_JSON="$(gh api "repos/${REPO}/environments/release" 2>/dev/null)"; then
  if [[ "${EXP_REVIEWERS}" == "true" ]]; then
    if jq -e '.protection_rules[]? | select(.type == "required_reviewers" and (.reviewers | length) > 0)' <<<"${ENV_JSON}" >/dev/null; then
      ok "Environment 'release' has required_reviewers configured"
    else
      drift "Environment 'release' is missing required_reviewers"
    fi
  fi
else
  drift "Environment 'release' not found or inaccessible"
fi

echo "=========================================================="
if [[ "${DRIFT}" -ne 0 ]]; then
  echo "Policy drift detected! Repository settings do not match ${BASELINE}."
  exit 1
fi
echo "All checked repository settings match ${BASELINE}."
