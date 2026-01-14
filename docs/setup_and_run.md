# Setup & Run Guide

## Prerequisites
- Flutter SDK (3.27.x stable). Install from https://docs.flutter.dev/get-started/install and add `flutter` to PATH.
- Android Studio or cmdline tools (SDK/platform-tools) for Android builds/emulators.
- Java 17+ on PATH (Gradle/Android builds).
- Device or emulator with SIM/telephony for USSD/SMS features; otherwise mock/stub for dev.

## Bootstrap
1) Clone repo and open in VS Code/Android Studio.
2) Fetch packages:
   ```bash
   flutter pub get
   ```
3) (macOS/iOS) Install CocoaPods deps:
   ```bash
   cd ios && pod install && cd ..
   ```

## Platform Config
- **.env / Assets**: Assets are already listed in `pubspec.yaml`

## Running
- Hot run on a device/emulator:
  ```bash
  flutter run
  ```
- Build Android APK (release-like symbols split):
  ```bash
  flutter build apk --obfuscate --release
  ```

## Project Structure (quick map)
- Entry: [lib/main.dart](../lib/main.dart)
- Dashboard: [lib/screens/dashboard/](../lib/screens/dashboard/)
- Automation services: [lib/services/](../lib/services/) (USSD/SMS/SQLite/background)
- Components/dialogs: [lib/components/](../lib/components/)
- Docs: [docs/](.)

## Common Issues
- **Missing Android SDK / licenses**: run `flutter doctor --android-licenses`.
- **Gradle Java version**: ensure JAVA_HOME points to JDK 17+.
- **Permissions blocked**: manually enable SMS/phone/accessibility on device.
- **Remote config files**: ensure any environment-specific config files are present for your target platform.

## Useful Commands
- Verify setup: `flutter doctor -v`
- Analyze: `flutter analyze`
- Tests: `flutter test`
- Clean: `flutter clean && flutter pub get`

## Notes for USSD/SMS Testing
- Prefer real SIM on a physical device; emulators often lack USSD/SMS support.
- Keep the app foregrounded for advanced USSD flows unless queued; grant accessibility/overlay permissions when prompted.
