# Operations

Use this as the compact execution playbook.

## 1. Inventory

Use when the user asks what is available or what sources exist.

```bash
bash scripts/sync_manager.sh inventory --json
```

To limit inventory to selected sources:

```bash
bash scripts/sync_manager.sh inventory --sources cc-switch,agents --json
```

What to report:

- all discovered skills
- which source each skill comes from
- any duplicate names across selected sources

## 2. Status

Use when the user asks what is missing, what is already linked, or which tools are out of sync.

```bash
bash scripts/sync_manager.sh plan-status \
  --sources cc-switch,agents \
  --scope project \
  --tools cursor,codex \
  --skills all \
  --project-root "$PWD" \
  --json
```

Preferred output order:

1. `scope`
2. selected tools
3. `missing_by_tool`
4. `stale_by_tool` for dangling symlinks whose source skill was removed
5. rows or summary that show `covered-by-external-source` when applicable
6. any conflicts that need a source choice
7. the shorter `summary`

## 3. Sync

Use when the user wants to add or repair links.

```bash
bash scripts/sync_manager.sh plan-sync \
  --sources cc-switch,agents \
  --scope both \
  --tools claude-code,cursor \
  --skills pdf \
  --project-root "$PWD" \
  --source-choice pdf=cc-switch \
  --output /tmp/skill-sync.plan \
  --json
```

Then wait for explicit confirmation before:

```bash
bash scripts/sync_manager.sh apply \
  --plan /tmp/skill-sync.plan \
  --json
```

## 4. Remove

Use when the user wants to remove links but keep source skills intact.

```bash
bash scripts/sync_manager.sh plan-remove \
  --scope user \
  --tools cursor,codex \
  --skills agent-browser \
  --output /tmp/skill-remove.plan \
  --json
```

Then wait for confirmation before:

```bash
bash scripts/sync_manager.sh apply \
  --plan /tmp/skill-remove.plan \
  --json
```

`plan-sync` and `plan-remove` write an apply-ready plan file to `--output`, while stdout stays as a JSON dry-run summary.

## Safety reminders

- Never skip the planning step.
- Never delete a real directory.
- Never install missing skills as part of this workflow.
- If a conflict exists, stop and ask the user which source wins.
- Prefer adding new sources or agent mappings through the config file instead of editing the script.
- If an agent auto-loads external sources, let sync/status account for that instead of forcing redundant links.
