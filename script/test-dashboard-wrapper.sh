#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM

mkdir -p "$TMP/script" "$TMP/control/output" "$TMP/bin"
cp "$SCRIPT_DIR/azam-dashboard.sh" "$TMP/script/"

cat > "$TMP/script/test-project-manager.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "self-test-ok"
EOF

cat > "$TMP/script/azam-project-manager.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > "${AZAM_TEST_LOG}/manager-args.txt"
mkdir -p "${AZAM_REPO_CONTROL_OUTDIR}"
printf '<html>ok</html>\n' > "${AZAM_REPO_CONTROL_OUTDIR}/project-manager.html"
echo "manager-ok"
EOF

cat > "$TMP/bin/termux-open" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > "${AZAM_TEST_LOG}/open-args.txt"
EOF

chmod +x "$TMP/script/"*.sh "$TMP/bin/termux-open"
export AZAM_TEST_LOG="$TMP"
export AZAM_REPO_CONTROL_OUTDIR="$TMP/control/output"
export PATH="$TMP/bin:$PATH"

OUT1="$TMP/out1.txt"
bash "$TMP/script/azam-dashboard.sh" --no-refresh --no-open > "$OUT1"
grep -q 'self-test-ok' "$OUT1"
grep -q 'manager-ok' "$OUT1"
grep -q -- '--no-refresh' "$TMP/manager-args.txt"
test ! -f "$TMP/open-args.txt"

OUT2="$TMP/out2.txt"
bash "$TMP/script/azam-dashboard.sh" > "$OUT2"
grep -q 'self-test-ok' "$OUT2"
grep -q 'manager-ok' "$OUT2"
[[ "$(cat "$TMP/manager-args.txt")" == "" ]]
grep -q 'project-manager.html' "$TMP/open-args.txt"
grep -q 'Dashboard opened with termux-open.' "$OUT2"

if bash "$TMP/script/azam-dashboard.sh" --bad-option >/dev/null 2>&1; then
  echo "FAIL: unknown option unexpectedly succeeded" >&2
  exit 1
fi

echo "PASS: Dashboard wrapper offline self-test"
