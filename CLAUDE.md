# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

A collection of AI agent skills for Kotlin projects, following the [Agent Skills specification](https://agentskills.io). Skills are self-contained folders with instructions, scripts, and resources — not compilable code. There is no build system, test suite, or linting toolchain.

## CI Validation

CI runs on PRs/pushes to `main` when `**/SKILL.md` files change:
1. Validates skill directory naming: `kotlin-<category>-<functional-name>`
2. Validates category against the `CATEGORIES` file (currently: `backend`, `tooling`)
3. Validates functional-name is kebab-case
4. Runs `Flash-Brew-Digital/validate-skill@v1` on each changed skill

## Creating and Validating Skills

Use https://claude.com/plugins/skill-creator to create and validate skills.

## Skill Structure

Each skill lives under `skills/` and must contain a `SKILL.md` with YAML frontmatter (`name` and `description` required). Skills may also have:
- `references/` — detailed how-to guides and framework documentation
- `assets/` — checklists and supporting materials
- `scripts/` — shell scripts for automation

## Naming Convention

Skill directories must match: `kotlin-<category>-<functional-name>` where:
- `<category>` is listed in the `CATEGORIES` file at repo root
- `<functional-name>` is kebab-case (lowercase alphanumeric + hyphens)

## Contribution Rules

- Only Kotlin language or `kotlinx.*` library skills are accepted
- No third-party dependencies (except well-known, widely-used libraries)
- New skills should be proposed via an issue first
- Skills must follow the [Agent Skills specification](https://agentskills.io/specification)
