# Testing

This skill is A/B evaluated with the JetBrains [`skills-ab-eval`](https://github.com/JetBrains/skills-ab-eval-cookbook) tool.
The suite lives at
[`kotlin-tooling-native-build-performance`](https://github.com/JetBrains/skills-ab-eval-cookbook/tree/main/kotlin-tooling-native-build-performance)
and contains two tasks:

- **`native-build-performance-audit-task`** — a synthetic KMP iOS fixture
  seeded with common Kotlin/Native build-performance mistakes.
- **`kotlinproject-native-build-performance-task`** — a KotlinProject template
  copy with intentional cache, target, local-build, CI, and export regressions.

Each task runs the agent with and without the skill and scores the result on a
weighted rubric (reward 0–1), requiring a `BUILD_PERFORMANCE_REPORT.md` that
preserves production release behavior.

## Latest results (2026-07-06)

Run via `skills-ab-eval` on the `codex` agent, `openai/gpt-5.5` at low reasoning
effort, n = 6 pairs per task:

| Task | Without skill | With skill | Δ | Significance |
|---|---:|---:|---:|---|
| Synthetic native build audit | 0.74 ± 0.05 | 0.99 ± 0.02 | +0.25 | p = 0.031 |
| KotlinProject native build audit | 0.59 ± 0.05 | 0.90 ± 0.02 | +0.31 | p = 0.031 |

The with-skill arms are near-deterministic (σ ≤ 0.02): the diagnostic procedure
lives in the skill, not in the model's reasoning budget. Additional
`openai/gpt-5.4-mini` runs (high and low reasoning) are recorded per task.

See each task's `EVALUATION.md` in the cookbook for full per-trial reward
breakdowns and token/cost metrics.
