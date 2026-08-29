#!/usr/bin/env bash
set -euo pipefail

# Repository Change Detector
# --------------------------
# Compares two Repository Control Center snapshots and reports meaningful changes.
# By default it compares the two newest repo-control-*.json files in control/output/.

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
JSON_OUT="${OUT_DIR}/repo-delta.json"
MD_OUT="${OUT_DIR}/repo-delta.md"
HTML_OUT="${OUT_DIR}/repo-delta.html"

mkdir -p "$OUT_DIR"

usage() {
  cat <<'EOF'
Usage: bash script/azam-repo-delta.sh [PREVIOUS_JSON CURRENT_JSON]

With no arguments, compare the two newest repo-control-*.json snapshots.
With two arguments, compare those explicit snapshot files.
EOF
}

if [[ "$#" -eq 0 ]]; then
  mapfile -t SNAPSHOTS < <(find "$OUT_DIR" -maxdepth 1 -type f -name 'repo-control-*.json' | sort)
  if [[ "${#SNAPSHOTS[@]}" -lt 2 ]]; then
    CURRENT="${SNAPSHOTS[-1]:-}"
    jq -n \
      --arg current "${CURRENT}" \
      '{schema_version:"1.0",status:"BASELINE_ONLY",message:"Need at least two timestamped repository snapshots before change detection is available.",previous_snapshot:null,current_snapshot:(if $current == "" then null else $current end),summary:{changed:0,new:0,removed:0,own_projects_changed:0,new_pushes:0,attention_escalations:0,attention_improvements:0,open_item_increases:0,open_item_decreases:0},changes:[]}' \
      > "$JSON_OUT"

    cat > "$MD_OUT" <<'EOF'
# Repository Change Report

Baseline only. At least two timestamped repository snapshots are required before changes can be calculated.
EOF

    cat > "$HTML_OUT" <<'EOF'
