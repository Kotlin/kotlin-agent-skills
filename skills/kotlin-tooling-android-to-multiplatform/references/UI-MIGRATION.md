# UI Migration: Compose to Compose Multiplatform

Guide for migrating Jetpack Compose UI code to Compose Multiplatform, enabling shared UI across Android and iOS (with optional Desktop and Web support).

## Table of Contents

1. [Resource Migration](#resource-migration)
2. [Theme and Design System](#theme-and-design-system)
3. [Screen-by-Screen Migration](#screen-by-screen-migration)
4. [Navigation](#navigation)
5. [ViewModel Migration](#viewmodel-migration)
6. [Platform-Specific UI](#platform-specific-ui)

---

## Resource Migration

The biggest mechanical change is how resources are organized and accessed.

### Directory Structure

```
# Before (Android)
module/src/main/res/
    ├── values/
    │   ├── strings.xml
    │   └── colors.xml
    ├── drawable/
    │   └── ic_logo.xml
    └── font/
        └── roboto_regular.ttf

# After (Compose Multiplatform)
module/src/commonMain/composeResources/
    ├── values/
    │   ├── strings.xml        
    │   └── colors.xml ← same format, but no @android:color references
    ├── drawable/
    │   └── ic_logo.xml
    └── font/
        └── roboto_regular.ttf
```

**Key differences:**
- Directory is `composeResources`, not `res`
- The generated accessor class is `Res` instead of `R`
- No `@android:color` or any other android references in XML

### Code Changes

| Android                               | Compose Multiplatform                   |
|---------------------------------------|-----------------------------------------|
| `stringResource(R.string.app_name)`   | `stringResource(Res.string.app_name)`   |
| `painterResource(R.drawable.ic_logo)` | `painterResource(Res.drawable.ic_logo)` |
| `Font(R.font.roboto_regular)`         | `Font(Res.font.roboto_regular)`         |
| `colorResource(R.color.primary)`      | `colorResource(Res.color.primary)`      |

**Import change:** Replace `import com.example.R` with the generated `Res` import (typically `import <module>.generated.resources.*` or the specific `Res` class).

### Regenerating Accessors

After moving resources to `composeResources/`, run a Gradle sync or build to regenerate the `Res` class. Then update imports throughout the UI code.

### Qualifiers

Compose Multiplatform supports resource qualifiers similar to Android:

```
composeResources/
├── values/
│   └── strings.xml              ← default
├── values-de/
│   └── strings.xml              ← German
├── drawable-night/
│   └── background.xml           ← dark mode
└── drawable-xxhdpi/
    └── icon.png                 ← density qualifier
```

See the [Compose Multiplatform resources documentation](https://kotlinlang.org/docs/multiplatform/compose-multiplatform-resources.html) for the full list of supported qualifiers.

### Resource Configuration

Configure the generated `Res` class in `build.gradle.kts` via the `compose.resources` block — custom package name (`packageOfResClass`), public visibility (`publicResClass`), and generation mode (`generateResClass`). See the [setup documentation](https://kotlinlang.org/docs/multiplatform/compose-multiplatform-resources-setup.html).

When using the `androidLibrary` target, enable Android resources explicitly: `androidResources.enable = true` inside the `androidLibrary {}` block.

### Strings, Arrays, and Plurals

String format is similar to Android — `stringResource()`, `stringArrayResource()`, `pluralStringResource()` all work the same way. Key differences:
- `%s` and `%d` are interchangeable — no type enforcement
- No need to escape `@` or `?` characters
- Non-composable `suspend` variants available: `getString()`, `getStringArray()`, `getPluralString()`

See the [resource usage documentation](https://kotlinlang.org/docs/multiplatform/compose-multiplatform-resources-usage.html) for full API reference.

### Raw Files and URIs

Raw files go in `composeResources/files/` (any subdirectory structure). Unlike other resources, they are loaded **asynchronously** via `Res.readBytes()` and do not support qualifiers.

Use `Res.getUri()` to get a platform-specific URI for passing to system APIs (video players, WebViews) instead of loading files into memory.

### Drawable Gotchas

- **Android XML vectors** must not reference external Android resources (`?attr/...`, `@android:...`)
- **SVG** is supported on all platforms **except Android** — use XML vectors for cross-platform graphics
- **Material icons** from Google Fonts: set `android:fillColor` to `#000000`, remove `android:tint` and `?attr/colorControlNormal`; use `ColorFilter.tint()` at runtime

### Runtime Locale, Theme, and Density

Resource qualifiers resolve automatically from the system environment. To override at runtime (e.g., in-app language switcher), use `CompositionLocalProvider` with platform-specific `expect`/`actual` implementations. See the [resource environment documentation](https://kotlinlang.org/docs/multiplatform/compose-resource-environment.html).

---

## Theme and Design System

### Color Scheme

Dynamic colors (Material You) are Android-only. For multiplatform, provide a platform-aware color scheme:

```kotlin
// commonMain
@Composable
expect fun appColorScheme(): ColorScheme

// androidMain
@Composable
actual fun appColorScheme(): ColorScheme {
    val context = LocalContext.current
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        dynamicDarkColorScheme(context) // or dynamicLightColorScheme
    } else {
        defaultColorScheme()
    }
}

// iosMain
@Composable
actual fun appColorScheme(): ColorScheme = defaultColorScheme()
```

### Typography

Font loading differs in Compose Multiplatform. Fonts must be loaded as composable
resources:

```kotlin
// commonMain
@Composable
fun AppTypography(): Typography {
    val robotoRegular = Font(Res.font.roboto_regular)
    val robotoBold = Font(Res.font.roboto_bold, FontWeight.Bold)

    val fontFamily = FontFamily(robotoRegular, robotoBold)

    return Typography(
        bodyLarge = TextStyle(fontFamily = fontFamily, fontSize = 16.sp),
        titleLarge = TextStyle(fontFamily = fontFamily, fontWeight = FontWeight.Bold, fontSize = 22.sp),
    )
}
```

**Note:** Font resources should be in the top-level shared module's `composeResources/font/`
directory. Fonts in sub-modules may not be accessible via iOS framework exports.

### Theme Wrapper

```kotlin
// commonMain
@Composable
fun AppTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = appColorScheme(),
        typography = AppTypography(),
        content = content,
    )
}
```

---

## Screen-by-Screen Migration

Migrate screens incrementally. Start with leaf screens (fewest dependencies on other
screens) and work toward the root.

### Per-Screen Checklist

For each screen:

1. **Check dependencies** — does the screen's ViewModel use only shared (commonMain) dependencies? 
   If not, those dependencies need to be migrated first or the screen stays Android-only for now.

2. **Move composable functions** — copy from the Android module to `commonMain` in the
   shared UI module. Compile to see what breaks.

3. **Fix resource references** — `R.*` → `Res.*` for all string, drawable, color, and font references.

4. **Fix Android-specific APIs** — look for:
   - `LocalContext.current` — wrap in expect/actual or remove
   - `Toast.makeText(...)` — replace with a shared notification pattern
   - `startActivity(...)` — use a platform-specific navigation callback
   - `AnnotatedString.fromHtml()` — use a multiplatform HTML parser if possible

5. **Update the screen's entry in navigation** — the navigation graph references the
   new shared composable instead of the Android-only one.

6. **Test** — run the Android app and verify the migrated screen works identically.

### Leaving Screens Behind

It's perfectly fine to migrate only some screens. A navigation graph can mix:
- Shared screens (from `commonMain`)
- Platform-specific screens (from `androidMain` or the Android app module)

This lets the migration happen gradually without blocking releases.

---

## Navigation

### Compose Multiplatform Navigation

Compose Multiplatform includes navigation support compatible with Jetpack Navigation.
The typical migration:

```kotlin
// commonMain — shared navigation graph
@Composable
fun AppNavigation(
    navController: NavHostController = rememberNavController(),
    platformScreens: @Composable (NavGraphBuilder.() -> Unit)? = null,
) {
    NavHost(navController = navController, startDestination = "home") {
        composable("home") { HomeScreen(navController) }
        composable("details/{id}") { backStackEntry ->
            DetailsScreen(
                id = backStackEntry.arguments?.getString("id") ?: "",
                navController = navController,
            )
        }
        // Inject platform-specific screens
        platformScreens?.invoke(this)
    }
}
```

On Android, inject any remaining platform-specific screens:

```kotlin
// androidMain or Android app module
AppNavigation(
    platformScreens = {
        composable("player") { PlayerScreen() }  // not yet migrated
    },
)
```

### Type-Safe Navigation

If the project uses type-safe navigation routes (serializable objects), these work in
Compose Multiplatform with `kotlinx-serialization`:

```kotlin
@Serializable
data class DetailsRoute(val id: String)
```

---

## ViewModel Migration

### Google's Multiplatform ViewModel

Google provides multiplatform ViewModel support through the lifecycle-viewmodel library.
For modules already using `androidx.lifecycle.ViewModel`, the migration is minimal:

```kotlin
// commonMain
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn

class HomeViewModel(
    private val repository: PodcastRepository,
) : ViewModel() {

    val podcasts: StateFlow<List<Podcast>> = repository.getPodcasts()
        .stateIn(viewModelScope, SharingStarted.Lazily, emptyList())
}
```

### DI Integration

With Koin, ViewModels in shared code:

```kotlin
// commonMain — DI module
val viewModelModule = module {
    viewModelOf(::HomeViewModel)
}

// commonMain — composable
@Composable
fun HomeScreen() {
    val viewModel: HomeViewModel = koinViewModel()
    val podcasts by viewModel.podcasts.collectAsStateWithLifecycle()
    // ...
}
```

---

## Platform-Specific UI

### expect/actual for UI Components

When a UI component needs platform-specific behavior:

```kotlin
// commonMain
@Composable
expect fun VideoPlayer(url: String, modifier: Modifier = Modifier)

// androidMain
@Composable
actual fun VideoPlayer(url: String, modifier: Modifier) {
    AndroidView(
        factory = { context -> ExoPlayerView(context).apply { setUrl(url) } },
        modifier = modifier,
    )
}

// iosMain
@Composable
actual fun VideoPlayer(url: String, modifier: Modifier) {
    UIKitView(
        factory = { AVPlayerView().apply { load(url) } },
        modifier = modifier,
    )
}
```

### Platform Insets and System UI

Window insets handling differs across platforms. Use Compose Multiplatform's built-in
inset support where available, and provide platform implementations where needed:

```kotlin
// commonMain — Compose Multiplatform provides these
Modifier.windowInsetsPadding(WindowInsets.systemBars)
Modifier.windowInsetsPadding(WindowInsets.statusBars)
Modifier.windowInsetsPadding(WindowInsets.navigationBars)
```

### Compose Previews

`@Preview` works in `commonMain` — previews render in IntelliJ IDEA and Android Studio without running an emulator. The project must have an Android target, as previews rely on Android libraries under the hood.

**Setup:** Add the annotation dependency in `commonMain` and the tooling dependency for Android:

```kotlin
// commonMain
commonMain.dependencies {
    implementation("org.jetbrains.compose.ui:ui-tooling-preview:<cmp-version>")
}

// root dependencies block
dependencies {
    // AGP 9 (com.android.kotlin.multiplatform.library):
    androidRuntimeClasspath("org.jetbrains.compose.ui:ui-tooling:<cmp-version>")
    // Older AGP (com.android.application or com.android.library):
    // debugImplementation("org.jetbrains.compose.ui:ui-tooling:<cmp-version>")
}
```

```kotlin
// commonMain
import androidx.compose.ui.tooling.preview.Preview

@Preview
@Composable
fun HomeScreenPreview() {
    AppTheme {
        HomeScreen()
    }
}
```

Supported `@Preview` parameters: `name`, `group`, `widthDp`, `heightDp`, `locale`, `showBackground`, `backgroundColor`.

For live iteration on desktop targets, use [Compose Hot Reload](https://github.com/niceda/compose-hot-reload).

See the [Compose previews documentation](https://kotlinlang.org/docs/multiplatform/compose-previews.html) for the full setup reference.
