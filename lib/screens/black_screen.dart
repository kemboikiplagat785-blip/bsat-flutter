import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_brightness/screen_brightness.dart';

void main() {
  runApp(const MaterialApp(home: BlackoutScreen()));
}

class BlackoutScreen extends StatefulWidget {
  const BlackoutScreen({super.key});

  @override
  State<BlackoutScreen> createState() => _BlackoutScreenState();
}

class _BlackoutScreenState extends State<BlackoutScreen> {
  DateTime? _lastPressedAt;
  var brightness = 0.7;

  @override
  void initState() {
    super.initState();
    // 1. Hide the Status Bar and Navigation Bar (Immersive Mode)
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // 2. Set the device to stay awake (Optional: requires wakelock_plus package)
    // WakelockPlus.enable();
    getBrightness();
    Future.delayed(const Duration(milliseconds: 1000), () {
      _setBrightness(0.0);
    });
  }

  void _setBrightness(double brightness) async {
    try {
      await ScreenBrightness().setScreenBrightness(brightness);
    } catch (e) {
    }
  }

  void getBrightness() async {
    try {
      brightness = await ScreenBrightness().current;
    } catch (e) {
    }
  }

  void _unlock() {
    // Restore the UI bars
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    // stop controlling brightness
    _setBrightness(brightness);

    // Navigate to your main app content
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    // Restore System UI when leaving this screen
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 3. PopScope prevents the physical 'Back' button from working
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        final now = DateTime.now();
        final doublePressInterval = const Duration(seconds: 2);

        if (_lastPressedAt == null ||
            now.difference(_lastPressedAt!) > doublePressInterval) {
          // First press: store the time
          _lastPressedAt = now;

          // Optional: Show a subtle hint (remove if you want it 100% black)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Press back two more times to unlock"),
              duration: Duration(seconds: 1),
            ),
          );
        } else {
          // Second press within 2 seconds: Unlock
          _unlock();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        // 4. AbsorbPointer stops all touch events (tap, swipe, etc.)
        body: AbsorbPointer(
          absorbing: true,
          child: Container(
            color: Colors.black,
            width: double.infinity,
            height: double.infinity,
          ),
        ),
      ),
    );
  }
}