<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Repository Changes</title><style>body{font-family:system-ui,-apple-system,sans-serif;margin:0;background:#0d1117;color:#e6edf3}.wrap{max-width:760px;margin:auto;padding:20px}.box{background:#161b22;border:1px solid #30363d;border-radius:14px;padding:16px}.muted{color:#8b949e}</style></head><body><div class="wrap"><h1>Repository Changes</h1><div class="box"><b>Baseline only</b><p class="muted">Run the repository control center again later. Two timestamped snapshots are required before changes can be calculated.</p></div></div></body></html>
EOF

    echo "Repository Change Detector complete"
    echo "Baseline only: fewer than two snapshots are available."
    echo "Delta JSON: $JSON_OUT"
    echo "Delta MD  : $MD_OUT"
    echo "Delta HTML: $HTML_OUT"
    exit 0
  fi
  PREVIOUS="${SNAPSHOTS[$((${#SNAPSHOTS[@]} - 2))]}"
  CURRENT="${SNAPSHOTS[$((${#SNAPSHOTS[@]} - 1))]}"
elif [[ "$#" -eq 2 ]]; then
  PREVIOUS="$1"
  CURRENT="$2"
else
  usage >&2
  exit 2
fi

for file in "$PREVIOUS" "$CURRENT"; do
  if [[ ! -f "$file" ]]; then
    echo "ERROR: snapshot not found: $file" >&2
    exit 1
  fi
  jq -e '.repositories | type == "array"' "$file" >/dev/null || {
    echo "ERROR: invalid repository snapshot: $file" >&2
    exit 1
  }
done

jq -n \
  --slurpfile prev "$PREVIOUS" \
  --slurpfile curr "$CURRENT" \
  --arg previous_snapshot "$PREVIOUS" \
  --arg current_snapshot "$CURRENT" '
  def attention_rank($level):
    if $level == "ACTION" then 3
    elif $level == "WARN" then 2
    elif $level == "INFO" then 1
    else 0 end;

  def map_by_name($repos):
    reduce $repos[] as $r ({}; .[$r.full_name] = $r);

  def field_change($field; $before; $after):
    if (($before[$field] // null) != ($after[$field] // null))
    then {field:$field,before:($before[$field] // null),after:($after[$field] // null)}
    else empty end;

  ($prev[0]) as $p |
  ($curr[0]) as $c |
  (map_by_name($p.repositories // [])) as $pm |
  (map_by_name($c.repositories // [])) as $cm |
  ((($pm|keys_unsorted) + ($cm|keys_unsorted)) | unique | sort) as $names |

  [
    $names[] as $name |
    ($pm[$name] // null) as $before |
    ($cm[$name] // null) as $after |
    if $before == null then
      {
        full_name:$name,
        status:"NEW",
        own_project:(($after.fork // false) == false),
        role:($after.role // null),
        new_push:false,
        open_item_delta:null,
        attention_delta:attention_rank($after.attention_level // "NONE"),
        health_score_delta:null,
        changes:[{field:"repository",before:null,after:"NEW"}]
      }
    elif $after == null then
      {
        full_name:$name,
        status:"REMOVED",
        own_project:(($before.fork // false) == false),
        role:($before.role // null),
        new_push:false,
        open_item_delta:null,
        attention_delta:(0 - attention_rank($before.attention_level // "NONE")),
        health_score_delta:null,
        changes:[{field:"repository",before:"PRESENT",after:null}]
      }
    else
      ([
        field_change("pushed_at"; $before; $after),
        field_change("open_issues"; $before; $after),
        field_change("health_state"; $before; $after),
        field_change("health_score"; $before; $after),
        field_change("activity"; $before; $after),
        field_change("attention_level"; $before; $after),
        field_change("attention"; $before; $after),
        field_change("visibility"; $before; $after),
        field_change("archived"; $before; $after),
        field_change("default_branch"; $before; $after)
      ]) as $changes |
      {
        full_name:$name,
        status:(if ($changes|length) > 0 then "CHANGED" else "UNCHANGED" end),
        own_project:(($after.fork // false) == false),
        role:($after.role // null),
        new_push:(($before.pushed_at // null) != ($after.pushed_at // null) and ($after.pushed_at // null) != null),
        open_item_delta:(if (($before.open_issues|type) == "number" and ($after.open_issues|type) == "number") then ($after.open_issues - $before.open_issues) else null end),
        attention_delta:(attention_rank($after.attention_level // "NONE") - attention_rank($before.attention_level // "NONE")),
        health_score_delta:(if (($before.health_score|type) == "number" and ($after.health_score|type) == "number") then ($after.health_score - $before.health_score) else null end),
        before:{health_state:$before.health_state,health_score:$before.health_score,activity:$before.activity,attention_level:$before.attention_level,attention:$before.attention,open_issues:$before.open_issues,pushed_at:$before.pushed_at},
        after:{health_state:$after.health_state,health_score:$after.health_score,activity:$after.activity,attention_level:$after.attention_level,attention:$after.attention,open_issues:$after.open_issues,pushed_at:$after.pushed_at},
        changes:$changes
      }
    end
  ] as $items |
  ($items | map(select(.status != "UNCHANGED"))) as $changed |
  {
    schema_version:"1.0",
    status:"OK",
    previous_snapshot:$previous_snapshot,
    current_snapshot:$current_snapshot,
    previous_generated_at:($p.generated_at // null),
    current_generated_at:($c.generated_at // null),
    note:"open_item_delta is based on GitHub repository open_issues_count and can include pull requests as well as issues.",
    summary:{
      repositories_compared:($items|length),
      changed:($items|map(select(.status == "CHANGED"))|length),
      unchanged:($items|map(select(.status == "UNCHANGED"))|length),
      new:($items|map(select(.status == "NEW"))|length),
      removed:($items|map(select(.status == "REMOVED"))|length),
      own_projects_changed:($changed|map(select(.own_project == true))|length),
      new_pushes:($items|map(select(.new_push == true))|length),
      attention_escalations:($items|map(select((.attention_delta // 0) > 0))|length),
      attention_improvements:($items|map(select((.attention_delta // 0) < 0))|length),
      open_item_increases:($items|map(select((.open_item_delta // 0) > 0))|length),
      open_item_decreases:($items|map(select((.open_item_delta // 0) < 0))|length)
    },
    changes:$changed
  }
' > "$JSON_OUT"

{
  echo "# Repository Change Report"
  echo
  echo "Previous: $(jq -r '.previous_generated_at // "unknown"' "$JSON_OUT")"
  echo "Current: $(jq -r '.current_generated_at // "unknown"' "$JSON_OUT")"
  echo
  echo "## Summary"
  echo
  jq -r '
    "- Changed repositories: \(.summary.changed)\n" +
    "- New repositories: \(.summary.new)\n" +
    "- Removed repositories: \(.summary.removed)\n" +
    "- Own projects changed: \(.summary.own_projects_changed)\n" +
    "- New pushes: \(.summary.new_pushes)\n" +
    "- Attention escalations: \(.summary.attention_escalations)\n" +
    "- Attention improvements: \(.summary.attention_improvements)\n" +
    "- Open-item increases: \(.summary.open_item_increases)\n" +
    "- Open-item decreases: \(.summary.open_item_decreases)"
  ' "$JSON_OUT"
  echo
  echo "## Changes"
  echo
  echo '| Repository | Status | Push | Open-item Δ | Attention Δ | Health-score Δ |'
  echo '|---|---|---|---:|---:|---:|'
  jq -r '.changes[] | "| \(.full_name) | \(.status) | \(if .new_push then "YES" else "-" end) | \(.open_item_delta // "-") | \(.attention_delta // "-") | \(.health_score_delta // "-") |"' "$JSON_OUT"
  echo
  echo "> Open-item changes use GitHub repository open_issues_count, which can include pull requests as well as issues."
} > "$MD_OUT"

jq -r '
  def h: @html;
  def badge:
    if . == "NEW" then "good"
    elif . == "REMOVED" then "bad"
    else "neutral" end;
  "<!doctype html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>Repository Changes</title>" +
  "<style>body{font-family:system-ui,-apple-system,sans-serif;margin:0;background:#0d1117;color:#e6edf3}.wrap{max-width:900px;margin:auto;padding:18px}.muted{color:#8b949e}.summary{display:grid;grid-template-columns:repeat(auto-fit,minmax(120px,1fr));gap:10px;margin:18px 0}.metric,.change{background:#161b22;border:1px solid #30363d;border-radius:13px;padding:13px}.metric b{display:block;font-size:1.55rem}.changes{display:grid;gap:10px}.head{display:flex;justify-content:space-between;gap:10px}.name{font-weight:750;overflow-wrap:anywhere}.pill{display:inline-block;border-radius:999px;padding:3px 8px;font-size:.75rem;font-weight:700}.good{background:#1f6f43}.neutral{background:#30363d}.bad{background:#8e2c2c}.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:8px;margin-top:10px}.kv{background:#0d1117;border-radius:9px;padding:9px}.kv span{display:block;color:#8b949e;font-size:.72rem}.note{margin-top:16px;padding:12px;border-left:3px solid #58a6ff;background:#161b22}@media(max-width:620px){.grid{grid-template-columns:1fr 1fr}h1{font-size:2rem}}@media(max-width:390px){.grid{grid-template-columns:1fr}}</style></head><body><div class=\"wrap\">" +
  "<h1>Repository Changes</h1><div class=\"muted\">" + ((.previous_generated_at // "unknown")|h) + " → " + ((.current_generated_at // "unknown")|h) + "</div>" +
  "<div class=\"summary\"><div class=\"metric\"><span class=\"muted\">Changed</span><b>" + (.summary.changed|tostring) + "</b></div><div class=\"metric\"><span class=\"muted\">New pushes</span><b>" + (.summary.new_pushes|tostring) + "</b></div><div class=\"metric\"><span class=\"muted\">Attention up</span><b>" + (.summary.attention_escalations|tostring) + "</b></div><div class=\"metric\"><span class=\"muted\">Own changed</span><b>" + (.summary.own_projects_changed|tostring) + "</b></div></div>" +
  "<div class=\"changes\">" +
  (.changes | map("<div class=\"change\"><div class=\"head\"><div class=\"name\">" + (.full_name|h) + "</div><span class=\"pill " + ((.status|badge)|h) + "\">" + (.status|h) + "</span></div><div class=\"grid\"><div class=\"kv\"><span>New push</span><b>" + (if .new_push then "YES" else "-" end) + "</b></div><div class=\"kv\"><span>Open-item Δ</span><b>" + ((.open_item_delta // "-")|tostring|h) + "</b></div><div class=\"kv\"><span>Attention Δ</span><b>" + ((.attention_delta // "-")|tostring|h) + "</b></div><div class=\"kv\"><span>Health-score Δ</span><b>" + ((.health_score_delta // "-")|tostring|h) + "</b></div></div></div>") | join("")) +
  "</div><div class=\"note\">Open-item changes use GitHub repository <code>open_issues_count</code>, which can include pull requests as well as issues.</div></div></body></html>"
' "$JSON_OUT" > "$HTML_OUT"

jq -r '
  "Repository Change Detector complete\n" +
  "Changed: \(.summary.changed) | New: \(.summary.new) | Removed: \(.summary.removed) | Own changed: \(.summary.own_projects_changed)\n" +
  "New pushes: \(.summary.new_pushes) | Attention up: \(.summary.attention_escalations) | Attention down: \(.summary.attention_improvements) | Open items up: \(.summary.open_item_increases)"
' "$JSON_OUT"

echo "Delta JSON: $JSON_OUT"
echo "Delta MD  : $MD_OUT"
echo "Delta HTML: $HTML_OUT"
