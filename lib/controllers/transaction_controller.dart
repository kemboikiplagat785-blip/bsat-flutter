import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:another_telephony/telephony.dart';
import 'package:bsat/models/transaction.dart';
import 'package:bsat/services/auth_service.dart';
import 'package:bsat/services/backend_service.dart';
import 'package:bsat/services/contacts_service.dart';
import 'package:bsat/services/payments.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:bsat/utils/date_ops.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import '../models/client.dart';
import '../models/code_signature.dart';
import '../models/transaction_message.dart';
import '../models/ussd_code.dart';
import '../services/client_service.dart';
import '../services/shared_preferences_service.dart';
import '../utils/forwarding_job_id.dart';

// import '../services/skills.dart';
import '../services/skills.dart';
import '../services/sms_sevice.dart';
import '../services/phone_service.dart';
import '../services/main_engine_ussd_bridge.dart';

/// Orchestrates the full M-PESA → offer → USSD → transaction lifecycle.
/// Entry point is [makeTransaction], which parses inbound SMS, applies
/// business rules (blacklist, forwarding, subscription/tokens, offer state),
/// dials the mapped USSD (advanced or normal), records outcomes to SQLite,
/// and emits replies/side effects (auto-save contacts, send confirmations).
class TransactionController {
  final PhoneService _phoneService = PhoneService();
  final SQLiteService _sqliteService = SQLiteService();
  final _paymentOps = PaymentOps();

  final _sharedPreferencesService = SharedPreferencesService();

  /// Process a single payment SMS into a transaction.
  /// Steps (in order):
  /// 1) Housekeeping: optional auto-delete old transactions, trim SMS body.
  /// 2) Parse primitives: id, number, amount, name; blacklist check.
  /// 3) Forwarding: reroute if forwarding rules match (returns early).
  /// 4) Offer safety: pause if offers flagged as changed; reject invalid numbers/Airtel.
  /// 5) Resolve offer: pick USSD + SIM + retry/advanced flags; check subscription/token/auto-renew.
  /// 6) Compound amounts: attempt to combine smaller offers if exact match missing.
  /// 7) Guardrails: pause inactive offers; enqueue advanced calls if app inactive.
  /// 8) Execute USSD: advanced or standard dial; derive transaction status.
  /// 9) Persist result to SQLite, emit replies, and auto-save contact when enabled.
  ///
  Future<void> _sendForwardingConfirmation({
    required String forwardingJobId,
    required String recipientDeviceName,
    String? transactionId,
  }) async {
    final senderDeviceName =
        await SharedPreferencesService().getDeviceName() ?? '';

    if (senderDeviceName.isEmpty || recipientDeviceName.isEmpty) {
      debugPrint(
        'FORWARDED_SMS CONFIRMATION: '
        'Missing sender/recipient device name. '
        'sender=$senderDeviceName, recipient=$recipientDeviceName',
      );
      return;
    }

    try {
      final result = await BackendService().post(
        '/api/fcm/send-secure',
        body: {
          'title': 'BSAT Online Forwarding',
          'body': 'Forwarded transaction confirmed',
          'senderDeviceName': senderDeviceName,
          'recipientDeviceName': recipientDeviceName,
          'data': {
            'type': 'forwarded_sms_ack',
            'ackKind': 'confirmed',
            'status': TransactionStatuses.doneConfirmed,
            'forwardingJobId': forwardingJobId,
            'transactionId': transactionId ?? '',
            'senderDeviceName': senderDeviceName,
            'recipientDeviceName': recipientDeviceName,
          },
        },
      );

      debugPrint(
        'FORWARDED_SMS CONFIRMATION SENT: '
        'jobId=$forwardingJobId, '
        'from=$senderDeviceName, '
        'to=$recipientDeviceName, '
        'result=$result',
      );
    } catch (e) {
      debugPrint(
        'FORWARDED_SMS CONFIRMATION FAILED: $e',
      );
    }
  }

// ADD THIS NEW PUBLIC METHOD HERE
  Future<void> sendForwardingConfirmation({
    required String forwardingJobId,
    required String recipientDeviceName,
    String? transactionId,
  }) async {
    await _sendForwardingConfirmation(
      forwardingJobId: forwardingJobId,
      recipientDeviceName: recipientDeviceName,
      transactionId: transactionId,
    );
  }

  Future<void> _sendForwardedAlternativeResult({
    required String forwardingJobId,
    required String recipientDeviceName,
    required String transactionId,
    required String ussdReply,
  }) async {
    final senderDeviceName =
        await SharedPreferencesService().getDeviceName() ?? '';
    if (senderDeviceName.isEmpty || recipientDeviceName.isEmpty) {
      debugPrint(
        'ALT RESULT: cannot send jobId=$forwardingJobId; '
        'sender or recipient device name is missing',
      );
      return;
    }

    debugPrint(
      'ALT RESULT: sending doneConfirmed jobId=$forwardingJobId '
      'transactionId=$transactionId to $recipientDeviceName',
    );
    try {
      final result = await BackendService().post(
        '/api/fcm/send-secure',
        body: {
          'title': 'BSAT Online Forwarding',
          'body': 'Alternative USSD execution confirmed',
          'senderDeviceName': senderDeviceName,
          'recipientDeviceName': recipientDeviceName,
          'data': {
            'type': 'forwarded_alt_result',
            'transactionId': transactionId,
            'forwardingJobId': forwardingJobId,
            'status': TransactionStatuses.doneConfirmed,
            'ussdReply': ussdReply,
            'senderDeviceName': senderDeviceName,
            'recipientDeviceName': recipientDeviceName,
          },
        },
      );
      debugPrint(
        'ALT RESULT: sent jobId=$forwardingJobId '
        'transactionId=$transactionId result=$result',
      );
    } catch (e) {
      debugPrint('ALT RESULT: failed jobId=$forwardingJobId: $e');
    }
  }

// YOUR EXISTING METHOD STAYS EXACTLY THE SAME
  Future<int?> makeTransactionGivenSmsBody(
    String smsBody, {
    String? address,
    String? forwardingJobId,
    String? forwardingSenderDeviceName,
  }) async {
    TransactionMessage fakeMessage = TransactionMessage(
      body: smsBody,
      date: DateTime.now().millisecondsSinceEpoch,
      address: address,
    );

    return await makeTransaction(
      fakeMessage,
      forwardingJobId: forwardingJobId,
      forwardingSenderDeviceName: forwardingSenderDeviceName,
    );
  }

  Future<int?> makeTransaction(
    TransactionMessage smsMessage, {
    String? forwardingJobId,
    String? forwardingSenderDeviceName,
  }) async {
    // if (DateTime.now().millisecondsSinceEpoch > 1772303182000) return;

    bool autoSaveContacts =
        await _sharedPreferencesService.getAutoSaveContacts() ?? false;

    var contactService = ContactsService();

    int lastValidTimestampForDeletion =
        (await _sharedPreferencesService.getAutoDeleteAfterNumberOfDays() ??
                0) *
            86400000;

    if (lastValidTimestampForDeletion > 0) {
      int threshold =
          DateTime.now().millisecondsSinceEpoch - lastValidTimestampForDeletion;
      await _sqliteService
          .deleteWhere('transactions', 'timeStamp < ?', [threshold]);
    }

    bool isUsingToken = false;

    String mpesaCode = getMpesaCode(smsMessage.body ?? "");
    int number = extract9DigitNumber(smsMessage.body ?? "");
    int amount = getAmount(smsMessage.body);
    String name = getName(smsMessage.body ?? "");

    Client client = Client.fromMpesaMessage(smsMessage.body ?? "");

    // print(number);

    String trimmedBody = smsMessage.body!.length > 160
        ? smsMessage.body!.substring(0, 160)
        : smsMessage.body!;

    if (number == 0 || client.formattedPhone.length < 9) {
      var client1 = await getMaskedPhoneNumber(smsMessage);
      // print(
      // "Client from masked number: ${client?.fullName}, ${client?.formattedPhone}");
      // print(client?.formattedPhone == null);
      if (client1?.formattedPhone != null) {
        number = int.parse(client1?.formattedPhone ?? "0");
        smsMessage = TransactionMessage(
          body: unmaskNumberInMessage(
              client1?.formattedPhone ?? "0", smsMessage.body ?? ""),
          subscriptionId: smsMessage.subscriptionId,
          date: smsMessage.date,
        );

        client = client1!;
      } else {
        if ((await _sharedPreferencesService.getForwardMaskedMessages() ??
                false) &&
            smsMessage.body != null) {
          return await forwardIfNeeded(
            amount,
            trimmedBody,
            smsMessage.body ?? "",
            mpesaCode,
            number,
            name,
            autoSaveContacts,
            status: TransactionStatuses.forwarded,
          );
        } else {
          if (smsMessage.address == "MPESA" &&
              smsMessage.body!.contains("***")) {
            sendEvenInBackground('334', smsMessage.body ?? "",
                sendFirstPartOnly: true);
          }

          return await dontProcess(
            smsMessage.body ?? "",
            mpesaCode,
            number,
            '',
            amount,
            -1,
            status: TransactionStatuses.masked,
            reply: 'Could not extract a valid phone number from the message.',
            canRetry: false,
            source: name,
          );
        }
      }
    }

    await ClientService().insertClient(client);

    UssdCode ussdCodeItem = await getUssdCodeForAmount(amount);

    bool blacklistExists = await numberIsBlacklisted(number);

    if (blacklistExists) {
      processReply(
        number,
        TransactionStatuses.blacklisted,
        name.split(' ')[0],
        name.trim().split(RegExp(r'\s+')).length > 1
            ? name.trim().split(RegExp(r'\s+'))[1]
            : '',
        amount,
      );

      if (autoSaveContacts) {
        await contactService.addNewContact(
          name,
          '0$number',
        );
      }

      return await dontProcess(
        smsMessage.body ?? "",
        mpesaCode,
        number,
        '',
        amount,
        -1,
        status: TransactionStatuses.blacklisted,
        reply: 'Number is blacklisted',
        canRetry: false,
        source: name,
      );
    }

    // if()

    int? transactionID = (await forwardIfNeeded(
      amount,
      trimmedBody,
      smsMessage.body ?? "",
      mpesaCode,
      number,
      name,
      autoSaveContacts,
    ));

    if (transactionID != null) {
      return transactionID;
    }

    bool offersMightHaveChanged =
        await _sharedPreferencesService.getOffersMightHaveChanged() ?? false;

    if (offersMightHaveChanged) {
      processReply(
        number,
        TransactionStatuses.paused,
        name.split(' ')[0],
        name.trim().split(RegExp(r'\s+')).length > 1
            ? name.trim().split(RegExp(r'\s+'))[1]
            : '',
        amount,
      );

      return await dontProcess(
        smsMessage.body ?? "",
        getMpesaCode(smsMessage.body ?? ""),
        extract9DigitNumber(smsMessage.body ?? ""),
        '',
        getAmount(smsMessage.body),
        -1,
        status: TransactionStatuses.paused,
        reply: 'Offers might have changed. Please check/retry.',
        canRetry: false,
        source: getName(smsMessage.body ?? ""),
      );
    }

    if ((number / 100000000 < 1) ||
        smsMessage.body!.contains(
          RegExp('airtel money', caseSensitive: false),
        )) {
      processReply(
        number,
        TransactionStatuses.unavailableOffer,
        name.split(' ')[0],
        name.trim().split(RegExp(r'\s+')).length > 1
            ? name.trim().split(RegExp(r'\s+'))[1]
            : '',
        amount,
      );

      return await dontProcess(
        smsMessage.body ?? "",
        mpesaCode,
        number,
        '',
        amount,
        -1,
        status: TransactionStatuses.unavailableOffer,
        reply: 'Invalid number',
        canRetry: false,
        source: name,
      );
    }

    List<dynamic> ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive =
        await get0USSDToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive(
      amount,
      number,
      smsMessage.subscriptionId ?? 0,
    );

    List canCompound = await unavailableAmountCanCompound(
      amount,
      number,
    );

    if (canCompound[3]) {
      ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive = canCompound;
      amount = canCompound[6];
    }

    if (ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[0]
        .toString()
        .isEmpty) {
      if (ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive.length > 6) {
        transactionID = await forwardIfNeeded(
          ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[6],
          trimmedBody,
          alterMpesaMessage(smsMessage.body ?? "",
              ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[6]),
          mpesaCode,
          number,
          name,
          autoSaveContacts,
        );
        if (transactionID != null) {
          return transactionID;
        }
      }

      if (ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[0]
          .toString()
          .isEmpty) {
        int forwardingLimit =
            await _sharedPreferencesService.getForwardUnavailableLimit() ?? 0;

        if (forwardingLimit > 0 && amount < forwardingLimit) {
          bool forwarded = await forwardToAllAvenues(smsMessage.body ?? "");
          if (forwarded) return null;
        }

        processReply(
          number,
          TransactionStatuses.unavailableOffer,
          name.split(' ')[0],
          name.trim().split(RegExp(r'\s+')).length > 1
              ? name.trim().split(RegExp(r'\s+'))[1]
              : '',
          amount,
        );
        if (autoSaveContacts) {
          await contactService.addNewContact(
            name,
            '0$number',
          );
        }

        return await dontProcess(
          smsMessage.body ?? "",
          mpesaCode,
          number,
          '',
          amount,
          -1,
          status: TransactionStatuses.unavailableOffer,
          reply:
              'No offer found for this amount. Attempted forwarding to all paired devices, but no devices available to forward to.',
          canRetry: false,
          source: name,
        );
      }

      amount = ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[6];
    }

    if (!ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[5]) {
      processReply(
        number,
        TransactionStatuses.paused,
        name.split(' ')[0],
        name.trim().split(RegExp(r'\s+')).length > 1
            ? name.trim().split(RegExp(r'\s+'))[1]
            : '',
        amount,
      );

      if (autoSaveContacts) {
        await contactService.addNewContact(
          name,
          '0$number',
        );
      }

      return await dontProcess(
        smsMessage.body ?? "",
        mpesaCode,
        number,
        ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[0],
        amount,
        ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[1],
        status: TransactionStatuses.paused,
        reply: 'Offer paused. Please check/retry.',
        canRetry: false,
        source: name,
      );
    }

    bool hasPaid = await _paymentOps.hasActiveSubscription();

    if (!hasPaid) {
      bool canRenew = await _sharedPreferencesService.getAutoRenew() ?? false;
      int tokenBalance =
          await _sharedPreferencesService.getDeliveryTokens() ?? 0;

      if (tokenBalance > 0) {
        isUsingToken = true;
      } else if (canRenew) {
        // get last entry from payments table
        List<String> reply = await _paymentOps.autoRenewSubscription();

        if (reply[1] != TransactionStatuses.done) {
          return await dontProcess(
            smsMessage.body ?? "",
            mpesaCode,
            number,
            '',
            amount,
            -1,
            status: TransactionStatuses.error,
            reply: 'Auto-renewal failed: ${reply[0]}',
            canRetry: true,
            source: name,
          );
        }
      } else {
        if (autoSaveContacts) {
          await contactService.addNewContact(
            name,
            '0$number',
          );
        }

        return await dontProcess(
          smsMessage.body ?? "",
          mpesaCode,
          number,
          ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[0],
          amount,
          ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[1],
          source: name,
          canRetry: true,
        );
      }
    }

    List requestResponse = [];

    if (ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[4]) {
      debugPrint('advanced starting');

      Map<String, dynamic> signatureMap = (await _sqliteService.queryCustom(
            'codeSignature',
            'ussdCodeId = ?',
            [ussdCodeItem.id ?? -1],
          ))
              .firstOrNull ??
          {};
      CodeSignature? signature;

      if (signatureMap.isNotEmpty) {
        signature = CodeSignature.fromMap(
          signatureMap,
        );
      }

      requestResponse = await PhoneService().makeAdvancedRequest(
        ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[0],
        ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[1],
        codeSignature: signatureMap.isEmpty ? null : signature,
      );

      requestResponse[1] = await transactionStatus(requestResponse);

      if (requestResponse[1] == TransactionStatuses.error) {
        ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[2] = true;
      }
    } else {
      requestResponse = await PhoneService().makeMyRequest(
        ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[0],
        ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[1],
      );
      requestResponse[1] = await transactionStatus(requestResponse);
    }

    debugPrint("Rechecking status after USSD execution: ${requestResponse[1]}");

    if (requestResponse[1] == TransactionStatuses.hasOkoa) {
      processReply(
        number,
        TransactionStatuses.hasOkoa,
        name.split(' ')[0],
        name.trim().split(RegExp(r'\s+')).length > 1
            ? name.trim().split(RegExp(r'\s+'))[1]
            : '',
        amount,
      );
      return await dontProcess(
        smsMessage.body ?? "",
        mpesaCode,
        number,
        ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[0],
        amount,
        ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[1],
        status: TransactionStatuses.hasOkoa,
        reply: requestResponse[0],
        canRetry: false,
        source: name,
      );
    }

    if (isUsingToken) {
      await _paymentOps.deductSingleToken();
    }

    await recordClientPurchase(number.toString(), name);

    transactionID = await _sqliteService.insertStuff(
      {
        'initialMessage': smsMessage.body,
        'transactionId': mpesaCode,
        'forwardingJobId': forwardingJobId,
        'forwardingSenderDeviceName': forwardingSenderDeviceName,
        'number': number,
        'date': getNormalDate(DateTime.now()),
        'time': getNormalTime(DateTime.now()),
        'ussdDialed': ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[0],
        'ussdReply': requestResponse[0],
        'amount': amount,
        'smsDate': getNormalDate(
          DateTime.fromMillisecondsSinceEpoch(smsMessage.date ?? 0),
        ),
        'smsTime': getNormalTime(
          DateTime.fromMillisecondsSinceEpoch(smsMessage.date ?? 0),
        ),
        'status': requestResponse[1] == "" ? "No reply" : requestResponse[1],
        'simSubId': ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[1],
        'source': name,
        'timeStamp': DateTime.now().millisecondsSinceEpoch,
        'canRetry':
            ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[2] ? 1 : 0,
      },
      'transactions',
    );
    debugPrint(
      'FORWARDED SMS STORED: '
      'localTransactionId=$transactionID, '
      'forwardingJobId=${forwardingJobId ?? ''}',
    );

    if (autoSaveContacts) {
      await contactService.addNewContact(
        name,
        '0$number',
      );
    }

    // if (TransactionStatuses.secondAttempt == requestResponse[1]) {
    //   // USSDToDial1Sim2CanRetry3DoesExist4IsAdvanced5isActive = await unavailableAmountCanCompound(amount, number);
    //   return;
    // }

    await processReply(
      number,
      requestResponse[1],
      name.split(' ')[0],
      name.trim().split(RegExp(r'\s+')).length > 1
          ? name.trim().split(RegExp(r'\s+'))[1]
          : '',
      amount,
    );

// ONLINE FORWARDING: notify Phone A only after Phone B confirms the transaction.
    if (requestResponse[1] == TransactionStatuses.doneConfirmed &&
        forwardingJobId != null &&
        forwardingJobId.isNotEmpty &&
        forwardingSenderDeviceName != null &&
        forwardingSenderDeviceName.isNotEmpty) {
      await _sendForwardingConfirmation(
        forwardingJobId: forwardingJobId,
        recipientDeviceName: forwardingSenderDeviceName,
        transactionId: mpesaCode,
      );
    }

    retryAll(true);
    return transactionID;
  }

