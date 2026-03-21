# Cross-Agent Skill Sync

`cross-agent-skill-sync` manages already-installed skills across multiple agent tools. It does not install new skills or edit skill contents. It compares cross-agent skill state, plans symlink changes, and applies them only after explicit confirmation.

## Example Screenshot

The screenshot below shows a real interaction flow: checking current cross-agent skill coverage, reviewing the dry-run plan, and then applying the confirmed changes.

![Cross-Agent Skill Sync example screenshot](./cross-agent-skill-sync.jpeg)

## Example Use Cases

This skill is most useful when the problem is about existing skills across multiple agent tools rather than creating new ones.

Typical examples:

- You have not checked your setup in a while and want to see which skills are missing or different across Codex, Cursor, Gemini, and Claude Code.
- You want to sync an existing skill such as `pdf` or `brainstorming` from a source directory into several agent tools.
- You want to remove a previously linked skill from selected agents without deleting any real directories.
- You know some tools auto-load external skill sources and want status and sync behavior to reflect that correctly.

## Installation

This skill can be used as a normal skill directory or packaged as a `.skill` archive.

Directory-based install example:

```bash
cp -R cross-agent-skill-sync ~/.codex/skills/
```

If your target tool uses a different local skill directory, copy the folder there instead.

Packaged archive example:

```bash
cd cross-agent-skill-sync
zip -qr /tmp/cross-agent-skill-sync.skill .
```

Then import or extract that archive using the target agent tool's normal skill-loading flow.

After installation, check:

1. The tool can read `SKILL.md`
2. `scripts/sync_manager.sh` is present
3. Your config file paths match your local source and agent directories

## Updating

If you installed the directory directly, pull the latest repository changes and replace the local skill directory.

If you installed from a packaged archive, download the newer `.skill` asset and replace the previously installed version.

When updating, re-check:

- custom `SOURCE_*` entries
- custom `AGENT_*` mappings
- `AGENT_<name>_EXTERNAL_SOURCES` entries for tools that auto-load external sources

## What This Skill Is For

This skill covers two main scenarios:

1. Direct operations
   Sync, remove, repair, or align skills across multiple agents.
2. Status-first exploration
   Inspect the current skill state first, then decide what to change.

The topic must stay centered on `skill`, `skills`, `agent skill`, or equivalent wording. General agent comparison or model-capability questions are out of scope.

## Guided Workflow

The interaction is intentionally structured. The skill should not jump straight into scanning or execution.

Typical order:

1. Confirm `scope`
2. If the action is `inventory`, `status`, or `sync`, confirm `source`
3. Confirm `skill`
4. Confirm target `agent`
5. Show a dry-run plan or structured status summary
6. Execute only after explicit confirmation
7. End with a structured result summary

Special case:

- `remove` does not require `source`
- `remove` uses `scope -> skill -> agent -> dry-run -> confirm -> apply`

## Trigger Guidance

These natural requests should usually trigger the skill because they are explicitly about skills:

- “Show me the skill differences across these agents”
- “I am not sure whether the current skills are aligned”
- “Which agents are missing this skill?”
- “Check the current agent-skill state before I decide what to sync”
- “Sync this skill to the other agents”
- “Remove this skill from these agents”

These should not trigger the skill unless the user clearly brings the topic back to skills:

- “Compare these agents”
- “Which model performs better?”
- “Show me the current agent state”
- “Analyze capability differences”

## Numbered Choices

When the skill presents options for scope, source, skill, or agent, it should use numbered lists.

Example:

```text
Select a source:
1. cc-switch
2. agents
3. all
```

The user should be able to reply with:

- `1`
- `2`
- `3`
- `cc-switch`
- `agents`
- `1,3` for multi-select

## Default Sources And Agents

Default sources:

- `cc-switch` -> `~/.cc-switch/skills`
- `agents` -> `~/.agents/skills`

Default agents:

- `claude-code`
- `codex`
- `gemini`
- `opencode`
- `openclaw`
- `cursor`
- `copilot`

## Config Files

The script reads config in this order:

1. `~/.config/cross-agent-skill-sync/config.conf`
2. `./.cross-agent-skill-sync.conf`
3. `SKILL_SYNC_CONFIG=/path/to/config.conf`

