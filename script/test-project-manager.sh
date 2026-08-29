#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_ROOT="$(mktemp -d)"
OUT_DIR="${TMP_ROOT}/control/output"
trap 'rm -rf "${TMP_ROOT}"' EXIT INT TERM
mkdir -p "${OUT_DIR}"

cat > "${OUT_DIR}/latest.json" <<'JSON'
{
  "generated_at": "2026-08-29T12:42:10Z",
  "repositories": [
    {
      "full_name": "example/healthy-project",
      "fork": false,
      "visibility": "private",
      "health_state": "HEALTHY",
      "health_score": 100,
      "activity": "ACTIVE",
      "attention_level": "NONE",
      "attention": "NONE",
      "open_issues": 0,
      "pushed_at": "2026-08-29T10:00:00Z",
      "default_branch": "main",
      "url": "https://example.invalid/healthy-project",
      "project": "Healthy Project",
      "purpose": "Self-test fixture",
      "lifecycle": "ACTIVE"
    },
    {
      "full_name": "example/watch-project",
      "fork": false,
      "visibility": "private",
      "health_state": "WATCH",
      "health_score": 65,
      "activity": "AGING",
      "attention_level": "WARN",
      "attention": "DORMANT_180",
      "open_issues": 2,
      "pushed_at": "2026-02-01T10:00:00Z",
      "default_branch": "main",
      "url": "https://example.invalid/watch-project",
      "project": null,
      "purpose": null,
      "lifecycle": null
    },
    {
      "full_name": "example/reference-fork",
      "fork": true,
      "visibility": "public",
      "health_state": "REFERENCE",
      "health_score": 90,
      "activity": "ACTIVE",
      "attention_level": "INFO",
      "attention": "PUBLIC_FORK",
      "open_issues": 1,
      "pushed_at": "2026-08-20T10:00:00Z",
      "default_branch": "master",
      "url": "https://example.invalid/reference-fork",
      "project": null,
      "purpose": null,
      "lifecycle": null
    }
  ]
}
JSON

bash -n "${SCRIPT_DIR}/azam-project-manager.sh"

AZAM_REPO_CONTROL_OUTDIR="${OUT_DIR}" \
  bash "${SCRIPT_DIR}/azam-project-manager.sh" --no-refresh > "${TMP_ROOT}/run.log"

grep -q 'Project Manager complete' "${TMP_ROOT}/run.log"
grep -q 'Own: 2 | Active own: 1 | Own need review: 1 | Reference forks: 1' "${TMP_ROOT}/run.log"
grep -q 'example/watch-project' "${OUT_DIR}/project-manager.md"
grep -q 'Reference forks (1)' "${OUT_DIR}/project-manager.html"
grep -q 'Own projects first' "${OUT_DIR}/project-manager.html"

# WARN/ACTION projects should sort before healthy projects in the management table.
FIRST_OWN="$(grep '^| example/' "${OUT_DIR}/project-manager.md" | head -n1 | cut -d'|' -f2 | xargs)"
[[ "${FIRST_OWN}" == "example/watch-project" ]] || {
  echo "FAIL: expected warning project first, got: ${FIRST_OWN}" >&2
  exit 1
}

echo "PASS: Project Manager offline self-test"
