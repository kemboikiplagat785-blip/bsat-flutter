// import 'dart:async';
// import 'package:flutter/material.dart';
// import 'package:flutter_accessibility_service/flutter_accessibility_service.dart';
// import 'package:app_settings/app_settings.dart';

// class AccessibilitySetupProcedure {

//   /// Main procedure to enforce accessibility activation and handle Android 13+ restrictions.
//   static Future<void> turnOnAccessibility(BuildContext context) async {
//     // Check if it's already enabled
//     bool isEnabled = await FlutterAccessibilityService.isAccessibilityPermissionEnabled();
//     if (isEnabled) {
//       _showSnackBar(context, "Accessibility Service is already enabled.");
//       return;
//     }

//     // Step 1: Open Accessibility Service settings
//     await _showInstructionDialog(
//       context,
//       "Turn on Accessibility",
//       "Please find our app under 'Installed Apps' (or 'Downloaded Apps') and turn on the Accessibility Service."
//     );

//     await FlutterAccessibilityService.requestAccessibilityPermission();
//     await _waitForAppResume();

//     // Check if the user turned it on successfully
//     isEnabled = await FlutterAccessibilityService.isAccessibilityPermissionEnabled();
//     if (isEnabled) {
//       _showSnackBar(context, "Accessibility Service enabled successfully!");
//       return;
//     }

//     // Step 2: If it isn't turned on, it might be due to Android 13+ Restricted Settings
//     await _showInstructionDialog(
//       context,
//       "Restricted Settings Detected",
//       "If the setting was grayed out with a 'Restricted Setting' warning, we need to allow it first.\n\n"
//       "We will now open the App Info page. Please click the 3 vertical dots in the top right corner and select 'Allow restricted settings'."
//     );

//     // Open Settings -> Apps -> My App (App Info)
//     await AppSettings.openAppSettings();
//     await _waitForAppResume();

//     // Step 3: Reopen Accessibility settings
//     await _showInstructionDialog(
//       context,
//       "Final Step",
//       "Now that restricted settings are allowed, let's go back and turn on the Accessibility Service. Click 'Allow' when prompted."
//     );

//     await FlutterAccessibilityService.requestAccessibilityPermission();
//     await _waitForAppResume();

//     // Final Validation Check
//     isEnabled = await FlutterAccessibilityService.isAccessibilityPermissionEnabled();
//     if (isEnabled) {
//       _showSnackBar(context, "Accessibility Service enabled successfully!");
//     } else {
//       _showSnackBar(context, "Accessibility Service is still not enabled. You may need to try again.");
//     }
//   }

//   /// Helper to wait until the app returns to the foreground.
//   static Future<void> _waitForAppResume() async {
//     final completer = Completer<void>();
//     bool hasGoneToBackground = false;

//     final observer = _LifecycleObserver(
//       onStateChanged: (state) {
//         if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
//           hasGoneToBackground = true;
//         } else if (state == AppLifecycleState.resumed && hasGoneToBackground) {
//           if (!completer.isCompleted) completer.complete();
//         }
//       },
//     );
//     WidgetsBinding.instance.addObserver(observer);

//     // Safety timeout: If the settings fail to open, don't freeze the app infinitely.
//     Future.delayed(const Duration(seconds: 2), () {
//       if (!hasGoneToBackground && !completer.isCompleted) {
//         completer.complete();
//       }
//     });

//     await completer.future;
//     WidgetsBinding.instance.removeObserver(observer);
//   }

//   /// Helper to show an instructional dialog requiring the user to tap "Got it"
//   static Future<void> _showInstructionDialog(BuildContext context, String title, String content) async {
//     return showDialog<void>(
//       context: context,
//       barrierDismissible: false, // Forces user to click the button
//       builder: (BuildContext context) {
//         return AlertDialog(
//           title: Text(title),
//           content: Text(content),
//           actions: <Widget>[
//             TextButton(
//               child: const Text('Got it'),
//               onPressed: () => Navigator.of(context).pop(),
//             ),
//           ],
//         );
//       },
//     );
//   }

//   static void _showSnackBar(BuildContext context, String text) {
//     ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
//   }
// }

