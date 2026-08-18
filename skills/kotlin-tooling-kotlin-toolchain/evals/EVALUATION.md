# Evaluation

This skill is A/B evaluated with a scaffolding task pair: **arm A** scaffolds a
Kotlin project with Android and iOS platforms *without* the skill, and **arm B**
runs the identical prompt *with* the `kotlin-tooling-kotlin-toolchain` skill mounted.
Both arms run the [Kotlin Toolchain](https://kotlin-toolchain.org/) `0.11.1`
CLI, and the verifier scores whether the result is a working Toolchain project
(`project.yaml` + `module.yaml`, `./kotlin` wrapper, no Gradle build) that loads
and builds.

The machine-checkable expectations are captured in [`evals.json`](evals.json).

## Latest results (2026-08-14)

Run with the JetBrains skills A/B eval harness, `claude-code` agent, n = 10
pairs per model.

| Model | Reward without skill | Reward with skill | Δ | Significance |
|---|---:|---:|---:|---|
| `anthropic/claude-opus-5` | 0.00 ± 0.00 | 0.83 ± 0.00 | +0.83 | p < 0.05 |
| `anthropic/claude-sonnet-5` | 0.00 ± 0.00 | 0.83 ± 0.00 | +0.83 | p < 0.05 |

Without the skill both models default to Gradle (6–7 `gradle` invocations per
trial, `kotlin init` never used) and score zero on the Toolchain rubric. With
the skill they switch to the Toolchain (0 `gradle` calls, 6–7 `kotlin` calls,
`kotlin init` used in every trial) and the reward is near-deterministic
(σ ≈ 0.00): the build-tool decision moves into the skill rather than the model's
reasoning. The with-skill arm also uses markedly fewer tool calls and tokens.

## Scope note

The A/B suite above targets the `kotlin-tooling-kotlin-toolchain` skill directly. The
companion skills (`kotlin-tooling-kotlin-toolchain-plugin-authoring`,
`kotlin-tooling-gradle-to-kotlin-toolchain-plugin`,
`kotlin-tooling-gradle-to-kotlin-toolchain-project`) share the same Toolchain `0.11.1`
baseline and model/agent, and ship their own `evals.json`; their formal A/B runs
are tracked separately.
