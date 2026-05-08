import 'dart:convert';
import 'dart:io';

import 'package:bsat/controllers/transaction_controller.dart';
import 'package:bsat/main.dart';
import 'package:bsat/screens/online_management/paired_devices.dart';
import 'package:bsat/services/backend_service.dart';
import 'package:bsat/services/contacts_service.dart';
import 'package:bsat/services/offers_transfer_service.dart';
import 'package:bsat/services/shared_preferences_service.dart';
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

  if (await _processIncomingAcknowledgement(message, type)) {
    return;
  }

  // return acknowledgement first
  print(
      "Received FCM message with type: $type, data: ${message.data}, notification: ${message.notification}");

  await _sendImmediateAck(message, originalType: type);

  switch (type) {
    case 'process_alt_request':
      if (!(await subscribedToOnline("Online"))) {
        if (!(await PaymentOps().deductSingleToken())) {
          return;
        }
      }

      String ussdCode = message.data['ussdCode'] ?? '';
      int simSubId = await PhoneService().mostCommonDialSim();
      int amount = getAmount(message.data['smsMessage'] ?? '') ?? 0;
      int number = extract9DigitNumber(message.data['smsMessage'] ?? '') ?? 0;
      final dynamic isAdvancedRaw = message.data['isAdvanced'];
      final bool isAdvanced = isAdvancedRaw == true ||
          isAdvancedRaw == 1 ||
          isAdvancedRaw?.toString().toLowerCase() == 'true';

      await TransactionController().transactGivenUssdAndDialSim(
        ussdCode,
        simSubId,
        amount,
        isAdvanced,
        number,
        message: message.data['smsMessage'] ?? '',
      );
      break;

    case 'request_contacts_from_device':
    case 'forwarded_sms':
      // Handle the forwarded SMS case
      String body = message.data['body'] ?? message.notification?.body ?? "";
      if (!await subscribedToOnline("Online")) {
        // If not subscribed to Online,
        if (!(await PaymentOps().deductSingleToken())) {
          await TransactionController().dontProcess(
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
      }
      if (body.isNotEmpty) {
        await TransactionController().makeTransactionGivenSmsBody(body);
      }
      break;

    case 'CHECK_UPDATE':
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
            if (kDebugMode && resp['success'] == false) {}
          }
        } catch (e) {
          if (kDebugMode) print('Failed to send ping acknowledgement: $e');
        }
      }
      break;

    case 'DATA_REQUEST':
      if (!(await subscribedToOnline("Online +"))) {
        if (!(await PaymentOps().deductSingleToken())) {
          // If not subscribed to Online, return an error response if callbackUrl is provided
          String callbackUrl =
              message.data['callbackUrl'] ?? '/api/fcm/receive-data';
          // print(
          // "User not subscribed to Online + tier, callbackUrl: $callbackUrl");
          if (callbackUrl.isNotEmpty) {
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
                final resp = await BackendService()
                    .post(callbackUrl, body: errorPayload);
                if (kDebugMode && resp['success'] == false) {}
              }
            } catch (e) {
              if (kDebugMode)
                print('Failed to send subscription error response: $e');
            }
          }
          return; // Don't proceed with data request handling
        }
      }
      await _handleGetMyDBData(message);
      break;

    case 'GENERIC_DATA_REQUEST':
      if (!(await subscribedToOnline("Online +"))) {
        if (!(await PaymentOps().deductSingleToken())) {
          String callbackUrl =
              message.data['callbackUrl'] ?? '/api/fcm/receive-data';
          if (callbackUrl.isNotEmpty) {
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
                final resp = await BackendService()
                    .post(callbackUrl, body: errorPayload);
                if (kDebugMode && resp['success'] == false) {}
              }
            } catch (e) {
              if (kDebugMode)
                print('Failed to send subscription error response: $e');
            }
          }
          return; // Don't proceed with generic data request handling
        }
      }
      await _handleGenericDataRequest(message);
      break;

    case 'DEVICE_SETTINGS_REQUEST':
      if (!(await subscribedToOnline("Online +"))) {
        if (!(await PaymentOps().deductSingleToken())) {
          String callbackUrl =
              message.data['callbackUrl'] ?? '/api/fcm/receive-data';
          if (callbackUrl.isNotEmpty) {
            final errorPayload = {
              'type': 'SETTINGS_RESPONSE',
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
                final resp = await BackendService()
                    .post(callbackUrl, body: errorPayload);
                if (kDebugMode && resp['success'] == false) {}
              }
            } catch (e) {
              if (kDebugMode)
                print('Failed to send subscription error response: $e');
            }
          }
          return;
        }
      }
      await _handleSettingsRequest(message);
      break;

    case 'SETTINGS_RESPONSE':
      await _handleSettingsResponse(message);
      break;

    case 'CONTACTS_TRANSFER_READY':
      final transferId = message.data['transferId'];
      if (transferId != null) {
        await ContactsService().handleTransferReady(transferId);
      }
      break;

    case 'OFFERS_REQUEST':
      final bool canDownloadOffers =
          await SharedPreferencesService().getDownloadOffers() ?? true;
      if (!canDownloadOffers) {
        break;
      }

      final String requesterDeviceName =
          message.data['requesterDeviceName']?.toString() ?? '';
      final String? requestId = message.data['requestId']?.toString();

      if (requesterDeviceName.isEmpty) {
        break;
      }

      await OffersTransferService().sendOffersToDevice(
        requesterDeviceName,
        requestId: requestId,
      );
      break;

    case 'OFFERS_RESPONSE':
      final bool canDownloadOffers =
          await SharedPreferencesService().getDownloadOffers() ?? true;
      if (!canDownloadOffers) {
        break;
      }

      final dynamic rawOffers = message.data['offers'];
      await OffersTransferService().importOffersFromPayload(rawOffers);
      break;

    case 'renew_subscription':
      int subId = await PhoneService().mostCommonDialSim();
      int planId = 6;
      String tier = 'Online +';
      await PaymentOps().payCore(25, 1, subId, planId, tier);
      break;

    case 'update_offers':
      if (!(await subscribedToOnline("Online +"))) {
        if (!(await PaymentOps().deductSingleToken())) {
          // If not subscribed to Online, return an error response if callbackUrl is provided
          String callbackUrl =
              message.data['callbackUrl'] ?? '/api/fcm/receive-data';
          if (callbackUrl.isNotEmpty) {
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
                final resp = await BackendService()
                    .post(callbackUrl, body: errorPayload);
                if (kDebugMode && resp['success'] == false) {}
              }
            } catch (e) {
              if (kDebugMode)
                print('Failed to send subscription error response: $e');
            }
          }
          return; // Don't proceed with offer update handling
        }
      }
      await _handleEditOffer(message);
      break;

    case 'retry_transaction':
      if (!(await subscribedToOnline("Online +"))) {
        // If not subscribed to Online, return an error response if callbackUrl is provided
        if (!(await PaymentOps().deductSingleToken())) {
          String callbackUrl =
              message.data['callbackUrl'] ?? '/api/fcm/receive-data';
          if (callbackUrl.isNotEmpty) {
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
                final resp = await BackendService()
                    .post(callbackUrl, body: errorPayload);
                if (kDebugMode && resp['success'] == false) {}
              }
            } catch (e) {
              if (kDebugMode)
                print('Failed to send subscription error response: $e');
            }
          }
          return; // Don't proceed with retry transaction handling
        }
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

