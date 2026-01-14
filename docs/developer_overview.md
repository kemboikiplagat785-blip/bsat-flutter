# BSAT (Bingwa Sokoni Automation Toolkit) — Developer Onboarding

## What BSAT Does
- Automates agents’ sale of data bundles, SMS, and minutes by watching incoming M-PESA payment SMS, mapping the amount to the right offer, and executing the matching USSD flow.
- Keeps a local event log and counters (SQLite) and can sync/observe remote state via the online management features (multi-device coordination, forwarding).
- Exposes a dashboard for KPIs, recent activity, tools, and subscription status.

## High-Level Architecture
- **Flutter UI (screens/components)**: Entry at [lib/main.dart](lib/main.dart) boots SQLite, crash reporting hooks, then routes to onboarding or the dashboard. UI is broken into screens (dashboard, offers, inbox, replies, tasks, stats, settings, online management) and reusable components (dialogs, tool buttons, transaction list items).
- **State/ViewModels**: Provider-based `ChangeNotifier` models (e.g., [lib/screens/dashboard/dashboard_view_model.dart](lib/screens/dashboard/dashboard_view_model.dart)) expose derived UI state, handle polling, and coordinate services.
- **Domain/Use-Case Logic** (spread across services):
  - SMS/USSD automation: parse M-PESA SMS, pick an offer, dial USSD, capture replies, persist to SQLite, update counters.
   - Background execution: `flutter_background_service` keeps processing outside the foreground UI.
   - Auth/online: `AuthService`, online presence, and device coordination in the `online_management` screens.
- **Data Layer**: Services wrap plugins/platform APIs: SQLite (`sqlite_service.dart`), shared prefs (`shared_preferences_service.dart`), telephony/USSD (`my_ussd_service.dart`, `sms_service.dart`, `phone_service.dart`), sockets, file handling, contacts, remote config.
- **Assets/Config**: `pubspec.yaml` declares dependencies; `assets/` holds icons, images, fonts; platform folders contain native configs.

## Core Flows
1) **App launch** (see [lib/main.dart](lib/main.dart))
   - Initialize Flutter binding, open/create `bsat_app.db` via `SQLiteService`, wire crash reporting, start app with `ThemeProvider`.
   - Decide home: if `SharedPreferencesService.getRunningStatus()` is true → dashboard; else onboarding.

2) **Dashboard loop** (see [lib/screens/dashboard/dashboard.dart](lib/screens/dashboard/dashboard.dart) and [lib/screens/dashboard/dashboard_tools.dart](lib/screens/dashboard/dashboard_tools.dart))
   - ViewModel polls SQLite/shared prefs for transaction counts, balances, subscription expiry, and running state.
   - UI shows KPIs, recent transactions, and a collapsible “My tools” set of shortcuts (history, stats, dialpad, inbox, blacklist, offers, replies, scheduler, subscription, settings, online management).

3) **Automation pipeline** (services; refer to `sms_service.dart`, `my_ussd_service.dart`, `phone_service.dart`, `sqlite_service.dart`)
   - Background service listens for incoming M-PESA SMS.
   - Parser extracts amount, maps to an offer, and triggers the matching USSD code.
   - USSD replies and transaction status are stored in SQLite; dashboard reflects via periodic reloads.
   - SharedPrefs hold lightweight flags (running state, auto-retry, tokens, expiry) used by UI and background workers.

4) **Online management** (see [lib/screens/online_management/](lib/screens/online_management/))
   - Auth via `AuthService` gates remote features.
   - Pages for login/signup/OTP/reset, forward/receive requests, selling links, and device control (some marked coming soon).

5) **Subscriptions & offers**
   - Offers UI and dialogs live under [lib/screens/offers/](lib/screens/offers/); subscription purchase/renewal under [lib/screens/subscriptions/](lib/screens/subscriptions/).

## Key Modules (by directory)
- `lib/screens/dashboard/` — dashboard surface, view model, tools section.
- `lib/screens/offers/` — offer listing/editing.
- `lib/screens/transactions/` — history views and transaction list items.
- `lib/screens/replies/`, `inbox.dart`, `foward_sms.dart` — messaging/reply flows.
- `lib/screens/tasks/`, `stats/`, `settings/`, `subscriptions/` — supporting features.
- `lib/screens/online_management/` — cloud-backed login, forwarding, presence.
- `lib/components/` — shared UI (headers, hero, dialogs, tool buttons, transaction rows).
- `lib/services/` — platform and backend glue (auth, background service, SQLite, shared prefs, USSD/SMS, sockets, payments, remote config, contacts, files).
- `lib/utils/` — constants, theming helpers, date/number formatting, SIM helpers.

## Data & State
- **SQLite**: primary store for transactions, offers, codes; initialized in [lib/main.dart](lib/main.dart) and used throughout via `SQLiteService`.
- **Shared Preferences**: quick flags/counters for session state (running status, auto-retry, tokens, expiry, username) via `SharedPreferencesService`.
- **Remote/cloud (optional)**: online features can sync state across devices via the services under `online_management`.

## Background/Permissions
- Background work uses `flutter_background_service` plus telephony/USSD plugins; ensure required Android permissions (SMS, phone, overlays/accessibility where needed) are granted. See dialogs under `components/dialogs/` for permission prompts.

## Local Development Setup
1) Install Flutter 3.2+ and Android/iOS tooling; run `flutter pub get`.
2) Ensure any platform-specific config files are present for your target (e.g., Android/iOS service configs if used).
3) Run the app: `flutter run` (ensure a device/emulator with SIM/telephony support for USSD tests, or mock services in debug).
4) Tests: start with `flutter test` (unit/widget). Integration of telephony/USSD may require device testing or mocks.

## Working Patterns
- Keep widgets presentational; push logic into view models/services.
- When adding tools/shortcuts, use the extracted `DashboardToolsSection` and provide an `onReload` callback to refresh state after navigation.
- Prefer new dialogs/components under `components/` for reuse and consistency.
- For new flows, wire navigation via `PageRouteBuilder` (matching existing transitions) and update ViewModel to expose any new counters/state.

## Troubleshooting
- Dashboard not updating: check background service running state and shared prefs flags; verify `SQLiteService` queries and timer/polling in `DashboardViewModel`.
- SMS/USSD not firing: confirm Android permissions, SIM availability, and that telephony plugins are initialized. Review `phone_service.dart`/`sms_service.dart` logs.
- Online sync issues: verify connectivity and service availability for the online features.

## Quick Entry Points
- App bootstrap: [lib/main.dart](lib/main.dart)
- Dashboard UI: [lib/screens/dashboard/dashboard.dart](lib/screens/dashboard/dashboard.dart)
- Dashboard view model: [lib/screens/dashboard/dashboard_view_model.dart](lib/screens/dashboard/dashboard_view_model.dart)
- Tools section: [lib/screens/dashboard/dashboard_tools.dart](lib/screens/dashboard/dashboard_tools.dart)
- Automation services: see `lib/services/` (notably `sms_service.dart`, `my_ussd_service.dart`, `phone_service.dart`, `sqlite_service.dart`).
