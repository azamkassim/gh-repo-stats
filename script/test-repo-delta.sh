#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM

mkdir -p "$TMP/control/output"

cat > "$TMP/previous.json" <<'JSON'
{
  "generated_at":"2026-08-22T10:00:00Z",
  "repositories":[
    {"full_name":"example/alpha","fork":false,"role":"OWN_PROJECT","pushed_at":"2026-08-20T10:00:00Z","open_issues":2,"health_state":"HEALTHY","health_score":100,"activity":"ACTIVE","attention_level":"NONE","attention":"NONE","visibility":"private","archived":false,"default_branch":"main"},
    {"full_name":"example/beta","fork":false,"role":"OWN_PROJECT","pushed_at":"2026-07-01T10:00:00Z","open_issues":0,"health_state":"OK","health_score":85,"activity":"CURRENT","attention_level":"NONE","attention":"NONE","visibility":"private","archived":false,"default_branch":"main"},
    {"full_name":"example/reference","fork":true,"role":"UPSTREAM_FORK","pushed_at":"2026-08-01T10:00:00Z","open_issues":1,"health_state":"REFERENCE","health_score":90,"activity":"ACTIVE","attention_level":"INFO","attention":"PUBLIC_FORK","visibility":"public","archived":false,"default_branch":"main"},
    {"full_name":"example/old-reference","fork":true,"role":"UPSTREAM_FORK","pushed_at":"2026-01-01T10:00:00Z","open_issues":0,"health_state":"REFERENCE","health_score":90,"activity":"DORMANT","attention_level":"INFO","attention":"PUBLIC_FORK","visibility":"public","archived":false,"default_branch":"main"}
  ]
}
JSON

cat > "$TMP/current.json" <<'JSON'
{
  "generated_at":"2026-08-29T10:00:00Z",
  "repositories":[
    {"full_name":"example/alpha","fork":false,"role":"OWN_PROJECT","pushed_at":"2026-08-29T09:00:00Z","open_issues":3,"health_state":"HEALTHY","health_score":100,"activity":"ACTIVE","attention_level":"NONE","attention":"NONE","visibility":"private","archived":false,"default_branch":"main"},
    {"full_name":"example/beta","fork":false,"role":"OWN_PROJECT","pushed_at":"2026-02-01T10:00:00Z","open_issues":0,"health_state":"WATCH","health_score":65,"activity":"AGING","attention_level":"WARN","attention":"DORMANT_180","visibility":"private","archived":false,"default_branch":"main"},
    {"full_name":"example/reference","fork":true,"role":"UPSTREAM_FORK","pushed_at":"2026-08-01T10:00:00Z","open_issues":1,"health_state":"REFERENCE","health_score":90,"activity":"ACTIVE","attention_level":"INFO","attention":"PUBLIC_FORK","visibility":"public","archived":false,"default_branch":"main"},
    {"full_name":"example/gamma","fork":false,"role":"OWN_PROJECT","pushed_at":"2026-08-28T10:00:00Z","open_issues":0,"health_state":"HEALTHY","health_score":100,"activity":"ACTIVE","attention_level":"NONE","attention":"NONE","visibility":"private","archived":false,"default_branch":"main"}
  ]
}
JSON

AZAM_REPO_CONTROL_OUTDIR="$TMP/control/output" \
  bash "$SCRIPT_DIR/azam-repo-delta.sh" "$TMP/previous.json" "$TMP/current.json" > "$TMP/run.txt"

DELTA="$TMP/control/output/repo-delta.json"
MD="$TMP/control/output/repo-delta.md"
HTML="$TMP/control/output/repo-delta.html"

test -s "$DELTA"
test -s "$MD"
test -s "$HTML"

jq -e '.status == "OK"' "$DELTA" >/dev/null
jq -e '.summary.changed == 2' "$DELTA" >/dev/null
jq -e '.summary.unchanged == 1' "$DELTA" >/dev/null
jq -e '.summary.new == 1' "$DELTA" >/dev/null
jq -e '.summary.removed == 1' "$DELTA" >/dev/null
jq -e '.summary.own_projects_changed == 3' "$DELTA" >/dev/null
jq -e '.summary.new_pushes == 2' "$DELTA" >/dev/null
jq -e '.summary.attention_escalations == 1' "$DELTA" >/dev/null
jq -e '.summary.open_item_increases == 1' "$DELTA" >/dev/null
jq -e '.changes | any(.full_name == "example/beta" and .attention_delta == 2 and .health_score_delta == -20)' "$DELTA" >/dev/null
jq -e '.changes | any(.full_name == "example/gamma" and .status == "NEW")' "$DELTA" >/dev/null
jq -e '.changes | any(.full_name == "example/old-reference" and .status == "REMOVED")' "$DELTA" >/dev/null

grep -q 'Repository Change Report' "$MD"
grep -q 'example/alpha' "$MD"
grep -q 'Repository Changes' "$HTML"
grep -q 'example/beta' "$HTML"

BASE="$TMP/baseline"
mkdir -p "$BASE"
cp "$TMP/current.json" "$BASE/repo-control-20260829-100000.json"
AZAM_REPO_CONTROL_OUTDIR="$BASE" bash "$SCRIPT_DIR/azam-repo-delta.sh" > "$TMP/baseline.txt"
jq -e '.status == "BASELINE_ONLY"' "$BASE/repo-delta.json" >/dev/null
grep -q 'Baseline only' "$BASE/repo-delta.md"

echo "PASS: Repository delta offline self-test"
