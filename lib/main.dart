// import 'dart:ui';

import 'package:bsat/firebase_options.dart';
import 'package:bsat/screens/dashboard.dart';
import 'package:bsat/screens/onboarding/main_page.dart';
import 'package:bsat/services/shared_preferences_service.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';

import 'providers/theme_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  var databasesPath = await getDatabasesPath();
  String path = join(databasesPath, 'bsat_app.db');

  SQLiteService sqLiteService = SQLiteService();

  await openDatabase(
    path,
    version: 1,
    onCreate: sqLiteService.onCreate,
  );

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

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
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(builder: (context, themeProvider, child) {
      return MaterialApp(
        title: 'BSAT',
        theme: themeProvider.currentTheme,
        home: FutureBuilder<bool?>(
          future: SharedPreferencesService().getRunningStatus(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            } else if (snapshot.hasError) {
              return const Center(child: Text('Error loading app'));
            } else {
              bool? isRunning = snapshot.data;
              return isRunning ?? false
                  ? const DashBoardPage()
                  : const OnboardingPage();
            }
          },
        ),
      );
    });
  }
}
