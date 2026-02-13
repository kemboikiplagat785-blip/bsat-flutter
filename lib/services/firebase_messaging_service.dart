import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // If you're going to use other Firebase services in the background, such as Firestore,
  // make sure you call `initializeApp` before using other Firebase services.
  // await Firebase.initializeApp();

  if (kDebugMode) {
    print("Handling a background message: ${message.messageId}");
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
    await _firebaseMessaging.subscribeToTopic('general');
    if (kDebugMode) {
      print('Subscribed to topic: general');
    }

    // Initialize background settings
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (kDebugMode) {
        print('Got a message whilst in the foreground!');
        print('Message data: ${message.data}');
      }

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
