# Azam Repository Control Center

This fork keeps the upstream `gh-repo-stats` migration scanner intact and adds a separate, privacy-aware repository governance layer for personal development projects.

## Purpose

Use this layer to maintain a lightweight inventory of repositories you own and quickly identify:

- active versus dormant repositories;
- own projects versus upstream forks;
- public versus private exposure;
- informational fork status versus genuine review actions;
- project purpose and lifecycle annotations;
- repositories that may need cleanup, archiving, or renewed attention.

This is **development governance tooling**. It is not a NEXUS business engine and must never become a source of banking facts, customer information, policy decisions, credit analysis, credentials, or governed evidence.

## Privacy model

The control center discovers repositories at runtime using the currently authenticated GitHub CLI account.

Generated inventory files are written to `control/output/` and are ignored by Git. This matters because the inventory and HTML dashboard can include private repository names and metadata.

Optional project annotations live in `control/project-overrides.json`, which is also ignored. Only `control/project-overrides.example.json` is committed.

Never store GitHub tokens in this repository. Authenticate with the GitHub CLI (`gh auth login`) or another approved credential mechanism.

## Requirements

- Bash
- GitHub CLI (`gh`)
- `jq`
- authenticated GitHub CLI session with read access to the repositories you want included

The Azam control layer only performs read operations against repository metadata.

## Run

From the repository root:

```bash
bash script/azam-repo-control.sh
```

Outputs:

```text
control/output/latest.json
control/output/latest.csv
control/output/latest.md
control/output/latest.html
```

Timestamped copies are retained in the same local output directory.

On Termux, the local HTML dashboard can normally be opened with:

```bash
termux-open control/output/latest.html
```

If `termux-open` is unavailable, open the file with any local browser/file viewer. The dashboard does not use external JavaScript, CSS, fonts, analytics, or remote assets.

## Optional project mapping

Copy the example file:

```bash
cp control/project-overrides.example.json control/project-overrides.json
```

Then annotate only the repositories you want to classify locally:

```json
{
  "your-login/your-repo": {
    "project": "Project Name",
    "purpose": "Short purpose",
    "lifecycle": "ACTIVE",
    "notes": "Optional local note"
  }
}
```

Because `control/project-overrides.json` is ignored, private project names and notes remain local.

## Activity classification

| Status | Rule |
|---|---|
| `ACTIVE` | pushed within 30 days |
| `CURRENT` | pushed within 31–90 days |
| `AGING` | pushed within 91–180 days |
| `DORMANT` | no push for more than 180 days |
| `ARCHIVED` | repository is archived |
| `UNKNOWN` | no usable push timestamp |

## Operational health state

The control center also calculates a simple operational activity score. It is intentionally narrow: it does **not** measure code quality, test coverage, vulnerabilities, branch protection, dependency health, or business importance.

| Health | Score | Meaning |
|---|---:|---|
| `HEALTHY` | 100 | own project pushed within 30 days |
| `OK` | 85 | own project pushed within 31–90 days |
| `WATCH` | 65 | own project pushed within 91–180 days |
| `REVIEW` | 40–50 | own project dormant or without usable push history |
| `REFERENCE` | 90 | upstream fork; activity is not treated like an owned build project |
| `ARCHIVED` | 100 | intentionally archived lifecycle state |

A fork is treated as a reference repository by default so a public fork does not automatically make the dashboard look unhealthy.

## Attention levels

Attention is now separated from information:

| Level | Meaning |
|---|---|
| `NONE` | no governance action indicated |
| `INFO` | useful context, but no action required by default |
| `WARN` | review should be considered |
| `ACTION` | explicit repository-governance review recommended |

Current rules:

- `PUBLIC_FORK` and `PRIVATE_FORK` are `INFO` only;
- an own project dormant for more than 180 days becomes `WARN`;
- an own project dormant for more than 365 days becomes `ACTION`;
- an own project with no usable push history becomes `ACTION`;
- archived repositories do not generate review actions.

`summary.needs_review` counts only `WARN` and `ACTION`. Informational fork flags are reported separately.

## Local HTML dashboard

`control/output/latest.html` provides a phone-friendly local dashboard with:

- repository totals;
- own-project and upstream-fork counts;
- active count;
- informational versus review counts;
- repository visibility;
- operational health state and score;
- activity state;
- attention level and reason;
- last push and open issue count.

The HTML is generated locally from the same JSON report and remains under the Git-ignored `control/output/` directory.

## Architecture boundary

```text
GitHub metadata (read-only)
          |
          v
Azam Repository Control Center
          |
          +--> local JSON inventory
          +--> local CSV inventory
          +--> local Markdown report
          +--> local HTML dashboard
          |
          v
Human review / development governance
```

No output from this utility is authoritative for NEXUS customer, application, facility, security, policy, evidence, scorecard, cash-flow, credit, workflow, approval, or reporting decisions.

## Upstream compatibility

The original `gh-repo-stats` script is intentionally left unchanged. Azam-specific functionality lives in separate files so upstream updates from `mona-actions/gh-repo-stats` can be merged with minimal conflict.
