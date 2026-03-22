---
name: cross-agent-skill-sync
description: "Use this skill to manage already-installed skills across Claude Code, Codex, Gemini, OpenCode, OpenClaw, Cursor, Copilot, and other configured agent tools by comparing skill status and linking from configured source directories such as ~/.cc-switch/skills/ and ~/.agents/skills/. Trigger it in two major cases: first, when the user wants to sync, remove, repair, or align skills or agent skills across multiple agents; second, when the user does not yet know the current skill state and wants to inspect skill differences, missing skills, per-agent skill coverage, per-skill coverage, or decide what skill changes to make next. Use this skill when the topic is cross-agent skill or agent-skill management, not for general agent comparison, general model capability questions, or creating, editing, or installing skills from GitHub."
compatibility: Requires bash and a filesystem that supports symbolic links. Uses only standard local shell utilities, live directory scans, shell config files, and local CLI execution.
---

# Cross-Agent Skill Sync

Use this skill to manage existing skills across multiple AI agents. It does not create, edit, download, or upgrade skills. It discovers configured source skills, explains current status clearly, plans symlink changes, and applies them only after explicit confirmation.

## Hard boundaries

- Do not install new skills.
- Do not call `npx skills add`, `skills add`, `git clone`, or any other installation workflow.
- Do not edit source skill contents.
- Do not use `rm -rf`.
- Only remove symlinks with `unlink`, and only when the target is actually a symlink.
- If a target path is a real directory or file, refuse to remove it and report the reason.
- Never execute changes before the user has confirmed the dry-run plan.

## Core rule

This skill is a strict guided workflow, not an autonomous operator.

Every time the skill triggers:

1. Explain how the workflow will proceed.
2. Determine the action.
3. Collect required selections in a fixed order.
4. Stop at the first missing selection and ask only for that item.
5. Do not continue until the user has answered that specific step.
6. After all required inputs are complete, show a dry-run plan or a structured status summary.
7. Apply changes only after explicit confirmation.
8. End with a structured result summary.

If the model can infer some fields from the user's original request, keep them. If a field is not explicit, do not guess. Ask.

This skill has two equally important entry scenarios:

- direct operation: the user already knows what they want to sync, remove, or repair
- status-first exploration: the user does not yet know the current skill state and wants to inspect skill differences before deciding what to do

For `inventory`, `status`, and `sync`, the main gating order is action, scope, source, then the rest.
For `remove`, source is not required because removal only affects target-side links.
The subject must stay centered on `skill`, `skills`, `agent skill`, `agent skills`, or equivalent wording. Do not trigger this skill for generic agent-state or model-comparison questions that are not about skills.

## What to say first

At the start of the interaction, explain the workflow in plain language before doing anything else. Use this shape:

```text
I will handle this request in a fixed order:
1. Confirm the scope
2. If this is sync or status work, confirm the source
3. Confirm the skill selection
4. Confirm the target agents
5. Show you a dry-run plan or a status summary
6. Only execute after you confirm
```

If the user already provided some of these items, say that you will keep the provided values and ask only for the missing ones.
If the request sounds like "show me the current skill state first" or "I am not sure what to change yet", first check that the topic is clearly about skills or agent skills. If it is, say that you will first clarify scope and source, then show a skill-status summary before proposing any change.

## Supported actions

Classify the request into one of these actions:

- `inventory`: list available skills from selected sources
- `status`: show missing skills, linked state, external-source coverage, or sync coverage
- `sync`: create or repair symlinks
- `remove`: unlink selected symlink targets

If the action is unclear, stop and ask which action the user wants. Do not inspect sources or targets until the action is clear.

When the user says things like:

- "I am not sure about the current skill state"
- "Show me the skill differences first"
- "I have not checked these agent skills in a while"
- "Analyze the agent skill state before I decide what to sync"

Prefer `status` or `inventory` rather than jumping to `sync`.

Do not trigger this skill for prompts like:

- "I am not sure about these agents"
- "Compare these models"
- "Which agent performs better"

unless the prompt clearly brings the topic back to skills or agent skills.

## Config model

The script is configuration-driven.

Config loading order (later overrides earlier):

1. Bundled `config.conf` in the skill directory — base defaults, do not modify
2. `~/.config/cross-agent-skill-sync/config.conf` — user-level overrides
3. `./.cross-agent-skill-sync.conf` — project-level overrides
4. `SKILL_SYNC_CONFIG=/path/to/config.conf` — explicit override

