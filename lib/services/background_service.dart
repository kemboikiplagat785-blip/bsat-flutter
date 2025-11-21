import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:bsat/services/skills.dart';
import 'package:bsat/services/socket.io_service.dart';
import 'package:bsat/services/shared_preferences_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
  DartPluginRegistrant.ensureInitialized();
  
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  final TransactionController transactionController = TransactionController();
  final SocketService socketService = SocketService();
  final _prefs = SharedPreferencesService();

  // Initialize Socket.IO connection
  String? token = await _prefs.getJwtToken(); // JWT token
  String? deviceDbId = await _prefs.getDeviceId(); // Device database ID
  
  if (token != null && deviceDbId != null) {
    // Setup socket callbacks
    socketService.onMessage = (data) async {
      print('Background: Message received from ${data['fromDeviceName']}: ${data['payload']}');
      
      // Parse payload to determine action
      final payload = data['payload'];
      
      if (payload is Map<String, dynamic>) {
        switch (payload['type']) {
          case 'transaction':
            print('Background: New transaction received');
            // Process transaction data
            if (payload['auto_process'] == true) {
              // Auto-process transaction
              await _processTransaction(payload['data'], transactionController);
            } else {
              // Show notification for manual processing
              _showNotification(
                flutterLocalNotificationsPlugin,
                'New Transaction',
                'From: ${data['fromDeviceName']}',
              );
            }
            break;
            
          case 'offer_update':
            print('Background: Offer update received');
            await _prefs.setOffersMightHaveChanged(true);
            _showNotification(
              flutterLocalNotificationsPlugin,
              'Offer Updated',
              'Your offers have been updated',
            );
            break;
            
          case 'retry_failed':
            print('Background: Retry failed transactions');
            await transactionController.retryAll(true);
            break;
            
          case 'sync_transactions':
            print('Background: Sync transactions requested');
            // Implement sync logic
            break;
            
          case 'notification':
            _showNotification(
              flutterLocalNotificationsPlugin,
              'BSAT Notification',
              payload['message'] ?? 'New notification',
            );
            break;
            
          default:
            print('Background: Unknown message type: ${payload['type']}');
            _showNotification(
              flutterLocalNotificationsPlugin,
              'Message from ${data['fromDeviceName']}',
              payload.toString(),
            );
        }
      } else {
        // Handle simple text messages
        _showNotification(
          flutterLocalNotificationsPlugin,
          'Message from ${data['fromDeviceName']}',
          payload.toString(),
        );
      }
    };

    socketService.onError = (error) {
      // print('Background: Socket error: ${error['message']}');
    };

    socketService.onConnect = () {
      print('Background: Socket connected');
    };

    socketService.onDisconnect = () {
      print('Background: Socket disconnected');
    };

    // Connect to socket
    socketService.connect(token: token, deviceDbId: deviceDbId);
  }

  if (serviceInstance is AndroidServiceInstance) {
    serviceInstance.on('setAsForeground').listen((event) {
      serviceInstance.setAsForegroundService();
    });
    
    serviceInstance.on('setAsBackground').listen((event) {
      serviceInstance.setAsBackgroundService();
    });
  }

  serviceInstance.on('stopService').listen((event) {
    socketService.disconnect();
    serviceInstance.stopSelf();
  });

  initMessagesPlatformState();

  Timer.periodic(const Duration(seconds: 60), (timer) async {
    if (serviceInstance is AndroidServiceInstance) {
      initMessagesPlatformState();

      if (await serviceInstance.isForegroundService()) {
        initMessagesPlatformState();

        // Keep socket alive - reconnect if disconnected
        if (!socketService.isConnected()) {
          String? token = await _prefs.getJwtToken();
          String? deviceDbId = await _prefs.getDeviceId() ?? '-1';
          
          if (token != null && deviceDbId != null) {
            print('Reconnecting socket...');
            socketService.connect(token: token, deviceDbId: deviceDbId);
          }
        }

        await transactionController.retryAll(true);
        await TransactionController().checkSkipped();
        await TransactionController().runScheduled();

        serviceInstance.setForegroundNotificationInfo(
          title: 'BSAT',
          content: 'Running - Socket: ${socketService.isConnected() ? "Connected" : "Disconnected"}',
        );
      }
    }
  });
}

Future<void> _processTransaction(
  Map<String, dynamic> transactionData,
  TransactionController controller,
) async {
  try {
    // Implement your transaction processing logic here
    print('Processing transaction: $transactionData');
    // Example: controller.processTransaction(transactionData);
  } catch (e) {
    print('Error processing transaction: $e');
  }
}

void _showNotification(
  FlutterLocalNotificationsPlugin plugin,
  String title,
  String body,
) async {
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'bsat_channel',
    'BSAT Notifications',
    importance: Importance.high,
    priority: Priority.high,
  );

  const NotificationDetails details = NotificationDetails(android: androidDetails);
  
  await plugin.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000,
    title,
    body,
    details,
  );
}