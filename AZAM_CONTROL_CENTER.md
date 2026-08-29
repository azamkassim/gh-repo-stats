# Azam Repository Control Center

This fork keeps the upstream `gh-repo-stats` migration scanner intact and adds a separate, privacy-aware repository governance layer for personal development projects.

## Purpose

Use this layer to maintain a lightweight inventory of repositories you own and quickly identify:

- active versus dormant repositories;
- own projects versus upstream forks;
- public versus private exposure;
- public forks that should be reviewed periodically;
- project purpose and lifecycle annotations;
- repositories that may need cleanup, archiving, or renewed attention.

This is **development governance tooling**. It is not a NEXUS business engine and must never become a source of banking facts, customer information, policy decisions, credit analysis, credentials, or governed evidence.

## Privacy model

The control center discovers repositories at runtime using the currently authenticated GitHub CLI account.

Generated inventory files are written to `control/output/` and are ignored by Git. This matters because the inventory can include private repository names and metadata.

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
```

Timestamped copies are retained in the same local output directory.

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

## Attention flags

`REVIEW_PUBLIC_FORK` means a repository is both public and a fork. This is not a security incident; it is a reminder to confirm that the fork is still needed, appropriately named, and not unintentionally exposing custom work.

`REVIEW_DORMANT` means the repository has not been pushed for more than 180 days and may warrant archival or reactivation.

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
          |
          v
Human review / development governance
```

No output from this utility is authoritative for NEXUS customer, application, facility, security, policy, evidence, scorecard, cash-flow, credit, workflow, approval, or reporting decisions.

## Upstream compatibility

The original `gh-repo-stats` script is intentionally left unchanged. Azam-specific functionality lives in separate files so upstream updates from `mona-actions/gh-repo-stats` can be merged with minimal conflict.