The config file is shell syntax, not JSON. Read `references/config.example.conf` when the user wants to add a new source or a new agent mapping.

Configuration shape:

- `SOURCE_<name>=/absolute/path`
- `AGENT_<name>_USER=/absolute/path`
- `AGENT_<name>_PROJECT=.relative/path/from/project/root`
- `AGENT_<name>_EXTERNAL_SOURCES=source_a,source_b`

`AGENT_<name>_EXTERNAL_SOURCES` means that the agent automatically loads those configured external sources in addition to its own skill directory. This is useful for tools such as Gemini that already read `~/.agents/skills`.

Default sources:

- `cc-switch`
- `agents`

Default agents:

- `claude-code`
- `codex`
- `gemini`
- `opencode`
- `openclaw`
- `cursor`
- `copilot`

## Missing config behavior

Before collecting the rest of the workflow inputs, check whether any user or project config file exists beyond the bundled default:

- `~/.config/cross-agent-skill-sync/config.conf`
- `./.cross-agent-skill-sync.conf`
- the file pointed to by `SKILL_SYNC_CONFIG`, if present

If none of them exists, the bundled `config.conf` is still loaded automatically. The user may optionally create a custom config to override defaults.

## Mandatory workflow

Follow this order every time. Do not skip ahead.

### Step 0: Confirm action

If the request does not clearly say whether the user wants `inventory`, `status`, `sync`, or `remove`, ask only for the action.

### Step 1: Confirm scope

Scope is always the first required selection after the action is clear.

Allowed options:

- `user`
- `project`
- `both`

If scope is not explicit, ask only for scope and wait.
When presenting choices, use a numbered list and allow the user to reply with either the number or the label.

Example:

```text
Select a scope:
1. user
2. project
3. both
```

### Step 2: Confirm source

Check whether the user already specified sources.

Skip this step when the action is `remove`. Remove does not depend on source selection because it only acts on target-side symlinks.

If not, present a source list built from configuration:

- all configured sources
- `all`

Keep the list concrete. Include the default sources and any configured custom sources.

If source is not explicit, ask only for source and wait.
Present the source list as a numbered list. Include `all` as one numbered option. Allow replies by number, label, or comma-separated multiple numbers if multi-select is needed.

### Step 3: Confirm skill

Check whether the user already specified skill names.

If not, inspect the selected sources and present the available skills:

- the concrete skill list from the selected sources
- `all`

Do not ask for skills before source is known for `inventory`, `status`, and `sync`, because the skill list depends on the selected sources.
For `remove`, ask for skills immediately after scope because source is not needed.

If skills are not explicit, ask only for skills and wait.
Present the skill list as a numbered list. Include `all` as one numbered option. Allow replies by number, label, or comma-separated multiple numbers.

For `status` and `inventory`, skill selection is optional unless the user explicitly wants to narrow the inspection. If the user just wants a broad comparison and has already confirmed scope and source, you may inspect all skills in the selected sources. Do not ask for skill first in that scenario unless the user requested a filtered view.

### Step 4: Confirm target agent

Check whether the user already specified target agents.

If not, present the configured agent list:

- all configured agents
- `all`

If agents are not explicit, ask only for agents and wait.
Present the agent list as a numbered list. Include `all` as one numbered option. Allow replies by number, label, or comma-separated multiple numbers.

For `status`, agent selection is also optional. If the user wants a broad comparison, you may inspect all configured agents after scope and source are confirmed. If the user wants only some agents, ask for that filter before running the status view.

### Step 5: Resolve source conflicts

If a selected skill exists in more than one selected source, stop and ask the user which source should win for that skill.

Do not choose automatically.

### Step 6: Build the plan or status view

After the required inputs are confirmed, build the dry-run plan or status view.

Required inputs by action:

- `inventory`: action, scope, source
- `status`: action, scope, source
- `sync`: action, scope, source, skill, agent
- `remove`: action, scope, skill, agent

Use the bundled script:

```bash
bash scripts/sync_manager.sh inventory --sources cc-switch,agents --json
```

For broad status-first exploration, once action, scope, and source are confirmed, use `inventory` or `plan-status` to inspect the current state before asking the user to commit to a concrete sync or remove action.

