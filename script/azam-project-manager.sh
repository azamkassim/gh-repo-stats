#!/usr/bin/env bash
set -euo pipefail

# Azam Project Manager
# --------------------
# Management projection over the local Repository Control Center inventory.
# Own projects are primary. Upstream forks are secondary reference material.
# No repository names are hard-coded; all data comes from local latest.json.

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $1" >&2
    exit 1
  fi
}

require_cmd jq

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUT_DIR="${AZAM_REPO_CONTROL_OUTDIR:-${REPO_ROOT}/control/output}"
INVENTORY="${OUT_DIR}/latest.json"
HTML_OUT="${OUT_DIR}/project-manager.html"
MD_OUT="${OUT_DIR}/project-manager.md"

if [[ "${1:-}" != "--no-refresh" ]]; then
  bash "${SCRIPT_DIR}/azam-repo-control.sh"
fi

if [[ ! -f "${INVENTORY}" ]]; then
  echo "ERROR: inventory not found: ${INVENTORY}" >&2
  echo "Run: bash script/azam-repo-control.sh" >&2
  exit 1
fi

jq -e '.repositories | type == "array"' "${INVENTORY}" >/dev/null || {
  echo "ERROR: invalid Repository Control Center inventory." >&2
  exit 1
}

# Concise text/Markdown management view.
{
  echo "# Project Manager"
  echo
  echo "Generated from Repository Control Center inventory: $(jq -r '.generated_at' "${INVENTORY}")"
  echo
  jq -r '
    (.repositories | map(select(.fork == false))) as $own |
    "## Management Summary\n\n" +
    "- Own projects: \($own | length)\n" +
    "- Active own projects: \($own | map(select(.activity == \"ACTIVE\")) | length)\n" +
    "- Own projects needing review: \($own | map(select(.attention_level == \"WARN\" or .attention_level == \"ACTION\")) | length)\n" +
    "- Reference forks: \(.repositories | map(select(.fork == true)) | length)"
  ' "${INVENTORY}"
  echo
  echo "## Own Projects"
  echo
  echo '| Repository | Health | Score | Activity | Attention | Issues | Last Push |'
  echo '|---|---|---:|---|---|---:|---|'
  jq -r '
    def rank: if .attention_level == "ACTION" then 0 elif .attention_level == "WARN" then 1 else 2 end;
    [.repositories[] | select(.fork == false)]
    | sort_by(rank, .health_score, .full_name)
    | .[]
    | "| \(.full_name) | \(.health_state) | \(.health_score) | \(.activity) | \(.attention_level):\(.attention) | \(.open_issues) | \(.pushed_at // \"-\") |"
  ' "${INVENTORY}"
  echo
  echo "## Reference Forks"
  echo
  echo "Upstream forks are reference/dependency material and do not compete with own projects for management priority."
} > "${MD_OUT}"