// /// A custom WidgetsBindingObserver to listen for app background/foreground state changes
// class _LifecycleObserver extends WidgetsBindingObserver {
//   final Function(AppLifecycleState) onStateChanged;

//   _LifecycleObserver({required this.onStateChanged});

//   @override
//   void didChangeAppLifecycleState(AppLifecycleState state) {
//     onStateChanged(state);
//   }
// }








import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_accessibility_service/flutter_accessibility_service.dart';
import 'package:app_settings/app_settings.dart';

class AccessibilityTutorialScreen extends StatefulWidget {
  const AccessibilityTutorialScreen({Key? key}) : super(key: key);

  @override
  State<AccessibilityTutorialScreen> createState() =>
      _AccessibilityTutorialScreenState();
}

class _AccessibilityTutorialScreenState
    extends State<AccessibilityTutorialScreen> {
  // 0 = Try Enabling, 1 = Allow Restricted, 2 = Final Try
  int _currentStep = 0;
  int _highestStepReached = 0;
  bool _isLoading = false;
  bool _isSuccess = false;

  @override
  void initState() {
    super.initState();
    _checkInitialState();
  }

  Future<void> _checkInitialState() async {
    bool isEnabled =
        await FlutterAccessibilityService.isAccessibilityPermissionEnabled();
    if (isEnabled) {
      setState(() => _isSuccess = true);
    }
  }

  /// Main handler for each step's button press
  Future<void> _executeStep(int step) async {
    if (_isLoading) return;
    setState(() {
      _currentStep = step;
      _isLoading = true;
    });

    try {
      if (step == 0) {
        // Step 1: Request Permission directly
        await FlutterAccessibilityService.requestAccessibilityPermission();
        await _waitForAppResume();

        bool isEnabled = await FlutterAccessibilityService
            .isAccessibilityPermissionEnabled();
        if (isEnabled) {
          setState(() => _isSuccess = true);
          _showSnackBar("🎉 Yay! Accessibility enabled!");
        } else {
          // Did not work, likely restricted. Move to step 1 (App Info)
          setState(() {
            _highestStepReached = max(_highestStepReached, 1);
            _currentStep = 1;
          });
        }
      } else if (step == 1) {
        // Step 2: Open App Info for Restricted Settings
        await AppSettings.openAppSettings();
        await _waitForAppResume();

        // Move to step 2 (Final Try)
        setState(() {
          _highestStepReached = max(_highestStepReached, 2);
          _currentStep = 2;
        });
      } else if (step == 2) {
        // Step 3: Final attempt to turn it on
        await FlutterAccessibilityService.requestAccessibilityPermission();
        await _waitForAppResume();

        bool isEnabled = await FlutterAccessibilityService
            .isAccessibilityPermissionEnabled();
        if (isEnabled) {
          setState(() => _isSuccess = true);
          _showSnackBar("🌟 You did it! Accessibility is on!");
        } else {
          _showSnackBar("Still not enabled. Let's try that step again!");
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Helper to wait until the app returns to the foreground.
  Future<void> _waitForAppResume() async {
    final completer = Completer<void>();
    bool hasGoneToBackground = false;

    final observer = _LifecycleObserver(
      onStateChanged: (state) {
        if (state == AppLifecycleState.paused ||
            state == AppLifecycleState.inactive) {
          hasGoneToBackground = true;
        } else if (state == AppLifecycleState.resumed && hasGoneToBackground) {
          if (!completer.isCompleted) completer.complete();
        }
      },
    );
    WidgetsBinding.instance.addObserver(observer);

    // Safety timeout: If settings fail to open, don't freeze the app.
    Future.delayed(const Duration(seconds: 2), () {
      if (!hasGoneToBackground && !completer.isCompleted) {
        completer.complete();
      }
    });

    await completer.future;
    WidgetsBinding.instance.removeObserver(observer);
  }

  void _showSnackBar(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
      backgroundColor: Colors.deepPurple,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDF8EE), // Creamy paper color
      appBar: AppBar(
        title: const Text("Setup Guide",
            style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.brown[800],
        centerTitle: true,
      ),
      body: _isSuccess
          ? _buildSuccessScreen()
          : Stack(
              children: [
                // The wobbly kid-book path in the background
                Positioned.fill(
                  child: CustomPaint(painter: MapPathPainter()),
                ),
                // The interactive steps
                ListView(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  children: [
                    _buildStepNode(
                      stepIndex: 0,
                      title: "1. Find Our App",
                      description:
                          "Let's turn on Accessibility! Find us under 'Installed Apps' and flip the switch.",
                      buttonText: "Go to Settings",
                      icon: Icons.settings,
                      color: Colors.blueAccent,
                    ),
                    const SizedBox(height: 40),
                    _buildStepNode(
                      stepIndex: 1,
                      title: "2. Restricted?",
                      description:
                          "Grayed out? Tap here to open App Info, click the 3 dots (⋮) top right, and hit 'Allow restricted settings'.",
                      buttonText: "Unlock Settings",
                      icon: Icons.lock_open_rounded,
                      color: Colors.orangeAccent,
                    ),
                    const SizedBox(height: 40),
                    _buildStepNode(
                      stepIndex: 2,
                      title: "3. Final Try!",
                      description:
                          "Now that it's unlocked, let's go back and turn it on for real! Hit 'Allow'.",
                      buttonText: "Turn On",
                      icon: Icons.check_circle_outline,
                      color: Colors.green,
                    ),
                    const SizedBox(height: 80), // Padding at bottom
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildStepNode({
    required int stepIndex,
    required String title,
    required String description,
    required String buttonText,
    required IconData icon,
    required Color color,
  }) {
    bool isLocked = stepIndex > _highestStepReached;
    bool isActive = stepIndex == _currentStep;

    return GestureDetector(
      onTap: () {
        if (!isLocked && !_isLoading) {
          setState(() => _currentStep = stepIndex);
        }
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left side: The bubble on the path
          SizedBox(
            width: 80,
            child: Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: isActive ? 50 : 40,
                  height: isActive ? 50 : 40,
                  decoration: BoxDecoration(
                    color: isLocked ? Colors.grey[400] : color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white,
                      width: isActive ? 4 : 2,
                    ),
                    boxShadow: [
                      if (!isLocked)
                        BoxShadow(
                          color: color.withOpacity(0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        )
                    ],
                  ),
                  child: Icon(
                    isLocked ? Icons.lock : icon,
                    color: Colors.white,
                    size: isActive ? 24 : 18,
                  ),
                ),
              ],
            ),
          ),

          // Right side: The playful card
          Expanded(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: isLocked ? 0.5 : 1.0,
              child: Container(
                margin: const EdgeInsets.only(right: 20),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isActive ? color : Colors.grey[200]!,
                    width: isActive ? 3 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    )
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Colors.brown[800],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.brown[600],
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (isActive)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: color,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed:
                              _isLoading ? null : () => _executeStep(stepIndex),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 3))
                              : Text(
                                  buttonText,
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold),
                                ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text("🎉", style: TextStyle(fontSize: 80)),
          const SizedBox(height: 20),
          Text(
            "All Set!",
            style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: Colors.brown[800]),
          ),
          const SizedBox(height: 10),
          Text(
            "Accessibility is turned on.\nYou are ready to go!",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, color: Colors.brown[600]),
          ),
          const SizedBox(height: 40),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
            ),
            onPressed: () => Navigator.of(context).pop(), // Close tutorial
            child: const Text("Continue",
                style: TextStyle(
                    fontSize: 18,
                    color: Colors.white,
                    fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }
}

/// A playful custom painter that draws a wobbly dotted "treasure map" line down the left side
class MapPathPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.brown[300]!.withOpacity(0.5)
      ..style = PaintingStyle.fill;

    // We draw a dotted wobbly line at X = 40 (center of the 80px width left margin)
    for (double y = 0; y < size.height; y += 15) {
      // sin wave makes it wobble playfully
      double xOffset = sin(y / 30) * 8;
      canvas.drawCircle(Offset(40 + xOffset, y), 3, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Helper lifecycle observer to detect when user returns from settings
class _LifecycleObserver extends WidgetsBindingObserver {
  final Function(AppLifecycleState) onStateChanged;

  _LifecycleObserver({required this.onStateChanged});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    onStateChanged(state);
  }
}