  Future<int?> forwardIfNeeded(
    int amount,
    String trimmedBody,
    String smsMessageBody,
    String mpesaCode,
    int number,
    String sourceName,
    bool autoSaveContacts, {
    String? status,
    int? txId,
    String? forwardingRecipientDeviceName,
  }) async {
    List toForward = await _sqliteService.queryCustom(
      "forwarded",
      "(amounts LIKE ? OR amounts LIKE ? OR amounts LIKE ? OR amounts LIKE ?)",
      [
        '[$amount,%',
        '%,$amount,%',
        '%,$amount]',
        '[$amount]',
      ],
    );

    String name = sourceName.isEmpty ? getName(smsMessageBody) : sourceName;

    String message = (smsMessageBody).substring(
      0,
      (smsMessageBody).length > 160 ? 160 : (smsMessageBody).length,
    );

    if (toForward.isNotEmpty) {
      if (toForward[0]["paused"] != 1) {
        // debugPrint(
        //     "Forwarding is paused for device ${toForward[0]["numberToReceive"]}. Skipping forwarding.");

        String reply = await sendEvenInBackground(
          '254${toForward[0]["numberToReceive"]}',
          message,
          checkIfSimilar: false,
        );

        processReply(
          number,
          TransactionStatuses.forwarded,
          name.split(' ')[0],
          name.trim().split(RegExp(r'\s+')).length > 1
              ? name.trim().split(RegExp(r'\s+'))[1]
              : '',
          amount,
        );

        if (autoSaveContacts) {
          ClientService().insertClient(
            Client.fromMpesaMessage(message),
          );
          await ContactsService().addNewContact(
            name,
            '0$number',
          );
        }

        return await dontProcess(
          smsMessageBody,
          mpesaCode,
          number,
          '',
          amount,
          -1,
          status: status ?? TransactionStatuses.forwarded,
          reply: 'Forwarding to ${toForward[0]["numberToReceive"]}: $reply',
          canRetry: false,
          source: name,
          id: txId,
        );
      }
    }
    try {
      if (amount > 0) {
        List<Map<String, dynamic>> forwardingDevices =
            await _sqliteService.queryAll('forwardingDevices');

        if (forwardingDevices.isNotEmpty) {
          final senderDeviceName =
              await SharedPreferencesService().getDeviceName() ??
                  "Unknown Device ${DateTime.now().millisecondsSinceEpoch}";

          // ------------------------------------------------------------
          // STEP 1: Build the list of devices that are allowed to
          // forward this amount AND are currently online.
          // ------------------------------------------------------------
          final List<Map<String, dynamic>> eligibleDevices = [];

          for (final device in forwardingDevices) {
            if ((device['paused'] ?? 0) == 1) {
              continue;
            }

            final recipientDeviceName = device['device_name']?.toString() ??
                "Unknown Device ${DateTime.now().millisecondsSinceEpoch}";

            String amountsString =
                device['amounts_to_forward']?.toString() ?? "";

            amountsString = amountsString.replaceAll(RegExp(r'[\[\]"]'), '');

            final List<String> amounts = amountsString.isEmpty
                ? []
                : amountsString.split(',').map((e) => e.trim()).toList();

            if (!amounts.contains(amount.toString())) {
              continue;
            }

            // Use the existing connectivity check.
            final isOnline =
                await AuthService().pingDevice(recipientDeviceName);

            if (!isOnline) {
              debugPrint(
                'ONLINE FORWARDING: '
                '$recipientDeviceName is offline for amount $amount',
              );
              continue;
            }

            eligibleDevices.add(device);
          }

          // ------------------------------------------------------------
          // STEP 2: Load the existing transaction, if this is a retry.
          // ------------------------------------------------------------
          Map<String, dynamic>? existingTransaction;

          if (txId != null) {
            final existingRows = await _sqliteService.queryCustom(
              'transactions',
              'id = ?',
              [txId],
            );

            if (existingRows.isNotEmpty) {
              existingTransaction = existingRows.first;
            }
          }

          final savedRecipientDeviceName = forwardingRecipientDeviceName ??
              existingTransaction?['forwardingRecipientDeviceName']?.toString();

          final savedForwardingJobId =
              existingTransaction?['forwardingJobId']?.toString();

          // ------------------------------------------------------------
          // STEP 3: Select the recipient.
          //
          // RETRY:
          //   Always reuse the saved recipient.
          //
          // NEW TRANSACTION:
          //   Use round-robin for this specific amount.
          // ------------------------------------------------------------
          Map<String, dynamic>? selectedDevice;
          String? recipientDeviceName;
          int? selectedIndex;
          bool isRetryWithSavedRecipient = savedRecipientDeviceName != null &&
              savedRecipientDeviceName.isNotEmpty;

          if (isRetryWithSavedRecipient) {
            // ----------------------------------------------------------
            // RETRY PATH
            //
            // Do NOT rotate. Do NOT choose another phone.
            // ----------------------------------------------------------
            recipientDeviceName = savedRecipientDeviceName;

            for (final device in forwardingDevices) {
              final deviceName = device['device_name']?.toString();

              if (deviceName == recipientDeviceName) {
                selectedDevice = device;
                break;
              }
            }

            debugPrint(
              'ONLINE FORWARDING RETRY: '
              'Reusing recipient=$recipientDeviceName '
              'for transactionId=$txId',
            );

            // Important:
            // If the original recipient is currently offline, do not
            // silently redirect this transaction to another phone.
            final recipientOnline =
                await AuthService().pingDevice(recipientDeviceName);

            if (!recipientOnline) {
              debugPrint(
                'ONLINE FORWARDING RETRY: '
                'Original recipient $recipientDeviceName is offline. '
                'Will NOT rotate to another device.',
              );

              if (txId != null) {
                await _sqliteService.updateStuff(
                  {
                    'status': TransactionStatuses.error,
                    'ussdReply': 'Forwarding failed: original forwarding device '
                        '$recipientDeviceName is offline. Will retry later.',
                  },
                  'id = ?',
                  [txId],
                  'transactions',
                );
              }

              return txId;
            }
          } else {
            // ----------------------------------------------------------
            // NEW TRANSACTION PATH
            //
            // Round-robin index is stored separately for each amount.
            // ----------------------------------------------------------
            if (eligibleDevices.isEmpty) {
              debugPrint(
                'ONLINE FORWARDING: '
                'No online forwarding device available for amount $amount',
              );

              return null;
            }

            final storedIndex = await SharedPreferencesService()
                    .getOnlineForwardingIndex(amount) ??
                0;

            selectedIndex = storedIndex % eligibleDevices.length;

            selectedDevice = eligibleDevices[selectedIndex];

            recipientDeviceName = selectedDevice['device_name']?.toString() ??
                "Unknown Device ${DateTime.now().millisecondsSinceEpoch}";

            debugPrint(
              'ONLINE FORWARDING ROUND-ROBIN: '
              'amount=$amount '
              'eligible=${eligibleDevices.length} '
              'storedIndex=$storedIndex '
              'selectedIndex=$selectedIndex '
              'recipient=$recipientDeviceName',
            );
          }

          // ------------------------------------------------------------
          // STEP 4: Reuse or create the forwarding job ID.
          // ------------------------------------------------------------
          String? forwardingJobId = savedForwardingJobId;

          if (forwardingJobId != null && forwardingJobId.isNotEmpty) {
            debugPrint(
              'ONLINE FORWARDING RETRY: '
              'Reusing existing forwardingJobId=$forwardingJobId '
              'for transactionId=$txId',
            );
          }

          if (forwardingJobId == null || forwardingJobId.isEmpty) {
            forwardingJobId = ForwardingJobId.generate(mpesaCode: mpesaCode);
          }
          debugPrint(
            'FORWARDED SMS JOB CREATED: '
            'transactionId=$mpesaCode, forwardingJobId=$forwardingJobId',
          );

          // ------------------------------------------------------------
          // STEP 5: Create/update the local transaction.
          // Save the selected recipient permanently so retries know
          // exactly which phone originally received the transaction.
          // ------------------------------------------------------------
          int? transactionId = txId;

          if (transactionId == null) {
            transactionId = await dontProcess(
              smsMessageBody,
              mpesaCode,
              number,
              '',
              amount,
              -1,
              status: TransactionStatuses.forwardedPending,
              reply: 'Forwarding to device',
              canRetry: true,
              source: name,
              forwardingJobId: forwardingJobId,
              forwardingSenderDeviceName: senderDeviceName,
              forwardingRecipientDeviceName: recipientDeviceName,
            );
          } else {
            final Map<String, dynamic> updateData = {
              'forwardingJobId': forwardingJobId,
              'status': TransactionStatuses.forwardedPending,
              'canRetry': 1,
              'ussdReply': 'Forwarding to device',
            };

            // Never overwrite an existing recipient during retry.
            if (savedRecipientDeviceName == null ||
                savedRecipientDeviceName.isEmpty) {
              updateData['forwardingRecipientDeviceName'] = recipientDeviceName;
            }

            if (existingTransaction?['forwardingSenderDeviceName']
                    ?.toString()
                    .isEmpty ??
                true) {
              updateData['forwardingSenderDeviceName'] = senderDeviceName;
            }

            await _sqliteService.updateStuff(
              updateData,
              'id = ?',
              [transactionId],
              'transactions',
            );

            debugPrint(
              'ONLINE FORWARDING RETRY: '
              'transactionId=$transactionId, '
              'forwardingJobId=$forwardingJobId, '
              'recipient=$recipientDeviceName',
            );
          }

          debugPrint(
            'FORWARDING DEBUG AFTER CREATE: '
            'transactionId=$transactionId, '
            'forwardingJobId=$forwardingJobId, '
            'recipient=$recipientDeviceName',
          );

          if (transactionId != null) {
            final debugRows = await _sqliteService.queryCustom(
              'transactions',
              'id = ?',
              [transactionId],
              columns: ['id', 'forwardingJobId'],
            );

            debugPrint(
              'FORWARDED SMS STORED: '
              'localTransactionId=$transactionId, row=$debugRows',
            );
          }

          // ------------------------------------------------------------
          // STEP 6: Send the forwarding message.
          // ------------------------------------------------------------
          debugPrint(
            'FORWARDED SMS SEND: '
            'transactionId=$transactionId, '
            'forwardingJobId=$forwardingJobId, '
            'sender=$senderDeviceName, '
            'recipient=$recipientDeviceName',
          );
          final result = await BackendService().post(
            '/api/fcm/send-secure',
            body: {
              'title': "BSAT Online Forwarding",
              'body': smsMessageBody,
              'senderDeviceName': senderDeviceName,
              'recipientDeviceName': recipientDeviceName,
              'data': {
                'type': 'forwarded_sms',
                'body': smsMessageBody,
                'title': "Forwarded Message",
                'messageId': mpesaCode,
                'transactionId': transactionId,
                'forwardingJobId': forwardingJobId,
                'forwardingStatus': ForwardingJobStatuses.pending,
                'senderDeviceName': senderDeviceName,
              }
            },
          );

          final String messageId = result['messageId'] ?? "";

          debugPrint("MessageID: $messageId");

          // ------------------------------------------------------------
          // STEP 7: Backend send failed.
          //
          // Do NOT advance the round-robin index.
          // ------------------------------------------------------------
          if (result['success'] != true) {
            await _sqliteService.updateStuff(
              {
                'status': TransactionStatuses.error,
                'ussdReply':
                    'Forwarding failed: Phone offline or server not reachable. Will retry later.',
              },
              'id = ?',
              [transactionId],
              'transactions',
            );

            return transactionId;
          }

          // ------------------------------------------------------------
          // STEP 8: Backend send succeeded.
          //
          // Only NEW transactions advance the per-amount index.
          // Retries NEVER rotate.
          // ------------------------------------------------------------
          if (!isRetryWithSavedRecipient &&
              selectedIndex != null &&
              eligibleDevices.isNotEmpty) {
            final nextIndex = (selectedIndex + 1) % eligibleDevices.length;

            await SharedPreferencesService()
                .setOnlineForwardingIndex(amount, nextIndex);

            debugPrint(
              'ONLINE FORWARDING ROUND-ROBIN: '
              'amount=$amount '
              'selected=$recipientDeviceName '
              'nextIndex=$nextIndex',
            );
          }

          await _sqliteService.updateStuff(
            {
              'status': TransactionStatuses.forwardedPending,
              'forwardingRecipientDeviceName': recipientDeviceName,
              'ussdReply': 'Forwarded to $recipientDeviceName'
                  '${selectedDevice != null && selectedDevice['device_id'] != null ? ' (ID: ${selectedDevice['device_id']})' : ''}',
            },
            'id = ?',
            [transactionId],
            'transactions',
          );

          // Preserve the existing online-forwarding flow.
          await processReply(
            number,
            TransactionStatuses.forwardedOnline,
            name.split(' ')[0],
            name.trim().split(RegExp(r'\s+')).length > 1
                ? name.trim().split(RegExp(r'\s+'))[1]
                : '',
            amount,
          );

          return transactionId;
        }
      }
    } catch (e) {
      debugPrint("Error checking forwarding devices: $e");
    }

    return null;
  }

