# How to contribute to this repository?

This repository is a curated catalogue of skills for the Kotlin language and kotlinx libraries. Our goal is to provide Kotlin skills that are useful, maintainable, are easy to discover and safe. We will not accept skills that are using/adding some third-party dependencies. Exceptions are well-known and widely used libraries. Before submitting a new skill, please check the existing skill catalogue. If there is an overlap, we might suggest extending an existing skill instead. 

## Process overview

Before creating a PR for a new skill, please open an issue first and provide the following description:
- Problem and use case: Why must this be a skill?
- How will it be maintained? (estimate maintenance effort and cadence):
  How many hours per month are you able to allocate for the skill support?
- Does the skill have dependencies that might signal potential skill deprecation?
- What changes must we consider for this skill to be usable?
- When should this skill be revisited/updated and can you commit to it?

NB! By submitting the skill to this repository, you commit to maintaining it and updating its documentation accordingly. In case your contribution goes stale (not tested on the newer models, no dependency upgrade identified), we: contact you and ask for an update; in case we do not receive a reply in 30 days - the skill is archived.

In case you identify that some critical dependencies change faster than you can maintain the skill - you don’t need this skill. After submission, we will review the issue first, discuss scope, overlaps and decide on the next steps (e.g. new skill, extension of the existing skill).

### PR Requirements
In case we move past the initial approval stage, the submitted skill must follow the provided format and conventions.

- Check out the [skill-creator](https://github.com/anthropics/skills/tree/main/skills/skill-creator) skill.
- SKILL.md frontmatter must contain the following fields:
 ```yaml
name: kotlin-<category>-<functional-name>
description: >
  Load when ...
license: Apache-2.0
metadata:
  author: github:@your-handle
  version: "0.1.0"
  provider: anthropic
  tested_models: "anthropic/claude-sonnet-5, anthropic/claude-opus-5"
  agent_version: "claude-code 2.1.332"
  last_eval: "2026-06-10"
```
  `metadata` is a flat map of strings (Agent Skills specification; CI fails on nested maps or non-string values):
  quote versions and dates, and list several tested models comma-separated as `provider/model`.
 
The description says when an agent should load the skill, not what it does or why it is needed. We rely on the style guidelines from [Perplexity Research](https://research.perplexity.ai/articles/designing-refining-and-maintaining-agent-skills-at-perplexity):
- Starts with “Load, when..”
- Target 50 words or fewer
- Describes the user’s intent, from real queries
- Does not summarize the workflow

## Categories
Every skill is named `kotlin-<category>-<functional-name>`, where `<category>` is one of the predefined categories. The authoritative list of categories lives in the repository (`CATEGORIES`). If your skill doesn't fit an existing category, propose a new one
in the issue before opening a PR.

## Testing
### Write the evals and test your solution 
To ensure reproducibility and maintainability, each skill must come with a set of evals. We expect you to provide some basic test cases with prompt, expected output and files (if needed), as well as assertions. Please provide the evals in evals/evals.json inside your skill directory. You can see some examples [here](https://agentskills.io/skill-creation/evaluating-skills). 

### Optional, but preferred
If possible, include a comparison of agent performance with and without the skill (e.g., success rate or output quality).
  
## Quick contribution checklist

- ✅ Issue opened first and approved by maintainers
- ✅ No overlap with existing skills
- ✅ The skill must follow the Agent Skills specification
- ✅ Naming: kotlin-<category>-<functional-name>, correct category assigned
- ✅ SKILL.md has valid YAML frontmatter: name, description, required metadata (all string values): author, version, provider, tested_models, agent_version, last_eval
- ✅ Description tells when to load the skill and is ≤ 50 words
- ✅ Clear documentation and use cases
- ✅ No security vulnerabilities or malicious code
- ✅ evals/evals.json included
- ✅ List of projects the skill was tested on (links if public), optionally a with/without-skill comparison

## Adding a new distribution way

Please open a new issue and describe the new distribution way you would like to add. 
We will review it and provide feedback. Then you can submit a PR with the required changes.
