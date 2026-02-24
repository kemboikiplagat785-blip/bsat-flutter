import 'dart:io';
import 'dart:convert';
import 'package:pub_semver/pub_semver.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

enum KillswitchEnforcement { safe, softKill, hardKill, offlineLockout }

class KillswitchConfig {
  final KillswitchEnforcement enforcement;
  final int daysRemaining;
  final String message;
  final String updateUrl;

  KillswitchConfig({
    required this.enforcement,
    required this.daysRemaining,
    required this.message,
    required this.updateUrl,
  });
}

class KillswitchService {
  static const String _configUrl = 'https://api.bsat.co.ke/api/devices/app-config';

  static Future<KillswitchConfig> evaluateKillswitch() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Load cached values
    String minVersionStr = prefs.getString('ks_min_version') ?? '0.0.0';
    String deadlineStr = prefs.getString('ks_deadline') ?? '';
    String killMessage =
        prefs.getString('ks_message') ?? 'Please update the app to continue.';
    String updateUrl = prefs.getString('ks_url') ?? '';
    String lastCheckedStr = prefs.getString('ks_last_checked') ?? '';

    bool fetchSuccess = false;

    // 2. Try to fetch fresh data from server
    try {
      final response = await http.get(Uri.parse(_configUrl));

      if (response.statusCode == 200) {
        var data = json.decode(response.body);

        data = data['appConfig'] ?? {}; // Adjust based on actual API response structure

        print("response from killswitch endpoint, min_version: ${data['min_supported_version']}, deadline: ${data['last_supported_date']}");

        minVersionStr = data['min_supported_version'] ?? minVersionStr;
        deadlineStr = data['last_supported_date'] ?? deadlineStr;
        killMessage = data['kill_message'] ?? killMessage;
        updateUrl = Platform.isIOS
            ? (data['ios_store_url'] ?? '')
            : (data['android_store_url'] ?? '');

        // Cache the new data AND the current time
        await prefs.setString('ks_min_version', minVersionStr);
        await prefs.setString('ks_deadline', deadlineStr);
        await prefs.setString('ks_message', killMessage);
        await prefs.setString('ks_url', updateUrl);
        await prefs.setString(
            'ks_last_checked', DateTime.now().toIso8601String());

        fetchSuccess = true;
      }
    } catch (e) {
      print('Failed to fetch remote config: $e');
    }

    // 3. Check the 14-Day Offline Limit
    if (!fetchSuccess) {
      // If never checked before, default to epoch 0 (which guarantees > 14 days difference)
      DateTime lastChecked = lastCheckedStr.isNotEmpty
          ? DateTime.tryParse(lastCheckedStr) ??
              DateTime.fromMillisecondsSinceEpoch(0)
          : DateTime.fromMillisecondsSinceEpoch(0);

      if (DateTime.now().difference(lastChecked).inDays > 14) {
        final cfg = KillswitchConfig(
          enforcement: KillswitchEnforcement.offlineLockout,
          daysRemaining: 0,
          message:
              "Please connect to the internet temporarily to check for updates and continue using the app.",
          updateUrl: '',
        );
        _maybeExitForEnforcement(cfg.enforcement);
        return cfg;
      }
    }

    // 4. Evaluate Version & Deadline Logic
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    Version currentVersion = Version.parse(packageInfo.version);
    Version minVersion = Version.parse(minVersionStr);

    print("Old Config - minVersion: $minVersionStr, deadline: $deadlineStr");
    print("Current Version: ${packageInfo.version}"); 

    // If app is strictly up to date
    if (currentVersion >= minVersion) {
      return KillswitchConfig(
        enforcement: KillswitchEnforcement.safe,
        daysRemaining: 0,
        message: killMessage,
        updateUrl: updateUrl,
      );
    }

    // App is outdated. Calculate the countdown
    int daysRemaining = 0;
    KillswitchEnforcement enforcement = KillswitchEnforcement.hardKill;

    if (deadlineStr.isNotEmpty) {
      DateTime deadline = DateTime.parse(deadlineStr).toLocal();
      DateTime now = DateTime.now();

      daysRemaining = deadline.difference(now).inDays;

      if (now.isBefore(deadline)) {
        enforcement = KillswitchEnforcement.softKill; // Grace period active
      }
    }

    final cfg = KillswitchConfig(
      enforcement: enforcement,
      daysRemaining: daysRemaining,
      message: killMessage,
      updateUrl: updateUrl,
    );
    _maybeExitForEnforcement(cfg.enforcement);
    return cfg;
  }

  /// If enforcement requires immediate app termination, exit the process.
  /// Uses `exit(0)` which forcefully terminates the Dart VM; this is intended
  /// for strict killswitch scenarios where the app must not continue.
  static void _maybeExitForEnforcement(KillswitchEnforcement enforcement) {
    if (enforcement == KillswitchEnforcement.hardKill ||
        enforcement == KillswitchEnforcement.offlineLockout) {
      try {
        print('Killswitch enforcement triggered: $enforcement. Exiting app.');
        exit(0);
      } catch (e) {
        // If exit fails for any reason, just log and continue.
        print('Failed to exit app for killswitch: $e');
      }
    }
  }
}
