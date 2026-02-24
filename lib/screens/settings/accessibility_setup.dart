import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_accessibility_service/flutter_accessibility_service.dart';
import 'package:app_settings/app_settings.dart';

class AccessibilitySetupProcedure {
  
  /// Main procedure to enforce accessibility activation and handle Android 13+ restrictions.
  static Future<void> turnOnAccessibility(BuildContext context) async {
    // Check if it's already enabled
    bool isEnabled = await FlutterAccessibilityService.isAccessibilityPermissionEnabled();
    if (isEnabled) {
      _showSnackBar(context, "Accessibility Service is already enabled.");
      return;
    }

    // Step 1: Open Accessibility Service settings
    await _showInstructionDialog(
      context, 
      "Turn on Accessibility", 
      "Please find our app under 'Installed Apps' (or 'Downloaded Apps') and turn on the Accessibility Service."
    );
    
    await FlutterAccessibilityService.requestAccessibilityPermission();
    await _waitForAppResume();

    // Check if the user turned it on successfully
    isEnabled = await FlutterAccessibilityService.isAccessibilityPermissionEnabled();
    if (isEnabled) {
      _showSnackBar(context, "Accessibility Service enabled successfully!");
      return;
    }

    // Step 2: If it isn't turned on, it might be due to Android 13+ Restricted Settings
    await _showInstructionDialog(
      context, 
      "Restricted Settings Detected", 
      "If the setting was grayed out with a 'Restricted Setting' warning, we need to allow it first.\n\n"
      "We will now open the App Info page. Please click the 3 vertical dots in the top right corner and select 'Allow restricted settings'."
    );

    // Open Settings -> Apps -> My App (App Info)
    await AppSettings.openAppSettings();
    await _waitForAppResume();

    // Step 3: Reopen Accessibility settings
    await _showInstructionDialog(
      context, 
      "Final Step", 
      "Now that restricted settings are allowed, let's go back and turn on the Accessibility Service. Click 'Allow' when prompted."
    );

    await FlutterAccessibilityService.requestAccessibilityPermission();
    await _waitForAppResume();

    // Final Validation Check
    isEnabled = await FlutterAccessibilityService.isAccessibilityPermissionEnabled();
    if (isEnabled) {
      _showSnackBar(context, "Accessibility Service enabled successfully!");
    } else {
      _showSnackBar(context, "Accessibility Service is still not enabled. You may need to try again.");
    }
  }

  /// Helper to wait until the app returns to the foreground.
  static Future<void> _waitForAppResume() async {
    final completer = Completer<void>();
    bool hasGoneToBackground = false;

    final observer = _LifecycleObserver(
      onStateChanged: (state) {
        if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
          hasGoneToBackground = true;
        } else if (state == AppLifecycleState.resumed && hasGoneToBackground) {
          if (!completer.isCompleted) completer.complete();
        }
      },
    );
    WidgetsBinding.instance.addObserver(observer);

    // Safety timeout: If the settings fail to open, don't freeze the app infinitely.
    Future.delayed(const Duration(seconds: 2), () {
      if (!hasGoneToBackground && !completer.isCompleted) {
        completer.complete();
      }
    });

    await completer.future;
    WidgetsBinding.instance.removeObserver(observer);
  }

  /// Helper to show an instructional dialog requiring the user to tap "Got it"
  static Future<void> _showInstructionDialog(BuildContext context, String title, String content) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // Forces user to click the button
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: <Widget>[
            TextButton(
              child: const Text('Got it'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  static void _showSnackBar(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

/// A custom WidgetsBindingObserver to listen for app background/foreground state changes
class _LifecycleObserver extends WidgetsBindingObserver {
  final Function(AppLifecycleState) onStateChanged;

  _LifecycleObserver({required this.onStateChanged});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    onStateChanged(state);
  }
}