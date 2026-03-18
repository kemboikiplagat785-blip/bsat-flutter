import 'dart:convert';
import 'dart:io';

import 'package:bsat/controllers/transaction_controller.dart';
import 'package:bsat/main.dart';
import 'package:bsat/screens/online_management/paired_devices.dart';
import 'package:bsat/services/backend_service.dart';
import 'package:bsat/services/sms_sevice.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:bsat/services/phone_service.dart';
import 'package:sim_data/sim_data.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../utils/constants.dart';
import 'payments.dart';
import 'skills.dart';

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
    payload: jsonEncode(message.data),
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
  // if (kDebugMode) {
  // }

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
      if (!await subscribedToOnline("Online")) {
        // If not subscribed to Online,
        TransactionController().dontProcess(
          body,
          "00",
          0,
          "",
          0,
          -1,
          reply:
              "You received a forwarded message but it seems you are not subscribed to the Online tier. Please subscribe to Online to process forwarded messages.",
          status: TransactionStatuses.paused,
        );
        return;
      }
      if (body.isNotEmpty) {
        TransactionController().makeTransactionGivenSmsBody(body);
      }
      break;

    case 'offer_update':
      Skills().small(message.data['hash'] ?? '');
      break;

    case 'pairing_request':
      await _showNotification(message);
      break;

    case 'ping':
      await _showNotification(message);

      String? callbackUrl = message.data['callbackUrl'];
      final ackPayload = {
        'type': 'PING_RESPONSE',
        'messageId': message.messageId,
        'status': 'alive',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      if (callbackUrl != null && callbackUrl.isNotEmpty) {
        try {
          if (callbackUrl.startsWith('http')) {
            await http.post(
              Uri.parse(callbackUrl),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(ackPayload),
            );
          } else {
            final resp =
                await BackendService().post(callbackUrl, body: ackPayload);
            if (kDebugMode && resp['success'] == false) {
            }
          }
        } catch (e) {
          if (kDebugMode) print('Failed to send ping acknowledgement: $e');
        }
      }
      break;

    case 'DATA_REQUEST':
      if (!(await subscribedToOnline("Online +"))) {
        // If not subscribed to Online, return an error response if callbackUrl is provided
        String? callbackUrl = message.data['callbackUrl'];
        if (callbackUrl != null && callbackUrl.isNotEmpty) {
          final errorPayload = {
            'type': 'DATA_RESPONSE',
            'requestId': message.data['requestId'],
            'dataType': message.data['tableName'] ?? 'unknown',
            'data': null,
            'messageId': message.messageId,
            'error': 'User not subscribed to Online + tier',
          };

          try {
            if (callbackUrl.startsWith('http')) {
              await http.post(
                Uri.parse(callbackUrl),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode(errorPayload),
              );
            } else {
              final resp =
                  await BackendService().post(callbackUrl, body: errorPayload);
              if (kDebugMode && resp['success'] == false) {
              }
            }
          } catch (e) {
            if (kDebugMode)
              print('Failed to send subscription error response: $e');
          }
        }
        return; // Don't proceed with data request handling
      }
      await _handleGetMyDBData(message);
      break;

    case 'GENERIC_DATA_REQUEST':
      if (!(await subscribedToOnline("Online +"))) {
        String? callbackUrl = message.data['callbackUrl'];
        if (callbackUrl != null && callbackUrl.isNotEmpty) {
          final errorPayload = {
            'type': 'GENERIC_DATA_RESPONSE',
            'requestId': message.data['requestId'],
            'data': null,
            'messageId': message.messageId,
            'error': 'User not subscribed to Online + tier',
          };

          try {
            if (callbackUrl.startsWith('http')) {
              await http.post(
                Uri.parse(callbackUrl),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode(errorPayload),
              );
            } else {
              final resp =
                  await BackendService().post(callbackUrl, body: errorPayload);
              if (kDebugMode && resp['success'] == false) {
              }
            }
          } catch (e) {
            if (kDebugMode)
              print('Failed to send subscription error response: $e');
          }
        }
        return; // Don't proceed with generic data request handling
      }
      await _handleGenericDataRequest(message);
      break;

    case 'update_offers':
      if (!(await subscribedToOnline("Online +"))) {
        // If not subscribed to Online, return an error response if callbackUrl is provided
        String? callbackUrl = message.data['callbackUrl'];
        if (callbackUrl != null && callbackUrl.isNotEmpty) {
          final errorPayload = {
            'type': 'UPDATE_OFFERS_RESPONSE',
            'messageId': message.messageId,
            'status': 'error',
            'error': 'User not subscribed to Online + tier',
          };

          try {
            if (callbackUrl.startsWith('http')) {
              await http.post(
                Uri.parse(callbackUrl),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode(errorPayload),
              );
            } else {
              final resp =
                  await BackendService().post(callbackUrl, body: errorPayload);
              if (kDebugMode && resp['success'] == false) {
              }
            }
          } catch (e) {
            if (kDebugMode)
              print('Failed to send subscription error response: $e');
          }
        }
        return; // Don't proceed with offer update handling
      }
      await _handleEditOffer(message);
      break;

    case 'retry_transaction':
      if (!(await subscribedToOnline("Online +"))) {
        // If not subscribed to Online, return an error response if callbackUrl is provided
        String? callbackUrl = message.data['callbackUrl'];
        if (callbackUrl != null && callbackUrl.isNotEmpty) {
          final errorPayload = {
            'type': 'RETRY_TRANSACTION_RESPONSE',
            'messageId': message.messageId,
            'status': 'error',
            'error': 'User not subscribed to Online + tier',
          };

          try {
            if (callbackUrl.startsWith('http')) {
              await http.post(
                Uri.parse(callbackUrl),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode(errorPayload),
              );
            } else {
              final resp =
                  await BackendService().post(callbackUrl, body: errorPayload);
              if (kDebugMode && resp['success'] == false) {
              }
            }
          } catch (e) {
            if (kDebugMode)
              print('Failed to send subscription error response: $e');
          }
        }
        return; // Don't proceed with retry transaction handling
      }
      await _handleRetryTransaction(message);
      break;

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

Future<void> _handleGetMyDBData(RemoteMessage message) async {
  final db = SQLiteService();

  // Extract parameters from the new message format
  String tableName = message.data['tableName'] ?? 'ussdCodes';
  String? queryParamsString = message.data['queryParams'];
  String? requestId = message.data['requestId'];
  String callbackUrl = message.data['callbackUrl'] ??
      '/api/fcm/receive-data'; // Default callback endpoint

  Map<String, dynamic> queryParams = {};
  if (queryParamsString != null && queryParamsString.isNotEmpty) {
    try {
      queryParams = jsonDecode(queryParamsString);
    } catch (e) {
      if (kDebugMode) print("Error parsing queryParams: $e");
    }
  }

  // Determine query options
  int? limit = queryParams['limit'] != null
      ? int.tryParse(queryParams['limit'].toString())
      : null;
  int? offset = queryParams['offset'] != null
      ? int.tryParse(queryParams['offset'].toString())
      : null;
  String? orderBy = queryParams['orderBy']?.toString();
  String? whereClause = queryParams['where']?.toString();
  List<Object?>? whereArgs = queryParams['whereArgs'] != null
      ? (queryParams['whereArgs'] as List).cast<Object?>()
      : null;

  List<Map<String, dynamic>> results = [];

  try {
    results = await db.queryAll(
      tableName,
      limit: limit,
      offset: offset,
      orderBy: orderBy,
      where: whereClause,
      whereArgs: whereArgs,
    );
  } catch (e) {
    if (kDebugMode) print("Error querying database for $tableName: $e");
  }


  // if (callbackUrl != null) {
  final payload = {
    'type': 'DATA_RESPONSE',
    'requestId': requestId,
    'dataType': tableName,
    'data': results,
    'messageId': message.messageId,
    'error': results.isEmpty ? 'No data found or error occurred' : null,
  };

  try {
    // if (callbackUrl.startsWith('http')) {
    //   await http.post(
    //     Uri.parse(callbackUrl),
    //     headers: {'Content-Type': 'application/json'},
    //     body: jsonEncode(payload),
    //   );
    // } else {
    final resp = await BackendService().post(callbackUrl, body: payload);
    if (kDebugMode && resp['success'] == false) {
    }
    // }
  } catch (e) {
    if (kDebugMode) print("Error sending data back: $e");
  }
  // }
}

Future<void> _handleEditOffer(RemoteMessage message) async {
  final db = SQLiteService();
  final rawOffer = message.data['offer'];
  Map<String, dynamic> offer = {};
  if (rawOffer == null) {
    offer = {};
  } else if (rawOffer is String) {
    try {
      final parsed = jsonDecode(rawOffer);
      if (parsed is Map) offer = Map<String, dynamic>.from(parsed);
    } catch (e) {
      if (kDebugMode) print('Failed to parse offer string: $e');
      offer = {};
    }
  } else if (rawOffer is Map) {
    offer = Map<String, dynamic>.from(rawOffer as Map);
  }

  int? id = offer['id'] != null ? int.tryParse(offer['id'].toString()) : null;
  Map<String, dynamic> updateData = {};

  if (offer['code'] != null) updateData['code'] = offer['code'];
  if (offer['amount'] != null) {
    updateData['amount'] = int.tryParse(offer['amount'].toString());
  }
  if (offer['fromSim'] != null) {
    updateData['fromSim'] = int.tryParse(offer['fromSim'].toString());
  }
  if (offer['dialSim'] != null) {
    updateData['dialSim'] = int.tryParse(offer['dialSim'].toString());
  }
  if (offer['canRetry'] != null) {
    updateData['canRetry'] = int.tryParse(offer['canRetry'].toString());
  }
  if (offer['isAdvanced'] != null) {
    updateData['isAdvanced'] = int.tryParse(offer['isAdvanced'].toString());
  }

  if (offer['enabled'] != null) {
    updateData['enabled'] = int.tryParse(offer['enabled'].toString());
  }

  if (id != null) {
    await db.updateStuff(updateData, 'id = ?', [id], 'ussdCodes');
  } else {
    await db.insertStuff(updateData, 'ussdCodes');
  }
}

Future<void> _handleRetryTransaction(RemoteMessage message) async {
  // String? transactionId = message.data['transactionId'];
  int? id = int.tryParse(message.data['id']?.toString() ?? '');

  if (id != null) {
    // Fetch transaction by ID if needed or just use logic
    final db = SQLiteService();
    var transaction = await db.queryOne('transactions', id);
    if (transaction != null) {
      // Re-trigger transaction logic
      // Assuming TransactionController has a method for this, otherwise we might need to recreate the request
      // For simplicity, we'll try to re-process if we have the SMS body/context
      // Or if it's a specific USSD:
      if (transaction['ussdDialed'] != null &&
          transaction['simSubId'] != null) {
        // This is simplified; retry usually requires context
        TransactionController().transactGivenUssdAndDialSim(
          transaction['ussdDialed'],
          transaction['simSubId'],
          transaction['amount'],
          false, // IsAdvanced not always stored, might need to fetch from offer or guess
          transaction['number'],
        );
      }
    }
  }
}

Future<void> _handleGenericDataRequest(RemoteMessage message) async {
  String? callbackUrl = '/api/fcm/receive-data'; // Default callback endpoint
  String? requestId = message.data['requestId'];

  // Get battery level
  int? batteryLevel;
  try {
    Battery battery = Battery();
    batteryLevel = await battery.batteryLevel;
  } catch (e) {
    if (kDebugMode) print('Failed to get battery level: $e');
  }

  // Get SIM cards and airtime balances
  List<Map<String, dynamic>> sims = [];
  try {
    // Use sim_data to get sim metadata
    final simData = await SimDataPlugin.getSimData();
    for (var card in simData.cards) {
      int? subId = card.subscriptionId;
      String displayName = card.displayName ?? card.carrierName ?? '';
      int balance = 0;
      int number = 0;

      try {
        balance = await PhoneService().getAirtimeBalance(subscriptionId: subId);
        number = extract9DigitNumber(
            (await PhoneService().makeMyRequest("*100*4*1#", subId)).first ??
                "");
      } catch (e) {
        if (kDebugMode) print('Failed to get balance for sim $subId: $e');
      }
      sims.add({
        'subscriptionId': subId,
        'displayName': displayName,
        'slotIndex': card.slotIndex,
        'carrierName': card.carrierName,
        'balance': balance,
        'number': number,
      });
    }
  } catch (e) {
    if (kDebugMode) print('Failed to get SIM data or balances: $e');
  }

  final payload = {
    'type': 'GENERIC_DATA_RESPONSE',
    'requestId': requestId,
    'data': {
      'batteryLevel': batteryLevel,
      'sims': sims,
    },
    'messageId': message.messageId
  };

  await BackendService().post(callbackUrl, body: payload);
}

@pragma('vm:entry-point')
void _onDidReceiveNotificationResponse(NotificationResponse response) {
  if (response.payload != null) {
    // Determine context safely
    _handleNotificationPayload(response.payload!);
  }
}

void _handleNotificationPayload(String payload) {
  try {
    final data = jsonDecode(payload);
    if (data['type'] == 'pairing_request') {
      // Small delay to ensure navigator is mounted if coming from cold start
      Future.delayed(const Duration(milliseconds: 500), () {
        navigatorKey.currentState?.push(
          CupertinoPageRoute(
            builder: (context) => const PairedDevices(),
          ),
        );
      });
    }
  } catch (e) {
    if (kDebugMode) {
      print('Error parsing notification payload: $e');
    }
  }
}

Future<bool> subscribedToOnline(String tier) async {
  String paidTier = (await Payment.getHighestTierPayment()).type;

  // "Online" or "Online +"
  return paidTier.contains(tier);
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

    // Initialize Local Notifications
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/launcher_icon');

    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    // Initialise the plugin. app_icon needs to be a added as a drawable resource to the Android head project
    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onDidReceiveNotificationResponse,
    );

    // Check if the app was launched by a notification
    final NotificationAppLaunchDetails? notificationAppLaunchDetails =
        await flutterLocalNotificationsPlugin
            .getNotificationAppLaunchDetails(); // Corrected method name check if needed

    // Note: getNotificationAppLaunchDetails helps for local notifications.
    // For FCM remote notifications that launch the app, getInitialMessage handles it.

    if (notificationAppLaunchDetails?.didNotificationLaunchApp ?? false) {
      if (notificationAppLaunchDetails!.notificationResponse?.payload != null) {
        _handleNotificationPayload(
            notificationAppLaunchDetails.notificationResponse!.payload!);
      }
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

    // Handle initial message (terminated state)
    _firebaseMessaging.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        if (message.data['type'] == 'pairing_request') {
          // Provide delayed navigation to ensure context is ready
          Future.delayed(const Duration(milliseconds: 500), () {
            navigatorKey.currentState?.push(
              CupertinoPageRoute(
                builder: (context) => const PairedDevices(),
              ),
            );
          });
        }
      }
    });

    // Handle background message tap (app running in background)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      if (message.data['type'] == 'pairing_request') {
        navigatorKey.currentState?.push(
          CupertinoPageRoute(
            builder: (context) => const PairedDevices(),
          ),
        );
      }
    });

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
