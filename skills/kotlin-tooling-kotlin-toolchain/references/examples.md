# Kotlin Toolchain configuration examples

## project.yaml — project-level config

`project.yaml` lives at the repo root and declares the modules that make up the project, plus any local
build plugins. Paths are relative to the project root.

```yaml
# project.yaml
modules:
  - app                       # a jvm/app module in ./app
  - lib                       # a jvm/lib module in ./lib
  - plugins/release           # a jvm/amper-plugin module

# Local build plugins the modules can enable under `plugins:` in their module.yaml.
plugins:
  - ./plugins/release
```

Notes:

- Each `modules:` entry is the path to a directory containing a `module.yaml`.
- The top-level `plugins:` block is what makes a local plugin's id resolvable from a consumer module. See the
  [`kotlin-tooling-kotlin-toolchain-plugin-authoring` skill](../../kotlin-tooling-kotlin-toolchain-plugin-authoring/SKILL.md) for more details.
- Project-wide settings do not live here — there is no project-level `settings:` block. Share configuration
  (Kotlin language version, common test dependencies, repositories) via module templates instead (see the
  [Templates](../SKILL.md#templates) section of the skill).