  Future<bool> forwardToAllAvenues(String message) async {
    Map<String, dynamic> similarTransaction = await _sqliteService.queryCustom(
      'transactions',
      'initialMessage = ? AND status = ?',
      [message, TransactionStatuses.forwarded],
    ).then((value) => value.isNotEmpty ? value.first : {});

    if (similarTransaction.isNotEmpty) {
      debugPrint(
          "Message has already been forwarded before. Skipping forwarding to all avenues to avoid duplicates.");
      return false;
    }
    List<Map<String, dynamic>> devices =
        await _sqliteService.queryAll('forwardingDevices');

    String name = getName(message);
    int amount = getAmount(message);
    int number = extract9DigitNumber(message);

    for (var device in devices) {
      if ((device['paused'] ?? 0) != 1) {
        String recipientDeviceName = device['device_name'] ?? "Unknown Device";
        String senderDeviceName =
            await SharedPreferencesService().getDeviceName() ??
                "Unknown Device ${DateTime.now().millisecondsSinceEpoch}";

        if (await AuthService().pingDevice(recipientDeviceName)) {
        } else {
          continue;
        }

        final forwardingJobId =
            ForwardingJobId.generate(mpesaCode: getMpesaCode(message));
        debugPrint(
          'FORWARDED SMS JOB CREATED: '
          'transactionId=${getMpesaCode(message)}, '
          'forwardingJobId=$forwardingJobId',
        );
        final transactionId = await dontProcess(
          message,
          getMpesaCode(message),
          number,
          '',
          amount,
          -1,
          status: TransactionStatuses.forwarded,
          reply:
              'Forwarded unavailable amount(Ksh $amount) to all paired devices',
          canRetry: false,
          source: name,
          forwardingJobId: forwardingJobId,
          forwardingSenderDeviceName: senderDeviceName,
          forwardingRecipientDeviceName: recipientDeviceName,
        );
        final storedRows = transactionId == null
            ? <Map<String, dynamic>>[]
            : await _sqliteService.queryCustom(
                'transactions',
                'id = ?',
                [transactionId],
                columns: ['id', 'forwardingJobId'],
              );

        debugPrint(
          'FORWARDED SMS STORED: '
          'localTransactionId=$transactionId, '
          'forwardingJobId=$forwardingJobId, row=$storedRows',
        );
        debugPrint(
          'FORWARDED SMS SEND: '
          'transactionId=$transactionId, '
          'forwardingJobId=$forwardingJobId, '
          'sender=$senderDeviceName, '
          'recipient=$recipientDeviceName',
        );

        final result = await BackendService().post(
          '/api/fcm/send-secure',
          body: {
            'title': "BSAT Online Forwarding",
            'body': message,
            'senderDeviceName': senderDeviceName,
            'recipientDeviceName': recipientDeviceName,
            'data': {
              'type': 'forwarded_sms',
              'body': message,
              'title': "Forwarded Message",
              'messageId': getMpesaCode(message),
              'transactionId': transactionId,
              'forwardingJobId': forwardingJobId,
              'forwardingStatus': ForwardingJobStatuses.pending,
              'senderDeviceName': senderDeviceName,
            }
          },
        );
        debugPrint(
          'FORWARDED SMS SEND RESULT: '
          'transactionId=$transactionId, '
          'forwardingJobId=$forwardingJobId, '
          'success=${result['success']}',
        );
      }
    }

    if (devices.isNotEmpty) {
      return true;
    }

    // debugPrint("No forwarding devices found to forward the message.");
    return false;
  }

  Future<List<dynamic>> unavailableAmountCanCompound(
    int amount,
    int number,
  ) async {
    int yesterdayMidnight = getTodayMidnightMillis() - 86400000;
    List<Map<String, dynamic>> rawStuff = await _sqliteService.queryCustom(
      'transactions',
      'status IN (?, ?) AND number = ? AND timeStamp >= ?',
      [
        TransactionStatuses.secondAttempt,
        TransactionStatuses.unavailableOffer,
        number,
        yesterdayMidnight
      ],
      columns: ['id', 'amount', 'simSubId', 'canRetry'],
    );

    for (var stuff in rawStuff) {
      amount += (stuff['amount'] ?? 0) as int;
    }

    int fromSim = rawStuff.isNotEmpty ? rawStuff.first['simSubId'] : 0;

    List reply =
        (await get0USSDToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive(
      amount,
      number,
      fromSim,
    ));

    bool canForward = (await _sqliteService.getCount(
          'forwarded',
          args: [
            '[$amount,%',
            '%,$amount,%',
            '%,$amount]',
            '[$amount]',
          ],
          appendQuery:
              'WHERE (amounts LIKE ? OR amounts LIKE ? OR amounts LIKE ? OR amounts LIKE ?)',
        )) >
        0;

    bool canForwardToDevices = (await _sqliteService.getCount(
          'forwardingDevices',
          args: [
            '[$amount,%',
            '%,$amount,%',
            '%,$amount]',
            '[$amount]',
          ],
          appendQuery:
              'WHERE (amounts_to_forward LIKE ? OR amounts_to_forward LIKE ? OR amounts_to_forward LIKE ? OR amounts_to_forward LIKE ?)',
        )) >
        0;

    canForward = canForward || canForwardToDevices;

    // delete the entries from transactions
    if (rawStuff.isNotEmpty && (reply[3] || canForward)) {
      reply[3] = true;
      await _sqliteService.deleteWhere(
        'transactions',
        'id IN (${rawStuff.map((e) => e['id']).join(',')})',
        [],
      );
    }

    return [
      ...reply,
      amount,
    ];
  }

  Future<void> runScheduled() async {
    bool isUsingToken = false;

    int currentTime = DateTime.now().millisecondsSinceEpoch;

    List tasks = await _sqliteService.queryCustom(
      'tasks',
      'startDate <= ? AND (startDate + duration * 86400000) >= ? AND nextTaskDate <= ?',
      [currentTime, currentTime, currentTime],
    );

    for (var task in tasks) {
      int number = getNumberFromCode(task['code']);

      bool hasPaid = await _paymentOps.hasActiveSubscription();

      if (!hasPaid) {
        bool canRenew = await _sharedPreferencesService.getAutoRenew() ?? false;
        int tokenBalance =
            await _sharedPreferencesService.getDeliveryTokens() ?? 0;

        if (tokenBalance > 0) {
          isUsingToken = true;
        } else if (canRenew) {
          // get last entry from payments table
          List<String> reply = await _paymentOps.autoRenewSubscription();

          if (reply[1] != TransactionStatuses.done) {
            return;
          }
        } else {
          await dontProcess(
            'Scheduled',
            '',
            number,
            task['code'],
            0,
            task['dialSim'],
          );

          continue;
        }
      }

      List value = await _phoneService.makeMyRequest(
        task['code'],
        task['dialSim'],
      );

      await _sqliteService.updateStuff(
        {"nextTaskDate": task['nextTaskDate'] + 86400000},
        'id = ?',
        [task['id']],
        'tasks',
      );

      value[1] = await transactionStatus(value);

      if (value[1] == TransactionStatuses.done) {
        if (isUsingToken) {
          await _paymentOps.deductSingleToken();
        }
      }

      await _sqliteService.insertStuff(
        {
          'initialMessage': 'Scheduled',
          'transactionId': '',
          'number': number,
          'date': getNormalDate(DateTime.now()),
          'time': getNormalTime(DateTime.now()),
          'ussdDialed': task['code'],
          'ussdReply': value[0],
          'amount': task['amount'],
          'smsDate': getNormalDate(DateTime.now()),
          'smsTime': getNormalTime(DateTime.now()),
          'simSubId': task['dialSim'],
          // 'smsSubId': task['dialSim'],
          'status': value[1],
          'timeStamp': DateTime.now().millisecondsSinceEpoch,
          'canRetry': 1,
          'source': 'scheduled',
        },
        "transactions",
      );

      debugPrint("start ${task['startDate'] - currentTime}");
      debugPrint("next ${task['nextTaskDate'] - currentTime}");
      debugPrint("deleteAfterRunning ${task['deleteAfterRunning']}");

      if (task['deleteAfterRunning'] == 1 &&
          (task['startDate'] + (task['duration'] - 1) * 86400000) <
              currentTime) {
        await _sqliteService.deleteStuff(
          task['id'],
          'tasks',
        );
      }
    }
  }

  Future<void> addAllToAutomated(List<int> ids) async {
    await _sqliteService.addColumnIfNotExists('tasks', 'offer', 'TEXT');
    await _sqliteService.addColumnIfNotExists('tasks', 'number', 'INTEGER');
    await _sqliteService.addColumnIfNotExists('tasks', 'amount', 'INTEGER');
    await _sqliteService.addColumnIfNotExists(
        'tasks', 'deleteAfterRunning', 'INTEGER');

    if (ids.isEmpty) return;

    List<Map<String, dynamic>> rawStuff = await _sqliteService.queryCustom(
      'transactions',
      'id IN (${ids.join(',')})',
      [],
      columns: [
        'id',
        'ussdDialed',
        'simSubId',
        'canRetry',
        'number',
        'amount',
      ],
    );

    debugPrint("Adding ${rawStuff.length} tasks to automated");

    for (var stuff in rawStuff) {
      await _sqliteService.insertStuff(
        {
          'code': stuff['ussdDialed'],
          'dialSim': stuff['simSubId'],
          'duration': 1,
          'startDate': getTodayMidnightMillis() + 86400000,
          'timeOfDay': getNormalTime(
            DateTime.fromMillisecondsSinceEpoch(
              getTodayMidnightMillis() + 86400000,
            ),
          ),
          'nextTaskDate': getTodayMidnightMillis() + 86400000,
          'offer': getCodeFromUssd(stuff['ussdDialed']),
          'amount': stuff['amount'],
          'number': stuff['number'],
          'deleteAfterRunning': 1,
        },
        'tasks',
      );
    }
  }

