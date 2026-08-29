#!/usr/bin/env bash
set -euo pipefail

# One-command launcher for the local Repository Control Center / Project Manager.
# Sequence: self-test -> refresh/build -> open local dashboard when supported.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DASHBOARD="${AZAM_REPO_CONTROL_OUTDIR:-${REPO_ROOT}/control/output}/project-manager.html"

NO_OPEN=0
NO_REFRESH=0

usage() {
  cat <<'EOF'
Usage: bash script/azam-dashboard.sh [--no-open] [--no-refresh]

  --no-open     Build the dashboard but do not open it.
  --no-refresh  Reuse the current local inventory instead of querying GitHub.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --no-open) NO_OPEN=1 ;;
    --no-refresh) NO_REFRESH=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown option: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

echo "=== REPOSITORY CONTROL CENTER SELF-TEST ==="
bash "${SCRIPT_DIR}/test-project-manager.sh"

echo
echo "=== PROJECT MANAGER ==="
if [[ "$NO_REFRESH" -eq 1 ]]; then
  bash "${SCRIPT_DIR}/azam-project-manager.sh" --no-refresh
else
  bash "${SCRIPT_DIR}/azam-project-manager.sh"
fi

if [[ ! -f "$DASHBOARD" ]]; then
  echo "ERROR: expected dashboard not found: $DASHBOARD" >&2
  exit 1
fi

echo
echo "Dashboard ready: $DASHBOARD"

if [[ "$NO_OPEN" -eq 1 ]]; then
  exit 0
fi

if command -v termux-open >/dev/null 2>&1; then
  termux-open "$DASHBOARD"
  echo "Dashboard opened with termux-open."
else
  echo "termux-open not found; open the dashboard manually."
fi
