# Changing the App Theme

## How Themes Work Here
- The app uses a `ThemeProvider` (Provider/ChangeNotifier) to expose `currentTheme` to `MaterialApp`.
- Themes live under `lib/utils/theme.dart` and can be switched at runtime via the provider.

## Quick Steps to Switch Theme (in code)
1) Open [lib/utils/theme.dart](../lib/utils/theme.dart) to view/edit the light/dark (or custom) ThemeData definitions.
2) Open [lib/providers/theme_provider.dart](../lib/providers/theme_provider.dart) to see how the provider stores and toggles the current theme.
3) To change defaults, adjust the ThemeData in `theme.dart` and ensure `ThemeProvider` points to it.
4) If you want a toggle action in UI, inject `ThemeProvider` (via `Provider.of` / `Consumer`) and call its toggle/set method.

## Adding a New Theme Variant
1) In `lib/utils/theme.dart`, define a new `ThemeData` (e.g., `highContrastTheme`).
2) Update `ThemeProvider` to expose and switch to that variant (add a method like `setTheme(AppTheme.newVariant)`).
3) Persist the choice (optional): extend `ThemeProvider` to save the selected theme key in `SharedPreferencesService` and restore on startup.

## Where to Wire the Theme
- Entry point: [lib/main.dart](../lib/main.dart) uses `ThemeProvider` to supply `currentTheme` into `MaterialApp`.
- Any widget can read the current theme with `Theme.of(context)` or listen to `ThemeProvider` for changes.

## Tips
- Keep colors and typography in one place (`theme.dart`) to avoid divergence across the app.
- Test both light and dark (or custom) for contrast and readability, especially dialogs and inputs.
- If introducing new brand colors, update `constants.dart` only for non-ThemeData constants; prefer using Theme colors in widgets when possible.