Later files override earlier files.

Files included in this skill:

- `config.conf`
- `references/config.example.conf`
- `README-zh.md`

If no config file exists yet, the skill should ask whether to create a default one instead of writing files automatically.

## Config Shape

The config file uses shell syntax:

```bash
SOURCE_cc_switch="$HOME/.cc-switch/skills"
SOURCE_agents="$HOME/.agents/skills"
SOURCE_team_shared="$HOME/company/skills"

AGENT_gemini_USER="$HOME/.gemini/skills"
AGENT_gemini_PROJECT=".gemini/skills"
AGENT_gemini_EXTERNAL_SOURCES="agents"
```

Supported config keys:

- `SOURCE_<name>`: define a source directory
- `AGENT_<name>_USER`: define the user-level target directory
- `AGENT_<name>_PROJECT`: define the project-level target directory
- `AGENT_<name>_EXTERNAL_SOURCES`: define which external sources this agent auto-loads

Variable names use underscores in config, while the skill shows them to users as hyphenated names.

## External Source Loading

Some agents automatically load skills from external sources in addition to their own skill directory.

Example:

```bash
AGENT_gemini_EXTERNAL_SOURCES="agents"
```

This means:

- Gemini still has its own directory at `~/.gemini/skills`
- Gemini also auto-loads the external source `agents`
- Status checks should count those skills as available even if no symlink exists in `~/.gemini/skills`
- Sync should avoid creating redundant links for those skills
- If a redundant symlink already exists for the same externally loaded source, the plan should treat it as cleanup work

## Boundary Rules For External Sources

This behavior is generic and config-driven. Gemini is only one example.

If another tool also auto-loads some external sources, add them in config:

```bash
AGENT_some_tool_EXTERNAL_SOURCES="agents,team_shared"
```

Behavior by action:

- `status`
  A skill from an externally loaded source counts as available even if there is no symlink in the agent directory.
- `sync`
  The plan should not create a redundant link for a skill that is already available through an external source.
- `sync` cleanup case
  If a redundant symlink already exists for the same externally loaded source, the plan may mark it for cleanup instead of keeping it.
- `remove`
  Remove still only unlinks target-side symlinks. It does not disable external-source loading configured for that agent.

Recommended status interpretation:

- `linked-correctly`
  The skill is present through an explicit symlink.
- `covered-by-external-source`
  The skill is available because the agent auto-loads the selected external source.
- `linked-correctly-but-externally-covered`
  A symlink exists, but the agent would already get the skill from the external source. This usually means the link is redundant.
- `missing`
  The skill is not linked and is not covered by an external source.

## How To Read Status Output

For status-first requests, the clearest order is:

1. `scope`
2. `source`
3. `Agent View`
4. `Skill View`
5. `Summary`
6. `Next Suggestion`

Recommended interpretation:

- `Agent View`
  Which skills each agent is missing, linked, or covered by an external source
- `Skill View`
  Which agents each skill is present in, missing from, or covered externally by
- `Summary`
  The main gap or pattern
- `Next Suggestion`
  The most sensible next sync step if the user wants to continue

## Common Commands

Inventory:

```bash
bash scripts/sync_manager.sh inventory --json
```

Scoped status:

```bash
bash scripts/sync_manager.sh plan-status \
  --sources cc-switch,agents \
  --scope project \
  --tools codex,cursor \
  --skills pdf \
  --project-root "$PWD" \
  --json
```

Sync:

```bash
bash scripts/sync_manager.sh plan-sync \
  --sources cc-switch,agents \
  --scope both \
  --tools codex,cursor \
  --skills pdf \
  --project-root "$PWD" \
  --source-choice pdf=cc-switch \
  --output /tmp/skill-sync.plan \
  --json
```

Remove:

```bash
bash scripts/sync_manager.sh plan-remove \
  --scope both \
  --tools codex,cursor \
  --skills pdf \
  --project-root "$PWD" \
  --output /tmp/skill-remove.plan \
  --json
```

Apply A Confirmed Plan:

