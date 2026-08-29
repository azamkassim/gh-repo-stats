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
HTML_OUT="${OUT_DIR}/repo-control-${STAMP}.html"
LATEST_JSON="${OUT_DIR}/latest.json"
LATEST_CSV="${OUT_DIR}/latest.csv"
LATEST_MD="${OUT_DIR}/latest.md"
LATEST_HTML="${OUT_DIR}/latest.html"

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

# Read-only endpoint. --paginate + --slurp preserves all pages before flattening.
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

  # Operational activity score only. It is not a code-quality or security score.
  def health($days):
    if .archived then {state: "ARCHIVED", score: 100}
    elif .fork then {state: "REFERENCE", score: 90}
    elif .pushed_at == null then {state: "REVIEW", score: 50}
    elif $days <= 30 then {state: "HEALTHY", score: 100}
    elif $days <= 90 then {state: "OK", score: 85}
    elif $days <= 180 then {state: "WATCH", score: 65}
    else {state: "REVIEW", score: 40}
    end;

  # Public/private fork status is informational. Only WARN/ACTION contributes to needs_review.
  def attention($days):
    if .archived then {level: "NONE", code: "NONE"}
    elif .fork and .private == false then {level: "INFO", code: "PUBLIC_FORK"}
    elif .fork then {level: "INFO", code: "PRIVATE_FORK"}
    elif .pushed_at == null then {level: "ACTION", code: "NO_PUSH_HISTORY"}
    elif $days > 365 then {level: "ACTION", code: "DORMANT_365"}
    elif $days > 180 then {level: "WARN", code: "DORMANT_180"}
    else {level: "NONE", code: "NONE"}
    end;

  ($overrides[0] // {}) as $o |
  map(select(.owner.login == $owner)) |
  map(
    . as $r |
    (age_days) as $days |
    (health($days)) as $health |
    (attention($days)) as $attention |
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
      health_state: $health.state,
      health_score: $health.score,
      attention_level: $attention.level,
      attention: $attention.code,
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
    schema_version: "1.1",
    generated_at: $generated_at,
    owner: $owner,
    privacy: "Generated locally. Do not commit control/output or project-overrides.json.",
    score_note: "Health score reflects repository activity/lifecycle only; it is not a code-quality or security assessment.",
    summary: {
      total: ($repos | length),
      public: ($repos | map(select(.private == false)) | length),
      private: ($repos | map(select(.private == true)) | length),
      own_projects: ($repos | map(select(.fork == false)) | length),
      upstream_forks: ($repos | map(select(.fork == true)) | length),
      active: ($repos | map(select(.activity == "ACTIVE")) | length),
      healthy_or_reference: ($repos | map(select(.health_state == "HEALTHY" or .health_state == "REFERENCE" or .health_state == "ARCHIVED")) | length),
      informational: ($repos | map(select(.attention_level == "INFO")) | length),
      warnings: ($repos | map(select(.attention_level == "WARN")) | length),
      actions: ($repos | map(select(.attention_level == "ACTION")) | length),
      needs_review: ($repos | map(select(.attention_level == "WARN" or .attention_level == "ACTION")) | length)
    },
    repositories: ($repos | sort_by(.full_name))
  }
' "${TMP_REPOS}" > "${JSON_OUT}"

jq -r '
  ["full_name","visibility","role","health_state","health_score","activity","attention_level","attention","age_since_push_days","size_kb","default_branch","open_issues","project","purpose","lifecycle","pushed_at","url"],
  (.repositories[] | [
    .full_name,
    .visibility,
    .role,
    .health_state,
    .health_score,
    .activity,
    .attention_level,
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
    "- Informational flags: \(.summary.informational)\n" +
    "- Warnings: \(.summary.warnings)\n" +
    "- Actions: \(.summary.actions)\n" +
    "- Needs review: \(.summary.needs_review)"
  ' "${JSON_OUT}"
  echo
  echo "## Repository Inventory"
  echo
  echo '| Repository | Visibility | Role | Health | Score | Activity | Attention | Last Push | Project |'
  echo '|---|---|---|---|---:|---|---|---|---|'
  jq -r '.repositories[] | "| \(.full_name) | \(.visibility) | \(.role) | \(.health_state) | \(.health_score) | \(.activity) | \(.attention_level):\(.attention) | \(.pushed_at // "-") | \(.project // "-") |"' "${JSON_OUT}"
  echo
  echo "> Health score reflects repository activity/lifecycle only. It is not a code-quality or security assessment."
  echo
  echo "> Local governance report only. It is not a NEXUS banking engine and must not contain banking/customer data or credentials."
} > "${MD_OUT}"

jq -r '
  def h: @html;
  def state_class:
    if . == "HEALTHY" then "good"
    elif . == "REFERENCE" or . == "OK" or . == "ARCHIVED" then "neutral"
    elif . == "WATCH" then "warn"
    else "bad" end;
  def attention_class:
    if . == "ACTION" then "bad"
    elif . == "WARN" then "warn"
    elif . == "INFO" then "neutral"
    else "good" end;
  "<!doctype html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>Repository Control Center</title>" +
  "<style>body{font-family:system-ui,-apple-system,sans-serif;margin:0;background:#0d1117;color:#e6edf3}.wrap{max-width:1200px;margin:auto;padding:18px}.muted{color:#8b949e}.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(130px,1fr));gap:10px;margin:18px 0}.card{background:#161b22;border:1px solid #30363d;border-radius:12px;padding:14px}.card b{font-size:1.6rem;display:block}.table{overflow:auto;border:1px solid #30363d;border-radius:12px}table{border-collapse:collapse;width:100%;background:#161b22}th,td{padding:10px;border-bottom:1px solid #30363d;text-align:left;white-space:nowrap}th{position:sticky;top:0;background:#21262d}.pill{border-radius:999px;padding:3px 8px;font-size:.78rem;font-weight:650}.good{background:#1f6f43}.neutral{background:#30363d}.warn{background:#7a4f01}.bad{background:#8e2c2c}a{color:#58a6ff;text-decoration:none}.note{margin-top:16px;padding:12px;border-left:3px solid #58a6ff;background:#161b22}</style></head><body><div class=\"wrap\">" +
  "<h1>Repository Control Center</h1><div class=\"muted\">Generated " + (.generated_at|h) + " · owner " + (.owner|h) + "</div>" +
  "<div class=\"cards\">" +
    "<div class=\"card\"><span class=\"muted\">Total</span><b>" + (.summary.total|tostring) + "</b></div>" +
    "<div class=\"card\"><span class=\"muted\">Own projects</span><b>" + (.summary.own_projects|tostring) + "</b></div>" +
    "<div class=\"card\"><span class=\"muted\">Upstream forks</span><b>" + (.summary.upstream_forks|tostring) + "</b></div>" +
    "<div class=\"card\"><span class=\"muted\">Active</span><b>" + (.summary.active|tostring) + "</b></div>" +
    "<div class=\"card\"><span class=\"muted\">Info</span><b>" + (.summary.informational|tostring) + "</b></div>" +
    "<div class=\"card\"><span class=\"muted\">Needs review</span><b>" + (.summary.needs_review|tostring) + "</b></div>" +
  "</div>" +
  "<div class=\"table\"><table><thead><tr><th>Repository</th><th>Visibility</th><th>Role</th><th>Health</th><th>Score</th><th>Activity</th><th>Attention</th><th>Last push</th><th>Issues</th></tr></thead><tbody>" +
  (.repositories | map(
    "<tr><td><a href=\"" + (.url|h) + "\">" + (.full_name|h) + "</a></td>" +
    "<td>" + (.visibility|h) + "</td>" +
    "<td>" + (.role|h) + "</td>" +
    "<td><span class=\"pill " + ((.health_state|state_class)|h) + "\">" + (.health_state|h) + "</span></td>" +
    "<td>" + (.health_score|tostring) + "</td>" +
    "<td>" + (.activity|h) + "</td>" +
    "<td><span class=\"pill " + ((.attention_level|attention_class)|h) + "\">" + (.attention_level|h) + "</span> " + (.attention|h) + "</td>" +
    "<td>" + ((.pushed_at // "-")|h) + "</td>" +
    "<td>" + (.open_issues|tostring) + "</td></tr>"
  ) | join("")) +
  "</tbody></table></div>" +
  "<div class=\"note\">Health score reflects activity/lifecycle only; it is not a code-quality or security assessment. Generated data is local and may include private repository metadata. Do not commit <code>control/output/</code>.</div>" +
  "</div></body></html>"
' "${JSON_OUT}" > "${HTML_OUT}"

cp "${JSON_OUT}" "${LATEST_JSON}"
cp "${CSV_OUT}" "${LATEST_CSV}"
cp "${MD_OUT}" "${LATEST_MD}"
cp "${HTML_OUT}" "${LATEST_HTML}"

jq -r '
  "Repository Control Center complete\n" +
  "Total: \(.summary.total) | Public: \(.summary.public) | Private: \(.summary.private) | Forks: \(.summary.upstream_forks)\n" +
  "Info: \(.summary.informational) | Warnings: \(.summary.warnings) | Actions: \(.summary.actions) | Needs review: \(.summary.needs_review)"
' "${JSON_OUT}"

echo "JSON: ${JSON_OUT}"
echo "CSV : ${CSV_OUT}"
echo "MD  : ${MD_OUT}"
echo "HTML: ${HTML_OUT}"
echo "Latest report   : ${LATEST_MD}"
echo "Latest dashboard: ${LATEST_HTML}"
