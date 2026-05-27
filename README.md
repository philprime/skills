# philprime's Skills

Personal agent skills following the [Agent Skills](https://agentskills.io) format.

This repository keeps reusable workflows in a simple `skills/` tree and uses dotagents for local skill dependencies.
The approach is inspired by `getsentry/sentry-skills` and `getsentry/sentry-for-ai`.

## Setup

After checkout, initialize the repo:

```bash
make init
```

This installs local hooks and upstream skills from `agents.toml`.

Refresh upstream skills:

```bash
make skills
```

Format repository files:

```bash
make format
```

Dotagents configuration lives in `agents.toml`. Generated dotagents state, including `agents.lock` and `.agents/`, should not be edited by hand.

Canonical personal skills live in `skills/<skill-name>/`.
The `.agents/skills` directory is managed by dotagents, and `.claude/skills`
points at that managed directory for local tool compatibility.

## Creating Or Updating Skills

Use `skill-writer` from `getsentry/sentry-skills` for new skills and material
updates. It handles source coverage, authoring, registration, and validation.

Rules:

- Put runtime instructions in `SKILL.md`.
- Put intent, scope, evidence model, validation, limitations, and maintenance
  notes in `SPEC.md`.
- Put source inventories, decisions, and gaps in `SOURCES.md`.
- Keep `SKILL.md` under 500 lines.
- Move optional deep detail to focused files under `references/`.
- Use `uv run <script>` for Python scripts.
- Do not create per-skill alias or symlink skills.

## Acknowledgments

The skills in this repo are inspired by and adapted from Sentry's `sentry-skills` and `sentry-for-ai` repositories, with adjustments for personal use and public sharing.