Future<void> _sendImmediateAck(
  RemoteMessage message, {
  String? originalType,
}) async {
  // Build a safe acknowledgement payload and ensure required fields (title, body,
  // senderDeviceName, recipientDeviceName) are provided to the backend.
  String? callbackUrl = message.data['callbackUrl']?.toString();
  if (callbackUrl == null || callbackUrl.isEmpty) {
    callbackUrl = '/api/fcm/send-secure';
  }

  // Prefer the locally configured device name for the sender; fall back to any
  // names included in the incoming message data.
  String senderDeviceName = (await SharedPreferencesService().getDeviceName()) ?? '';
  if (senderDeviceName.isEmpty) {
    senderDeviceName = message.data['recipientDeviceName']?.toString() ?? '';
  }

  String recipientDeviceName = message.data['senderDeviceName']?.toString() ?? '';

  final payload = {
    'type': 'MESSAGE_ACK',
    'ackKind': 'received',
    'messageId': message.messageId ?? '',
    'requestId': message.data['requestId'] ?? '',
    'originalType': originalType ?? '',
    'status': 'received',
    'receivedAt': DateTime.now().millisecondsSinceEpoch,
    'senderDeviceName': senderDeviceName,
    'recipientDeviceName': recipientDeviceName,
    'body': 'received',
    'title': 'received',
  };

  // The backend expects 'title' and 'body' to be strings. Send the payload as
  // a JSON string in 'body' and include the device names explicitly.
  final postBody = {
    'title': 'BSAT Online Forwarding',
    'body': jsonEncode(payload),
    'senderDeviceName': senderDeviceName,
    'recipientDeviceName': recipientDeviceName,
    'data': {
      'type': 'MESSAGE_ACK',
      'body': payload,
      'title': 'Ack receive',
    }
  };

  try {
    await BackendService().post(callbackUrl, body: postBody);
  } catch (e) {
    if (kDebugMode) {
      print('Failed to send immediate message ack: $e');
    }
  }
}

