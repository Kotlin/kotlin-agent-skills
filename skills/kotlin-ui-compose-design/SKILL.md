---
name: kotlin-ui-compose-design
description: Create distinctive, production-grade Compose Multiplatform interfaces with high design quality. Use this skill when the user asks to build composables, screens, components, or applications in Compose or Jetpack Compose (examples include Android screens, multiplatform apps, dashboards, onboarding screens, Material 3 designs, or when styling/beautifying any Compose UI). Generates creative, polished Kotlin code that avoids Material defaults and generic AI aesthetics.
---

This skill guides creation of distinctive, production-grade Compose interfaces that avoid generic "AI slop" aesthetics. Implement real, compiling Kotlin with exceptional attention to aesthetic choices and Material 3's customization surfaces.

The user provides UI requirements: a composable, screen, component, or application to build. They may include context about purpose, audience, target platform, or technical constraints. Unless they target a single platform, default to `commonMain`-compatible APIs so the work runs unchanged across Android, iOS, Desktop, and Web.

## Design Thinking

Before writing a single composable, commit to a BOLD aesthetic direction:
- **Purpose**: What problem does this interface solve? Who uses it, on which surface (phone, tablet, desktop, web)?
- **Tone**: Pick an extreme: brutalist-mono, maximalist-expressive, neo-editorial, retro-futurist, organic-soft, luxury-restrained, playful-toy, soft-pastel, industrial-grid, art-deco-geometric, terminal-dark, etc. Use as inspiration; design one true to the chosen direction.
- **Constraints**: Target surfaces, Material 3 Expressive availability, performance, accessibility.
- **Differentiation**: What makes this UNFORGETTABLE? What single thing will the user remember after closing the app?

**CRITICAL**: Commit, don't blend. Refined minimalism and maximalist expression both work — what kills a Compose UI is sitting in the middle and accepting Material defaults wherever a choice was required. Intentionality beats intensity.

Then implement Kotlin that is compiling and runnable, visually striking on first frame, cohesive with one point-of-view end to end, and materially correct — Material 3 components used with intent, not as scaffolding.

## Compose Aesthetics Guidelines

Focus on:
- **Typography**: Distinctive fonts referenced via `compose-resources` (`Font(Res.font.x)`) — never `FontFamily.Default` or platform sans. Pair a characterful display family with a refined body family. Vary deliberately across generations and avoid converging on the same family twice. When fonts are not yet wired, leave a brief comment pointing to the module's `commonMain/composeResources/font/` directory and the Google Fonts URL.
- **Color & ColorScheme**: Hand-pick both `lightColorScheme(...)` and `darkColorScheme(...)`. M3's baseline palette (purple seed `#6750A4`, surfaced by an unmodified `lightColorScheme()` / `darkColorScheme()`) and Android `dynamicColor` wallpaper-derived schemes are forbidden — they are the AI-Compose fingerprint. One dominant color, one or two sharp accents, a neutral foundation; M3's `tertiary` is a contrast point, not filler. Tokens live in the scheme; never scatter raw `Color(0xFF...)` through composables.
- **Motion**: Treat as a primary expressive medium. `animate*AsState` with custom `spring` / `tween` specs (never default), `AnimatedContent` / `AnimatedVisibility` with explicit `enter` / `exit`, `rememberInfiniteTransition` for ambient drift (slow, 4–12s cycles), `SharedTransitionLayout` for hero moments. Stagger first-composition reveals via offset `delayMillis` per child — orchestrated entry, not everything-at-once.
- **Spatial Composition**: Reach past the safe `Column { ... }`. `Box` with z-stacked, offset, rotated, scaled children; `Modifier.offset` / `.rotate` / `.scale` / `.graphicsLayer` to break grid alignment; `ConstraintLayout` for asymmetric anchors; custom `Layout { ... }` when nothing built-in fits. Generous negative space OR controlled density — never the boring middle, never uniform 16.dp everywhere.
- **Atmosphere & Surfaces**: Backgrounds carry mood. `Brush.linearGradient` / `radialGradient` / `sweepGradient` (or a custom `ShaderBrush`) for chromatic depth; `Modifier.drawBehind` / `.drawWithCache` for grain, dot grids, geometric overlays; `Modifier.blur` for frosted layers; layered transparency via `.copy(alpha = ...)`. Custom shapes via `CutCornerShape`, asymmetric `RoundedCornerShape(topStart = ..., bottomEnd = ...)`, or `GenericShape` on hero surfaces — never universal `RoundedCornerShape(8.dp)`.

Wrap `MaterialTheme` in an `AppTheme` composable that owns the `ColorScheme`, `Typography`, and optional `Shapes` tokens. Decompose screens into small, hoisted composables — state in, callbacks out. Add a `@Preview` so the result is immediately viewable in the IDE.

NEVER use generic Compose aesthetics: `MaterialTheme` without a custom `ColorScheme` and `Typography`; Roboto / SF / system fonts as primary; stacks of identical `Card { Row { Icon; Text; Icon } }` rows; static screens with no motion; default `AnimatedContent` transforms; imports from `androidx.compose.material.*` (Material 2 — always `material3`). Convergence across generations on the same font, palette, or layout pattern is failure.

Interpret creatively and make unexpected choices that feel genuinely designed for the context. No two designs should be the same. Vary between light and dark themes across generations, vary fonts, vary the dominant color, vary which Material component you customize most aggressively — treat each request as a one-off.

**IMPORTANT**: Match implementation complexity to the aesthetic vision. Maximalist designs need elaborate `drawBehind` layers, layered `Brush`es, and orchestrated transitions; refined designs need surgical typography, precise spacing rhythm, and restrained motion. Elegance is execution, not absence.

Claude is capable of extraordinary creative work in Compose. The default Material rails are *one* path; this skill is permission to leave them.
