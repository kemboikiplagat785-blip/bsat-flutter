import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:bsat/services/skills.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import './sms_sevice.dart';
import '../controllers/transaction_controller.dart';

const notificationChannelId = 'meister_foreground';

Future<void> initializeBackgroundService() async {
  final flutterBackgroundService = FlutterBackgroundService();
// if (Platform.isAndroid) {
//   FlutterBackgroundServiceAndroid().setAutoStartOnBootMode(true);
//   FlutterBackgroundServiceAndroid().setForegroundMode(true);
// }

  initMessagesPlatformState();

  // print('Openning BG Service');
  await flutterBackgroundService.configure(
    iosConfiguration: IosConfiguration(),
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      // autoStart: true,
      isForegroundMode: true,
      // autoStartOnBoot: true,
      // notificationChannelId: notificationChannelId,
      foregroundServiceNotificationId: 888,
    ),
  );

  await flutterBackgroundService.startService();
}

@pragma('vm:entry-point')
void onStart(ServiceInstance serviceInstance) async {
  /// OPTIONAL when use custom notification
  // WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  final TransactionController transactionController = TransactionController();

  // print("\n\n\tStarted Service \n\n");

  // DartPluginRegistrant.ensureInitialized();
  if (serviceInstance is AndroidServiceInstance) {
    serviceInstance.on('setAsForeground').listen((event) {
      serviceInstance.setAsForegroundService();
    });
    serviceInstance.on('setAsBackground').listen((event) {
      serviceInstance.setAsBackgroundService();
    });
  }

  serviceInstance.on('stopService').listen((event) {
    serviceInstance.stopSelf();
  });

  initMessagesPlatformState();

  Timer.periodic(const Duration(seconds: 60), (timer) async {
    if (serviceInstance is AndroidServiceInstance) {
      initMessagesPlatformState();

      if (await serviceInstance.isForegroundService()) {
        initMessagesPlatformState();

        await transactionController.retryAll(true);

        await TransactionController().checkSkipped();

        await TransactionController().runScheduled();

        // await SkillsService().processSkill();

        // await TransactionController().

        serviceInstance.setForegroundNotificationInfo(
          title: 'BSAT',
          content: 'Running',
        );
      } else {}
    }
  });
}