Future<bool> _processIncomingAcknowledgement(
  RemoteMessage message,
  String? type,
) async {
  if (!_isAckLikeMessage(message, type)) {
    return false;
  }

  final String normalizedType = (type ?? '').toUpperCase();
  final String originalType =
      message.data['originalType']?.toString().toUpperCase() ?? '';

  if (normalizedType == 'PING_RESPONSE') {
    await _handlePingAck(message);
    return true;
  }

  if (normalizedType == 'MESSAGE_ACK') {
    await _handleGenericMessageAck(message);

    switch (originalType) {
      case 'PROCESS_ALT_REQUEST':
      case 'FORWARDED_SMS':
      await _handleProcessAltRequestAck(message);
      break;
      case 'REQUEST_CONTACTS_FROM_DEVICE':
        await _handleForwardedSmsAck(message);
        break;
      case 'DATA_REQUEST':
        await _handleDataRequestAck(message);
        break;
      case 'GENERIC_DATA_REQUEST':
        await _handleGenericDataRequestAck(message);
        break;
      case 'DEVICE_SETTINGS_REQUEST':
        await _handleDeviceSettingsRequestAck(message);
        break;
      case 'OFFERS_REQUEST':
        await _handleOffersRequestAck(message);
        break;
      case 'OFFERS_RESPONSE':
        await _handleOffersResponseAck(message);
        break;
      case 'UPDATE_OFFERS':
        await _handleUpdateOffersAck(message);
        break;
      case 'RETRY_TRANSACTION':
        await _handleRetryTransactionAck(message);
        break;
      case 'CONTACTS_TRANSFER_READY':
        await _handleContactsTransferReadyAck(message);
        break;
      case 'RENEW_SUBSCRIPTION':
        await _handleRenewSubscriptionAck(message);
        break;
      default:
        await _handleUnknownAck(message);
        break;
    }

    return true;
  }

  switch (normalizedType) {
    case 'DATA_REQUEST_ACK':
      await _handleDataRequestAck(message);
      break;
    case 'GENERIC_DATA_REQUEST_ACK':
      await _handleGenericDataRequestAck(message);
      break;
    case 'DEVICE_SETTINGS_REQUEST_ACK':
      await _handleDeviceSettingsRequestAck(message);
      break;
    case 'OFFERS_REQUEST_ACK':
      await _handleOffersRequestAck(message);
      break;
    case 'OFFERS_RESPONSE_ACK':
      await _handleOffersResponseAck(message);
      break;
    case 'UPDATE_OFFERS_ACK':
      await _handleUpdateOffersAck(message);
      break;
    case 'RETRY_TRANSACTION_ACK':
      await _handleRetryTransactionAck(message);
      break;
    case 'PROCESS_ALT_REQUEST_ACK':
      await _handleProcessAltRequestAck(message);
      break;
    case 'FORWARDED_SMS_ACK':
    case 'REQUEST_CONTACTS_FROM_DEVICE_ACK':
      await _handleForwardedSmsAck(message);
      break;
    case 'CONTACTS_TRANSFER_READY_ACK':
      await _handleContactsTransferReadyAck(message);
      break;
    case 'RENEW_SUBSCRIPTION_ACK':
      await _handleRenewSubscriptionAck(message);
      break;
    default:
      await _handleUnknownAck(message);
      break;
  }

  await _persistAckState(message, ackScope: normalizedType.toLowerCase());
  return true;
}

