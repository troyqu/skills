# Skills

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Repo: skills](https://img.shields.io/badge/repo-multi--skill-blue.svg)](https://github.com/troyqu/skills)

Reusable skills for AI coding agents.

This repository is organized as a multi-skill workspace so new skills can be added over time without creating a new repository for each one.

## Included Skills

| Skill | Purpose | Docs |
| --- | --- | --- |
| `cross-agent-skill-sync` | Inspect cross-agent skill differences, plan symlink changes, sync existing skills, and safely remove target-side links. | `cross-agent-skill-sync/README.md` |

## Featured Skill

`cross-agent-skill-sync` is the first published skill in this repository.

Use it when you need to:

- inspect skill differences across multiple agent tools
- see which skills are missing or only externally covered
- sync existing skills through planned symlink changes
- remove target-side skill links safely

Entry points:

- English docs: `cross-agent-skill-sync/README.md`
- 中文文档: `cross-agent-skill-sync/README-zh.md`

## Quick Start

Choose the skill directory you want and copy it into your local agent skill folder.

Example:

```bash
cp -R cross-agent-skill-sync ~/.codex/skills/
```

If your tool expects a packaged archive instead, create one from the skill directory:

```bash
cd cross-agent-skill-sync
zip -qr /tmp/cross-agent-skill-sync.skill .
```

Then extract or import that archive using your tool's normal skill installation flow.

## Repository Layout

```text
skills/
  cross-agent-skill-sync/
    SKILL.md
    README.md
    README-zh.md
    config.conf
    scripts/
    references/
    evals/
```

## Language Support

- English: `cross-agent-skill-sync/README.md`
- 中文: `cross-agent-skill-sync/README-zh.md`

## Downloads

Published releases are skill-specific.

Current downloadable asset:

- Release page: `releases/tag/cross-agent-skill-sync-v0.1.0`
- Asset: `cross-agent-skill-sync.skill`

## Contributing

Contributions are welcome. New skills should stay self-contained in their own directory with a clear `SKILL.md`, user-facing documentation, and any supporting scripts or references they need.

## License

This repository is licensed under the MIT License. See `LICENSE`.