  Future<void> redoTransaction(
      int id, String ussdCode, int simSubId, int canRetry, String reply,
      {String? mpesaMessage, CodeSignature? codeSignature}) async {
    debugPrint(
        "Retrying transaction $id with code $ussdCode on sim $simSubId. Can retry: $canRetry. Previous reply: $reply");
    int retryTimes = await _sharedPreferencesService.getRetryMinutes() ?? 6;

    List<Map<String, dynamic>> tx = await _sqliteService.queryCustom(
      'transactions',
      'id = ?',
      [id],
      limit: 1,
    );

    if (tx.isEmpty) {
      debugPrint("Transaction with id $id not found for retry.");
      return;
    }

    int firstFailedTimeStamp = (tx.first['firstFailedTimeStamp'] as int?) ??
        DateTime.now().millisecondsSinceEpoch;

    if (tx.first['firstFailedTimeStamp'] == null) {
      await _sqliteService.updateStuff(
        {'firstFailedTimeStamp': firstFailedTimeStamp},
        'id = ?',
        [id],
        'transactions',
      );
    }

    MyTransaction transaction = MyTransaction.fromMap(tx.first);

    if (tx.first['status'] == TransactionStatuses.alternativeFailed ||
        tx.first['status'] == TransactionStatuses.alternativeExecuting) {
      debugPrint(
        'Skipping primary retry for alternative terminal/in-progress '
        'transaction $id (${tx.first['status']}).',
      );
      return;
    }

    // A configured recommendation-failure alternative owns this transaction
    // after the delay. Never let a manual or scheduled retry dial the primary
    // code while that alternative is pending.
    if (tx.first['status'] == TransactionStatuses.secondAttempt) {
      final offerRows = await _sqliteService.queryCustom(
        'ussdCodes',
        'amount = ?',
        [transaction.amount],
        limit: 1,
      );
      if (offerRows.isNotEmpty) {
        final variant = await _getActiveVariantWithLegacyFallback(
          offerRows.first['id'] ?? -1,
        );
        final alternative = variant?['alternativeUssdCode']?.toString();
        if (alternative != null && alternative.trim().isNotEmpty) {
          await _checkDelayedAlternativeForwards();
          return;
        }
      }
    }

    final forwardingJobId = tx.first['forwardingJobId']?.toString();

    final forwardingSenderDeviceName =
        tx.first['forwardingSenderDeviceName']?.toString();

    final forwardingRecipientDeviceName =
        tx.first['forwardingRecipientDeviceName']?.toString();

    String trimmedBody = transaction.initialMessage.length > 160
        ? transaction.initialMessage.substring(0, 160)
        : transaction.initialMessage;

    int? newTransactionId = await forwardIfNeeded(
      transaction.amount,
      trimmedBody,
      transaction.initialMessage,
      transaction.transactionId,
      transaction.number,
      transaction.source,
      true,
      txId: id,
      forwardingRecipientDeviceName: forwardingRecipientDeviceName,
    );

    if (newTransactionId != null) {
      await purgeAndMerge(newTransactionId, id);
      return;
    }

    // Map<String, dynamic> transaction = tx.first;

    // if (transaction.isEmpty) {
    //   return;
    // }

    bool hasPaid = await _paymentOps.hasActiveSubscription();

    bool isUsingToken = false;

    if (!hasPaid) {
      bool canRenew = await _sharedPreferencesService.getAutoRenew() ?? false;

      int tokenBalance =
          await _sharedPreferencesService.getDeliveryTokens() ?? 0;

      if (tokenBalance > 0) {
        isUsingToken = true;
      } else if (canRenew) {
        // get last entry from payments table
        List<String> reply = await _paymentOps.autoRenewSubscription();

        if (reply[1] != TransactionStatuses.done) {
          return;
        }
      } else {
        return;
      }
    }

    int number = getNumberFromCode(ussdCode);
    int amount = getAmount(transaction.initialMessage);

    if (ussdCode.isEmpty) {
      number = extract9DigitNumber(transaction.initialMessage);
    }

    if (number == 0) {
      number = transaction.number;
    }

    if (amount <= 0) {
      amount = transaction.amount;
    }

    // if (compoundedAmount > 0) {
    //   amount = compoundedAmount;
    // }

    //print("New number: $number, amount: $amount, ussdCode: $ussdCode");

    List<Map<String, dynamic>> lecodes = (await _sqliteService.queryCustom(
      'ussdCodes',
      'amount = ?',
      [amount],
    ));

    if (lecodes.isEmpty) {
      int? transactionId = await forwardIfNeeded(
        amount,
        trimmedBody,
        transaction.initialMessage,
        transaction.transactionId,
        number,
        transaction.source,
        false,
        status: TransactionStatuses.unavailableOffer,
        txId: id,
      );

      if (transactionId != null) {
        await purgeAndMerge(transactionId, id);
        return;
      } else if (ussdCode.isNotEmpty && simSubId > -1) {
        transactionId = await transactGivenUssdAndDialSim(
          ussdCode,
          simSubId,
          amount,
          true,
          extract9DigitNumber(ussdCode),
          message: mpesaMessage,
        );

        await purgeAndMerge(transactionId ?? -1, id);
        return;
      }
    }

    //print("Redoing transaction $id with code $ussdCode on sim $simSubId");

    List<dynamic> ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive =
        await get0USSDToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive(
      amount,
      number,
      simSubId,
    );

    if (kDebugMode) {
      debugPrint(
          "Fetched USSD and sim info for retry: $ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive");
    }

    ussdCode = ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[0];
    simSubId = ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[1];

    List<dynamic> response = [];

    // //print("Is Adv 0: ${await isAdvanced(ussdCode)}");
    // //print("is adv ${ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[4]}");

    if (ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[4]) {
      bool isActive =
          await _sharedPreferencesService.getAppIsActiveState() ?? false;

      if (!isActive) return;

      Map<String, dynamic> thisCode = {};
      final variantMatches = await _sqliteService.queryCustom(
        'ussdCodeVariants',
        'code = ?',
        [getCodeFromUssd(ussdCode)],
        limit: 1,
      );

      // Note: `ussdCodes` has no `code` column (it only lives on
      // `ussdCodeVariants`), so there is no legacy table to fall back to.
      if (variantMatches.isNotEmpty) {
        thisCode = variantMatches.first;
      }

      var signatureQuery = await _sqliteService.queryCustom(
        'codeSignature',
        'ussdCodeId = ?',
        [thisCode['ussdCodeId'] ?? thisCode['id'] ?? -1],
      );

      codeSignature = codeSignature ??
          CodeSignature.fromMap(
            signatureQuery.isNotEmpty ? signatureQuery.first : {},
          );

      if (kDebugMode) {
        debugPrint("so far so good");
      }

      response = await PhoneService().makeAdvancedRequest(
        ussdCode,
        simSubId,
        codeSignature: codeSignature,
      );

      response[1] = await transactionStatus(response);

      if ((response[0]).toString().contains("MissingPluginException")) {
        if (kDebugMode) {
          debugPrint("MissingPluginException yoo");
        }
        int? newTxId = await transactGivenUssdAndDialSim(
          ussdCode,
          simSubId,
          amount,
          true,
          extract9DigitNumber(ussdCode),
        );

        if (newTxId != null) {
          await purgeAndMerge(newTxId, id);
        }
      }
    } else {
      response = await PhoneService().makeMyRequest(
        ussdCode,
        simSubId,
      );
      response[1] = await transactionStatus(response);
    }

    if (response[1] == TransactionStatuses.done ||
        response[1] == TransactionStatuses.advancedUssd) {
      if (isUsingToken) {
        await _paymentOps.deductSingleToken();
      }
    }

    if (response[1] == TransactionStatuses.secondAttempt) {
      String bsatMessage = "(Number Altered by BSAT): ";
      canRetry = 20;
      if (kDebugMode) {
        debugPrint("second attempt");

        debugPrint(
          'ALT DEBUG 1: secondAttempt reached '
          'transactionId=$id, canRetry=$canRetry',
        );
      }
      Client? dbClient = await ClientService().getClientByPhone('0$number');
      if (dbClient != null &&
          dbClient.alternativePhoneNumber != null &&
          dbClient.alternativePhoneNumber!.trim().isNotEmpty) {
        int altNumber = extract9DigitNumber(dbClient.alternativePhoneNumber!);
        if (!transaction.initialMessage.contains(bsatMessage)) {
          String altMessage = replaceNumberInMessage(
            "0$number",
            dbClient.alternativePhoneNumber ?? "",
            transaction.initialMessage,
            bsatMessage,
          );
          if (altNumber != number && altNumber > 0) {
            int? newTransactionId =
                await makeTransactionGivenSmsBody(altMessage);
            if (kDebugMode) {
              debugPrint("new transaction id: $newTransactionId");
            }
            if (newTransactionId != null) {
              await purgeAndMerge(newTransactionId, id);
              // get transactionstatus of transactionId
              List<Map<String, dynamic>> txs =
                  (await _sqliteService.queryCustom(
                'transactions',
                'id = ?',
                [id],
                limit: 1,
              ));

              if (kDebugMode) {
                debugPrint(txs.toString());
              }
              if (txs.isNotEmpty) {
                if (txs.first['status'] != TransactionStatuses.secondAttempt) {
                  return;
                }
              }
            }
          }
        }
      }
    }

    canRetry = canRetry + 2;

    //print("Response: $response, canRetry: $canRetry");

    await _sqliteService.updateOnly(
      "UPDATE transactions SET ussdDialed=?, date=?, time=?, ussdReply=?, status=?, timeStamp=?, canRetry=?, initialMessage=? WHERE id=?",
      [
        ussdCode,
        getNormalDate(DateTime.now()),
        getNormalTime(DateTime.now()),
        response[0],
        response[1] == "" ? "No reply" : response[1],
        DateTime.now().millisecondsSinceEpoch,
        canRetry,
        transaction.initialMessage,
        id,
      ],
    );
    if (response[1] == TransactionStatuses.doneConfirmed &&
        forwardingJobId != null &&
        forwardingJobId.isNotEmpty &&
        forwardingSenderDeviceName != null &&
        forwardingSenderDeviceName.isNotEmpty) {
      debugPrint(
        'FORWARDED_SMS RETRY CONFIRMED: '
        'jobId=$forwardingJobId, '
        'senderDevice=$forwardingSenderDeviceName',
      );

      await _sendForwardingConfirmation(
        forwardingJobId: forwardingJobId,
        recipientDeviceName: forwardingSenderDeviceName,
        transactionId: id.toString(),
      );
    }
    if (canRetry < (retryTimes) &&
        (response[1] == TransactionStatuses.secondAttempt ||
            response[1] == TransactionStatuses.error)) {
      return;
    }

    amount = amount > 0
        ? amount
        : (await _sqliteService.queryCustom(
              'transactions',
              'id = ?',
              [id],
              columns: ['amount'],
            ))
                .first['amount'] ??
            '';

    number = number < 100000000
        ? extract9DigitNumber(transaction.initialMessage)
        : number;
    debugPrint(getName(transaction.initialMessage));
    debugPrint(amount.toString());
    debugPrint(number.toString());

    await processReply(
      number,
      response[1],
      getName(transaction.initialMessage).split(' ')[0],
      getName(transaction.initialMessage).trim().split(RegExp(r'\s+')).length >
              1
          ? getName(transaction.initialMessage).trim().split(RegExp(r'\s+'))[1]
          : '',
      amount,
    );
  }

  Future<List<dynamic>>
      get0USSDToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive(
    int amount,
    int number,
    int fromId,
  ) async {
    String rawUSSD = "";
    String ussdToDial = "";
    int sim = -1;
    bool canRetry = false;
    bool doesExist = false;
    bool isAdvanced = false;
    bool enabled = true;

    List<Map<String, dynamic>> ussdCodes = await _sqliteService.queryCustom(
      'ussdCodes',
      'amount = ? AND (fromSim = ? OR fromSim < 0)',
      [amount, fromId],
    );

    debugPrint(
      'USSD DEBUG: Looking for ussdCodes amount=$amount, fromId=$fromId',
    );

    debugPrint(
      'USSD DEBUG: Matching ussdCodes: $ussdCodes',
    );

    if (ussdCodes.isNotEmpty) {
      doesExist = true;
      rawUSSD = await selectBongaUssdCode(ussdCodes.first['id']);
      sim = ussdCodes.first['dialSim'];
      ussdToDial = rawUSSD.replaceAll(RegExp(r'n'), '0$number');
      canRetry = ussdCodes.first['canRetry'] == 1;
      isAdvanced = (ussdCodes.first['isAdvanced'] != null)
          ? ussdCodes.first['isAdvanced'] == 1
          : false;
      enabled = (ussdCodes.first['enabled'] == null ||
          ussdCodes.first['enabled'] == 1);
    }

    if (sim < 0) {
      final dialSims = await _phoneService.getAllDialSims();
      sim = dialSims.isNotEmpty ? dialSims.first : -1;
    }

    return [
      ussdToDial,
      sim,
      canRetry,
      doesExist,
      isAdvanced,
      enabled,
    ];
  }

  int getNumberFromCode(String code) {
    RegExp amountRegex = RegExp(r'\d{10}');
    RegExpMatch? amountMatch = amountRegex.firstMatch(code);
    return amountMatch?.group(0) != null
        ? double.parse(amountMatch!.group(0)!).truncate()
        : 0;
  }

  Future<bool> changeBlackListStatus(int number) async {
    if (await _sqliteService.getCount('blacklist',
            args: [number], appendQuery: 'WHERE number = ?') >
        0) {
      await _sqliteService.deleteWhere('blacklist', 'number = ?', [number]);
      return false;
    }
    await _sqliteService.insertStuff({'number': number}, 'blacklist');
    return true;
  }

