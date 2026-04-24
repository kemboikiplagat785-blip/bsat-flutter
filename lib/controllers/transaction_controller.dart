import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:another_telephony/telephony.dart';
import 'package:bsat/services/auth_service.dart';
import 'package:bsat/services/backend_service.dart';
import 'package:bsat/services/contacts_service.dart';
import 'package:bsat/services/payments.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:bsat/utils/date_ops.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';

import '../models/client.dart';
import '../models/code_signature.dart';
import '../models/transaction_message.dart';
import '../models/ussd_code.dart';
import '../services/client_service.dart';
import '../services/shared_preferences_service.dart';

// import '../services/skills.dart';
import '../services/sms_sevice.dart';
import '../services/phone_service.dart';

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

  Future<void> makeTransactionGivenSmsBody(String smsBody,
      {String? address}) async {
    TransactionMessage fakeMessage = TransactionMessage(
      body: smsBody,
      date: DateTime.now().millisecondsSinceEpoch,
      address: address,
    );

    makeTransaction(fakeMessage);
  }

  void makeTransaction(TransactionMessage smsMessage) async {
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

    String transactionId = getMpesaCode(smsMessage.body ?? "");
    int number = extract9DigitNumber(smsMessage.body ?? "");
    int amount = getAmount(smsMessage.body);
    String name = getName(smsMessage.body ?? "");

    Client client = Client.fromMpesaMessage(smsMessage.body ?? "");

    // print(number);

    String trimmedBody = smsMessage.body!.length > 160
        ? smsMessage.body!.substring(0, 160)
        : smsMessage.body!;

    if (number == 0 ||
        client.formattedPhone == null ||
        client.formattedPhone!.length < 9) {
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
          await forwardIfNeeded(
            amount,
            trimmedBody,
            smsMessage.body ?? "",
            transactionId,
            number,
            name,
            autoSaveContacts,
            status: TransactionStatuses.forwarded,
          );
        } else {
          dontProcess(
            smsMessage.body ?? "",
            transactionId,
            number,
            '',
            amount,
            -1,
            status: TransactionStatuses.masked,
            reply: 'Could not extract a valid phone number from the message.',
            canRetry: false,
            source: name,
          );

          if (smsMessage.address == "MPESA" &&
              smsMessage.body!.contains("***")) {
            sendEvenInBackground('334', smsMessage.body ?? "",
                sendFirstPartOnly: true);
          }
        }

        return;
      }
    }

    UssdCode ussdCodeItem = await getUssdCodeForAmount(amount);

    bool blacklistExists = await numberIsBlacklisted(number);

    if (blacklistExists) {
      dontProcess(
        smsMessage.body ?? "",
        transactionId,
        number,
        '',
        amount,
        -1,
        status: TransactionStatuses.blacklisted,
        reply: 'Number is blacklisted',
        canRetry: false,
        source: name,
      );
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

      return;
    }

    // if()

    if ((await forwardIfNeeded(
      amount,
      trimmedBody,
      smsMessage.body ?? "",
      transactionId,
      number,
      name,
      autoSaveContacts,
    ))) {
      return;
    }

    bool offersMightHaveChanged =
        await _sharedPreferencesService.getOffersMightHaveChanged() ?? false;

    if (offersMightHaveChanged) {
      dontProcess(
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

      processReply(
        number,
        TransactionStatuses.paused,
        name.split(' ')[0],
        name.trim().split(RegExp(r'\s+')).length > 1
            ? name.trim().split(RegExp(r'\s+'))[1]
            : '',
        amount,
      );

      return;
    }

    if ((number / 100000000 < 1) ||
        smsMessage.body!.contains(
          RegExp('airtel money', caseSensitive: false),
        )) {
      dontProcess(
        smsMessage.body ?? "",
        transactionId,
        number,
        '',
        amount,
        -1,
        status: TransactionStatuses.unavailableOffer,
        reply: 'Invalid number',
        canRetry: false,
        source: name,
      );

      processReply(
        number,
        TransactionStatuses.unavailableOffer,
        name.split(' ')[0],
        name.trim().split(RegExp(r'\s+')).length > 1
            ? name.trim().split(RegExp(r'\s+'))[1]
            : '',
        amount,
      );

      return;
    }

    List<dynamic> USSDToDial1Sim2CanRetry3DoesExist4IsAdvanced5isActive =
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
      USSDToDial1Sim2CanRetry3DoesExist4IsAdvanced5isActive = canCompound;
      amount = canCompound[6];
    }

    if (USSDToDial1Sim2CanRetry3DoesExist4IsAdvanced5isActive[0]
        .toString()
        .isEmpty) {
      if (USSDToDial1Sim2CanRetry3DoesExist4IsAdvanced5isActive.length > 6) {
        if (await forwardIfNeeded(
          USSDToDial1Sim2CanRetry3DoesExist4IsAdvanced5isActive[6],
          trimmedBody,
          alterMpesaMessage(smsMessage.body ?? "",
              USSDToDial1Sim2CanRetry3DoesExist4IsAdvanced5isActive[6]),
          transactionId,
          number,
          name,
          autoSaveContacts,
        )) {
          return;
        }
      }

      if (USSDToDial1Sim2CanRetry3DoesExist4IsAdvanced5isActive[0]
          .toString()
          .isEmpty) {
        int forwardingLimit =
            await _sharedPreferencesService.getForwardUnavailableLimit() ?? 0;

        if (forwardingLimit > 0 && amount < forwardingLimit) {
          bool forwarded = await forwardToAllAvenues(smsMessage.body ?? "");
          if (forwarded) return;
        }

        dontProcess(
          smsMessage.body ?? "",
          transactionId,
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

        return;
      }

      amount = USSDToDial1Sim2CanRetry3DoesExist4IsAdvanced5isActive[6];
    }

    if (!USSDToDial1Sim2CanRetry3DoesExist4IsAdvanced5isActive[5]) {
      dontProcess(
        smsMessage.body ?? "",
        transactionId,
        number,
        USSDToDial1Sim2CanRetry3DoesExist4IsAdvanced5isActive[0],
        amount,
        USSDToDial1Sim2CanRetry3DoesExist4IsAdvanced5isActive[1],
        status: TransactionStatuses.paused,
        reply: 'Offer paused. Please check/retry.',
        canRetry: false,
        source: name,
      );

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

      return;
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
          dontProcess(
            smsMessage.body ?? "",
            transactionId,
            number,
            '',
            amount,
            -1,
            status: TransactionStatuses.error,
            reply: 'Auto-renewal failed: ${reply[0]}',
            canRetry: true,
            source: name,
          );
          return;
        }
      } else {
        dontProcess(
          smsMessage.body ?? "",
          transactionId,
          number,
          USSDToDial1Sim2CanRetry3DoesExist4IsAdvanced5isActive[0],
          amount,
          USSDToDial1Sim2CanRetry3DoesExist4IsAdvanced5isActive[1],
          source: name,
          canRetry: true,
        );

        if (autoSaveContacts) {
          await contactService.addNewContact(
            name,
            '0$number',
          );
        }

        return;
      }
    }

    List requestResponse = [];

    if (USSDToDial1Sim2CanRetry3DoesExist4IsAdvanced5isActive[4]) {
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
        USSDToDial1Sim2CanRetry3DoesExist4IsAdvanced5isActive[0],
        USSDToDial1Sim2CanRetry3DoesExist4IsAdvanced5isActive[1],
        codeSignature: signatureMap.isEmpty ? null : signature,
      );

      requestResponse[1] = await transactionStatus(requestResponse);

      if (requestResponse[1] == TransactionStatuses.error) {
        USSDToDial1Sim2CanRetry3DoesExist4IsAdvanced5isActive[2] = true;
      }
    } else {
      requestResponse = await PhoneService().makeMyRequest(
        USSDToDial1Sim2CanRetry3DoesExist4IsAdvanced5isActive[0],
        USSDToDial1Sim2CanRetry3DoesExist4IsAdvanced5isActive[1],
      );
      requestResponse[1] = await transactionStatus(requestResponse);
    }

    print("Rechecking status after USSD execution: ${requestResponse[1]}");

    if (requestResponse[1] == TransactionStatuses.hasOkoa) {
      dontProcess(
        smsMessage.body ?? "",
        transactionId,
        number,
        USSDToDial1Sim2CanRetry3DoesExist4IsAdvanced5isActive[0],
        amount,
        USSDToDial1Sim2CanRetry3DoesExist4IsAdvanced5isActive[1],
        status: TransactionStatuses.hasOkoa,
        reply: requestResponse[0],
        canRetry: false,
        source: name,
      );
      processReply(
        number,
        TransactionStatuses.hasOkoa,
        name.split(' ')[0],
        name.trim().split(RegExp(r'\s+')).length > 1
            ? name.trim().split(RegExp(r'\s+'))[1]
            : '',
        amount,
      );
      return;
    }

    if (isUsingToken) {
      await _paymentOps.deductSingleToken();
    }

    await recordClientPurchase(number.toString(), name);

    int insertedId = await _sqliteService.insertStuff(
      {
        'initialMessage': smsMessage.body,
        'transactionId': transactionId,
        'number': number,
        'date': getNormalDate(DateTime.now()),
        'time': getNormalTime(DateTime.now()),
        'ussdDialed': USSDToDial1Sim2CanRetry3DoesExist4IsAdvanced5isActive[0],
        'ussdReply': requestResponse[0],
        'amount': amount,
        'smsDate': getNormalDate(
          DateTime.fromMillisecondsSinceEpoch(smsMessage.date ?? 0),
        ),
        'smsTime': getNormalTime(
          DateTime.fromMillisecondsSinceEpoch(smsMessage.date ?? 0),
        ),
        'status': requestResponse[1] == "" ? "No reply" : requestResponse[1],
        'simSubId': USSDToDial1Sim2CanRetry3DoesExist4IsAdvanced5isActive[1],
        'source': name,
        'timeStamp': DateTime.now().millisecondsSinceEpoch,
        'canRetry':
            USSDToDial1Sim2CanRetry3DoesExist4IsAdvanced5isActive[2] ? 1 : 0,
      },
      'transactions',
    );

    if (autoSaveContacts) {
      await contactService.addNewContact(
        name,
        '0$number',
      );
    }

    if (TransactionStatuses.secondAttempt == requestResponse[1]) {
      // USSDToDial1Sim2CanRetry3DoesExist4IsAdvanced5isActive = await unavailableAmountCanCompound(amount, number);
      return;
    }

    await processReply(
      number,
      requestResponse[1],
      name.split(' ')[0],
      name.trim().split(RegExp(r'\s+')).length > 1
          ? name.trim().split(RegExp(r'\s+'))[1]
          : '',
      amount,
    );
    if (insertedId < 0) {}

    retryAll(true);
  }

  Future<bool> forwardIfNeeded(
      int amount,
      String trimmedBody,
      String smsMessageBody,
      String transactionId,
      int number,
      String name,
      bool autoSaveContacts,
      {String? status}) async {
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

    String name = getName(smsMessageBody);

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
        dontProcess(
          "$smsMessageBody $interpunct TPN${toForward[0]["numberToReceive"]}",
          transactionId,
          number,
          '',
          amount,
          -1,
          status: status ?? TransactionStatuses.forwarded,
          reply: 'Forwarding to ${toForward[0]["numberToReceive"]}: $reply',
          canRetry: false,
          source: name,
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

        return true;
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

          for (var device in forwardingDevices) {
            if ((device['paused'] ?? 0) != 1) {
              String recipientDeviceName = device['device_name'] ??
                  "Unknown Device ${DateTime.now().millisecondsSinceEpoch}";
              String amountsString = device['amounts_to_forward'] ?? "";
              // Remove brackets and quotes if it was stored as JSON string
              amountsString = amountsString.replaceAll(RegExp(r'[\[\]"]'), '');
              List<String> amounts = amountsString.isEmpty
                  ? []
                  : amountsString.split(',').map((e) => e.trim()).toList();

              if (amounts.contains(amount.toString())) {
                if (await AuthService().pingDevice(recipientDeviceName)) {
                } else {
                  dontProcess(
                    smsMessageBody,
                    transactionId,
                    number,
                    '',
                    amount,
                    -1,
                    status: TransactionStatuses.error,
                    reply:
                        'Forwarding failed: Server not reachable. Will retry later.',
                    canRetry: true,
                    source: name,
                  );
                  return true;
                }
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
                    }
                  },
                );

                smsMessageBody =
                    "$smsMessageBody $interpunct TDN$recipientDeviceName";

                // retry after 5 seconds on error
                if (result['success'] != true) {
                  dontProcess(
                    smsMessageBody,
                    transactionId,
                    number,
                    '',
                    amount,
                    -1,
                    status: TransactionStatuses.error,
                    reply:
                        'Forwarding failed. Server not reachable. Will retry later.',
                    canRetry: true,
                    source: name,
                  );
                  return true;
                }

                dontProcess(
                  smsMessageBody,
                  transactionId,
                  number,
                  '',
                  amount,
                  -1,
                  status: TransactionStatuses.forwarded,
                  reply:
                      'Forwarded to ${device['device_name']} (ID: ${device['device_id']})',
                  canRetry: false,
                  source: name,
                );

                return true;
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Error checking forwarding devices: $e");
    }

    return false;
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

        message = "$message $interpunct TDN${device['device_name']}";
        await BackendService().post(
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
            }
          },
        );

        // print("No forwarding devices found to forward the message.");
        dontProcess(
          message,
          '',
          number,
          '',
          amount,
          -1,
          status: TransactionStatuses.forwarded,
          reply:
              'Forwarded unavailable amount(Ksh $amount) to all paired devices',
          canRetry: false,
          source: name,
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
    int id,
    String ussdCode,
    int simSubId,
    int canRetry,
    String reply,
  ) async {
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

    Map<String, dynamic> transaction = tx.first;

    String initialMessage = transaction['initialMessage'] ?? '';

    int compoundedAmount = transaction['amount'] ?? 0;

    if (transaction.isEmpty) {
      return;
    }

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
    int amount = getAmount(initialMessage);

    if (ussdCode.isEmpty) {
      number = extract9DigitNumber(initialMessage);
    }

    if (number == 0) {
      number = transaction['number'] ?? 0;
    }

    if (amount <= 0) {
      amount = transaction['amount'] ?? 0;
    }

    if (compoundedAmount > 0) {
      amount = compoundedAmount;
    }

    //print("New number: $number, amount: $amount, ussdCode: $ussdCode");

    List<Map<String, dynamic>> lecodes = (await _sqliteService.queryCustom(
      'ussdCodes',
      'amount = ?',
      [amount],
    ));

    if (lecodes.isEmpty) {
      forwardIfNeeded(
        amount,
        initialMessage,
        initialMessage,
        transaction['transactionId'] ?? '',
        number,
        transaction['source'] ?? '',
        false,
        status: TransactionStatuses.unavailableOffer,
      );

      await _sqliteService.deleteStuff(
        id,
        'transactions',
      );
      return;
    }

    //print("Redoing transaction $id with code $ussdCode on sim $simSubId");

    List<dynamic> USSDToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive =
        await get0USSDToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive(
      amount,
      number,
      simSubId,
    );

    ussdCode = USSDToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[0];
    simSubId = USSDToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[1];

    List<dynamic> response = [];

    // //print("Is Adv 0: ${await isAdvanced(ussdCode)}");
    // //print("is adv ${USSDToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[4]}");

    if (USSDToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[4]) {
      bool isActive =
          await _sharedPreferencesService.getAppIsActiveState() ?? false;

      if (!isActive) return;

      Map<String, dynamic> thisCOde = lecodes.firstWhere(
        (code) => code['ussdCode'] == ussdCode,
        orElse: () => {},
      );

      var signatureQuery = await _sqliteService.queryCustom(
        'codeSignature',
        'ussdCodeId = ?',
        [thisCOde['id'] ?? -1],
      );

      CodeSignature signature = CodeSignature.fromMap(
        signatureQuery.isNotEmpty ? signatureQuery.first : {},
      );

      response = await PhoneService().makeAdvancedRequest(
        ussdCode,
        simSubId,
        codeSignature: signature,
      );

      response[1] = await transactionStatus(response);
    } else {
      response = await PhoneService().makeMyRequest(
        ussdCode,
        simSubId,
      );
      response[1] = await transactionStatus(response);
    }

    if (response[1] == TransactionStatuses.done) {
      if (isUsingToken) {
        await _paymentOps.deductSingleToken();
      }
    }

    if (response[1] == TransactionStatuses.secondAttempt) {
      String bsatMessage = "(Number Altered by BSAT): ";
      canRetry = 20;
      print("second attempt");
      Client? dbClient = await ClientService().getClientByPhone('0$number');
      if (dbClient != null &&
          dbClient.alternativePhoneNumber != null &&
          dbClient.alternativePhoneNumber!.trim().isNotEmpty) {
        int altNumber = extract9DigitNumber(dbClient.alternativePhoneNumber!);
        if (!initialMessage.contains(bsatMessage)) {
          String altMessage = replaceNumberInMessage(
            "0$number",
            dbClient.alternativePhoneNumber ?? "",
            initialMessage,
            bsatMessage,
          );
          if (altNumber != number && altNumber > 0) {
            await _sqliteService.deleteStuff(
              id,
              'transactions',
            );
            debugPrint(
                "Running transaction with alternative number: $altNumber");
            makeTransactionGivenSmsBody(altMessage);
            return;
          }
        }
      }
    }

    if (response[1] == TransactionStatuses.secondAttempt &&
        lecodes.isNotEmpty) {
      String? altUssdCode = lecodes.first['alternativeUssdCode'];
      String? runAltOn = lecodes.first['runAltOn'];
      bool altIsAdvanced = lecodes.first['altIsAdvanced'] == 1;

      // print(object)

      if (altUssdCode != null && altUssdCode.isNotEmpty) {

        altUssdCode = replaceNWithNumber(altUssdCode, number);

        if (runAltOn == null || runAltOn.isEmpty) {
          String processedAltUssdCode = replaceNWithNumber(altUssdCode, number);
          debugPrint('Running alternative USSD code: $processedAltUssdCode');
          List<dynamic> altResponse = [];
          if (altIsAdvanced) {
            CodeSignature altSignature = CodeSignature.fromMap(
              (await _sqliteService.queryCustom(
                'codeSignature',
                'ussdCodeId = ?',
                [lecodes.first['id'] ?? -1],
              ))
                  .first,
            );

            altResponse = await PhoneService().makeAdvancedRequest(
              processedAltUssdCode,
              simSubId,
              codeSignature: altSignature,
            );
            altResponse[1] = await transactionStatus(altResponse);
          } else {
            altResponse = await PhoneService().makeMyRequest(
              processedAltUssdCode,
              simSubId,
            );
            altResponse[1] = await transactionStatus(altResponse);
          }
          response = altResponse;
        } else {
          List deviceMatches = await _sqliteService.queryCustom(
            'forwardingDevices',
            'device_name = ?',
            [runAltOn],
          );
          if (deviceMatches.isEmpty) {
            deviceMatches = await _sqliteService.queryCustom(
              'whitelistedDevices',
              'device_name = ?',
              [runAltOn],
            );
          }
          if (deviceMatches.isNotEmpty) {
            String recipientDeviceName = deviceMatches.first['device_name'];
            String senderDeviceName =
                await SharedPreferencesService().getDeviceName() ??
                    "Unknown Device ${DateTime.now().millisecondsSinceEpoch}";

            print("Forwarding alternative USSD code request to $recipientDeviceName for transaction $id");

            final res = await BackendService().post(
              '/api/fcm/send-secure',
              body: {
                'title': "BSAT Online Forwarding",
                // keep notification.body scalar for FCM compatibility
                'body': 'Forwarded alternative USSD request',
                'senderDeviceName': senderDeviceName,
                'recipientDeviceName': recipientDeviceName,
                'data': {
                  'type': 'process_alt_request',
                  'ussdCode': altUssdCode,
                  'isAdvanced': altIsAdvanced.toString(),
                  'smsMessage': initialMessage,
                  'body': 'Forwarded alternative USSD request',
                  'title': "Forwarded Code",
                }
              },
            );

            initialMessage =
                "$initialMessage $interpunct TDN$recipientDeviceName";

            if (res['success'] == true) {
              debugPrint(
                  'Alternative USSD code request sent to ${deviceMatches.first['device_name']} successfully.');
              // add to ussdReply "sent alt ussd code request to deviceName"
              response[0] =
                  "\nSent alternative USSD code request to ${deviceMatches.first['device_name']} $interpunct ${tx[0]['ussdReply'] ?? ''}";
              response[1] = TransactionStatuses.doneConfirmed;
            } else {
              debugPrint(
                'Failed to send alternative USSD code request to ${deviceMatches.first['device_name']}.',
              );
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
        initialMessage,
        id,
      ],
    );

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

    number = number < 100000000 ? extract9DigitNumber(initialMessage) : number;
    debugPrint(getName(initialMessage));
    debugPrint(amount.toString());
    debugPrint(number.toString());

    await processReply(
      number,
      response[1],
      getName(initialMessage).split(' ')[0],
      getName(initialMessage).trim().split(RegExp(r'\s+')).length > 1
          ? getName(initialMessage).trim().split(RegExp(r'\s+'))[1]
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
      sim = (await _phoneService.getAllDialSims()).first;
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
    int lastCheckSkippedTime =
        await _sharedPreferencesService.getLastCheckSkippedTime() ?? 0;

    if (lastCheckSkippedTime == 0) {
      await _sharedPreferencesService.setLastCheckSkippedTime(
        DateTime.now().millisecondsSinceEpoch,
      );
      return;
    }

    if (DateTime.now().millisecondsSinceEpoch <
        (lastCheckSkippedTime + const Duration(minutes: 2).inMilliseconds)) {
      return;
    }

    bool hasPaid = await _paymentOps.hasActiveSubscription();

    if (!hasPaid) {
      return;
    }

    List<SmsMessage> smss = await getAllSince(lastCheckSkippedTime);

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

    // debugPrint("Done");

    await _sharedPreferencesService.setLastCheckSkippedTime(
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> dontProcess(
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
  }) async {
    await _sqliteService.insertStuff(
      {
        'initialMessage': initialMessage,
        'transactionId': transactionId,
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

  Future<void> retryAll(bool isAutoRetrying) async {
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
      ((status = ? OR status = ?) AND date = ? AND canRetry < $retryTimes)
    ''';

    List<Object> args = [
      TransactionStatuses.error,
      isAutoRetrying ? 1 : 0,
      TransactionStatuses.timedOut,
      TransactionStatuses.secondAttempt,
      getNormalDate(DateTime.now()),
      // TransactionStatuses.advance
    ];

    List<Map<String, dynamic>> rawStuff = await _sqliteService.queryCustom(
      'transactions',
      query,
      args,
      columns: ['id', 'ussdDialed', 'simSubId', 'canRetry', 'ussdReply'],
    );

    //print('Retrying all: ${rawStuff.length}');

    // debugPrint('Retrying all transactions: ${rawStuff}');

    for (var stuff in rawStuff) {
      debugPrint(' retrytimes $retryTimes, canRetry ${stuff['canRetry']}');
      await redoTransaction(
        stuff['id'],
        stuff['ussdDialed'],
        stuff['simSubId'],
        stuff['canRetry'] ?? 0,
        stuff["ussdReply"],
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

    if (responseText == "Success") {
      return TransactionStatuses.error;
    }

    if (responseText
        .contains(RegExp(r'successfully purchased', caseSensitive: false))) {
      return TransactionStatuses.doneConfirmed;
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

    if (RegExp(r'Invalid choice|max number of menu', caseSensitive: false)
        .hasMatch(responseText)) {
      return TransactionStatuses.error;
    }

    if (RegExp(r'connection code error|one minute', caseSensitive: false)
        .hasMatch(responseText)) {
      return TransactionStatuses.timedOut;
    }

    if (RegExp(r'queue', caseSensitive: false)
        .hasMatch(responseText)) {
      return TransactionStatuses.advancedQueue;
    }

    if (RegExp(
      r'error|duplicate|not available|unavailable|max number|try again|apologize|invalid|sorry|mmi complete|timed out',
      caseSensitive: false,
    ).hasMatch(responseText)) {
      return TransactionStatuses.error;
    }

    if (RegExp(r'already', caseSensitive: false)
        .hasMatch(responseText)) {
      return TransactionStatuses.secondAttempt;
    }

    return response[1];
  }

  Future<void> transactGivenUssdAndDialSim(
    String ussdCode,
    int simSubId,
    int amount,
    bool isAdvanced,
    int number,
  {String? message}
  ) async {
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
          dontProcess(
            message ?? "",
            "00",
            number,
            ussdCode,
            amount,
            simSubId,
            source: "manual",
            reply: 'No subscription found. Please renew.',
          );
          return;
        }
      } else {
        dontProcess(
          message ?? "",
          "00",
          number,
          ussdCode,
          amount,
          simSubId,
          source: "manual",
        );
        return;
      }
    }

    List<dynamic> response = [];

    if (isAdvanced) {
      String transStatus = TransactionStatuses.advancedUssd;
      String msg = 'Advanced. Added to queue.';

      bool anotherRunning = PhoneService.isRunning;

      if (anotherRunning) {
        transStatus = TransactionStatuses.error;
        msg = "Waiting for turn ...";
        dontProcess(
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

        return;
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

    if (isUsingToken) {
      await _paymentOps.deductSingleToken();
    }

    response[1] = await transactionStatus(response);

    await _sqliteService.insertStuff(
      {
        'initialMessage': 'Manual',
        'transactionId': '',
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
        'source': 'manual',
      },
      'transactions',
    );
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

    List offers = await _sqliteService.queryCustom(
      'ussdCodes',
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
      columns: ['id', 'status', 'ussdReply', 'amount', 'source'],
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

    if (status != TransactionStatuses.doneConfirmed) {
      if (status != TransactionStatuses.advancedQueue &&
          status != TransactionStatuses.advancedUssd) {
        status = TransactionStatuses.done;
      }
//     Thank You For Choosing Safaricom. You have purchased Tunukiwa Legacy Daily Data for 746234392. Continue connecting with Family & Friends!
//      · You have successfully recommended offer to 0746234392. Total Commission this week is Ksh.5867.3. Keep Selling, be a Bingwa Sokoni!!
//      · Recommendation for 0746234392 submitted successfully. Keep selling!! Be a Bingwa Sokoni Champion.
//      · Recommendation for 0746234392 submitted successfully. Keep selling!! Be a Bingwa Sokoni Champion.
      if (RegExp(
        r'total commission|have successfully|tunukiwa legacy daily data|have purchased',
        caseSensitive: false,
      ).hasMatch(smsMessage.body ?? "")) {
        status = TransactionStatuses.doneConfirmed;
      }

      if (RegExp(r'Recommendation failed', caseSensitive: false)
          .hasMatch(smsMessage.body ?? "")) {
        status = TransactionStatuses.secondAttempt;
      }
    }

    if (rawStuff.isNotEmpty) {
      //print("Updating advanced request");
      await _sqliteService.updateOnly(
        "UPDATE transactions SET ussdReply = ?, status = ? WHERE id = ?",
        [
          "${smsMessage.body} \n$interpunct ${rawStuff.first['ussdReply']}",
          status,
          rawStuff.first['id']
        ],
      );
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
    List<Map<String, dynamic>> ussdCodeItem = await _sqliteService.queryCustom(
      'ussdCodes',
      'id = ?',
      [id],
    );

    if (ussdCodeItem.first['usesBongaPoints'] == null ||
        ussdCodeItem.first['usesBongaPoints'] == 0) {
      return ussdCodeItem.first['code'];
    }

    List<dynamic> reply = await _phoneService.makeMyRequest(
      ussdCodeItem.first['balanceCheckCode'],
      ussdCodeItem.first['dialSim'],
    );

    int bongaBalance = await getBongaBalance(reply[0]);

    //print("Bonga balance: $bongaBalance");

    if (bongaBalance > ussdCodeItem.first['bongaPointsPerTransaction']) {
      return ussdCodeItem.first['code'];
    }

    return ussdCodeItem.first['fallbackCode'];
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

    return UssdCode(
      id: response.first['id'],
      code: response.first['code'],
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
  Future<String?> sortPleaseCallMe(SmsMessage message) async {
    if (message.body != null &&
        RegExp(r'please call|tried to|tried calling', caseSensitive: false)
            .hasMatch(message.body!)) {
      int number = extract9DigitNumber(message.address ?? "");

      // remove leading 254 if present
      if (number.toString().startsWith('254')) {
        number = int.parse(number.toString().substring(3));
      }

      List<Map<String, dynamic>> pausedTransactions = await _sqliteService
          .queryCustom(
              'transactions', 'status = ? OR status = ?', [TransactionStatuses.masked, TransactionStatuses.paused]);

      if (pausedTransactions.isNotEmpty) {
        for (var transaction in pausedTransactions) {
          String initialMessage = transaction['initialMessage'] ?? '';
          String? unmaskedReply =
              unmaskNumberInMessage('0$number', initialMessage);

          if (unmaskedReply != null) {
            await _sqliteService.deleteStuff(transaction['id'], 'transactions');
            makeTransactionGivenSmsBody(unmaskedReply);
            return unmaskedReply;
          }
        }
      }
    }
    return null;
  }

  Future<String?> sort334Reply(SmsMessage smsMessage) async {
    // reply might contain phone number.
    int number = extract9DigitNumber(smsMessage.body ?? "");

    String mpesaCode = getMpesaCode(smsMessage.body ?? "");

    if (number == 0) return null;

    Map<String, dynamic> transaction = (await _sqliteService.queryCustom(
      'transactions',
      '(status = ? OR status = ?) AND transactionId = ?',
      [TransactionStatuses.masked, TransactionStatuses.paused, mpesaCode],
    ))
        .first;

    // for (var transaction in transactions) {
    String initialMessage = transaction['initialMessage'] ?? '';
    String? unmaskedReply = unmaskNumberInMessage('0$number', initialMessage);
    //
    if (unmaskedReply != null) {
      await _sqliteService.deleteStuff(transaction['id'], 'transactions');
      // new client
      Client client = Client.fromMpesaMessage(unmaskedReply);

      await recordClientPurchase(
          client.phoneNumber, "${client.firstName} ${client.lastName}");

      await makeTransactionGivenSmsBody(unmaskedReply);
      return unmaskedReply;
    }
    // }

    return null;
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

        await _sqliteService.deleteStuff(recommendation['id'], 'transactions');
        await makeTransactionGivenSmsBody(initialMessage);
      }
    }
  }
}