# Local, dependency-free HTML management dashboard.
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
  def rank:
    if .attention_level == "ACTION" then 0
    elif .attention_level == "WARN" then 1
    else 2 end;
  (.repositories | map(select(.fork == false)) | sort_by(rank, .health_score, .full_name)) as $own |
  (.repositories | map(select(.fork == true)) | sort_by(.full_name)) as $forks |
  ($own | map(select(.activity == "ACTIVE")) | length) as $own_active |
  ($own | map(select(.attention_level == "WARN" or .attention_level == "ACTION")) | length) as $own_review |
  "<!doctype html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>Project Manager</title>" +
  "<style>body{font-family:system-ui,-apple-system,sans-serif;margin:0;background:#0d1117;color:#e6edf3}.wrap{max-width:980px;margin:auto;padding:18px}.muted{color:#8b949e}.summary{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin:18px 0}.metric,.project,.refbox{background:#161b22;border:1px solid #30363d;border-radius:14px;padding:14px}.metric b{font-size:1.65rem;display:block}.section-title{margin:24px 0 12px}.projects{display:grid;gap:12px}.head{display:flex;justify-content:space-between;align-items:flex-start;gap:10px}.name{font-weight:750;font-size:1.05rem;overflow-wrap:anywhere}.sub{font-size:.82rem;color:#8b949e;margin-top:4px}.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:9px;margin-top:12px}.kv{background:#0d1117;border-radius:10px;padding:9px;min-width:0}.kv span{display:block;color:#8b949e;font-size:.72rem;margin-bottom:4px}.kv strong{font-size:.9rem;overflow-wrap:anywhere}.pill{display:inline-block;border-radius:999px;padding:3px 8px;font-size:.76rem;font-weight:700}.good{background:#1f6f43}.neutral{background:#30363d}.warn{background:#7a4f01}.bad{background:#8e2c2c}a{color:#58a6ff;text-decoration:none}details{margin-top:18px;background:#161b22;border:1px solid #30363d;border-radius:14px;padding:12px}summary{cursor:pointer;font-weight:700}.refs{display:grid;gap:8px;margin-top:12px}.ref{display:flex;justify-content:space-between;gap:10px;padding:9px;background:#0d1117;border-radius:9px;overflow-wrap:anywhere}.note{margin-top:18px;padding:12px;border-left:3px solid #58a6ff;background:#161b22}@media(max-width:700px){.wrap{padding:16px}.summary{grid-template-columns:1fr 1fr}.summary .metric:last-child{grid-column:1/-1}.grid{grid-template-columns:1fr 1fr}h1{font-size:2rem;line-height:1.08}}@media(max-width:390px){.grid{grid-template-columns:1fr}}</style></head><body><div class=\"wrap\">" +
  "<h1>Project Manager</h1><div class=\"muted\">Own projects first · generated " + (.generated_at|h) + "</div>" +
  "<div class=\"summary\"><div class=\"metric\"><span class=\"muted\">Own projects</span><b>" + ($own|length|tostring) + "</b></div><div class=\"metric\"><span class=\"muted\">Active own</span><b>" + ($own_active|tostring) + "</b></div><div class=\"metric\"><span class=\"muted\">Own need review</span><b>" + ($own_review|tostring) + "</b></div></div>" +
  "<h2 class=\"section-title\">Own Projects</h2><div class=\"projects\">" +
  ($own | map(
    "<div class=\"project\"><div class=\"head\"><div><a class=\"name\" href=\"" + (.url|h) + "\">" + (.full_name|h) + "</a><div class=\"sub\">" + (.visibility|h) + (if .project then " · " + (.project|h) else "" end) + (if .lifecycle then " · " + (.lifecycle|h) else "" end) + "</div></div><span class=\"pill " + ((.health_state|state_class)|h) + "\">" + (.health_state|h) + "</span></div>" +
    (if .purpose then "<div class=\"sub\" style=\"margin-top:9px\">" + (.purpose|h) + "</div>" else "" end) +
    "<div class=\"grid\"><div class=\"kv\"><span>Health score</span><strong>" + (.health_score|tostring) + "</strong></div><div class=\"kv\"><span>Activity</span><strong>" + (.activity|h) + "</strong></div><div class=\"kv\"><span>Attention</span><strong><span class=\"pill " + ((.attention_level|attention_class)|h) + "\">" + (.attention_level|h) + "</span> " + (.attention|h) + "</strong></div><div class=\"kv\"><span>Open issues</span><strong>" + (.open_issues|tostring) + "</strong></div><div class=\"kv\"><span>Last push</span><strong>" + ((.pushed_at // "-")|h) + "</strong></div><div class=\"kv\"><span>Branch</span><strong>" + (.default_branch|h) + "</strong></div></div></div>"
  ) | join("")) +
  "</div>" +
  "<details><summary>Reference forks (" + ($forks|length|tostring) + ")</summary><div class=\"refs\">" +
  ($forks | map("<div class=\"ref\"><a href=\"" + (.url|h) + "\">" + (.full_name|h) + "</a><span class=\"muted\">" + (.activity|h) + "</span></div>") | join("")) +
  "</div></details>" +
  "<div class=\"note\">Management priority is based only on repository lifecycle/activity and attention flags. It does not assess code quality, security, business importance, or NEXUS banking authority. Generated data remains local.</div>" +
  "</div></body></html>"
' "${INVENTORY}" > "${HTML_OUT}"

jq -r '
  (.repositories | map(select(.fork == false))) as $own |
  "Project Manager complete\n" +
  "Own: \($own|length) | Active own: \($own|map(select(.activity == \"ACTIVE\"))|length) | Own need review: \($own|map(select(.attention_level == \"WARN\" or .attention_level == \"ACTION\"))|length) | Reference forks: \(.repositories|map(select(.fork == true))|length)"
' "${INVENTORY}"

echo "Manager MD  : ${MD_OUT}"
echo "Manager HTML: ${HTML_OUT}"
