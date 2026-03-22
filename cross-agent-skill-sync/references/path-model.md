# Path Model

This skill manages links from configured source roots into configured target tools.

## Config files

The script loads config from these locations, in this order (later overrides earlier):

1. Bundled `config.conf` in the skill directory — base defaults, do not modify
2. `~/.config/cross-agent-skill-sync/config.conf` — user-level overrides
3. `./.cross-agent-skill-sync.conf` — project-level overrides
4. `SKILL_SYNC_CONFIG=/path/to/config.conf` if explicitly provided

## Source roots

Default upstream sources:

- `~/.cc-switch/skills/`
- `~/.agents/skills/`

Add more sources by defining additional `SOURCE_<name>` variables in the config file.

Example:

```bash
SOURCE_cc_switch="$HOME/.cc-switch/skills"
SOURCE_agents="$HOME/.agents/skills"
SOURCE_team_shared="$HOME/company/skills"
```

## User-level target directories

Default user-level target directories resolved by `scripts/sync_manager.sh`:

- `claude-code` -> `~/.claude/skills`
- `codex` -> `~/.codex/skills`
- `gemini` -> `~/.gemini/skills`
- `opencode` -> `~/.opencode/skills`
- `openclaw` -> `~/.openclaw/skills`
- `cursor` -> `~/.cursor/skills`
- `copilot` -> `~/.copilot/skills`

Add or override user-level agent directories with `AGENT_<name>_USER`.
If an agent also auto-loads external sources beyond its own directory, declare them with `AGENT_<name>_EXTERNAL_SOURCES`.

## Project-level target directories

Default project-level target directories are relative to the current project root:

- `claude-code` -> `./.claude/skills`
- `codex` -> `./.codex/skills`
- `gemini` -> `./.gemini/skills`
- `opencode` -> `./.opencode/skills`
- `openclaw` -> `./.openclaw/skills`
- `cursor` -> `./.cursor/skills`
- `copilot` -> `./.copilot/skills`

Add or override project-level agent directories with `AGENT_<name>_PROJECT`.

## External source loading

Some agents load one or more external sources automatically in addition to their own skill directory.

Example:

```bash
AGENT_gemini_USER="$HOME/.gemini/skills"
AGENT_gemini_PROJECT=".gemini/skills"
AGENT_gemini_EXTERNAL_SOURCES="agents"
```

This means:

- Gemini still has its own target directory at `~/.gemini/skills`
- Gemini also auto-loads the configured external source `agents`
- Skills from that external source should be counted as available during status checks even if no symlink exists in the Gemini directory
- Sync planning should avoid creating redundant links for those externally loaded skills

OpenCode behaves the same way:

```bash
AGENT_opencode_USER="$HOME/.opencode/skills"
AGENT_opencode_PROJECT=".opencode/skills"
AGENT_opencode_EXTERNAL_SOURCES="agents"
```

## Resolution notes

- The skill scans source roots live each time. There is no cache and no manifest.
- A same-named skill in multiple selected source roots is a user decision point, not an automatic merge.
- Targets are managed as symlinks to entire skill directories, not copies of individual files.
- Config variable names use underscores, but the script shows them to users as hyphenated names.
- External source mappings are also config-driven, not hard-coded per agent.
