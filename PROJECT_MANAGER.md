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

## Run

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

## Priority meaning

The display order is a repository-maintenance priority only:

- `ACTION` first;
- `WARN` second;
- otherwise normal;
- lower activity health scores appear before higher scores within the same attention level.

This ordering is **not** a statement of business importance, code quality, cybersecurity posture, NEXUS authority, banking risk, or project value.

## Privacy

The Project Manager reads `control/output/latest.json` and writes only into `control/output/`, which is Git-ignored. The resulting local files can include private repository names and metadata and should not be committed or shared casually.
