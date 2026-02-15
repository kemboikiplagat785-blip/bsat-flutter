import 'package:bsat/controllers/transaction_controller.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

@pragma('vm:entry-point')
Future<void> _showNotification(RemoteMessage message) async {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/launcher_icon');

  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  const AndroidNotificationDetails androidNotificationDetails =
      AndroidNotificationDetails(
    'general_channel',
    'General Notifications',
    importance: Importance.max,
    priority: Priority.high,
  );

  const NotificationDetails notificationDetails = NotificationDetails(
    android: androidNotificationDetails,
  );

  await flutterLocalNotificationsPlugin.show(
    message.hashCode,
    message.notification?.title ?? message.data['title'] ?? 'Notification',
    message.notification?.body ?? message.data['body'] ?? '',
    notificationDetails,
  );
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // If you're going to use other Firebase services in the background, such as Firestore,
  // make sure you call `initializeApp` before using other Firebase services.
  await Firebase.initializeApp();

  await handleRemoteMessage(message);
}

@pragma('vm:entry-point')
Future<void> handleRemoteMessage(RemoteMessage message) async {
  if (kDebugMode) {
    print("Handling message: ${message.messageId}");
    print("Data: ${message.senderId}");
  }

  // Use 'type' from data payload to distinguish message types
  String? type = message.data['type'];

  // Check if it's a forwarded SMS based on title if type is missing (backend might not pass data)
  if (type == null) {
    String? title = message.data['title'] ?? message.notification?.title;
    if (title == "BSAT Online Forwarding") {
      type = 'forwarded_sms';
    }
  }

  switch (type) {
    case 'forwarded_sms':
      // Handle the forwarded SMS case
      String body = message.data['body'] ?? message.notification?.body ?? "";
      if (body.isNotEmpty) {
        TransactionController().makeTransactionGivenSmsBody(body);
      }
      break;

    // Add more cases here for different message types
    // case 'other_type':
    //   doSomething();
    //   break;

    default:
      // Show notification for other types
      await _showNotification(message);

      // Fallback: If no type is specified but notification exists, treat as SMS (legacy behavior)
      if (message.notification != null) {
        String body = message.notification!.body ?? "";
        if (body.isNotEmpty) {
          TransactionController().makeTransactionGivenSmsBody(body);
        }
      }
      break;
  }
}

class FirebaseMessagingService {
  final _firebaseMessaging = FirebaseMessaging.instance;

  // Initialize Notification Settings
  Future<void> initNotifications() async {
    // Request permission from user (will prompt on iOS)
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    if (kDebugMode) {
      print('User granted permission: ${settings.authorizationStatus}');
    }

    // Get the token for this device
    final fCMToken = await _firebaseMessaging.getToken();

    if (kDebugMode) {
      print('FCM Token: $fCMToken');
    }

    // Subscribe to a general topic so we can message all users easily
    // Don't await this so it doesn't block app initialization if network is slow/unavailable
    _firebaseMessaging.subscribeToTopic('general').then((_) {
      if (kDebugMode) {
        print('Subscribed to topic: general');
      }
    }).catchError((e) {
      if (kDebugMode) {
        print('Failed to subscribe to topic: $e');
      }
    });

    // Initialize background settings
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (kDebugMode) {
        print('Got a message whilst in the foreground!');
      }
      
      handleRemoteMessage(message);

      if (message.notification != null) {
        if (kDebugMode) {
          print(
              'Message also contained a notification: ${message.notification}');
        }
        // You could show a local notification here using flutter_local_notifications
      }
    });
  }
}
