import 'dart:convert';
import 'dart:developer' as developer;

import 'package:bsat/controllers/transaction_controller.dart';
import 'package:bsat/utils/top_up.dart';
import 'package:bsat/main.dart';
import 'package:bsat/screens/online_management/paired_devices.dart';
import 'package:bsat/services/backend_service.dart';
import 'package:bsat/services/contacts_service.dart';
import 'package:bsat/services/offers_transfer_service.dart';
import 'package:bsat/services/shared_preferences_service.dart';
import 'package:bsat/services/sms_sevice.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:bsat/services/phone_service.dart';
import 'package:another_telephony/telephony.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

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

  developer.log('Hello fcm');

  developer.log(
      "Received FCM message with type: $type, data: ${message.data}, notification: ${message.notification}");

  if (await _processIncomingAcknowledgement(message, type)) {
    return;
  }

  // return acknowledgement first
  developer.log(
      "Received FCM message with type: $type, data: ${message.data}, notification: ${message.notification}");

  // CHECK_UPDATE is a one-way app update notification, not a paired-device
  // forwarding request. Replying through the forwarding ACK path can lack the
  // sender/recipient fields that endpoint requires.
  if ((type ?? '').toUpperCase() != 'CHECK_UPDATE' &&
      (type ?? '').toUpperCase() != 'PROCESS_ALT_REQUEST' &&
      (type ?? '').toUpperCase() != 'FORWARDED_ALT_RESULT') {
    await _sendImmediateAck(message, originalType: type);
  }

  switch (type) {
    case 'process_alt_request':
      String ussdCode = message.data['ussdCode'] ?? '';
      int amount = getAmount(message.data['smsMessage'] ?? '');
      int number = extract9DigitNumber(message.data['smsMessage'] ?? '');
      final dynamic isAdvancedRaw = message.data['isAdvanced'];
      final bool isAdvanced = isAdvancedRaw == true ||
          isAdvancedRaw == 1 ||
          isAdvancedRaw?.toString().toLowerCase() == 'true';
      final forwardingJobId = message.data['forwardingJobId']?.toString();
      final forwardingSenderDeviceName =
          message.data['senderDeviceName']?.toString();
      final transactionId = message.data['transactionId']?.toString() ?? '';
      final forwardingRecipientDeviceName =
          message.data['recipientDeviceName']?.toString() ?? '';
      final smsMessage = message.data['smsMessage']?.toString() ?? '';
      debugPrint(
        'ALT REQUEST: received jobId=${forwardingJobId ?? ''}, '
        'sender=${forwardingSenderDeviceName ?? ''}, '
        'localTransactionId=${message.data['transactionId'] ?? ''}, '
        'forwardingTransactionId=${message.data['transactionId'] ?? ''}, '
        'recipient=${message.data['recipientDeviceName'] ?? ''}',
      );

      final controller = TransactionController();
      if (forwardingJobId == null ||
          forwardingJobId.isEmpty ||
          forwardingSenderDeviceName == null ||
          forwardingSenderDeviceName.isEmpty ||
          transactionId.isEmpty ||
          ussdCode.isEmpty) {
        debugPrint(
          'ALT DELIVERY: legacy/incomplete request; using direct execution',
        );
        if (!(await subscribedToOnline("Online")) &&
            !(await PaymentOps().deductSingleToken())) {
          return;
        }
        final simSubId = await PhoneService().mostCommonDialSim();
        await _sendImmediateAck(
          message,
          originalType: type,
          ackKind: 'received',
          status: 'received',
        );
        await controller.transactGivenUssdAndDialSim(
          ussdCode,
          simSubId,
          amount,
          isAdvanced,
          number,
          message: smsMessage,
          forwardingJobId: forwardingJobId,
          forwardingTransactionId: transactionId,
          forwardingSenderDeviceName: forwardingSenderDeviceName,
          forwardingRecipientDeviceName: forwardingRecipientDeviceName,
        );
        break;
      }

      var existingJob = await controller.getAlternativeRequest(forwardingJobId);
      if (existingJob != null) {
        if (existingJob['state'] == 'eligibility_pending') {
          debugPrint(
            'ALT DELIVERY: job=$forwardingJobId is still checking eligibility',
          );
          return;
        }
        await _sendImmediateAck(
          message,
          originalType: type,
          ackKind: 'alternative_received',
          status: 'alternative-received',
        );
        await controller.processReservedAlternativeRequest(forwardingJobId);
        break;
      }

      final reserved = await controller.reserveAlternativeRequest(
        forwardingJobId: forwardingJobId,
        transactionId: transactionId,
        ussdCode: ussdCode,
        isAdvanced: isAdvanced,
        smsMessage: smsMessage,
        senderDeviceName: forwardingSenderDeviceName,
        recipientDeviceName: forwardingRecipientDeviceName,
      );
      if (!reserved) {
        existingJob = await controller.getAlternativeRequest(forwardingJobId);
        if (existingJob == null ||
            existingJob['state'] == 'eligibility_pending') {
          debugPrint(
            'ALT DELIVERY: unable to claim job=$forwardingJobId yet',
          );
          return;
        }
        await _sendImmediateAck(
          message,
          originalType: type,
          ackKind: 'alternative_received',
          status: 'alternative-received',
        );
        await controller.processReservedAlternativeRequest(forwardingJobId);
        break;
      }

      if (!(await subscribedToOnline("Online")) &&
          !(await PaymentOps().deductSingleToken())) {
        await controller.discardIneligibleAlternativeRequest(forwardingJobId);
        debugPrint(
          'ALT DELIVERY: eligibility failed for new job=$forwardingJobId',
        );
        return;
      }
      if (!await controller.activateAlternativeRequest(forwardingJobId)) {
        debugPrint(
          'ALT DELIVERY: job=$forwardingJobId was claimed by another handler',
        );
        return;
      }

      await _sendImmediateAck(
        message,
        originalType: type,
        ackKind: 'alternative_received',
        status: 'alternative-received',
      );
      await controller.processReservedAlternativeRequest(forwardingJobId);
      break;

    case 'forwarded_alt_result':
      await _handleForwardedAltResult(message);
      break;

    case 'request_contacts_from_device':
    case 'forwarded_sms':
      // Handle the forwarded SMS case
      String body = message.data['body'] ?? message.notification?.body ?? "";
      final String? forwardingJobId =
          message.data['forwardingJobId']?.toString();
      final String? forwardingSenderDeviceName =
          message.data['senderDeviceName']?.toString();
      debugPrint(
        'FORWARDED SMS RECEIVE: '
        'incomingTransactionId=${message.data['transactionId'] ?? ''}, '
        'forwardingJobId=${forwardingJobId ?? ''}, '
        'sender=${forwardingSenderDeviceName ?? ''}, '
        'recipient=${message.data['recipientDeviceName'] ?? ''}',
      );
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
        await TransactionController().makeTransactionGivenSmsBody(
          body,
          forwardingJobId: forwardingJobId,
          forwardingSenderDeviceName: forwardingSenderDeviceName,
        );
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
              if (kDebugMode) {
                print('Failed to send subscription error response: $e');
              }
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
              if (kDebugMode) {
                print('Failed to send subscription error response: $e');
              }
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
              if (kDebugMode) {
                print('Failed to send subscription error response: $e');
              }
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
              if (kDebugMode) {
                print('Failed to send subscription error response: $e');
              }
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
              if (kDebugMode) {
                print('Failed to send subscription error response: $e');
              }
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
  String ackKind = 'received',
  String status = 'received',
}) async {
  // Build a safe acknowledgement payload and ensure required fields (title, body,
  // senderDeviceName, recipientDeviceName) are provided to the backend.
  String? callbackUrl = message.data['callbackUrl']?.toString();
  if (callbackUrl == null || callbackUrl.isEmpty) {
    callbackUrl = '/api/fcm/send-secure';
  }

  // Prefer the locally configured device name for the sender; fall back to any
  // names included in the incoming message data.
  String senderDeviceName =
      (await SharedPreferencesService().getDeviceName()) ?? '';
  if (senderDeviceName.isEmpty) {
    senderDeviceName = message.data['recipientDeviceName']?.toString() ?? '';
  }

  String recipientDeviceName =
      message.data['senderDeviceName']?.toString() ?? '';

  final payload = {
    'type': 'MESSAGE_ACK',
    'ackKind': ackKind,
    'messageId': message.messageId?.toString() ?? '',
    'requestId': message.data['requestId']?.toString() ?? '',
    'transactionId': message.data['transactionId']?.toString() ?? '',
    'forwardingJobId': message.data['forwardingJobId']?.toString() ?? '',
    'originalType': originalType ?? '',
    'status': status,
    if (originalType == 'forwarded_alt_result')
      'resultStatus': message.data['status']?.toString() ?? '',
    'receivedAt': DateTime.now().millisecondsSinceEpoch.toString(),
    'senderDeviceName': senderDeviceName,
    'recipientDeviceName': recipientDeviceName,
    'body': 'received',
    'title': 'received',
  };

  // The backend expects 'title' and 'body' to be strings. Spread the payload
  // into 'data' to ensure all fields are primitives (strings/numbers), avoiding
  // the [object Object] serialization issue caused by nested maps.
  final postBody = {
    'title': 'BSAT Online Forwarding',
    'body': jsonEncode(payload),
    'senderDeviceName': senderDeviceName,
    'recipientDeviceName': recipientDeviceName,
    'data': {
      ...payload,
      'type': 'MESSAGE_ACK',
      'title': 'Ack receive',
      'body': jsonEncode(payload),
    }
  };

  try {
    await BackendService().post(callbackUrl, body: postBody);
    debugPrint('Ack sent');
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

  var data = message.data;

  debugPrint("${data['body']}");

  debugPrint("Received ack from backend ${data['body']}");

  final String normalizedType = (type ?? '').toUpperCase();
  final String originalType =
      message.data['originalType']?.toString().toUpperCase() ?? '';

  if (originalType == 'CHECK_UPDATE') {
    debugPrint('Ignoring generic ACK for CHECK_UPDATE.');
    return true;
  }

  if (normalizedType == 'PING_RESPONSE') {
    await _handlePingAck(message);
    return true;
  }

  if (normalizedType == 'MESSAGE_ACK') {
    debugPrint(
      'MESSAGE_ACK DEBUG: '
      'originalType=${message.data['originalType']}, '
      'forwardingJobId=${message.data['forwardingJobId']}, '
      'transactionId=${message.data['transactionId']}, '
      'status=${message.data['status']}, '
      'data=${message.data}',
    );

    await _handleGenericMessageAck(message);

    switch (originalType) {
      case 'PROCESS_ALT_REQUEST':
        await _handleProcessAltRequestAck(message);
        break;
      case 'FORWARDED_ALT_RESULT':
        await _handleForwardedAltResultAck(message);
        break;

      case 'FORWARDED_SMS':
        await _handleForwardedSmsAck(message);
        break;
      case 'FORWARDED_SMS_ACK':
        await _handleForwardedSmsAck(message);
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
  final transactionId = message.data['transactionId']?.toString() ?? '';

  final forwardingJobId = message.data['forwardingJobId']?.toString() ?? '';
  final ackKind = message.data['ackKind']?.toString().toLowerCase() ?? '';
  final status = message.data['status']?.toString().toLowerCase() ?? '';

  debugPrint(
    'PROCESS_ALT_REQUEST ACK received: '
    'transactionId=$transactionId, '
    'forwardingJobId=$forwardingJobId, ackKind=$ackKind, status=$status',
  );

  if (ackKind != 'alternative_received' ||
      status != 'alternative-received' ||
      forwardingJobId.isEmpty ||
      transactionId.isEmpty) {
    debugPrint(
      'PROCESS_ALT_REQUEST ACK ignored: missing durable alternative receipt',
    );
    return;
  }

  final updatedRows = await SQLiteService().updateStuff(
    {
      'status': TransactionStatuses.forwardedPending,
      'alternativeDeliveryNextAttemptAt': null,
      'ussdReply': 'Alternative request durably received by target. '
          'Waiting for execution result.',
    },
    'forwardingJobId = ? AND id = ? AND status = ?',
    [
      forwardingJobId,
      int.tryParse(transactionId) ?? -1,
      TransactionStatuses.alternativeDeliveryPending,
    ],
    'transactions',
  );
  debugPrint(
    'ALT DELIVERY RECEIVED: job=$forwardingJobId, '
    'transaction=$transactionId, updatedRows=$updatedRows',
  );

  await _persistAckState(
    message,
    ackScope: 'process_alt_request',
  );
}

Future<void> _handleForwardedAltResultAck(RemoteMessage message) async {
  final forwardingJobId = message.data['forwardingJobId']?.toString() ?? '';
  final ackKind = message.data['ackKind']?.toString().toLowerCase() ?? '';
  final status = message.data['status']?.toString().toLowerCase() ?? '';
  final resultStatus = message.data['resultStatus']?.toString() ?? '';
  if (forwardingJobId.isEmpty ||
      ackKind != 'alternative_result_received' ||
      status != 'alternative-result-received' ||
      resultStatus.isEmpty) {
    debugPrint(
      'ALT RESULT ACK ignored: missing application-level receipt fields',
    );
    return;
  }

  final job = await SQLiteService().getAlternativeJob(forwardingJobId);
  if (job == null || job['resultStatus'] != resultStatus) {
    debugPrint(
      'ALT RESULT ACK ignored: stale result receipt '
      'job=$forwardingJobId resultStatus=$resultStatus',
    );
    return;
  }
  final expectedSender = job['senderDeviceName']?.toString() ?? '';
  final expectedRecipient = job['recipientDeviceName']?.toString() ?? '';
  final ackSender = message.data['senderDeviceName']?.toString() ?? '';
  final ackRecipient = message.data['recipientDeviceName']?.toString() ?? '';
  final transactionId = message.data['transactionId']?.toString() ?? '';
  final localDeviceName =
      await SharedPreferencesService().getDeviceName() ?? '';
  if (transactionId != job['transactionId']?.toString() ||
      (expectedSender.isNotEmpty && ackRecipient != expectedSender) ||
      (expectedRecipient.isNotEmpty && ackSender != expectedRecipient) ||
      (localDeviceName.isNotEmpty && expectedRecipient != localDeviceName)) {
    debugPrint(
      'ALT RESULT ACK ignored: job/device/transaction mismatch '
      'job=$forwardingJobId transaction=$transactionId',
    );
    return;
  }

  final updated = await SQLiteService().updateAlternativeJob(
    forwardingJobId,
    {
      'resultDeliveryState': 'delivered',
      'resultNextAttemptAt': 0,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    },
  );
  debugPrint(
    'ALT RESULT ACK: job=$forwardingJobId marked delivered; rows=$updated',
  );
  await TransactionController()
      .completeForwardedAlternativeResultAcknowledgement(forwardingJobId);
  await _persistAckState(message, ackScope: 'forwarded_alt_result');
}

Future<void> _handleForwardedAltResult(RemoteMessage message) async {
  final forwardingJobId = message.data['forwardingJobId']?.toString() ?? '';

  final transactionId = message.data['transactionId']?.toString() ?? '';

  final status = message.data['status']?.toString() ?? '';

  final ussdReply = message.data['ussdReply']?.toString() ?? '';

  debugPrint(
    'FORWARDED_ALT_RESULT received: '
    'transactionId=$transactionId, '
    'forwardingJobId=$forwardingJobId, '
    'status=$status',
  );

  if (forwardingJobId.isEmpty) {
    debugPrint(
      'FORWARDED_ALT_RESULT ignored: missing forwardingJobId',
    );
    return;
  }

  final matchingTransactions = await SQLiteService().queryCustom(
    'transactions',
    'forwardingJobId = ? AND id = ?',
    [forwardingJobId, int.tryParse(transactionId) ?? -1],
  );
  if (matchingTransactions.length != 1) {
    debugPrint(
      'FORWARDED_ALT_RESULT ignored: transaction/job mismatch '
      'job=$forwardingJobId transaction=$transactionId',
    );
    return;
  }
  final matchedTransaction = matchingTransactions.first;
  final expectedSender =
      matchedTransaction['forwardingRecipientDeviceName']?.toString() ?? '';
  final expectedRecipient =
      matchedTransaction['alternativeRequestSenderDeviceName']?.toString() ??
          await SharedPreferencesService().getDeviceName() ??
          '';
  final resultSender = message.data['senderDeviceName']?.toString() ?? '';
  final resultRecipient = message.data['recipientDeviceName']?.toString() ?? '';
  if ((expectedSender.isNotEmpty && resultSender != expectedSender) ||
      (expectedRecipient.isNotEmpty && resultRecipient != expectedRecipient)) {
    debugPrint(
      'FORWARDED_ALT_RESULT ignored: device mismatch '
      'job=$forwardingJobId from=$resultSender to=$resultRecipient',
    );
    return;
  }

  Future<void> acknowledgeResult() async {
    await _sendImmediateAck(
      message,
      originalType: 'forwarded_alt_result',
      ackKind: 'alternative_result_received',
      status: 'alternative-result-received',
    );
    await _persistAckState(
      message,
      ackScope: 'forwarded_alt_result',
    );
  }

  if (status == TransactionStatuses.alternativeAmbiguous) {
    final updatedRows = await SQLiteService().updateStuff(
      {
        'status': TransactionStatuses.alternativeAmbiguous,
        'canRetry': 0,
        'ussdReply': ussdReply,
        'timeStamp': DateTime.now().millisecondsSinceEpoch,
      },
      'forwardingJobId = ? AND id = ? AND status != ?',
      [
        forwardingJobId,
        matchedTransaction['id'],
        TransactionStatuses.doneConfirmed,
      ],
      'transactions',
    );
    final rows = await SQLiteService().queryCustom(
      'transactions',
      'forwardingJobId = ? AND id = ?',
      [forwardingJobId, matchedTransaction['id']],
      columns: ['status'],
    );
    final durablyHandled = rows.any(
      (row) =>
          row['status'] == TransactionStatuses.alternativeAmbiguous ||
          row['status'] == TransactionStatuses.doneConfirmed,
    );
    debugPrint(
      'ALT RESULT AMBIGUOUS: job=$forwardingJobId, '
      'updatedRows=$updatedRows, durablyHandled=$durablyHandled',
    );
    if (durablyHandled) {
      await acknowledgeResult();
    }
    return;
  }

  if (status == TransactionStatuses.advancedUssd) {
    debugPrint(
      'ALT RESULT: advancedUssd is intermediate for jobId=$forwardingJobId; '
      'leaving pending',
    );
    return;
  }

  if (status == TransactionStatuses.successfulPending) {
    final updatedRows = await SQLiteService().updateStuff(
      {
        'status': TransactionStatuses.successfulPending,
        'alternativeQueueState': 'released',
        'alternativeDeliveryNextAttemptAt': null,
        'canRetry': 0,
        'ussdReply': ussdReply,
        'timeStamp': DateTime.now().millisecondsSinceEpoch,
      },
      'forwardingJobId = ? AND id = ? AND alternativeQueueState = ? '
          'AND status IN (?, ?)',
      [
        forwardingJobId,
        matchedTransaction['id'],
        'active',
        TransactionStatuses.alternativeDeliveryPending,
        TransactionStatuses.forwardedPending,
      ],
      'transactions',
    );
    if (updatedRows == 1) {
      debugPrint(
        'ALT_QUEUE: T${matchedTransaction['id']} Successful(Pending)',
      );
      debugPrint(
        'ALT_QUEUE: recipient=$expectedSender released '
        'T${matchedTransaction['id']}',
      );
    }
    final currentRows = await SQLiteService().queryCustom(
      'transactions',
      'forwardingJobId = ? AND id = ?',
      [forwardingJobId, matchedTransaction['id']],
      columns: ['status', 'alternativeQueueState'],
    );
    final current = currentRows.firstOrNull;
    if (current?['status'] == TransactionStatuses.successfulPending &&
        current?['alternativeQueueState'] == 'released' &&
        expectedSender.isNotEmpty) {
      await TransactionController()
          .dispatchNextAlternativeDelivery(expectedSender);
    }
    if (currentRows.any((row) =>
        row['status'] == TransactionStatuses.successfulPending ||
        row['status'] == TransactionStatuses.doneConfirmed)) {
      await acknowledgeResult();
    }
    return;
  }

  if (status != TransactionStatuses.doneConfirmed) {
    debugPrint(
      'FORWARDED_ALT_RESULT: storing non-success alternative result '
      'for job=$forwardingJobId status=$status',
    );
    final updatedRows = await SQLiteService().updateStuff(
      {
        'status': TransactionStatuses.alternativeFailed,
        'alternativeQueueState': 'released',
        'canRetry': 0,
        'ussdReply': ussdReply,
        'timeStamp': DateTime.now().millisecondsSinceEpoch,
      },
      'forwardingJobId = ? AND id = ? AND alternativeQueueState = ? '
          'AND status != ?',
      [
        forwardingJobId,
        matchedTransaction['id'],
        'active',
        TransactionStatuses.doneConfirmed,
      ],
      'transactions',
    );
    final rows = await SQLiteService().queryCustom(
      'transactions',
      'forwardingJobId = ? AND id = ?',
      [forwardingJobId, matchedTransaction['id']],
      columns: ['status'],
    );
    if (rows
        .any((row) => row['status'] == TransactionStatuses.alternativeFailed)) {
      if (updatedRows == 1 && expectedSender.isNotEmpty) {
        await TransactionController()
            .dispatchNextAlternativeDelivery(expectedSender);
      }
      await acknowledgeResult();
    }
    return;
  }

  final updatedRows = await SQLiteService().updateStuff(
    {
      'status': TransactionStatuses.doneConfirmed,
      if (matchedTransaction['alternativeQueueState'] == 'active')
        'alternativeQueueState': 'released',
      'canRetry': 0,
      'ussdReply': ussdReply,
      'timeStamp': DateTime.now().millisecondsSinceEpoch,
    },
    'forwardingJobId = ? AND id = ? AND status != ?',
    [
      forwardingJobId,
      matchedTransaction['id'],
      TransactionStatuses.doneConfirmed,
    ],
    'transactions',
  );

  debugPrint(
    'FORWARDED_ALT_RESULT UPDATE: '
    'forwardingJobId=$forwardingJobId, '
    'updatedRows=$updatedRows',
  );

  if (updatedRows > 0) {
    debugPrint(
      'ALT RESULT: updated local transaction by jobId=$forwardingJobId',
    );
    debugPrint(
      'ALT_QUEUE: T${matchedTransaction['id']} final confirmation',
    );
    if (matchedTransaction['alternativeQueueState'] == 'active' &&
        expectedSender.isNotEmpty) {
      await TransactionController()
          .dispatchNextAlternativeDelivery(expectedSender);
    }
  } else {
    final existingRows = await SQLiteService().queryCustom(
      'transactions',
      'forwardingJobId = ? AND id = ?',
      [forwardingJobId, matchedTransaction['id']],
      columns: ['status'],
    );
    if (existingRows.isNotEmpty &&
        existingRows.every(
          (row) => row['status'] == TransactionStatuses.doneConfirmed,
        )) {
      debugPrint('ALT RESULT: duplicate final result ignored');
    } else {
      debugPrint(
        'ALT RESULT: no unconfirmed transaction found for jobId=$forwardingJobId',
      );
    }
  }

  final tx = await SQLiteService().queryCustom(
    'transactions',
    'forwardingJobId = ? AND id = ? AND status = ?',
    [
      forwardingJobId,
      matchedTransaction['id'],
      TransactionStatuses.doneConfirmed,
    ],
    limit: 1,
  );
  if (tx.isNotEmpty) {
    final forwardingSenderDeviceName =
        tx.first['forwardingSenderDeviceName']?.toString() ?? '';
    final confirmationDelivered =
        tx.first['alternativeConfirmationDelivered'] == 1;
    var confirmationDurablyRecorded =
        forwardingSenderDeviceName.isEmpty || confirmationDelivered;
    if (!confirmationDelivered) {
      final confirmation =
          await SQLiteService().getForwardingConfirmation(forwardingJobId);
      confirmationDurablyRecorded = confirmation != null;
      if (confirmation == null && forwardingSenderDeviceName.isNotEmpty) {
        await TransactionController().ensureForwardingConfirmation(
          forwardingJobId: forwardingJobId,
          recipientDeviceName: forwardingSenderDeviceName,
          transactionId: tx.first['id']?.toString() ?? '',
        );
        confirmationDurablyRecorded =
            await SQLiteService().getForwardingConfirmation(forwardingJobId) !=
                null;
      }
    }
    if (!confirmationDurablyRecorded) {
      debugPrint(
        'ALT RESULT: not acknowledging job=$forwardingJobId; '
        'B-to-A confirmation is not durably recorded',
      );
      return;
    }
    if (forwardingSenderDeviceName.isNotEmpty && !confirmationDelivered) {
      debugPrint(
        'ALT RESULT: B-to-A confirmation outbox is durable '
        'for jobId=$forwardingJobId',
      );
    }
  }

  final handledRows = await SQLiteService().queryCustom(
    'transactions',
    'forwardingJobId = ? AND id = ?',
    [forwardingJobId, matchedTransaction['id']],
    columns: ['status'],
  );
  if (handledRows.any(
    (row) => row['status'] == TransactionStatuses.doneConfirmed,
  )) {
    await acknowledgeResult();
  }
}

Future<void> _handleForwardedSmsAck(RemoteMessage message) async {
  final forwardingJobId = message.data['forwardingJobId']?.toString() ?? '';

  final ackKind = message.data['ackKind']?.toString().toLowerCase() ?? '';

  final status = message.data['status']?.toString().toLowerCase() ?? '';

  debugPrint(
    'FORWARDED_SMS ACK: '
    'ackKind=$ackKind, '
    'status=$status, '
    'forwardingJobId=$forwardingJobId',
  );

  // Receipt of this message means Phone A has durably handled the final ACK.
  // Remove Phone B's retry record only for this explicit receipt kind.
  if (ackKind == 'confirmation_received') {
    if (forwardingJobId.isNotEmpty) {
      await SQLiteService().acknowledgeForwardingConfirmation(forwardingJobId);
      await SQLiteService().updateStuff(
        {'awaitingTopUp': 0},
        'forwardingJobId = ?',
        [forwardingJobId],
        'transactions',
      );
    }
    await _persistAckState(message, ackScope: 'forwarded_sms_confirmation');
    return;
  }

  if (forwardingJobId.isEmpty) {
    debugPrint(
      'FORWARDED_SMS ACK received without forwardingJobId',
    );

    await _persistAckState(
      message,
      ackScope: 'forwarded_sms',
    );

    return;
  }

  // A normal "received" ACK only means Phone B received
  // the forwarded SMS. It MUST NOT confirm Phone A.
  if (ackKind == 'received' || status == 'received') {
    debugPrint(
      'FORWARDED_SMS: received ACK only. '
      'Keeping transaction forwarded-pending.',
    );

    await _persistAckState(
      message,
      ackScope: 'forwarded_sms',
    );

    return;
  }

  // Only an explicit transaction confirmation is allowed
  // to change Phone A to forwarded-confirmed.
  if (ackKind != 'confirmed' &&
      status != TransactionStatuses.doneConfirmed &&
      status != 'transaction-confirmed') {
    debugPrint(
      'FORWARDED_SMS: non-confirmation ACK. '
      'Keeping transaction forwarded-pending.',
    );

    await _persistAckState(
      message,
      ackScope: 'forwarded_sms',
    );

    return;
  }

  final beforeAckRows = await SQLiteService().queryCustom(
    'transactions',
    'forwardingJobId = ?',
    [forwardingJobId],
  );

  debugPrint(
    'FORWARDED_SMS CONFIRMATION LOOKUP: '
    'forwardingJobId=$forwardingJobId, '
    'rows=$beforeAckRows',
  );

  if (beforeAckRows.isEmpty) {
    debugPrint(
      'FORWARDED_SMS CONFIRMATION: '
      'No transaction found for forwardingJobId=$forwardingJobId',
    );

    await _persistAckState(
      message,
      ackScope: 'forwarded_sms',
    );

    return;
  }

  final resultStatus = message.data['resultStatus']?.toString() ?? '';
  var awaitingTopUp = false;
  int? requiredTopUp;
  int? targetAmount;
  int? unavailableNumber;
  String unavailableFirstName = '';
  String unavailableLastName = '';
  int unavailableAmount = 0;
  int? resolvedTargetOfferId;
  final sourceTransaction = beforeAckRows.first;
  if (resultStatus == TransactionStatuses.unavailableOffer) {
    // The origin transaction carries the configured target offer association.
    final amount =
        int.tryParse(sourceTransaction['amount']?.toString() ?? '') ?? 0;
    unavailableAmount = amount;
    final controller = TransactionController();
    final storedTargetOfferId =
        int.tryParse(sourceTransaction['targetOfferId']?.toString() ?? '');
    final configuredTarget = storedTargetOfferId != null
        ? (
            id: storedTargetOfferId,
            amount: await controller.getOfferAmountById(storedTargetOfferId),
          )
        : await controller.findConfiguredUnavailableTarget(amount);
    resolvedTargetOfferId = configuredTarget?.id ?? storedTargetOfferId;
    final resolvedTargetAmount = configuredTarget?.amount;
    final requiredAmount = calculateRequiredTopUp(amount, resolvedTargetAmount);
    final hasReply = await controller.hasConfiguredReplyFor(
      TransactionStatuses.unavailableOffer,
      amount,
    );
    if (requiredAmount != null && hasReply) {
      awaitingTopUp = true;
      targetAmount = resolvedTargetAmount;
      requiredTopUp = requiredAmount;
    }

    unavailableNumber =
        int.tryParse(sourceTransaction['number']?.toString() ?? '') ?? 0;
    final source = sourceTransaction['source']?.toString().trim() ?? '';
    final sourceParts = source.split(RegExp(r'\s+'));
    unavailableFirstName = sourceParts.isEmpty ? '' : sourceParts.first;
    unavailableLastName =
        sourceParts.length < 2 ? '' : sourceParts.skip(1).join(' ');
  }

  final updatedRows = await SQLiteService().updateStuff(
    {
      'status': awaitingTopUp
          ? TransactionStatuses.forwardedPending
          : TransactionStatuses.forwardedConfirmed,
      'canRetry': 0,
      'awaitingTopUp': awaitingTopUp ? 1 : 0,
      'requiredTopUp': requiredTopUp,
      'targetAmount': targetAmount,
      if (resolvedTargetOfferId != null) 'targetOfferId': resolvedTargetOfferId,
    },
    'forwardingJobId = ?',
    [forwardingJobId],
    'transactions',
  );

  debugPrint(
    'FORWARDED_SMS CONFIRMATION UPDATE: '
    'forwardingJobId=$forwardingJobId, '
    'updatedRows=$updatedRows',
  );

  await _persistAckState(
    message,
    ackScope: 'forwarded_sms',
  );

  if (resultStatus == TransactionStatuses.unavailableOffer &&
      unavailableNumber != null) {
    await TransactionController().processReply(
      unavailableNumber,
      TransactionStatuses.unavailableOffer,
      unavailableFirstName,
      unavailableLastName,
      unavailableAmount,
    );
  }

  // Send a receipt after the update (including idempotent duplicate delivery).
  // Phone B retries the final confirmation until this receipt arrives.
  final senderDeviceName =
      await SharedPreferencesService().getDeviceName() ?? '';
  final recipientDeviceName =
      message.data['senderDeviceName']?.toString() ?? '';
  if (senderDeviceName.isNotEmpty && recipientDeviceName.isNotEmpty) {
    await BackendService().post(
      '/api/fcm/send-secure',
      body: {
        'title': 'BSAT Online Forwarding',
        'body': 'Forwarding confirmation received',
        'senderDeviceName': senderDeviceName,
        'recipientDeviceName': recipientDeviceName,
        'data': {
          'type': 'forwarded_sms_ack',
          'ackKind': 'confirmation_received',
          'status': 'received',
          'forwardingJobId': forwardingJobId,
          'senderDeviceName': senderDeviceName,
          'recipientDeviceName': recipientDeviceName,
        },
      },
    );
  }
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
    offer = Map<String, dynamic>.from(rawOffer);
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
    // Re-trigger transaction logic
    // Assuming TransactionController has a method for this, otherwise we might need to recreate the request
    // For simplicity, we'll try to re-process if we have the SMS body/context
    // Or if it's a specific USSD:
    if (transaction['ussdDialed'] != null && transaction['simSubId'] != null) {
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
    final simData = await Telephony.instance.getSubscriptionList();
    for (var card in simData) {
      int? subId = card.subscriptionId;
      String displayName = card.displayName ?? card.carrierName ?? '';
      int balance = 0;
      int number = 0;

      try {
        if (subId != null) {
          balance =
              await PhoneService().getAirtimeBalance(subscriptionId: subId);
          number = extract9DigitNumber(
              (await PhoneService().makeMyRequest("*100*4*1#", subId)).first ??
                  "");
        }
      } catch (e) {
        if (kDebugMode) print('Failed to get balance for sim $subId: $e');
      }
      sims.add({
        'subscriptionId': subId,
        'displayName': displayName,
        'slotIndex': card.simSlotIndex,
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
