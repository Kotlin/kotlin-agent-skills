[![Incubator](https://jb.gg/badges/incubator-plastic.svg)](https://github.com/JetBrains#jetbrains-on-github)

# AI agent skills for Kotlin

A collection of AI agent skills useful for projects using the Kotlin language. Skills are following the Agent Skills
standard, see [agentskills.io](https://agentskills.io) for more information.

## How do Skills work?

In practice, skills are self-contained folders that package instructions, scripts, and resources together for 
an AI agent to use on a specific use case. Each folder includes a `SKILL.md` file with YAML 
frontmatter (name and description) followed by the guidance your coding agent follows while the skill is active.

### Skill naming conventions

All skills in the repository should follow the following naming convention: `kotlin-<category>-<functional-name>`.

`<category>` here is one of predefined categories. Current categories are:
- `backend` - server-side development skills, such as correct use of Spring, JPA, and other backend frameworks with Kotlin
- `tooling` - any tooling related skills, for example build tooling one

Please open an issue to add additional categories.

`<functional-name>` should be a short, descriptive name of the skill, using kebab-case naming convention. 

## Installation

### Using the skills CLI

Install skills from this repository:

```bash
npx skills add Kotlin/kotlin-agent-skills
```

See [npx skills](https://github.com/vercel-labs/skills) for more options.

### Claude Code

```sh
/plugin marketplace add Kotlin/kotlin-agent-skills
```

```sh
/plugin install kotlin-agent-skills@Kotlin
```

### Manual installation

Copy the desired skill folder from [skills](./skills) into the skills directory of your agent, for example:

```bash
cp -r skills/kotlin-tooling-agp9-migration .claude/skills/
```

### Repository layout

- [skills/](./skills) - a directory where all skills are located
