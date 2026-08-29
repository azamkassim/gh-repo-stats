# Project Manager

The Project Manager is a local management projection over the Repository Control Center inventory.

It does not change repository metadata and does not replace the upstream `gh-repo-stats` scanner.

## Purpose

The Repository Control Center inventories everything owned by the authenticated GitHub account. The Project Manager narrows that inventory for day-to-day management:

1. own projects are shown first;
2. projects with `ACTION` or `WARN` attention appear before normal projects;
3. upstream forks are moved into a secondary reference section;
4. local project/purpose/lifecycle annotations are displayed when present in the Git-ignored `control/project-overrides.json` file.

No private repository names are hard-coded in this public repository.

## Recommended one-command run

On Termux, the simplest entry point is:

```bash
bash script/azam-dashboard.sh
```

That command performs this sequence:

```text
offline self-test
      ↓
refresh repository inventory
      ↓
build Project Manager
      ↓
verify project-manager.html exists
      ↓
open it with termux-open when available
```

Useful options:

```bash
bash script/azam-dashboard.sh --no-open
bash script/azam-dashboard.sh --no-refresh
bash script/azam-dashboard.sh --no-refresh --no-open
```

`--no-open` builds without launching the browser. `--no-refresh` reuses the current local `latest.json` inventory instead of querying GitHub again.

The launcher itself has a network-free regression test:

```bash
bash script/test-dashboard-wrapper.sh
```

A successful launcher test ends with:

```text
PASS: Dashboard wrapper offline self-test
```

## Direct Project Manager run

From the repository root:

```bash
bash script/azam-project-manager.sh
```

That command first refreshes the Repository Control Center inventory, then writes:

```text
control/output/project-manager.md
control/output/project-manager.html
```

On Termux, open the local dashboard with:

```bash
termux-open control/output/project-manager.html
```

If the inventory is already fresh, skip the GitHub refresh with:

```bash
bash script/azam-project-manager.sh --no-refresh
```

## Offline self-test

The Project Manager includes a network-free runtime test with mock inventory data:

```bash
bash script/test-project-manager.sh
```

A successful test ends with:

```text
PASS: Project Manager offline self-test
```

The self-test checks Bash/JQ runtime validity, Markdown and HTML generation, summary counts, the reference-fork section, and priority ordering of a warning project ahead of a healthy project.

## Priority meaning

The display order is a repository-maintenance priority only:

- `ACTION` first;
- `WARN` second;
- otherwise normal;
- lower activity health scores appear before higher scores within the same attention level.

This ordering is **not** a statement of business importance, code quality, cybersecurity posture, NEXUS authority, banking risk, or project value.

## Privacy

The Project Manager reads `control/output/latest.json` and writes only into `control/output/`, which is Git-ignored. The resulting local files can include private repository names and metadata and should not be committed or shared casually.
