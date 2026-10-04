// import 'dart:ui';

import 'package:bsat/firebase_options.dart';
import 'package:bsat/screens/home/home.dart';
import 'package:bsat/screens/onboarding/main_page.dart';
import 'package:bsat/services/firebase_messaging_service.dart';
import 'package:bsat/services/shared_preferences_service.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:bsat/utils/logger.dart';

import 'providers/theme_provider.dart';
import 'screens/settings/kill_switch.dart';
import 'services/admin_management_service.dart';
import 'services/main_engine_ussd_bridge.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // BsatLogger.captureLogs();

  // whatsappService.initWhatsapp();

  // BsatLogger.runZonedWithLogs(() async {
  await BsatLogger.initFileLogging();

  var databasesPath = await getDatabasesPath();
  String path = join(databasesPath, 'bsat_app.db');

  SQLiteService sqLiteService = SQLiteService();

  await openDatabase(
    path,
    version: 1,
    onCreate: sqLiteService.onCreate,
  );

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  registerMainEngineAlternativeUssdBridge();

  // Initialize Firebase Messaging (Don't await to prevent blocking startup)
  FirebaseMessagingService().initNotifications();

  // Firebase crashlytics is already partly integrated via captureLogs, but we can keep these
  // or let logger.dart handle it if we want to forward it there instead.
  // We'll leave them as is for now.
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: MyApp(),
    ),
  );
  // });
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  KillswitchConfig? _config;
  bool _skippedKillswitch = false;

  @override
  void initState() {
    super.initState();
    _checkKillswitch();
  }

  Future<void> _checkKillswitch() async {
    setState(() => _config = null); // Shows loading spinner
    final config = await AdminManagementService.evaluateKillswitch();
    setState(() => _config = config);
  }

  Widget _getAppRoot() {
    // 1. Loading State
    if (_config == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // 2. Killswitch Enforcements (If not skipped)
    if (!_skippedKillswitch) {
      switch (_config!.enforcement) {
        case KillswitchEnforcement.hardKill:
          return KillswitchScreen(config: _config!, isDismissible: false);

        case KillswitchEnforcement.softKill:
          return KillswitchScreen(
            config: _config!,
            isDismissible: true,
            onSkip: () => setState(() => _skippedKillswitch = true),
          );

        case KillswitchEnforcement.offlineLockout:
          return KillswitchScreen(
            config: _config!,
            isDismissible: false,
            onRetry: _checkKillswitch,
          );

        case KillswitchEnforcement.safe:
          break; // App is safe, proceed to main flow
      }
    }

    // 3. Normal App Flow (Original FutureBuilder logic)
    return FutureBuilder<bool?>(
      future: SharedPreferencesService().getRunningStatus(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        } else if (snapshot.hasError) {
          return const Scaffold(body: Center(child: Text('Error loading app')));
        } else {
          bool? isRunning = snapshot.data;
          return isRunning ?? false ? const HomePage() : const OnboardingPage();
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          title: 'BSAT',
          theme: themeProvider.currentTheme,
          home:
              _getAppRoot(), // Routes intelligently based on killswitch & auth
        );
      },
    );
  }
}
