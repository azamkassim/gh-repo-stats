# Repository Change Detection

The Repository Change Detector compares two local Repository Control Center snapshots and reports what changed between them.

It is a downstream reporting layer. It does not change GitHub repositories, repository classifications, credentials, or the upstream `gh-repo-stats` scanner.

## What it detects

For each repository it can detect:

- a new or removed repository;
- a newer push timestamp;
- activity-state changes;
- health-state / health-score changes;
- attention changes (`NONE`, `INFO`, `WARN`, `ACTION`);
- changes to GitHub repository `open_issues_count`;
- visibility, archived-state, or default-branch changes.

The report highlights own-project changes separately from upstream/reference forks.

## Important count terminology

The local collector currently stores GitHub repository `open_issues_count` as `open_issues` for compatibility with its existing schema. GitHub's repository-level count can include pull requests as well as issues.

For that reason the Change Detector deliberately labels the difference as **Open-item delta**, not as a pure issue-count delta.

## Default run

```bash
bash script/azam-repo-delta.sh
```

With no arguments, the detector compares the two newest timestamped files matching:

```text
control/output/repo-control-*.json
```

It generates:

```text
control/output/repo-delta.json
control/output/repo-delta.md
control/output/repo-delta.html
```

## Explicit comparison

Two snapshots can be supplied directly:

```bash
bash script/azam-repo-delta.sh previous.json current.json
```

## Baseline-only behavior

If fewer than two timestamped snapshots exist, the detector succeeds with a `BASELINE_ONLY` result instead of failing. A later run can then compare against that baseline.

## One-command launcher

The normal Termux launcher now includes change detection automatically:

```bash
bash script/azam-dashboard.sh
```

The sequence is:

1. offline Project Manager self-test;
2. offline Change Detector self-test;
3. live Repository Control Center refresh / Project Manager build;
4. comparison with the previous timestamped snapshot;
5. Project Manager dashboard open via `termux-open` when available.

## Offline test

```bash
bash script/test-repo-delta.sh
```

A successful result ends with:

```text
PASS: Repository delta offline self-test
```

The test covers changed, unchanged, new, and removed repositories; own-project change counts; push detection; attention escalation; open-item increase; generated Markdown/HTML; and first-run baseline behavior.

## Privacy

All generated change reports stay inside the Git-ignored `control/output/` directory. They can contain private repository names and metadata and should not be committed or shared casually.