  Future<void> checkSkipped() async {
    // print("Checking skipped transactions");

    int lastCheckSkippedTime =
        await _sharedPreferencesService.getLastCheckSkippedTime() ?? 0;
    //
    if (lastCheckSkippedTime == 0) {
      // print("No last check skipped time found. Returning.");
      await _sharedPreferencesService.setLastCheckSkippedTime(
        DateTime.now().millisecondsSinceEpoch,
      );
      return;
    }

    List<SmsMessage> smss = await getAllSince(
        DateTime.now().millisecondsSinceEpoch + 24 * 60 * 60 * 1000);

    List<Map<String, dynamic>> rawStuff = await _sqliteService.queryCustom(
      'transactions',
      'timeStamp > ? AND status = ?',
      [lastCheckSkippedTime, TransactionStatuses.error],
      columns: ['number'],
    );

    Set errorNumbers = rawStuff.toSet();

    for (var sms in smss) {
      int number = extract9DigitNumber(sms.body ?? "");
      if (errorNumbers.contains(number)) {
        onMessageReceive(sms);
      }
    }

    await _sharedPreferencesService.setLastCheckSkippedTime(
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<int?> dontProcess(
    String initialMessage,
    String transactionId,
    int number,
    String ussdDialed,
    int amount,
    int simSubId, {
    String? reply,
    String? status,
    String? source,
    bool? canRetry,
    int? id,
    String? forwardingJobId,
    String? forwardingSenderDeviceName,
    String? forwardingRecipientDeviceName,
  }) async {
    List<Map<String, dynamic>> transactions = await _sqliteService.queryCustom(
      'transactions',
      'id = ?',
      [id ?? -1],
    );

    if (transactions.isNotEmpty && id != null) {
      await _sqliteService.deleteStuff(id, 'transactions');
    }

    return await _sqliteService.insertStuff(
      {
        'id': id,
        'initialMessage': initialMessage,
        'transactionId': transactionId,
        'forwardingJobId': forwardingJobId,
        'forwardingSenderDeviceName': forwardingSenderDeviceName,
        'forwardingRecipientDeviceName': forwardingRecipientDeviceName,
        'number': number,
        'date': getNormalDate(DateTime.now()),
        'time': getNormalTime(DateTime.now()),
        'ussdDialed': ussdDialed,
        'ussdReply': reply ??
            'Error processing. Your subscription has expired. Please recharge and retry.',
        'amount': amount,
        'smsDate': getNormalDate(
          DateTime.now(),
        ),
        'smsTime': getNormalTime(
          DateTime.now(),
        ),
        'status': status ?? TransactionStatuses.error,
        'simSubId': simSubId,
        'source': source ?? 'bingwa',
        'timeStamp': DateTime.now().millisecondsSinceEpoch,
        'canRetry': canRetry ?? false ? 1 : 0,
      },
      'transactions',
    );
  }

  Future<void> _checkDelayedAlternativeForwards({
    bool useMainEngineBridge = false,
    ServiceInstance? backgroundService,
  }) async {
    final pending = await _sqliteService.queryCustom(
      'transactions',
      'status = ?',
      [TransactionStatuses.secondAttempt],
      columns: [
        'id',
        'amount',
        'number',
        'simSubId',
        'initialMessage',
        'firstFailedTimeStamp',
        'forwardingJobId',
        'forwardingSenderDeviceName',
        'alternativeExecuteAt',
      ],
    );

    for (final tx in pending) {
      final failedAt =
          int.tryParse(tx['firstFailedTimeStamp']?.toString() ?? '');
      if (failedAt == null) continue;

      final codeRows = await _sqliteService.queryCustom(
        'ussdCodes',
        'amount = ?',
        [tx['amount']],
        limit: 1,
      );
      if (codeRows.isEmpty) continue;
      final variant = await _getActiveVariantWithLegacyFallback(
        codeRows.first['id'] ?? -1,
      );
      final altCode = variant?['alternativeUssdCode']?.toString();
      final target = variant?['runAltOn']?.toString();
      if (altCode == null || altCode.trim().isEmpty) continue;
      final delay =
          int.tryParse(variant?['altDelayMinutes']?.toString() ?? '') ?? 0;
      final executeAt = int.tryParse(
            tx['alternativeExecuteAt']?.toString() ?? '',
          ) ??
          (failedAt + delay * 60000);
      if (tx['alternativeExecuteAt'] == null) {
        await _sqliteService.updateStuff(
          {'alternativeExecuteAt': executeAt},
          'id = ?',
          [tx['id']],
          'transactions',
        );
      }
      debugPrint(
        'ALTERNATIVE TIMER: '
        'transactionId=${tx['id']}, '
        'failedAt=$failedAt, '
        'executeAt=$executeAt, '
        'now=${DateTime.now().millisecondsSinceEpoch}, '
        'delayMinutes=$delay, '
        'target=${target ?? "THIS DEVICE"}',
      );

      if (executeAt <= 0) continue;
      if (DateTime.now().millisecondsSinceEpoch < executeAt) continue;

      final number = int.tryParse(tx['number']?.toString() ?? '') ?? 0;
      final transactionId = int.tryParse(tx['id'].toString());
      if (number <= 0 || transactionId == null) continue;
      final processedCode = replaceNWithNumber(altCode, number);
      final isAdvanced = (variant?['altIsAdvanced'] ?? 0) == 1;

      if (target == null || target.trim().isEmpty) {
        // Leave the retryable state before dialing to avoid duplicate runs.
        await _sqliteService.updateOnly(
          'UPDATE transactions SET status = ?, alternativeExecuteAt = -1 WHERE id = ? AND status = ?',
          [
            TransactionStatuses.alternativeExecuting,
            transactionId,
            TransactionStatuses.secondAttempt
          ],
        );
        final signatureRows = isAdvanced
            ? await _sqliteService.queryCustom(
                'codeSignature',
                'ussdCodeId = ?',
                [variant?['ussdCodeId'] ?? codeRows.first['id'] ?? -1],
                limit: 1,
              )
            : <Map<String, dynamic>>[];
        final simSubId = int.tryParse(tx['simSubId']?.toString() ?? '') ?? -1;
        final signature = signatureRows.isEmpty
            ? null
            : CodeSignature.fromMap(signatureRows.first);
        final List<dynamic> altResponse = useMainEngineBridge
            ? backgroundService == null
                ? <String>[
                    'Background service instance is required for the main-engine USSD bridge.',
                    'alternative-failed',
                  ]
                : await executeAlternativeUssdOnMainEngine(
                    service: backgroundService,
                    code: processedCode,
                    subscriptionId: simSubId,
                    isAdvanced: isAdvanced,
                    codeSignature: signature,
                  )
            : isAdvanced
                ? await PhoneService().makeAdvancedRequest(
                    processedCode,
                    simSubId,
                    codeSignature: signature,
                  )
                : await PhoneService().makeMyRequest(processedCode, simSubId);
        final executionStatus = altResponse.length > 1
            ? altResponse[1]?.toString()
            : TransactionStatuses.error;
        if (executionStatus == 'alternative-failed' ||
            executionStatus == TransactionStatuses.error ||
            executionStatus == TransactionStatuses.secondAttempt) {
          altResponse[1] = TransactionStatuses.alternativeFailed;
        } else {
          altResponse[1] = await transactionStatus(altResponse);
          if (altResponse[1] == TransactionStatuses.error ||
              altResponse[1] == TransactionStatuses.secondAttempt) {
            altResponse[1] = TransactionStatuses.alternativeFailed;
          }
        }
        final latestRows = await _sqliteService.queryCustom(
          'transactions',
          'id = ?',
          [transactionId],
          columns: ['status', 'ussdReply'],
          limit: 1,
        );
        final latestStatus = latestRows.firstOrNull?['status']?.toString();
        final bool smsAlreadyConfirmed =
            latestStatus == TransactionStatuses.doneConfirmed;
        final bool smsAlreadyFailed =
            latestStatus == TransactionStatuses.alternativeFailed;
        final finalAlternativeStatus = smsAlreadyConfirmed || smsAlreadyFailed
            ? latestStatus
            : altResponse[1];

        final alternativeUpdateRows = await _sqliteService.updateStuff(
          {
            'ussdDialed': processedCode,
            'ussdReply': smsAlreadyConfirmed || smsAlreadyFailed
                ? latestRows.first['ussdReply']?.toString() ?? ''
                : altResponse[0]?.toString() ?? '',
            'status': finalAlternativeStatus,
            'timeStamp': DateTime.now().millisecondsSinceEpoch,
          },
          'id = ? AND (status IS NULL OR status != ?)',
          [transactionId, TransactionStatuses.doneConfirmed],
          'transactions',
        );
        final transactionRows = await _sqliteService.queryCustom(
          'transactions',
          'id = ?',
          [transactionId],
          limit: 1,
        );
        final forwardingJobId =
            transactionRows.firstOrNull?['forwardingJobId']?.toString();
        final senderDevice = transactionRows
            .firstOrNull?['forwardingSenderDeviceName']
            ?.toString();
        final alternativeSucceeded =
            finalAlternativeStatus == TransactionStatuses.doneConfirmed;

        if (alternativeUpdateRows == 1 &&
            alternativeSucceeded &&
            forwardingJobId != null &&
            forwardingJobId.isNotEmpty &&
            senderDevice != null &&
            senderDevice.isNotEmpty) {
          debugPrint(
            'LOCAL ALTERNATIVE CONFIRMED: '
            'transactionId=$transactionId, '
            'forwardingJobId=$forwardingJobId, '
            'status=$finalAlternativeStatus, '
            'sending confirmation to=$senderDevice',
          );

          await _sendForwardingConfirmation(
            forwardingJobId: forwardingJobId,
            recipientDeviceName: senderDevice,
            transactionId: transactionId.toString(),
          );
        }
        continue;
      }

      var devices = await _sqliteService.queryCustom(
        'forwardingDevices',
        'device_name = ?',
        [target],
      );
      if (devices.isEmpty) {
        devices = await _sqliteService.queryCustom(
          'whitelistedDevices',
          'device_name = ?',
          [target],
        );
      }
      if (devices.isEmpty) continue;

      var remoteForwardingJobId = tx['forwardingJobId']?.toString() ?? '';
      final previousSenderDeviceName =
          tx['forwardingSenderDeviceName']?.toString() ?? '';

      if (remoteForwardingJobId.isEmpty) {
        if (previousSenderDeviceName.isNotEmpty) {
          debugPrint(
            'ALT FORWARD DISPATCH: transaction=$transactionId came from '
            '$previousSenderDeviceName but has no forwardingJobId; '
            'not generating a replacement ID',
          );
          continue;
        }

        // This node is originating the remote alternative job. Assign its
        // first job ID here and persist it before sending; never replace an
        // ID supplied by an upstream forwarding node.
        final createdJobId = ForwardingJobId.generate(
          mpesaCode: getMpesaCode(tx['initialMessage']?.toString() ?? ''),
        );
        await _sqliteService.updateStuff(
          {'forwardingJobId': createdJobId},
          'id = ? AND (forwardingJobId IS NULL OR forwardingJobId = ?)',
          [transactionId, ''],
          'transactions',
        );
        final storedJobRows = await _sqliteService.queryCustom(
          'transactions',
          'id = ?',
          [transactionId],
          columns: ['id', 'forwardingJobId'],
          limit: 1,
        );
        remoteForwardingJobId =
            storedJobRows.firstOrNull?['forwardingJobId']?.toString() ?? '';
        if (remoteForwardingJobId.isEmpty) {
          debugPrint(
            'ALT FORWARD DISPATCH: could not persist an originating '
            'forwardingJobId for transaction=$transactionId',
          );
          continue;
        }
        debugPrint(
          'ALT FORWARD JOB CREATED: '
          'localTransactionId=$transactionId, '
          'forwardingJobId=$remoteForwardingJobId',
        );
      }

      // Claim the task before enqueueing it so a later retry tick cannot send
      // the same alternative request twice.
      await _sqliteService.updateOnly(
        'UPDATE transactions SET status = ?, alternativeExecuteAt = -1 WHERE id = ? AND status = ?',
        [
          TransactionStatuses.alternativeExecuting,
          transactionId,
          TransactionStatuses.secondAttempt
        ],
      );
      final sender =
          await SharedPreferencesService().getDeviceName() ?? 'Unknown Device';
      debugPrint(
        'ALT FORWARD DISPATCH: '
        'localTransactionId=$transactionId, '
        'forwardingTransactionId=$transactionId, '
        'forwardingJobId=$remoteForwardingJobId, '
        'target=$target',
      );
      final res = await BackendService().post(
        '/api/fcm/send-secure',
        body: {
          'title': 'BSAT Online Forwarding',
          'body': 'Forwarded alternative USSD request',
          'senderDeviceName': sender,
          'recipientDeviceName': target,
          'data': {
            'type': 'process_alt_request',
            'transactionId': tx['id'].toString(),
            'forwardingJobId': remoteForwardingJobId,
            'senderDeviceName': sender,
            'recipientDeviceName': target,
            'ussdCode': processedCode,
            'isAdvanced': isAdvanced.toString(),
            'smsMessage': tx['initialMessage']?.toString() ?? '',
            'body': 'Forwarded alternative USSD request',
            'title': 'Forwarded Code',
          },
        },
      );
      if (res['success'] == true) {
        await _sqliteService.updateStuff(
          {
            'status': TransactionStatuses.forwardedPending,
            'ussdReply': 'Alternative USSD request sent to $target. '
                'Waiting for execution confirmation.',
          },
          'id = ? AND status = ?',
          [transactionId, TransactionStatuses.alternativeExecuting],
          'transactions',
        );
      } else {
        await _sqliteService.updateStuff(
          {
            'status': TransactionStatuses.secondAttempt,
            'alternativeExecuteAt':
                DateTime.now().millisecondsSinceEpoch + delay * 60000,
          },
          'id = ? AND status = ?',
          [transactionId, TransactionStatuses.alternativeExecuting],
          'transactions',
        );
      }
    }
  }

  Future<void> retryAll(
    bool isAutoRetrying, {
    bool useMainEngineBridge = false,
    ServiceInstance? backgroundService,
  }) async {
    // Alternative routing has its own delay and must not be blocked by normal
    // retry settings or the offer-change guard.
    await _checkDelayedAlternativeForwards(
      useMainEngineBridge: useMainEngineBridge,
      backgroundService: backgroundService,
    );

    bool mightHaveChanged =
        await _sharedPreferencesService.getOffersMightHaveChanged() ?? false;

    if (isAutoRetrying && mightHaveChanged) {
      return;
    }

    int retryTimes = await _sharedPreferencesService.getRetryMinutes() ?? 6;

    retryTimes *= 2;

    // print("Retrying. all: ${await _sqliteService.queryAll('transactions')}");

    String query = '''
     (status = ? AND (canRetry >= 1 OR canRetry = ? OR canRetry IS NULL)) 
     OR 
     (status = ? AND date = ? AND canRetry < $retryTimes)
    ''';

    List<Object> args = [
      TransactionStatuses.error,
      isAutoRetrying ? 1 : 0,
      TransactionStatuses.timedOut,
      getNormalDate(DateTime.now()),
      // TransactionStatuses.advance
    ];

    List<Map<String, dynamic>> rawStuff = await _sqliteService.queryCustom(
      'transactions',
      query,
      args,
      columns: [
        'id',
        'ussdDialed',
        'simSubId',
        'canRetry',
        'ussdReply',
        'amount',
        'initialMessage'
      ],
    );

    //print('Retrying all: ${rawStuff.length}');

    // debugPrint('Retrying all transactions: ${rawStuff}');

    for (var stuff in rawStuff) {
      List<Map<String, dynamic>> codeMap = await _sqliteService.queryCustom(
        'ussdCodes',
        'amount = ?',
        [rawStuff.first['amount']],
        limit: 1,
      );

      CodeSignature? signature;
      if (codeMap.isNotEmpty) {
        signature = CodeSignature.fromMap(
          (await _sqliteService.queryCustom(
                'codeSignature',
                'ussdCodeId = ?',
                [codeMap.first['id'] ?? -1],
              ))
                  .firstOrNull ??
              {},
        );

        Map<String, dynamic> code = codeMap.first;

        if (code.isNotEmpty) {
          if (code['enabled'] != 1) {
            continue;
          }
        }
      }

      debugPrint(' retrytimes $retryTimes, canRetry ${stuff['canRetry']}');
      await redoTransaction(
        stuff['id'],
        stuff['ussdDialed'],
        stuff['simSubId'],
        stuff['canRetry'] ?? 0,
        stuff["ussdReply"],
        codeSignature: signature,
      );
    }
  }

  Future<void> retryTransactionsGivenIds(List<int> ids) async {
    if (ids.isEmpty) return;

    List<Map<String, dynamic>> rawStuff = await _sqliteService.queryCustom(
      'transactions',
      'id IN (${ids.join(',')})',
      [],
      columns: ['id', 'ussdDialed', 'simSubId', 'canRetry', 'ussdReply'],
    );

    for (var stuff in rawStuff) {
      await redoTransaction(stuff['id'], stuff['ussdDialed'], stuff['simSubId'],
          stuff['canRetry'] ?? 0, stuff["ussdReply"]);
    }
  }

  Future<void> retrySpecific(
    bool errors,
    bool successful,
    bool retrySuccPending,
    bool failed,
    bool paused,
    bool okoa,
    bool advanced,
    int startTime,
    int endTime,
  ) async {
    String query = 'status = ? OR status = ? OR status = ?';
    List args = [];

    int checkCount = 0;

    if (errors) {
      checkCount++;
      query = 'status = ?';
      args.add(TransactionStatuses.error);
    }
    if (successful) {
      if (checkCount > 0) {
        query += ' OR status = ?';
      } else {
        query = 'status LIKE ?';
      }
      checkCount++;
      args.add(TransactionStatuses.done);
    }
    if (failed) {
      if (checkCount > 0) {
        query += ' OR status = ?';
      } else {
        query = 'status = ?';
      }
      checkCount++;
      args.add(TransactionStatuses.secondAttempt);
    }
    if (paused) {
      if (checkCount > 0) {
        query += ' OR status = ?';
      } else {
        query = 'status = ?';
      }
      checkCount++;
      args.add(TransactionStatuses.paused);
    }
    if (okoa) {
      if (checkCount > 0) {
        query += ' OR status = ?';
      } else {
        query = 'status = ?';
      }
      checkCount++;
      args.add(TransactionStatuses.hasOkoa);
    }
    if (advanced) {
      if (checkCount > 0) {
        query += ' OR (status = ? OR status = ?)';
      } else {
        query = '(status = ? OR status = ?)';
      }
      checkCount++;
      args.add(TransactionStatuses.advancedUssd);
      args.add(TransactionStatuses.advancedQueue);
    }
    if (retrySuccPending) {
      if (checkCount > 0) {
        query += ' OR (status = ? AND canRetry < ?)';
      } else {
        query = '(status = ? AND canRetry < ?)';
      }
      checkCount++;
      args.add(TransactionStatuses.done);
    }

    List<Map<String, dynamic>> rawStuff = await _sqliteService.queryCustom(
      'transactions',
      '($query) AND timeStamp >= ? AND timeStamp <= ?',
      [...args, startTime, endTime],
      columns: ['id', 'ussdDialed', 'simSubId', 'canRetry', 'ussdReply'],
    );

    for (var stuff in rawStuff) {
      await redoTransaction(stuff['id'], stuff['ussdDialed'], stuff['simSubId'],
          stuff['canRetry'] ?? 0, stuff["ussdReply"]);
    }
  }

  Future<bool> numberIsBlacklisted(int number) async {
    int blacklistExists = await _sqliteService
        .getCount('blacklist', appendQuery: 'WHERE number = ?', args: [number]);

    return blacklistExists > 0;
  }

  Future<void> processReply(
    int number,
    String transactionStatus,
    String firstName,
    String lastName,
    int amount,
  ) async {
    String message = "";

    int condition = TransactionStatuses.statuses.keys.firstWhere(
      (key) => TransactionStatuses.statuses[key] == transactionStatus,
      orElse: () => -1,
    );

    List<Map<String, dynamic>> replies = await _sqliteService.queryCustom(
      'replies',
      '''conditionAmount = 1 AND condition = ? AND (
        amounts LIKE ? OR
        amounts LIKE ? OR
        amounts LIKE ? OR
        amounts LIKE ? OR
        amounts = '[]' OR amounts = ""
      )''',
      [
        condition,
        '[$amount,%',
        '%,$amount,%',
        '%,$amount]',
        '[$amount]',
      ],
      orderBy:
          'CASE WHEN amounts IS NULL OR amounts = "" THEN 1 ELSE 0 END, CAST(amounts AS INTEGER) ASC',
    );

    List<Map<String, dynamic>> matchingReplies = replies.where((reply) {
      String? amounts = reply['amounts'];

      if (amounts == null || amounts.isEmpty) {
        return true;
      }

      try {
        List<dynamic> amountsList = jsonDecode(amounts);

        return amountsList.contains(amount);
      } catch (e) {
        debugPrint('Error parsing amounts JSON: $e');
        return false;
      }
    }).toList();

    if (matchingReplies.isEmpty) {
      matchingReplies = replies;
    }

    //print("Matching replies: $matchingReplies");

    if (matchingReplies.isNotEmpty) {
      message = fillReplyTemplate(
        matchingReplies.first['reply'],
        number: number,
        firstName: firstName,
        lastName: lastName,
        amount: amount,
      );
    }

    List similar = await searchSentSms(
      '254$number',
      message.substring(
        0,
        message.length > 160 ? 160 : message.length,
      ),
      getTodayMidnightMillis(),
    );

    if (similar.isNotEmpty) return;

    sendEvenInBackground('254$number', message);
  }

  Future<String> transactionStatus(List response) async {
    debugPrint("Response: ${response[0]}");

    final String responseText =
        response.isNotEmpty ? response[0].toString() : '';

    // 1) Check custom codes first
    final List<Map<String, dynamic>> customCodes =
        await _sqliteService.getCustomCodes();

    for (final row in customCodes) {
      final String pattern = (row['pattern'] ?? '').toString().trim();
      final String mappedStatus = (row['transactionStatus'] ?? '').toString();
      final bool isCaseSensitive = (row['isCaseSensitive'] ?? 0) == 1;

      if (pattern.isEmpty || mappedStatus.isEmpty) continue;

      final bool matches = isCaseSensitive
          ? responseText.contains(pattern)
          : responseText.toLowerCase().contains(pattern.toLowerCase());

      if (matches) {
        return mappedStatus;
      }
    }

    if (responseText
        .contains(RegExp(r'Invalid choice', caseSensitive: false))) {
      return TransactionStatuses.paused;
    }

    if (responseText == "Success") {
      return TransactionStatuses.error;
    }

    // Successful (Confirmed):
// These messages indicate that the recommendation/purchase has been
// fully confirmed by the network.
    if (RegExp(
      r'successfully recommended offer|successfully purchased|total commission|continue connecting|have purchased',
      caseSensitive: false,
    ).hasMatch(responseText)) {
      debugPrint(
        "TRANSACTION STATUS DEBUG: confirmed success response matched "
        "-> doneConfirmed",
      );
      return TransactionStatuses.doneConfirmed;
    }

// Successful (Pending):
// The recommendation has been submitted successfully, but the final
// confirmation message has not yet been received.
    if (RegExp(
      r'submitted successfully',
      caseSensitive: false,
    ).hasMatch(responseText)) {
      debugPrint(
        "TRANSACTION STATUS DEBUG: submitted success response matched "
        "-> successfulPending",
      );
      return TransactionStatuses.successfulPending;
    }

    if (RegExp(
            r'bundle activation request has failed|okoa|pool state|Authentication failure',
            caseSensitive: false)
        .hasMatch(responseText)) {
      return TransactionStatuses.hasOkoa;
    }

    if (RegExp(
      r'USSD session already in progress',
      caseSensitive: false,
    ).hasMatch(responseText)) {
      return TransactionStatuses.error;
    }

    if (RegExp(r'max number of menu|error from application23',
            caseSensitive: false)
        .hasMatch(responseText)) {
      return TransactionStatuses.error;
    }

    if (RegExp(r'connection code error|one minute', caseSensitive: false)
        .hasMatch(responseText)) {
      return TransactionStatuses.timedOut;
    }

    if (RegExp(r'queue', caseSensitive: false).hasMatch(responseText)) {
      return TransactionStatuses.advancedQueue;
    }

    if (RegExp(
      r'error|duplicate|not available|unavailable|max number|try again|apologize|invalid|sorry|mmi complete|timed out',
      caseSensitive: false,
    ).hasMatch(responseText)) {
      return TransactionStatuses.error;
    }

    if (RegExp(r'already', caseSensitive: false).hasMatch(responseText)) {
      return TransactionStatuses.secondAttempt;
    }

    debugPrint(
      "TRANSACTION STATUS DEBUG: no success pattern matched. "
      "response=[$responseText], existingStatus=[${response[1]}]",
    );

    return response[1];
  }

  Future<int?> transactGivenUssdAndDialSim(
    String ussdCode,
    int simSubId,
    int amount,
    bool isAdvanced,
    int number, {
    String? message,
    String? forwardingJobId,
    String? forwardingTransactionId,
    String? forwardingSenderDeviceName,
    String? forwardingRecipientDeviceName,
  }) async {
    bool hasPaid = await _paymentOps.hasActiveSubscription();

    bool isUsingToken = false;

    // bool hasPaid = await _paymentOps.hasActiveSubscription();

    if (!hasPaid) {
      bool canRenew = await _sharedPreferencesService.getAutoRenew() ?? false;
      int tokenBalance =
          await _sharedPreferencesService.getDeliveryTokens() ?? 0;

      if (tokenBalance > 0) {
        isUsingToken = true;
      } else if (canRenew) {
        // get last entry from payments table
        List<String> reply = await _paymentOps.autoRenewSubscription();

        if (reply[1] != TransactionStatuses.done) {
          return await dontProcess(
            message ?? "",
            "00",
            number,
            ussdCode,
            amount,
            simSubId,
            source: "manual",
            reply: 'No subscription found. Please renew.',
          );
        }
      } else {
        return dontProcess(
          message ?? "",
          "00",
          number,
          ussdCode,
          amount,
          simSubId,
          source: "manual",
        );
      }
    }

    List<dynamic> response = [];

    if (isAdvanced) {
      if (forwardingJobId != null && forwardingJobId.isNotEmpty) {
        debugPrint(
          'ALT USSD: advanced request started jobId=$forwardingJobId',
        );
      }
      String transStatus = TransactionStatuses.advancedUssd;
      String msg = 'Advanced. Added to queue.';

      bool anotherRunning = PhoneService.isRunning;

      if (anotherRunning) {
        transStatus = TransactionStatuses.error;
        msg = "Waiting for turn ...";
        return await dontProcess(
          message ?? "",
          "00",
          number,
          ussdCode,
          amount,
          simSubId,
          status: transStatus,
          reply: msg,
          canRetry: true,
          source: "manual",
        );
      }

      response = await _phoneService.makeAdvancedRequest(
        ussdCode,
        simSubId,
      );
    } else {
      response = await _phoneService.makeMyRequest(
        ussdCode,
        simSubId,
      );
    }

    if (isUsingToken &&
        (response[1] == TransactionStatuses.done ||
            response[1] == TransactionStatuses.advancedUssd)) {
      await _paymentOps.deductSingleToken();
    }

    response[1] = await transactionStatus(response);

    final insertedId = await _sqliteService.insertStuff(
      {
        'initialMessage': message ?? 'Manual',
        'transactionId': forwardingTransactionId ?? '',
        'number': number,
        'date': getNormalDate(DateTime.now()),
        'time': getNormalTime(DateTime.now()),
        'ussdDialed': ussdCode,
        'ussdReply': response[0],
        'amount': amount,
        'smsDate': getNormalDate(DateTime.now()),
        'smsTime': getNormalTime(DateTime.now()),
        'simSubId': simSubId,
        'status': response[1],
        'timeStamp': DateTime.now().millisecondsSinceEpoch,
        'canRetry': 1,
        'forwardingJobId': forwardingJobId ?? '',
        'forwardingSenderDeviceName': forwardingSenderDeviceName ?? '',
        'forwardingRecipientDeviceName': forwardingRecipientDeviceName ?? '',
        'source': 'manual',
      },
      'transactions',
    );
    debugPrint(
      'ALT USSD STORED: localTransactionId=$insertedId, '
      'forwardingTransactionId=${forwardingTransactionId ?? ''}, '
      'forwardingJobId=${forwardingJobId ?? ''}, '
      'sender=${forwardingSenderDeviceName ?? ''}, '
      'recipient=${forwardingRecipientDeviceName ?? ''}',
    );

    if (forwardingJobId != null &&
        forwardingJobId.isNotEmpty &&
        forwardingSenderDeviceName != null &&
        forwardingSenderDeviceName.isNotEmpty) {
      if (response[1] != TransactionStatuses.doneConfirmed) {
        debugPrint(
          'ALT USSD: status=${response[1]} is not final; '
          'waiting for doneConfirmed jobId=$forwardingJobId, '
          'localTransactionId=$insertedId',
        );
        return insertedId;
      }

      debugPrint(
        'ALT FORWARD RESULT: '
        'localTransactionId=$insertedId, '
        'forwardingTransactionId=$forwardingTransactionId, '
        'forwardingJobId=$forwardingJobId, '
        'status=${response[1]}, '
        'senderDevice=$forwardingSenderDeviceName',
      );

      final senderDeviceName =
          (await _sharedPreferencesService.getDeviceName()) ?? '';

      final result = await BackendService().post(
        '/api/fcm/send-secure',
        body: {
          'title': 'BSAT Online Forwarding',
          'body': 'Alternative USSD execution result',
          'senderDeviceName': senderDeviceName,
          'recipientDeviceName': forwardingSenderDeviceName,
          'data': {
            'type': 'forwarded_alt_result',
            'transactionId': insertedId.toString(),
            'forwardingJobId': forwardingJobId,
            'status': response[1],
            'ussdReply': response[0]?.toString() ?? '',
            'senderDeviceName': senderDeviceName,
            'recipientDeviceName': forwardingSenderDeviceName,
          },
        },
      );
      debugPrint(
        'ALT RESULT: sent immediate non-advanced result '
        'jobId=$forwardingJobId, status=${response[1]}, result=$result',
      );
    }

    return insertedId;
  }

  String replaceNWithNumber(String ussdCode, int number) {
    return ussdCode.replaceAll(RegExp(r'n'), '0$number');
  }

  Future<double> getThisWeekCommision() async {
    List sales = await _sqliteService.queryCustom(
      'transactions',
      'timeStamp >= ? AND ussdDialed LIKE "%*180*%"',
      [getLastSundayMidnightMillis()],
    );

    double totalAmount =
        sales.fold(0, (sum, sale) => sum + (sale['amount'] ?? 0));
    return (totalAmount * 0.1);
  }

  Future<bool> isAdvanced(String code) async {
    String ussdRaw = getCodeFromUssd(code);

    // Note: `ussdCodes` has no `code` column (it only lives on
    // `ussdCodeVariants`), so there is no legacy table to fall back to.
    List offers = await _sqliteService.queryCustom(
      'ussdCodeVariants',
      'code = ?',
      [ussdRaw],
      columns: ['isAdvanced'],
    );

    return offers.isNotEmpty && offers.first['isAdvanced'] == 1;
  }

  String getCodeFromUssd(String code) {
    // Extract the 10-digit number from the USSD code
    RegExp amountRegex = RegExp(r'\d{10}');
    RegExpMatch? amountMatch = amountRegex.firstMatch(code);

    if (amountMatch != null) {
      // Get the matched amount
      String amount = amountMatch.group(0)!;

      // Replace the amount with 'n'
      String modifiedCode = code.replaceFirst(amount, 'n');

      return modifiedCode;
    }

    // Return original code if no match is found
    return code;
  }

  Future<void> updateWithMessage(TransactionMessage smsMessage) async {
    final confirmationBody = smsMessage.body ?? '';
    final isGiftConfirmation = RegExp(
      r'you\s+have\s+gifted',
      caseSensitive: false,
    ).hasMatch(confirmationBody);
    final hasCaringPhrase = RegExp(
      r'thank\s+you\s+for\s+caring',
      caseSensitive: false,
    ).hasMatch(confirmationBody);

    if (isGiftConfirmation && hasCaringPhrase) {
      debugPrint('SAFARICOM CONFIRMATION: confirmation SMS detected');

      // This confirmation SMS carries the offer price, while its recipient
      // phone number may be masked. Use the amount to locate the original
      // advanced transaction; proceed only when the match is unambiguous.
      final amountMatch = RegExp(
        r'\b(?:kshs?|kes)\s*([\d,]+)(?:\.\d+)?',
        caseSensitive: false,
      ).firstMatch(confirmationBody);
      final amount = int.tryParse(
        amountMatch?.group(1)?.replaceAll(',', '') ?? '',
      );
      debugPrint(
        'SAFARICOM CONFIRMATION: Safaricom amount=${amount ?? 'unknown'}',
      );

      final recipientMatch = RegExp(
        r'\bto\s+([+\d\s().-]*\*{2,})',
        caseSensitive: false,
      ).firstMatch(confirmationBody);
      final maskedRecipient = recipientMatch?.group(1) ?? '';
      var visibleRecipientPrefix = normalizeIncomingCallNumber(
        maskedRecipient.replaceAll('*', ''),
      );
      if (!visibleRecipientPrefix.startsWith('0') &&
          visibleRecipientPrefix.length >= 7 &&
          visibleRecipientPrefix.length <= 9) {
        visibleRecipientPrefix = '0$visibleRecipientPrefix';
      }
      if (visibleRecipientPrefix.isEmpty) {
        debugPrint(
          'SAFARICOM CONFIRMATION: could not extract masked recipient prefix',
        );
        return;
      }

      debugPrint(
        'SAFARICOM CONFIRMATION: amount=$amount, '
        'maskedRecipientPrefix=$visibleRecipientPrefix',
      );

      final smsTimestamp = smsMessage.date;
      if (smsTimestamp == null || smsTimestamp <= 0) {
        debugPrint(
          'SAFARICOM CONFIRMATION: missing SMS timestamp; leaving unresolved',
        );
        return;
      }

      final recipientDigits =
          visibleRecipientPrefix.replaceAll(RegExp(r'\D'), '');
      final nationalPrefix = recipientDigits.startsWith('0')
          ? recipientDigits.substring(1)
          : recipientDigits;
      final diagnosticRows = await _sqliteService.queryCustom(
        'transactions',
        'amount = ? OR CAST(number AS TEXT) LIKE ? OR '
            'CAST(number AS TEXT) LIKE ?',
        [amount ?? -1, '$nationalPrefix%', '254$nationalPrefix%'],
        columns: ['id', 'number', 'amount', 'status', 'timeStamp'],
        orderBy: 'timeStamp DESC',
      );

      for (final row in diagnosticRows) {
        final transactionId = row['id'];
        final rawNumber = row['number']?.toString() ?? '';
        final rawNumberDigits = rawNumber.replaceAll(RegExp(r'\D'), '');
        var normalizedNumber = normalizeIncomingCallNumber(rawNumber);
        if (normalizedNumber.length == 9 &&
            !rawNumberDigits.startsWith('254')) {
          normalizedNumber = '0$normalizedNumber';
        }
        final transactionAmount = int.tryParse(row['amount']?.toString() ?? '');
        final transactionTimestamp =
            int.tryParse(row['timeStamp']?.toString() ?? '');
        final transactionStatus = row['status']?.toString() ?? '';
        final amountMatched = transactionAmount == amount;
        final recipientPrefixMatched =
            normalizedNumber.startsWith(visibleRecipientPrefix);
        const timestampCorrelationWindowMs = 2 * 60 * 1000;
        final timestampMatched = transactionTimestamp != null &&
            (transactionTimestamp - smsTimestamp).abs() <=
                timestampCorrelationWindowMs;
        final statusMatched =
            transactionStatus == TransactionStatuses.advancedUssd ||
                transactionStatus == TransactionStatuses.successfulPending;

        if (!amountMatched ||
            !recipientPrefixMatched ||
            !timestampMatched ||
            !statusMatched) {
          debugPrint(
            'SAFARICOM CONFIRMATION DIAGNOSTIC: '
            'id=$transactionId, number=$rawNumber, '
            'amount=${row['amount']}, status=$transactionStatus, '
            'transactionTimestamp=${row['timeStamp']}, '
            'smsTimestamp=$smsTimestamp, '
            'normalizedNumber=$normalizedNumber, '
            'normalizedSmsPrefix=$visibleRecipientPrefix, '
            'amountMatched=$amountMatched, '
            'recipientPrefixMatched=$recipientPrefixMatched, '
            'timestampMatched=$timestampMatched, '
            'statusMatched=$statusMatched',
          );
        }
      }

      final amountAndStatusMatches = await _sqliteService.queryCustom(
        'transactions',
        'status IN (?, ?)',
        [
          TransactionStatuses.advancedUssd,
          TransactionStatuses.successfulPending,
        ],
        orderBy: 'timeStamp DESC',
      );

      final candidates = <Map<String, dynamic>>[];
      for (final transaction in amountAndStatusMatches) {
        final transactionTimestamp = int.tryParse(
          transaction['timeStamp']?.toString() ?? '',
        );
        const timestampCorrelationWindowMs = 2 * 60 * 1000;
        if (transactionTimestamp == null ||
            (transactionTimestamp - smsTimestamp).abs() >
                timestampCorrelationWindowMs) {
          debugPrint(
            'SAFARICOM CONFIRMATION: rejecting candidate '
            'id=${transaction['id']} due to timestamp outside '
            '${timestampCorrelationWindowMs}ms correlation window',
          );
          continue;
        }

        final rawNumber = transaction['number']?.toString() ?? '';
        final rawNumberDigits = rawNumber.replaceAll(RegExp(r'\D'), '');
        var normalizedNumber = normalizeIncomingCallNumber(rawNumber);
        if (normalizedNumber.length == 9 &&
            !rawNumberDigits.startsWith('254')) {
          normalizedNumber = '0$normalizedNumber';
        }

        if (!normalizedNumber.startsWith(visibleRecipientPrefix)) {
          debugPrint(
            'SAFARICOM CONFIRMATION: rejecting candidate '
            'id=${transaction['id']} due to recipient prefix',
          );
          continue;
        }
        candidates.add(transaction);
      }

      debugPrint(
        'SAFARICOM CONFIRMATION: eligible candidates=${candidates.length}',
      );

      if (candidates.length != 1) {
        debugPrint(
          candidates.isEmpty
              ? 'SAFARICOM CONFIRMATION: zero candidates; leaving unresolved'
              : 'SAFARICOM CONFIRMATION: multiple candidates; '
                  'leaving unresolved',
        );
        return;
      }

      final candidate = candidates.first;
      final transactionId = candidate['id'];
      final previousStatus = candidate['status']?.toString() ?? '';
      debugPrint(
        'SAFARICOM CONFIRMATION: transaction=$transactionId '
        'statusBefore=$previousStatus amount=$amount',
      );

      final updatedRows = await _sqliteService.updateStuff(
        {
          'status': TransactionStatuses.doneConfirmed,
          'ussdReply': '${confirmationBody.trim()}\n$interpunct '
              '${candidate['ussdReply'] ?? ''}',
          'timeStamp': DateTime.now().millisecondsSinceEpoch,
          'canRetry': 0,
        },
        'id = ? AND status IN (?, ?)',
        [
          transactionId,
          TransactionStatuses.advancedUssd,
          TransactionStatuses.successfulPending,
        ],
        'transactions',
      );

      final updated = await _sqliteService.queryCustom(
        'transactions',
        'id = ?',
        [transactionId],
        limit: 1,
      );
      final updatedStatus = updated.firstOrNull?['status']?.toString();
      debugPrint(
        'SAFARICOM CONFIRMATION: transaction=$transactionId '
        'statusAfter=$updatedStatus',
      );

      if (updatedRows == 1 &&
          updatedStatus == TransactionStatuses.doneConfirmed) {
        debugPrint(
          'SAFARICOM CONFIRMATION: confirmed transaction=$transactionId',
        );
        final forwardingJobId = candidate['forwardingJobId']?.toString() ?? '';
        final forwardingSender =
            candidate['forwardingSenderDeviceName']?.toString() ?? '';
        if (forwardingJobId.isNotEmpty && forwardingSender.isNotEmpty) {
          if (candidate['source']?.toString() == 'manual') {
            final finalReply = updated.firstOrNull?['ussdReply']?.toString() ??
                confirmationBody.trim();
            debugPrint(
              'ALT CONFIRMED: Safaricom confirmation matched '
              'jobId=$forwardingJobId, localTransactionId=$transactionId',
            );
            await _sendForwardedAlternativeResult(
              forwardingJobId: forwardingJobId,
              recipientDeviceName: forwardingSender,
              transactionId: transactionId.toString(),
              ussdReply: finalReply,
            );
          } else {
            debugPrint(
              'SAFARICOM CONFIRMATION: sending forwarding ACK '
              'for transaction=$transactionId',
            );
            await _sendForwardingConfirmation(
              forwardingJobId: forwardingJobId,
              recipientDeviceName: forwardingSender,
              transactionId: transactionId.toString(),
            );
          }
        }
      }
      return;
    }

    int number = extract9DigitNumber(smsMessage.body ?? "");

    if (number == 0) {
      return;
    }

    int twentyMinuteAgo = DateTime.now().millisecondsSinceEpoch - 1200000;
    int replyAmount = getAmount(smsMessage.body ?? "0");

    List<Map<String, dynamic>> rawStuff = await _sqliteService.queryCustom(
      'transactions',
      'number = ? AND timeStamp >= ? ',
      [
        number,
        twentyMinuteAgo,
      ],
      columns: [
        'id',
        'status',
        'ussdReply',
        'amount',
        'source',
        'ussdDialed',
        'firstFailedTimeStamp'
      ],
    );

    if (rawStuff.isEmpty) {
      return;
    }

    if (rawStuff.first['amount'] < getAmount(smsMessage.body ?? "1")) {}

    int amount = rawStuff.isNotEmpty
        ? rawStuff.first['amount'] ?? 0
        : getAmount(smsMessage.body ?? "");

    if (rawStuff.length == 1 &&
        replyAmount != 0 &&
        amount != 0 &&
        (amount < replyAmount * 0.69 || amount > replyAmount * 1.31)) {
      _sharedPreferencesService.setOffersMightHaveChanged(true);
    }

    String status = rawStuff.isNotEmpty ? rawStuff.first['status'] : '';
    final isAlternativeExecution =
        status == TransactionStatuses.alternativeExecuting;

    if (status != TransactionStatuses.doneConfirmed) {
      if (status != TransactionStatuses.advancedQueue &&
          status != TransactionStatuses.advancedUssd &&
          !isAlternativeExecution) {
        status = TransactionStatuses.done;
      }

//     Thank You For Choosing Safaricom. You have purchased Tunukiwa Legacy Daily Data for 746234392. Continue connecting with Family & Friends!
//     · You have successfully recommended offer to 0746234392. Total Commission this week is Ksh.5867.3. Keep Selling, be a Bingwa Sokoni!!
//     · Recommendation for 0746234392 submitted successfully. Keep selling!! Be a Bingwa Sokoni Champion.

      final body = smsMessage.body ?? '';

      final bool purchaseConfirmed = RegExp(
        r'thank\s+you\s+for\s+choosing\s+safaricom'
        r'.*?you\s+have\s+purchased\s+.+?'
        r'(?:for\s+\d+)?',
        caseSensitive: false,
        dotAll: true,
      ).hasMatch(body);

      final bool recommendationSubmitted = RegExp(
        r'recommendation\s+for\s+\d+\s+submitted\s+successfully',
        caseSensitive: false,
      ).hasMatch(body);

      final bool recommendationSuccessful = RegExp(
        r'you\s+have\s+successfully\s+recommended\s+offer',
        caseSensitive: false,
      ).hasMatch(body);

      if (purchaseConfirmed) {
        status = TransactionStatuses.doneConfirmed;
      } else if (recommendationSubmitted || recommendationSuccessful) {
        status = TransactionStatuses.successfulPending;
      }

      if (RegExp(
        r'Recommendation failed',
        caseSensitive: false,
      ).hasMatch(smsMessage.body ?? "")) {
        if (isAlternativeExecution) {
          status = TransactionStatuses.alternativeFailed;
        } else {
          status = TransactionStatuses.secondAttempt;

          debugPrint('ALTERNATIVE TIMER: '
              'transactionId=${rawStuff.first['id']}, '
              'existingFirstFailedTimeStamp=${rawStuff.first['firstFailedTimeStamp']}, ');
        }
      }
    }
    if (rawStuff.isNotEmpty) {
      //print("Updating advanced request");
      await _sqliteService.updateOnly(
        status == TransactionStatuses.secondAttempt
            ? "UPDATE transactions SET ussdReply = ?, status = ?, firstFailedTimeStamp = COALESCE(firstFailedTimeStamp, ?) WHERE id = ?"
            : "UPDATE transactions SET ussdReply = ?, status = ? WHERE id = ?",
        status == TransactionStatuses.secondAttempt
            ? [
                "${smsMessage.body} \n$interpunct ${rawStuff.first['ussdReply']}",
                status,
                DateTime.now().millisecondsSinceEpoch,
                rawStuff.first['id'],
              ]
            : [
                "${smsMessage.body} \n$interpunct ${rawStuff.first['ussdReply']}",
                status,
                rawStuff.first['id'],
              ],
      );
      if (status == TransactionStatuses.doneConfirmed) {
        final confirmedTx = await _sqliteService.queryCustom(
          'transactions',
          'id = ?',
          [rawStuff.first['id']],
          limit: 1,
        );
        final forwardingJobId =
            confirmedTx.firstOrNull?['forwardingJobId']?.toString();
        final forwardingSender =
            confirmedTx.firstOrNull?['forwardingSenderDeviceName']?.toString();
        if (forwardingJobId != null &&
            forwardingJobId.isNotEmpty &&
            forwardingSender != null &&
            forwardingSender.isNotEmpty) {
          await _sendForwardingConfirmation(
            forwardingJobId: forwardingJobId,
            recipientDeviceName: forwardingSender,
            transactionId: rawStuff.first['id'].toString(),
          );
        }
      }
      processReply(
        number,
        status,
        (rawStuff.firstOrNull?['source'] ?? 'unknown').split(' ')[0],
        (rawStuff.firstOrNull?['source'] ?? 'unknown').split(' ').length > 1
            ? (rawStuff.firstOrNull?['source'] ?? 'unknown').split(' ')[1]
            : '',
        amount,
      );
    }
  }

  String alterMpesaMessage(String smsMessage, int amount) {
    return smsMessage.replaceFirst(
      RegExp(
        r'(?:(((K?)sh(s?)[\s:]?)|kes[\s:]?)(\d{1,6}(?:,\d{3})*(?:\.\d+)?))|(\d{1,6}(?:,\d{3})*(?:\.\d+)?)[\s:]?((K?)sh(s?)|kes)',
        caseSensitive: false,
      ),
      'Ksh$amount',
    );
  }

  String fillReplyTemplate(
    String template, {
    required int number,
    String? firstName,
    String? lastName,
    int? amount,
  }) {
    return template
        .replaceAll('grti?', getGreeting(withEmoji: false))
        .replaceAll('numb?', number.toString())
        .replaceAll('fnam?', firstName ?? '')
        .replaceAll('lnam?', lastName ?? '')
        .replaceAll('amnt?', amount?.toString() ?? '')
        .replaceAll('time?', getNormalTime(DateTime.now()))
        .replaceAll('date?', getNormalDate(DateTime.now()))
        .replaceAll('dayw?', getDayOfWeek(DateTime.now()));
  }

  Future<void> recordClientPurchase(
      String phoneNumber, String senderName) async {
    final clientService = ClientService();

    // Check if client exists
    Client? existingClient = await clientService.getClientByPhone(phoneNumber);

    if (existingClient != null) {
      // Update existing client
      final updatedClient = existingClient.copyWith(
        lastBought: DateTime.now(),
        noOfPurchases: existingClient.noOfPurchases + 1,
      );
      await clientService.updateClient(updatedClient);
    } else {
      // Create new client
      final nameParts = senderName.trim().split(' ');
      final firstName = nameParts.isNotEmpty ? nameParts.first : 'Unknown';
      final lastName =
          nameParts.length > 1 ? nameParts.skip(1).join(' ') : 'Client';

      final newClient = Client(
        firstName: firstName,
        lastName: lastName,
        phoneNumber: phoneNumber,
        createdAt: DateTime.now(),
        lastBought: DateTime.now(),
        noOfPurchases: 1,
      );

      await clientService.insertClient(newClient);
    }
  }

  Future<String> selectBongaUssdCode(int id) async {
    // Load the ussdCodes row
    List<Map<String, dynamic>> ussdCodeItem = await _sqliteService.queryCustom(
      'ussdCodes',
      'id = ?',
      [id],
    );

    if (ussdCodeItem.isEmpty) return '';

    final row = ussdCodeItem.first;

    debugPrint('USSD DEBUG: ussdCodes row for id=$id: $row');

    final variants = await _sqliteService.queryCustom(
      'ussdCodeVariants',
      'ussdCodeId = ?',
      [id],
    );

    debugPrint('USSD DEBUG: variants for id=$id: $variants');

// choose active variant code for this ussdCode id
    String activeCode = await _getActiveVariantCode(row['id']);

    debugPrint('USSD DEBUG: activeCode for id=$id: "$activeCode"');

    if (row['usesBongaPoints'] == null || row['usesBongaPoints'] == 0) {
      return activeCode;
    }

    List<dynamic> reply = await _phoneService.makeMyRequest(
      row['balanceCheckCode'],
      row['dialSim'],
    );

    int bongaBalance = await getBongaBalance(reply[0]);

    if (bongaBalance > (row['bongaPointsPerTransaction'] ?? 0)) {
      return activeCode;
    }

    return row['fallbackCode'] ?? activeCode;
  }

  Future<String> _getActiveVariantCode(int ussdCodeId) async {
    try {
      final variant = await _getActiveVariantRow(ussdCodeId);

      if (variant == null) {
        return '';
      }

      return variant['code']?.toString() ?? '';
    } catch (e) {
      return '';
    }
  }

  Future<Map<String, dynamic>?> _getActiveVariantRow(int ussdCodeId) async {
    final variants = await _sqliteService.queryCustom(
      'ussdCodeVariants',
      'ussdCodeId = ?',
      [ussdCodeId],
    );

    if (variants.isEmpty) {
      return null;
    }

    final now = DateTime.now();
    final curMin = now.hour * 60 + now.minute;

    Map<String, dynamic>? fallback;
    for (final variant in variants) {
      fallback ??= variant;
      final s = variant['startTime']?.toString() ?? '';
      final e = variant['endTime']?.toString() ?? '';
      if (s.isEmpty && e.isEmpty) return variant;
      if (s.isEmpty || e.isEmpty) return variant;

      try {
        final sParts = s.split(':');
        final eParts = e.split(':');
        final sMin = int.parse(sParts[0]) * 60 + int.parse(sParts[1]);
        final eMin = int.parse(eParts[0]) * 60 + int.parse(eParts[1]);
        if (sMin <= eMin) {
          if (curMin >= sMin && curMin < eMin) return variant;
        } else {
          if (curMin >= sMin || curMin < eMin) return variant;
        }
      } catch (_) {
        return variant;
      }
    }

    return fallback;
  }

  Future<Map<String, dynamic>?> _getActiveVariantWithLegacyFallback(
    int ussdCodeId,
  ) async {
    final variantRow = await _getActiveVariantRow(ussdCodeId);
    final legacyRows = await _sqliteService.queryCustom(
      'ussdCodes',
      'id = ?',
      [ussdCodeId],
      limit: 1,
    );

    if (variantRow == null) {
      return legacyRows.isNotEmpty
          ? Map<String, dynamic>.from(legacyRows.first)
          : null;
    }

    // Query rows from sqflite are read-only; copy before mutating below.
    final variant = Map<String, dynamic>.from(variantRow);

    if (legacyRows.isNotEmpty) {
      final legacy = legacyRows.first;
      variant['alternativeUssdCode'] ??= legacy['alternativeUssdCode'];
      variant['runAltOn'] ??= legacy['runAltOn'];
      variant['altIsAdvanced'] ??= legacy['altIsAdvanced'];
      variant['altDelayMinutes'] ??= legacy['altDelayMinutes'];
    }

    return variant;
  }

  Future<Map<String, dynamic>> getOfferSignature(
      String code, int number, int simSubId) async {
    code = replaceNWithNumber(code, number);
    PhoneService phoneService = PhoneService();
    return (await phoneService.makeMyRequest(
      code,
      simSubId,
    ))[2];
  }

  Future<void> unmaskFromCall(String number) async {
    number = normalizeIncomingCallNumber(number);

    if (number.isEmpty) {
      return;
    }

    // llok for transactions with status masked which can
    // fit the number in the initialMessage

    List<Map<String, dynamic>> transactions = await _sqliteService.queryCustom(
      'transactions',
      'status = ?',
      [TransactionStatuses.masked],
    );

    for (var transaction in transactions) {
      String initialMessage = transaction['initialMessage'] ?? '';
      String? unmaskedReply = unmaskNumberInMessage(number, initialMessage);

      if (unmaskedReply != null) {
        int? newTxId = await makeTransactionGivenSmsBody(unmaskedReply);
        if (newTxId != null) {
          await purgeAndMerge(newTxId, transaction['id']);
        }
        return;
      }
    }

    // unmaskNumberInMessage(number, message)
  }

  Future<UssdCode> getUssdCodeForAmount(int amount) async {
    List response = await _sqliteService.queryCustom(
      'ussdCodes',
      'amount = ?',
      [amount],
    );

    if (response.isEmpty) {
      // Return a default UssdCode
      return UssdCode(
        id: -1,
        code: '',
        amount: 0,
        fromSim: -1,
        canRetry: false,
        isAdvanced: false,
        enabled: false,
      );
    }

    final ussdId = response.first['id'];
    final variantCode = await _getActiveVariantCode(ussdId);

    return UssdCode(
      id: response.first['id'],
      code: variantCode,
      amount: response.first['amount'] ?? 0,
      fromSim: response.first['fromSim'],
      canRetry: response.first['canRetry'] != 0,
      isAdvanced: response.first['isAdvanced'] != 0,
      enabled: response.first['enabled'] != 0,
    );
  }

  // check if sms message has "please call" and if it does,
  // extract the number from the address and look for a transaction
  // that is TransactionStatuses.paused with that hashed number in the message
  // and unmask the message and return it
  Future<String?> sortClientText(SmsMessage message) async {
    if (message.body != null
        // &&
        //     RegExp(r'please call|tried to|tried calling', caseSensitive: false)
        //         .hasMatch(message.body!)
        ) {
      int number = extract9DigitNumber(message.address ?? "");
      int numberInText = extract9DigitNumber(message.body ?? "");

      // remove leading 254 if present
      if (number.toString().startsWith('254')) {
        number = int.parse(number.toString().substring(3));
      }

      List<Map<String, dynamic>> pausedTransactions = await _sqliteService
          .queryCustom('transactions', 'status = ? OR status = ?',
              [TransactionStatuses.masked, TransactionStatuses.paused]);

      if (pausedTransactions.isNotEmpty) {
        for (var transaction in pausedTransactions) {
          String initialMessage = transaction['initialMessage'] ?? '';
          String? unmaskedReply =
              unmaskNumberInMessage('0$number', initialMessage);

          if (unmaskedReply != null) {
            int? newTxId = await makeTransactionGivenSmsBody(unmaskedReply);
            if (newTxId != null) {
              await purgeAndMerge(newTxId, transaction['id']);
            }
            return unmaskedReply;
          }

          unmaskedReply =
              unmaskNumberInMessage('0$numberInText', initialMessage);
          if (unmaskedReply != null) {
            int? newTxId = await makeTransactionGivenSmsBody(unmaskedReply);
            if (newTxId != null) {
              await purgeAndMerge(newTxId, transaction['id']);
            }
            return unmaskedReply;
          }
        }
      }

      // check message content for a valid phone number(s) using extract9DigitNumber
      sortMessageContent(message);
    }
    return null;
  }

  Future<String?> sortMessageContent(SmsMessage smsMessage) async {
    // reply might contain phone number.
    int number = extract9DigitNumber(smsMessage.body ?? "");

    String mpesaCode = getMpesaCode(smsMessage.body ?? "");

    if (number == 0) return null;

    Map<String, dynamic>? transaction = (await _sqliteService.queryCustom(
      'transactions',
      '(status = ? OR status = ?) AND transactionId = ?',
      [TransactionStatuses.masked, TransactionStatuses.paused, mpesaCode],
    ))
        .firstOrNull;

    if (transaction == null) return null;

    // for (var transaction in transactions) {
    String initialMessage = transaction['initialMessage'] ?? '';
    String? unmaskedReply = unmaskNumberInMessage('0$number', initialMessage);

    if (unmaskedReply != null) {
      // new client
      Client client = Client.fromMpesaMessage(unmaskedReply);

      await recordClientPurchase(
          client.phoneNumber, "${client.firstName} ${client.lastName}");

      int? newTxId = await makeTransactionGivenSmsBody(unmaskedReply);
      if (newTxId != null) {
        await purgeAndMerge(newTxId, transaction['id']);
      }
      return unmaskedReply;
    }

    return null;
  }

  String normalizeIncomingCallNumber(String? number) {
    if (number == null || number.trim().isEmpty) {
      return '';
    }

    String normalized = number.replaceAll(RegExp(r'[^0-9+]'), '');

    if (normalized.startsWith('+254')) {
      normalized = '0${normalized.substring(4)}';
    } else if (normalized.startsWith('254')) {
      normalized = '0${normalized.substring(3)}';
    }

    if (normalized.length < 7) {
      return '';
    }

    return normalized;
  }

  // autoScheduleFailedRecommendations
  Future<void> autoScheduleFailedRecommendations() async {
    int timestamp24HoursAgo = DateTime.now().millisecondsSinceEpoch -
        Duration(hours: 24).inMilliseconds;

    List<Map<String, dynamic>> failedRecommendations = await _sqliteService
        .queryCustom('transactions', 'status = ? AND timestamp > ?',
            [TransactionStatuses.secondAttempt, timestamp24HoursAgo]);

    for (var recommendation in failedRecommendations) {
      String? initialMessage = recommendation['initialMessage'];

      if (initialMessage != null) {
        initialMessage = "Yesterday's transaction redone: $initialMessage";

        int? newTxId = await makeTransactionGivenSmsBody(initialMessage);
        if (newTxId != null) {
          await purgeAndMerge(newTxId, recommendation['id']);
        }
      }
    }
  }

  /// Batch upload clients to server at midnight ±50 minutes.
  /// Max 1000 clients per day. Sends 50 clients per request.
  /// Tracks last uploaded client ID to resume from where it left off.
  Future<void> uploadClientsToBatchServer() async {
    try {
      const int maxClientsPerDay = 1000;
      const int clientsPerRequest = 50;
      final BackendService backendService = BackendService();

      // Check if we've already uploaded today
      String? lastUploadDate = await getClientBatchUploadDate();
      String todayDate = DateTime.now().toIso8601String().split('T')[0];

      int uploadedToday = 0;

      // Reset counter if it's a new day
      if (lastUploadDate != todayDate) {
        uploadedToday = 0;
        await setClientBatchUploadDate(todayDate);
        await setClientBatchUploadCount(0);
      } else {
        uploadedToday = await getClientBatchUploadCount();
      }

      // Check if we've exceeded daily limit
      if (uploadedToday >= maxClientsPerDay) {
        debugPrint(
            'Client batch upload: Daily limit ($maxClientsPerDay) reached');
        return;
      }

      // Get the last uploaded client ID
      int? lastUploadedId = await getLastUploadedClientId();
      lastUploadedId ??= 0;

      // Query all clients ordered by ID, starting after the last uploaded ID
      List<Map<String, dynamic>> allClients = await _sqliteService.queryAll(
        'clients',
        where: 'id > ?',
        whereArgs: [lastUploadedId],
        orderBy: 'id ASC',
      );

      if (allClients.isEmpty) {
        debugPrint('Client batch upload: No new clients to upload');
        return;
      }

      // Calculate how many clients we can upload today
      int remainingQuota = maxClientsPerDay - uploadedToday;
      int clientsToUpload = min(allClients.length, remainingQuota);

      // Split into batches of 50
      for (int i = 0; i < clientsToUpload; i += clientsPerRequest) {
        int end = min(i + clientsPerRequest, clientsToUpload);
        List<Map<String, dynamic>> batch = allClients.sublist(i, end);

        // Convert batch to Map<int, Map>
        Map<int, Map<String, dynamic>> batchMap = {};
        int lastIdInBatch = 0;

        for (var client in batch) {
          int clientId = client['id'] as int;
          batchMap[clientId] = client;
          lastIdInBatch = clientId;
        }

        try {
          // Send batch to server
          final response = await backendService.post(
            '/api/clients/batch-upload',
            body: {
              'clients': batchMap,
            },
          );

          if (response['success'] == true) {
            // Update last uploaded client ID
            await setLastUploadedClientId(lastIdInBatch);

            // Increment upload count
            int newCount = await getClientBatchUploadCount();
            await setClientBatchUploadCount(newCount + batch.length);

            debugPrint(
                'Client batch upload: Uploaded ${batch.length} clients (total: ${newCount + batch.length}/$maxClientsPerDay)');
          } else {
            debugPrint(
                'Client batch upload failed: ${response['message'] ?? 'Unknown error'}');
            // Don't break, try next batch
          }
        } catch (e) {
          debugPrint('Client batch upload request error: $e');
          // Don't break, try next batch
        }

        // Check if we've reached daily limit
        int totalUploaded = await getClientBatchUploadCount();
        if (totalUploaded >= maxClientsPerDay) {
          debugPrint(
              'Client batch upload: Reached daily limit ($maxClientsPerDay)');
          break;
        }
      }
    } catch (e) {
      debugPrint('Client batch upload error: $e');
    }
  }

  Future<void> purgeAndMerge(int toPurgeId, int toMergeId) async {
    print("PUEREGGEGEGEG");

    // Read the original transaction before deleting it.
    final originalTransaction =
        await _sqliteService.queryOne('transactions', toMergeId);

    // Read the newly created transaction.
    final purgeTransaction = MyTransaction.fromMap(
      await _sqliteService.queryOne('transactions', toPurgeId),
    );

    // The original transaction may contain the forwardingJobId.
    // Preserve it when replacing the original transaction with
    // the newly processed transaction.
    // The original transaction may contain forwarding context.
// Preserve it when replacing the original transaction with
// the newly processed transaction.
    final originalForwardingJobId =
        originalTransaction['forwardingJobId']?.toString();

    final originalForwardingSenderDeviceName =
        originalTransaction['forwardingSenderDeviceName']?.toString();

    if (originalForwardingJobId != null && originalForwardingJobId.isNotEmpty) {
      purgeTransaction.forwardingJobId = originalForwardingJobId;

      debugPrint(
        'PURGE/MERGE: Preserved forwardingJobId=$originalForwardingJobId',
      );
    }

    if (originalForwardingSenderDeviceName != null &&
        originalForwardingSenderDeviceName.isNotEmpty) {
      purgeTransaction.forwardingSenderDeviceName =
          originalForwardingSenderDeviceName;

      debugPrint(
        'PURGE/MERGE: Preserved '
        'forwardingSenderDeviceName=$originalForwardingSenderDeviceName',
      );
    }

    await _sqliteService.deleteStuff(toMergeId, 'transactions');
    await _sqliteService.deleteStuff(toPurgeId, 'transactions');

    purgeTransaction.id = toMergeId;

    await _sqliteService.insertStuff(
      purgeTransaction.toMap(),
      'transactions',
    );
  }
}
