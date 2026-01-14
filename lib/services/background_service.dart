import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:bsat/services/skills.dart';
import 'package:bsat/services/socket_service.dart';
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

  // ✅ ADD connection status tracking
  bool isSocketInitialized = false;
  StreamSubscription? _messageSubscription;

  Future<void> initializeSocket() async {
    String? token = await _prefs.getJwtToken();
    String? deviceDbId = await _prefs.getDeviceId();
    
    print('🔍 Token: ${token?.substring(0, 20)}...');
    print('🔍 Device ID: $deviceDbId');
    
    if (token != null && deviceDbId != null && deviceDbId != '-1') {
      try {
        await socketService.connect(token: token, deviceId: deviceDbId);
        isSocketInitialized = true;
        print('✅ Background: Socket connected');
        
        // Listen to incoming messages
        _messageSubscription?.cancel();
        _messageSubscription = socketService.messageStream.listen((data) async {
          print('📥 Background: Message received from ${data['fromDeviceName']}: ${data['payload']}');
        
        final payload = data['payload'];
        
        if (payload is Map<String, dynamic>) {
          switch (payload['type']) {
            case 'transaction':
              print('📥 Background: New transaction received');
              if (payload['auto_process'] == true) {
                await _processTransaction(payload['data'], transactionController);
              } else {
                _showNotification(
                  flutterLocalNotificationsPlugin,
                  'New Transaction',
                  'From: ${data['fromDeviceName']}',
                );
              }
              break;
              
            case 'offer_update':
              print('📥 Background: Offer update received');
              await _prefs.setOffersMightHaveChanged(true);
              _showNotification(
                flutterLocalNotificationsPlugin,
                'Offer Updated',
                'Your offers have been updated',
              );
              break;
              
            case 'retry_failed':
              print('📥 Background: Retry failed transactions');
              await transactionController.retryAll(true);
              break;
              
            case 'notification':
              _showNotification(
                flutterLocalNotificationsPlugin,
                'BSAT Notification',
                payload['message'] ?? 'New notification',
              );
              break;
              
            default:
              print('📥 Background: Unknown message type: ${payload['type']}');
              _showNotification(
                flutterLocalNotificationsPlugin,
                'Message from ${data['fromDeviceName']}',
                payload.toString(),
              );
          }
        } else {
          _showNotification(
            flutterLocalNotificationsPlugin,
            'Message from ${data['fromDeviceName']}',
            payload.toString(),
          );
        }
        });
      } catch (e) {
        print('❌ Failed to connect socket: $e');
        isSocketInitialized = false;
      }
    } else {
      print('❌ Cannot initialize socket: Missing token or device ID');
    }
  }

  // Initialize socket on service start
  await initializeSocket();

  if (serviceInstance is AndroidServiceInstance) {
    serviceInstance.on('setAsForeground').listen((event) {
      serviceInstance.setAsForegroundService();
    });
    
    serviceInstance.on('setAsBackground').listen((event) {
      serviceInstance.setAsBackgroundService();
    });
  }

  serviceInstance.on('stopService').listen((event) async {
    _messageSubscription?.cancel();
    await socketService.disconnect();
    serviceInstance.stopSelf();
  });

  initMessagesPlatformState();

  Timer.periodic(const Duration(seconds: 60), (timer) async {
    if (serviceInstance is AndroidServiceInstance) {
      initMessagesPlatformState();

      if (await serviceInstance.isForegroundService()) {
        initMessagesPlatformState();

        // ✅ IMPROVED: Better reconnection logic
        if (!socketService.isConnected && isSocketInitialized) {
          print('⚠️ Socket disconnected, attempting reconnect...');
          await initializeSocket();
        } else if (!isSocketInitialized) {
          print('⚠️ Socket not initialized, initializing...');
          await initializeSocket();
        }

        await transactionController.retryAll(true);
        await TransactionController().checkSkipped();
        await TransactionController().runScheduled();

        // ✅ IMPROVED: Show connection status with emoji
        final socketStatus = socketService.isConnected ? '🟢 Connected' : '🔴 Disconnected';
        serviceInstance.setForegroundNotificationInfo(
          title: 'BSAT Active',
          content: 'Socket: $socketStatus | Processing transactions...',
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