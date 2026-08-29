#!/usr/bin/env bash
set -euo pipefail

# Azam Repository Control Center
# --------------------------------
# Read-only inventory of repositories accessible to the authenticated GitHub user.
# Generated output is local-only by default and should remain ignored by Git.

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $1" >&2
    exit 1
  fi
}

require_cmd gh
require_cmd jq

OWNER="${AZAM_REPO_OWNER:-$(gh api user --jq '.login')}"
OUT_DIR="${AZAM_REPO_CONTROL_OUTDIR:-control/output}"
OVERRIDES_FILE="${AZAM_REPO_OVERRIDES:-control/project-overrides.json}"
STAMP="$(date +%Y%m%d-%H%M%S)"
JSON_OUT="${OUT_DIR}/repo-control-${STAMP}.json"
CSV_OUT="${OUT_DIR}/repo-control-${STAMP}.csv"
MD_OUT="${OUT_DIR}/repo-control-${STAMP}.md"
LATEST_JSON="${OUT_DIR}/latest.json"
LATEST_CSV="${OUT_DIR}/latest.csv"
LATEST_MD="${OUT_DIR}/latest.md"

mkdir -p "${OUT_DIR}"
TMP_REPOS="$(mktemp)"
TMP_OVERRIDES="$(mktemp)"
trap 'rm -f "${TMP_REPOS}" "${TMP_OVERRIDES}"' EXIT INT TERM

if [[ -f "${OVERRIDES_FILE}" ]]; then
  jq -e 'type == "object"' "${OVERRIDES_FILE}" >/dev/null || {
    echo "ERROR: ${OVERRIDES_FILE} must contain a JSON object keyed by full repository name." >&2
    exit 1
  }
  cp "${OVERRIDES_FILE}" "${TMP_OVERRIDES}"
else
  printf '{}\n' > "${TMP_OVERRIDES}"
fi

echo "Collecting repository metadata for ${OWNER}..."

# The endpoint is read-only. --paginate + --slurp preserves all pages before flattening.
gh api --paginate --slurp \
  -H 'Accept: application/vnd.github+json' \
  'user/repos?per_page=100&affiliation=owner&sort=updated' \
  | jq 'add // []' > "${TMP_REPOS}"

jq \
  --arg owner "${OWNER}" \
  --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --slurpfile overrides "${TMP_OVERRIDES}" '
  def age_days:
    if .pushed_at == null then null
    else (((now - (.pushed_at | fromdateiso8601)) / 86400) | floor)
    end;

  def activity($days):
    if .archived then "ARCHIVED"
    elif .pushed_at == null then "UNKNOWN"
    elif $days <= 30 then "ACTIVE"
    elif $days <= 90 then "CURRENT"
    elif $days <= 180 then "AGING"
    else "DORMANT"
    end;

  def repo_role:
    if .fork then "UPSTREAM_FORK" else "OWN_PROJECT" end;

  def attention($days):
    if .archived then "NONE"
    elif .fork and .private == false then "REVIEW_PUBLIC_FORK"
    elif $days != null and $days > 180 then "REVIEW_DORMANT"
    else "NONE"
    end;

  ($overrides[0] // {}) as $o |
  map(select(.owner.login == $owner)) |
  map(
    . as $r |
    (age_days) as $days |
    ($o[$r.full_name] // {}) as $custom |
    {
      name: $r.name,
      full_name: $r.full_name,
      visibility: $r.visibility,
      private: $r.private,
      fork: $r.fork,
      archived: $r.archived,
      role: repo_role,
      activity: activity($days),
      attention: attention($days),
      age_since_push_days: $days,
      size_kb: $r.size,
      default_branch: $r.default_branch,
      open_issues: $r.open_issues_count,
      created_at: $r.created_at,
      updated_at: $r.updated_at,
      pushed_at: $r.pushed_at,
      url: $r.html_url,
      project: ($custom.project // null),
      purpose: ($custom.purpose // null),
      lifecycle: ($custom.lifecycle // null),
      notes: ($custom.notes // null)
    }
  ) as $repos |
  {
    schema_version: "1.0",
    generated_at: $generated_at,
    owner: $owner,
    privacy: "Generated locally. Do not commit control/output or project-overrides.json.",
    summary: {
      total: ($repos | length),
      public: ($repos | map(select(.private == false)) | length),
      private: ($repos | map(select(.private == true)) | length),
      own_projects: ($repos | map(select(.fork == false)) | length),
      upstream_forks: ($repos | map(select(.fork == true)) | length),
      active: ($repos | map(select(.activity == "ACTIVE")) | length),
      needs_review: ($repos | map(select(.attention != "NONE")) | length)
    },
    repositories: ($repos | sort_by(.full_name))
  }
' "${TMP_REPOS}" > "${JSON_OUT}"

jq -r '
  ["full_name","visibility","role","activity","attention","age_since_push_days","size_kb","default_branch","open_issues","project","purpose","lifecycle","pushed_at","url"],
  (.repositories[] | [
    .full_name,
    .visibility,
    .role,
    .activity,
    .attention,
    (.age_since_push_days // ""),
    .size_kb,
    .default_branch,
    .open_issues,
    (.project // ""),
    (.purpose // ""),
    (.lifecycle // ""),
    (.pushed_at // ""),
    .url
  ]) | @csv
' "${JSON_OUT}" > "${CSV_OUT}"

{
  echo "# Repository Control Report"
  echo
  echo "Generated: $(jq -r '.generated_at' "${JSON_OUT}")"
  echo
  echo "## Summary"
  echo
  jq -r '
    "- Total repositories: \(.summary.total)\n" +
    "- Public: \(.summary.public)\n" +
    "- Private: \(.summary.private)\n" +
    "- Own projects: \(.summary.own_projects)\n" +
    "- Upstream forks: \(.summary.upstream_forks)\n" +
    "- Active (push <=30 days): \(.summary.active)\n" +
    "- Needs review: \(.summary.needs_review)"
  ' "${JSON_OUT}"
  echo
  echo "## Repository Inventory"
  echo
  echo '| Repository | Visibility | Role | Activity | Attention | Last Push | Project |'
  echo '|---|---|---|---|---|---|---|'
  jq -r '.repositories[] | "| \(.full_name) | \(.visibility) | \(.role) | \(.activity) | \(.attention) | \(.pushed_at // "-") | \(.project // "-") |"' "${JSON_OUT}"
  echo
  echo "> Local governance report only. It is not a NEXUS banking engine and must not contain banking/customer data or credentials."
} > "${MD_OUT}"

cp "${JSON_OUT}" "${LATEST_JSON}"
cp "${CSV_OUT}" "${LATEST_CSV}"
cp "${MD_OUT}" "${LATEST_MD}"

jq -r '
  "Repository Control Center complete\n" +
  "Total: \(.summary.total) | Public: \(.summary.public) | Private: \(.summary.private) | Forks: \(.summary.upstream_forks) | Needs review: \(.summary.needs_review)"
' "${JSON_OUT}"

echo "JSON: ${JSON_OUT}"
echo "CSV : ${CSV_OUT}"
echo "MD  : ${MD_OUT}"
echo "Latest report: ${LATEST_MD}"