```bash
bash scripts/sync_manager.sh apply --plan /tmp/skill-sync.plan --json
```

## Downloads

This skill can be installed from the repository directory or from the packaged release asset:

- `cross-agent-skill-sync.skill`

## Source Selection And Conflicts

- Use `--sources` when you want to inspect or operate on only some sources.
- If the same skill name exists in more than one source, use `--source-choice skill-name=source-name` to choose which source should win.
- If no source choice is provided for a conflicting skill, the script reports a conflict instead of choosing silently.

## Scope

- `user`: write to user-level directories such as `~/.codex/skills`
- `project`: write to project-level directories such as `./.codex/skills`
- `both`: handle both scopes

## Safety Boundaries

- Always plan before apply.
- Only unlink symlinks. Do not delete real directories or files.
- Do not use `rm -rf`.
- Do not install skills or download skills from GitHub.
- If a target path is already occupied by a normal directory or file, report it and skip it.

## Practical Tips

- Start with `inventory` or `plan-status` if you are not yet sure what to change.
- Add new sources or agent mappings through config first, not by editing the script.
- Use `--sources` when you want to limit an operation to a smaller part of your skill inventory.
- If the request is still ambiguous, clarify scope, source, skill, and agent before continuing.
- If you are unsure how to adjust your setup, ask for a status-first comparison before syncing anything.

## FAQ

### Will this create `config.conf` automatically on first use?

No. The safer behavior is to ask first and let the user choose whether to create a user-level config, a project-level config, or continue with built-in defaults.

### Why does the workflow confirm items one by one?

Because the goal is clarity, not guesswork. If scope, source, skill, or agent is unclear, the workflow should stop at that step and ask only for the missing item.

### Why does `remove` not ask for source?

Because `remove` only unlinks target-side symlinks. It does not need a source as the reference for deciding what to remove.

### Why are numbered choices recommended?

Because source, skill, and agent names can get long. Numbered lists make it easier to answer quickly and reduce input mistakes.

### What should I do if I do not know the current state yet?

Start with a status-first request. Confirm scope and source first, then inspect the result in this order: `Agent View`, `Skill View`, `Summary`, and `Next Suggestion`.

### Why can source conflicts happen?

If the same skill name exists in more than one source, the script will not silently choose for you. You should provide an explicit source choice during sync or status work.

Example:

```bash
bash scripts/sync_manager.sh plan-sync \
  --sources cc-switch,team-shared \
  --scope user \
  --tools codex \
  --skills pdf \
  --source-choice pdf=team-shared \
  --output /tmp/skill-sync.plan \
  --json
```

### Why was a target skipped?

If a target path is already a normal directory or file instead of a symlink, the script skips it and reports the reason to avoid deleting user-managed content.

Common reasons:

- you created a same-name directory manually
- the tool generated a same-name path on its own
- the target is not a symlink and cannot be safely unlinked

### Why did `plan-remove` not actually remove anything?

`plan-remove` and `plan-sync` only build a dry-run plan. They do not modify the filesystem until you explicitly apply the plan.

```bash
bash scripts/sync_manager.sh apply --plan /tmp/skill-remove.plan --json
```

### Why do project-level paths look like `./.codex/skills`?

`project` scope writes relative to the current project root. For example, if you run the command in `/path/to/my-project`, the project-level Codex path resolves to:

```text
/path/to/my-project/.codex/skills
```

If you pass `--project-root`, that path becomes the reference root instead.

### How do I add a new source or agent?

The simplest approach is to update `~/.config/cross-agent-skill-sync/config.conf`.

Example:

```bash
SOURCE_team_shared="$HOME/company/skills"

AGENT_custom_agent_USER="$HOME/.custom-agent/skills"
AGENT_custom_agent_PROJECT=".custom-agent/skills"
```

After that, you can use `team-shared` and `custom-agent` directly in commands.

### Why can `inventory` or `status` miss a skill I expected?

Check these first:

- whether `--sources` filtered out the source you expected
- whether your config file was loaded
- whether the configured directories really exist
- whether the skill directory name matches what you asked for

Use this command first to see what the sources actually expose:

```bash
bash scripts/sync_manager.sh inventory --json
```
