import 'dart:io';
import 'dart:convert';
import 'package:pub_semver/pub_semver.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/http.dart' as http;

enum KillswitchEnforcement { safe, softKill, hardKill, offlineLockout }

class KillswitchConfig {
  final KillswitchEnforcement enforcement;
  final int daysRemaining;
  final String message;
  final String updateUrl;

  const KillswitchConfig({
    required this.enforcement,
    required this.daysRemaining,
    required this.message,
    required this.updateUrl,
  });
}

class AdminManagementService {
  static const String _configUrl =
      'https://api.bsat.co.ke/api/devices/app-config';
      
  // Shared Preference key for the phone numbers
  static const String _phoneNumbersKey = 'admin_phone_numbers';

  /// GETTER for Phone Numbers
  static Future<List<int>> getPhoneNumbers() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> numbersString = prefs.getStringList(_phoneNumbersKey) ?? [];
    List<int> numbersInt = [];

    for (String number in numbersString) {
      numbersInt.add(int.parse(number));
    }

    return numbersInt;
  }

  /// SETTER for Phone Numbers
  static Future<void> setPhoneNumbers(List<String> numbers) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_phoneNumbersKey, numbers);
  }

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

    // 2. Try to fetch fresh data from server with a Timeout
    try {
      final response = await http
          .get(Uri.parse(_configUrl))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        var data = json.decode(response.body);
        data = data['appConfig'] ?? {};

        minVersionStr = data['min_supported_version'] ?? minVersionStr;
        deadlineStr = data['last_supported_date'] ?? deadlineStr;
        killMessage = data['kill_message'] ?? killMessage;

        if (Platform.isIOS) {
          updateUrl = data['ios_store_url'] ?? updateUrl;
        } else if (Platform.isAndroid) {
          updateUrl = data['android_store_url'] ?? updateUrl;
        }

        // --- NEW: Parse and Save Phone Numbers ---
        // Replace 'support_numbers' with the actual JSON key your API returns
        if (data['support_numbers'] != null) {
          // Safely convert the dynamic JSON list to a List<String>
          List<String> fetchedNumbers = List<String>.from(data['support_numbers']);
          await setPhoneNumbers(fetchedNumbers);
        }

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
      // Catching FormatExceptions, SocketExceptions, and TimeoutExceptions
    }

    // 3. Check the 14-Day Offline Limit
    if (!fetchSuccess) {
      DateTime lastChecked = lastCheckedStr.isNotEmpty
          ? DateTime.tryParse(lastCheckedStr) ?? DateTime.now()
          : DateTime.now();

      if (DateTime.now().difference(lastChecked).inDays > 14) {
        return const KillswitchConfig(
          enforcement: KillswitchEnforcement.offlineLockout,
          daysRemaining: 0,
          message:
              "Please connect to the internet temporarily to check for updates and continue using the app.",
          updateUrl: '',
        );
      }
    }

    // 4. Evaluate Version Logic
    PackageInfo packageInfo = await PackageInfo.fromPlatform();

    Version currentVersion;
    Version minVersion;

    try {
      currentVersion = Version.parse(_sanitizeVersion(packageInfo.version));
      minVersion = Version.parse(_sanitizeVersion(minVersionStr));
    } catch (e) {
      return KillswitchConfig(
        enforcement: KillswitchEnforcement.safe,
        daysRemaining: 0,
        message: killMessage,
        updateUrl: updateUrl,
      );
    }

    // If app is strictly up to date
    if (currentVersion >= minVersion) {
      return KillswitchConfig(
        enforcement: KillswitchEnforcement.safe,
        daysRemaining: 0,
        message: killMessage,
        updateUrl: updateUrl,
      );
    }

    // 5. App is outdated. Calculate the countdown
    int daysRemaining = 0;
    KillswitchEnforcement enforcement = KillswitchEnforcement.hardKill;

    if (deadlineStr.isNotEmpty) {
      DateTime? deadline = DateTime.tryParse(deadlineStr)?.toLocal();
      DateTime now = DateTime.now();

      if (deadline != null) {
        daysRemaining = (deadline.difference(now).inHours / 24).ceil();

        if (now.isBefore(deadline)) {
          enforcement = KillswitchEnforcement.softKill;
        }
      }
    }

    return KillswitchConfig(
      enforcement: enforcement,
      daysRemaining: daysRemaining > 0 ? daysRemaining : 0,
      message: killMessage,
      updateUrl: updateUrl,
    );
  }

  static String _sanitizeVersion(String version) {
    final parts = version.split('.');
    while (parts.length < 3) {
      parts.add('0');
    }
    return parts.take(3).join('.');
  }
}