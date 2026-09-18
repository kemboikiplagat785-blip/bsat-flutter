import 'dart:async';
import 'dart:ui';

// import 'package:bsat/services/skills.dart';
// import 'package:bsat/services/socket_service.dart';
import 'package:bsat/services/shared_preferences_service.dart';
import 'package:bsat/services/skills.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:phone_state/phone_state.dart';

import './sms_sevice.dart';
import '../controllers/transaction_controller.dart';

const notificationChannelId = 'meister_foreground';

Future<void> initializeBackgroundService() async {
  final flutterBackgroundService = FlutterBackgroundService();

  initMessagesPlatformState();

  await flutterBackgroundService.configure(
    iosConfiguration: IosConfiguration(),
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      isForegroundMode: true,
      foregroundServiceNotificationId: 888,
    ),
  );

  await flutterBackgroundService.startService();
}

class _TransactionControllerService {
  static final _TransactionControllerService _instance =
      _TransactionControllerService._internal();
  late TransactionController transactionController;

  _TransactionControllerService._internal();

  factory _TransactionControllerService() {
    return _instance;
  }
}

// Then update the onStart function:
@pragma('vm:entry-point')
void onStart(ServiceInstance serviceInstance) async {
  const int retryAfter = 20;
  const Duration maskedCallLogDelay = Duration(minutes: 5);
  bool isTickRunning = false;
  bool hasRunMidnightBatchUpload = false;
  Timer? pendingMaskedCheckTimer;
  StreamSubscription<PhoneState>? phoneStateSubscription;

  // Initialize the singleton
  final transactionService = _TransactionControllerService();
  transactionService.transactionController = TransactionController();
  final transactionController = transactionService.transactionController;

  final SharedPreferencesService sharedPreferencesService =
      SharedPreferencesService();

  DartPluginRegistrant.ensureInitialized();

  if (serviceInstance is AndroidServiceInstance) {
    serviceInstance.on('setAsForeground').listen((event) {
      serviceInstance.setAsForegroundService();
    });

    serviceInstance.on('setAsBackground').listen((event) {
      serviceInstance.setAsBackgroundService();
    });
  }

  serviceInstance.on('stopService').listen((event) async {
    pendingMaskedCheckTimer?.cancel();
    await phoneStateSubscription?.cancel();
    serviceInstance.stopSelf();
  });

  initMessagesPlatformState();

  if (serviceInstance is AndroidServiceInstance) {
    phoneStateSubscription = PhoneState.stream.listen((state) async {
      if (state.status == PhoneStateStatus.CALL_INCOMING) {
        // Check if permission is already granted
        // Note: Permission requests cannot be made from background service (no Activity context)
        // Permission must be requested in the main app when in foreground
        if ((await Permission.phone.status).isGranted) {
          print("call from ${state.number}");
          transactionController.unmaskFromCall(state.number ?? "");
        } else {
          print(
              "call from ${state.number} - Permission.phone not granted, skipping unmask");
        }
      }
    });
  }

  Timer.periodic(Duration(seconds: retryAfter), (timer) async {
    if (isTickRunning) return;
    isTickRunning = true;

    try {
      if (serviceInstance is AndroidServiceInstance) {
        initMessagesPlatformState();

        if (await serviceInstance.isForegroundService()) {
          initMessagesPlatformState();

          // Check for midnight ±50 minutes for client batch upload
          final now = DateTime.now();
          final midnight = DateTime(now.year, now.month, now.day);
          final minutesFromMidnight = now.difference(midnight).inMinutes;

          if ((minutesFromMidnight >= 0 && minutesFromMidnight <= 50) ||
              (minutesFromMidnight >= 1410 && minutesFromMidnight < 1440)) {
            if (!hasRunMidnightBatchUpload) {
              hasRunMidnightBatchUpload = true;
              await transactionController.uploadClientsToBatchServer();
            }
          } else {
            // Reset flag when we're outside the midnight window
            if (minutesFromMidnight > 100 && minutesFromMidnight < 1400) {
              hasRunMidnightBatchUpload = false;
            }
          }

          // check if time between midnight and midnight + retryAfter (seconds)
          if (DateTime.now().hour == 0 &&
              DateTime.now().minute == 0 &&
              DateTime.now().second <= retryAfter) {
            if ((await sharedPreferencesService.getAutoScheduleFailed() ??
                false)) {
              await transactionController.autoScheduleFailedRecommendations();
            }
          }

          await TransactionController().retryAll(true);
          await transactionController.checkSkipped();
          await transactionController.runScheduled();

          await Skills().large();

          serviceInstance.setForegroundNotificationInfo(
            title: 'BSAT Active',
            content: 'Working in the background',
          );
        }
      }
    } finally {
      isTickRunning = false;
    }
  });
}