```bash
bash scripts/sync_manager.sh plan-status \
  --sources cc-switch,agents \
  --scope user \
  --tools claude-code,codex \
  --skills pdf,agent-browser \
  --project-root "$PWD" \
  --json
```

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

```bash
bash scripts/sync_manager.sh plan-remove \
  --scope project \
  --tools cursor,codex \
  --skills agent-browser \
  --output /tmp/skill-remove.plan \
  --project-root "$PWD" \
  --json
```

### Step 7: Present the plan or status summary

Before any apply step, present the plan clearly.

Always include:

- action
- scope
- sources when applicable
- skills
- agents
- source decisions for conflicts when applicable
- planned commands or effects
- skipped items and reasons

For `status` and `inventory`, use a structured explanation instead of an execution plan. The explanation must stay logical and easy to understand.

Default status presentation order:

1. action
2. scope
3. sources
4. inspected agents
5. `Agent View`: which skills each agent is missing, linked, stale, or externally covered by
6. `Skill View`: which agents each key skill is present in, missing from, stale in, or covered externally by
7. `Summary`: most complete agent, biggest gap, or main pattern
8. `Next Suggestion`: the most sensible next sync step if the user wants to continue

When an external source covers a skill:

- treat it as available in status output
- do not count it as missing
- do not create a redundant link during sync
- if a redundant symlink already exists for the same externally loaded source, treat it as cleanup work instead of "correctly linked"

When a source skill has been removed (stale symlinks):

- during status, scan agent target directories for dangling symlinks not in the current inventory and report them as `stale`
- during sync, emit `unlink` actions for stale symlinks with reason `stale-source-skill-removed`
- include `stale_by_tool` in the status JSON alongside `missing_by_tool`
- always mention stale items in the summary so the user can decide whether to clean them up

### Step 8: Wait for confirmation

If the user has not explicitly confirmed, stop.

Do not apply.
Do not imply that dry-run already changed anything.

### Step 9: Execute

Only after explicit confirmation:

```bash
bash scripts/sync_manager.sh apply --plan /tmp/skill-sync.plan --json
```

## Interaction rules

- Ask one step at a time.
- If scope is missing, ask only for scope.
- If the action is `inventory`, `status`, or `sync` and scope is known but source is missing, ask only for source.
- If the action is `remove` and scope is known but skill is missing, ask only for skill.
- If the action is `sync` and source is known but skill is missing, ask only for skill.
- If the action is `sync` or `remove` and skill is known but agent is missing, ask only for agent.
- Do not batch unanswered questions together.
- Do not scan skills before source is confirmed.
- Do not ask for source during `remove` unless the user explicitly asks source-related diagnostic questions.
- Do not pick `all` unless the user explicitly requested all.
- If the user already provided a valid value, keep it and move to the next missing step.
- For broad `status` or `inventory` requests, scope and source are the main gates. After they are confirmed, you may inspect all relevant skills and agents unless the user asked for narrower filters.
- Whenever a list is shown, support both number-based replies and label-based replies.

## Handling conflicts and missing items

- If a requested skill is in none of the selected sources, report it as unavailable.
- If a requested skill is in multiple selected sources, require a user choice.
- If the status output contains `missing_by_tool`, use it for a gap-oriented answer.
- If the status output contains `rows_by_tool`, use it for a concise per-tool summary.
- Report partial success honestly.

## Result summary format

After execution, always give the user a clear summary in this shape:

```text
Action: sync
Scope: user
Sources: cc-switch
Skills: pdf, pptx
Agents: codex, cursor

Plan Summary
- create links: 4
- relink: 1
- covered by external source: 2
- stale unlink: 1
- skipped: 1

Result Summary
- linked successfully: 4
- relinked: 1
- cleaned redundant links: 1
- stale removed: 1
- already correct: 2
- skipped: 1

Skipped Details
- cursor/pdf: target exists and is not a symlink

Next Notes
- no remaining conflicts
- no further confirmation needed
```

For `inventory` and `status`, keep the same logical structure:

- what was inspected
- `Agent View`
- `Skill View`
- summary conclusion
- what needs user attention next

## References

Use bundled references instead of repeating long explanations inline:

- `references/path-model.md`
- `references/operations.md`
- `references/config.example.conf`
