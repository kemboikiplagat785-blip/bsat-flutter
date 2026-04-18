import 'dart:async';
import 'dart:ui';

// import 'package:bsat/services/skills.dart';
// import 'package:bsat/services/socket_service.dart';
import 'package:bsat/services/shared_preferences_service.dart';
import 'package:bsat/services/skills.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

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

@pragma('vm:entry-point')
void onStart(ServiceInstance serviceInstance) async {
  int retryAfter = 20;
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
    serviceInstance.stopSelf();
  });

  initMessagesPlatformState();

  Timer.periodic(Duration(seconds: retryAfter), (timer) async {
    if (serviceInstance is AndroidServiceInstance) {
      initMessagesPlatformState();

      if (await serviceInstance.isForegroundService()) {
        initMessagesPlatformState();

        // check if time between midnight and midnight + retryAfter (seconds)

        if (DateTime.now().hour == 0 && DateTime.now().minute == 0 && DateTime.now().second <= retryAfter) {
          if ((await SharedPreferencesService().getAutoScheduleFailed() ?? false)) {
            await TransactionController().autoScheduleFailedRecommendations();
          }
        }

        await TransactionController().retryAll(true);
        await TransactionController().checkSkipped();
        await TransactionController().runScheduled();

        await Skills().large();

        serviceInstance.setForegroundNotificationInfo(
          title: 'BSAT Active',
          content: 'Working in the background',
        );
      }
    }
  });
}