bool _isAckLikeMessage(RemoteMessage message, String? type) {
  final normalizedType = (type ?? '').toUpperCase();
  return normalizedType == 'MESSAGE_ACK' ||
      normalizedType == 'PING_RESPONSE' ||
      normalizedType.endsWith('_ACK') ||
      message.data['ackKind'] != null;
}

Future<void> _persistAckState(
  RemoteMessage message, {
  required String ackScope,
}) async {
  final requestId = message.data['requestId']?.toString();
  final status = message.data['status']?.toString();

  final settings = <String, dynamic>{
    'fcm_ack_${ackScope}_at': DateTime.now().millisecondsSinceEpoch,
    'fcm_ack_${ackScope}_message_id': message.messageId ?? '',
  };

  if (requestId != null && requestId.isNotEmpty) {
    settings['fcm_ack_${ackScope}_request_id'] = requestId;
  }
  if (status != null && status.isNotEmpty) {
    settings['fcm_ack_${ackScope}_status'] = status;
  }

  await SharedPreferencesService().setAll(settings);
}

Future<void> _handleGenericMessageAck(RemoteMessage message) async {
  await _persistAckState(message, ackScope: 'message');
}

Future<void> _handlePingAck(RemoteMessage message) async {
  await _persistAckState(message, ackScope: 'ping');
}

Future<void> _handleProcessAltRequestAck(RemoteMessage message) async {
  await _persistAckState(message, ackScope: 'process_alt_request');
}

Future<void> _handleForwardedSmsAck(RemoteMessage message) async {
  await _persistAckState(message, ackScope: 'forwarded_sms');
}

Future<void> _handleDataRequestAck(RemoteMessage message) async {
  await _persistAckState(message, ackScope: 'data_request');
}

Future<void> _handleGenericDataRequestAck(RemoteMessage message) async {
  await _persistAckState(message, ackScope: 'generic_data_request');
}

Future<void> _handleDeviceSettingsRequestAck(RemoteMessage message) async {
  await _persistAckState(message, ackScope: 'device_settings_request');
}

Future<void> _handleOffersRequestAck(RemoteMessage message) async {
  await _persistAckState(message, ackScope: 'offers_request');
}

Future<void> _handleOffersResponseAck(RemoteMessage message) async {
  await _persistAckState(message, ackScope: 'offers_response');
}

Future<void> _handleUpdateOffersAck(RemoteMessage message) async {
  await _persistAckState(message, ackScope: 'update_offers');
}

Future<void> _handleRetryTransactionAck(RemoteMessage message) async {
  await _persistAckState(message, ackScope: 'retry_transaction');
}

Future<void> _handleContactsTransferReadyAck(RemoteMessage message) async {
  await _persistAckState(message, ackScope: 'contacts_transfer_ready');
}

Future<void> _handleRenewSubscriptionAck(RemoteMessage message) async {
  await _persistAckState(message, ackScope: 'renew_subscription');
}

Future<void> _handleUnknownAck(RemoteMessage message) async {
  await _persistAckState(message, ackScope: 'unknown');
}

Future<void> _handleSettingsResponse(RemoteMessage message) async {
  final rawData = message.data['data'];
  Map<String, dynamic> settings = {};

  if (rawData is String) {
    try {
      settings = jsonDecode(rawData);
    } catch (e) {
      if (kDebugMode) print('Failed to parse settings data: $e');
    }
  } else if (rawData is Map) {
    settings = Map<String, dynamic>.from(rawData);
  }

  if (settings.isNotEmpty) {
    await SharedPreferencesService().setAll(settings);
    if (kDebugMode) print('Settings updated from SETTINGS_RESPONSE');
  }
}

Future<void> _handleSettingsRequest(RemoteMessage message) async {
  String? callbackUrl = message.data['callbackUrl'] ?? '/api/fcm/receive-data';
  String? requestId = message.data['requestId'];

  final settings = await SharedPreferencesService().getAll();

  final payload = {
    'type': 'SETTINGS_RESPONSE',
    'requestId': requestId,
    'data': settings,
    'messageId': message.messageId
  };

  await BackendService().post(callbackUrl!, body: payload);
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
    if (kDebugMode && resp['success'] == false) {}
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
      'transactonsSinceMidnight': await SQLiteService().getCount('transactions',
          appendQuery: 'where timestamp > ?',
          args: [
            DateTime.now().subtract(Duration(days: 1)).millisecondsSinceEpoch
          ]),
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
      // print('FCM Token: $fCMToken');
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
