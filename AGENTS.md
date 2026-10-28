# AGENTS.md

Guidance for AI coding agents working in this repository. Humans should start with [README.md](./README.md) and [CONTRIBUTING.md](./CONTRIBUTING.md).

## Project overview

- A curated catalogue of AI agent skills for the Kotlin language and `kotlinx.*` libraries, following the [Agent Skills specification](https://agentskills.io/specification).
- Skills are self-contained folders of Markdown instructions, scripts, and resources. There is no application code to compile and no runtime test suite.
- All skills live under `skills/`. Each skill directory contains a `SKILL.md` and may contain `references/` (detailed guides), `assets/` (checklists, templates), `scripts/` (automation), and `evals/` (test cases).
- Valid categories are listed in the `CATEGORIES` file at the repo root (currently `backend` and `tooling`).

## Validation and test commands

Run the same checks CI runs before committing:

```bash
scripts/validate-skills.sh                              # all skills
scripts/validate-skills.sh skills/kotlin-tooling-foo    # one or more skills
```

Requires `git` and `node` (20 or newer). The script fetches `Flash-Brew-Digital/validate-skill@v1` once into a temp directory and reuses it.

What CI (`.github/workflows/validate-skills.yml`) checks for every skill whose `SKILL.md` changed in the PR:

1. Directory name matches `kotlin-<category>-<functional-name>`.
2. `<category>` is one of the entries in `CATEGORIES`.
3. `<functional-name>` is kebab-case (`^[a-z0-9]+(-[a-z0-9]+)*$`).
4. `SKILL.md` complies with the Agent Skills spec via `Flash-Brew-Digital/validate-skill@v1`:
   - YAML frontmatter present between `---` markers and parseable.
   - `name`: 1 to 64 chars, lowercase letters, digits, hyphens, no leading, trailing, or double hyphens, and equal to the directory name.
   - `description`: non-empty, at most 1024 chars.
   - Optional fields typed correctly: `license` string, `compatibility` 1 to 500 chars, `metadata` map of string values, `allowed-tools` space-delimited string.
   - Warnings (non-fatal): description under 50 chars, empty body, body over 500 lines, unknown frontmatter fields.

CI does not run on draft PRs. Fix every error before marking a PR ready for review.

## Skill conventions

- Directory and `name` frontmatter: `kotlin-<category>-<functional-name>`.
- Required frontmatter beyond the spec (see CONTRIBUTING.md): `metadata.author` (`github:@handle`), `metadata.version`, `metadata.tested_models` (`provider`, `model`, `agent_version`, `last_eval`).
- `description` says when an agent should load the skill, not what it does. Start with "Load, when...", stay at or under 50 words, describe user intent from real queries, and do not summarize the workflow.
- Keep `SKILL.md` focused and under 500 lines. Move long how-to material into `references/` and link to it.
- Include `evals/evals.json` with prompts, expected output, and assertions.
- Use https://claude.com/plugins/skill-creator (or the `skill-creator` skill) to scaffold and iterate on skills.

## Contribution rules

- Only Kotlin language or `kotlinx.*` library skills are accepted.
- No third-party dependencies, except well-known, widely used libraries.
- Propose new skills in an issue first. Check the existing catalogue for overlap. Maintainers may suggest extending an existing skill instead.
- Propose new categories in the issue before opening a PR.
- Contributors commit to maintaining their skill. Stale skills are archived after a 30-day unanswered update request.

## Pull request guidelines

- Run `scripts/validate-skills.sh` on every skill you touched and make sure it passes.
- Reference the approved proposal issue in the PR description.
- When adding a skill, list the projects it was tested on and, if possible, a with/without-skill comparison.

## Security considerations

- Skills must not contain malicious code or instructions that exfiltrate data, weaken security settings, or run untrusted commands.
- Scripts under `scripts/` must be safe to run on a contributor's machine and must not fetch and execute unpinned remote code.
- Do not add credentials, tokens, or private URLs to any skill file.
