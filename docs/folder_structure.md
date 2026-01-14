# Folder Structure & Quick Notes

Top-level layout and what to expect/fix when working in each area.


# Folder Structure & Quick Notes

Top-level layout, with lib/ folders only

```
lib/
    main.dart                  # App bootstrap: SQLite init, crash reporting hooks, theme provider
    components/                # Reusable UI (headers, dialogs, tool buttons, transaction items)
        dialogs/                 # All dialogs (accessibility, delete, retry, success, etc.)
    controllers/               # Business logic controllers (e.g., transaction pipeline)
    data/                      # Fake/mock data for testing
    models/                    # Data models (transaction, client, etc.)
    providers/                 # State providers (e.g., theme)
    screens/                   # Feature screens
    services/                  # Platform/back-end glue
    utils/                     # Constants, theming helpers, date/number formatting, SIM helpers
```

Top-level layout, with lib/ fully expanded.

```
lib/
  main.dart                  # App bootstrap: SQLite init, crash reporting hooks, theme provider
  firebase_options.dart      # Generated Firebase options (if used)
  components/                # Reusable UI (headers, dialogs, tool buttons, transaction items)
    dialogs/                 # All dialogs (accessibility, delete, retry, success, etc.)
  controllers/
    transaction_controller.dart
  data/
    fake.dart
  models/
    client.dart
    transaction.dart
  providers/
    theme_provider.dart
  screens/                   # Feature screens
    blacklist.dart
    dialpad.dart
    foward_sms.dart
    inbox.dart
    clients/
      clients.dart
    dashboard/
      dashboard.dart
      dashboard_tools.dart
      dashboard_view_model.dart
    offers/
      offers.dart
      edit_offer.dart
    onboarding/
      automate_splash.dart
      choose_cards.dart
      main_page.dart
      permissions.dart
      updated_toolkit.dart
    online_management/
      login.dart
      signup.dart
      otp.dart
      reset_password.dart
      online_management.dart
      forward_receive.dart
      edit_forwarder.dart
      edit_online_offer.dart
      my_online_presence.dart
      search_device.dart
    replies/
      replies.dart
      edit_reply.dart
    settings/
      settings.dart
      about.dart
      coming_soon.dart
      test.dart
    stats/
      statistics.dart
      airtime_per_day.dart
      commission.dart
      daily_value_performance_over_time.dart
      sales_volume_per_offer.dart
    subscriptions/
      subscription.dart
      add_token.dart
      online_subscription.dart
    tasks/
      tasks.dart
      edit_task.dart
    transactions/
      transaction_history.dart
      single_transacton.dart
  services/                  # Platform/back-end glue
    auth_service.dart
    background_service.dart
    client_service.dart
    contacts_service.dart
    file_service.dart
    firebase_auth.dart
    firebase_sync_service.dart
    my_ussd_service.dart
    online_db_service.dart
    payments.dart
    phone_service.dart
    remote_config.dart
    shared_preferences_service.dart
    skills.dart
    sms_sevice.dart
    socket_service.dart
    sqlite_service.dart
    supabase_auth.dart
    test.dart
  utils/
    constants.dart
    date_ops.dart
    get_sim_cards.dart
    internet.dart
    numbers.dart
    theme.dart
assets/
  images/
  icons/
  google_fonts/
android/, ios/, macos/, windows/, linux/, web/  # Platform shells/configs
build/                       # Generated/build artifacts (avoid editing)
docs/                        # Project docs (setup, overview, controller notes, viewer)
pubspec.yaml                 # Dependencies, assets, versioning
```

## Quick Pointers / Fix Checklist
- Add new UI pieces under `lib/components/` when reusable; wire screens in `lib/screens/`.
- Keep business logic in `controllers/` or `services/` (not in widgets).
- Update `pubspec.yaml` for assets/deps; run `flutter pub get` after changes.
- Generated/build outputs under `build/` should not be edited or committed.
- When adding routes, ensure consistent transitions (see existing `PageRouteBuilder` usage in screens).
- Tests live under `test/`; add unit/widget tests for controllers/services where possible.
- USSD execution is ultimately hosted in the Android layer: see `android/app/src/main/.../MainActivity` where platform hooks for USSD calls live.

## Key Entry Points
- App start: [lib/main.dart](../lib/main.dart)
- Dashboard: [lib/screens/dashboard/dashboard.dart](../lib/screens/dashboard/dashboard.dart)
- Dashboard state: [lib/screens/dashboard/dashboard_view_model.dart](../lib/screens/dashboard/dashboard_view_model.dart)
- Tools section: [lib/screens/dashboard/dashboard_tools.dart](../lib/screens/dashboard/dashboard_tools.dart)
- Transaction pipeline: [lib/controllers/transaction_controller.dart](../lib/controllers/transaction_controller.dart)
- Shared services hub: [lib/services/](../lib/services/)
```

## Quick Pointers / Fix Checklist
- Add new UI pieces under `lib/components/` when reusable; wire screens in `lib/screens/`.
- Keep business logic in `controllers/` or `services/` (not in widgets).
- Update `pubspec.yaml` for assets/deps; run `flutter pub get` after changes.
- Generated/build outputs under `build/` should not be edited or committed.
- When adding routes, ensure consistent transitions (see existing `PageRouteBuilder` usage in screens).
- Tests live under `test/`; add unit/widget tests for controllers/services where possible.

## Key Entry Points
- App start: [lib/main.dart](../lib/main.dart)
- Dashboard: [lib/screens/dashboard/dashboard.dart](../lib/screens/dashboard/dashboard.dart)
- Dashboard state: [lib/screens/dashboard/dashboard_view_model.dart](../lib/screens/dashboard/dashboard_view_model.dart)
- Tools section: [lib/screens/dashboard/dashboard_tools.dart](../lib/screens/dashboard/dashboard_tools.dart)
- Transaction pipeline: [lib/controllers/transaction_controller.dart](../lib/controllers/transaction_controller.dart)
- Shared services hub: [lib/services/](../lib/services/)
