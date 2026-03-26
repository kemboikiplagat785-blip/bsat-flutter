import 'dart:ui';

import 'package:another_telephony/telephony.dart';
import 'package:background_sms/background_sms.dart' as backgroundSms;
import 'package:bsat/controllers/transaction_controller.dart';
import 'package:bsat/models/transaction_message.dart';
import 'package:bsat/models/client.dart';
import 'package:bsat/services/shared_preferences_service.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/date_ops.dart';
import 'package:flutter/material.dart';
import 'package:telephony_sms/telephony_sms.dart';

final telephony = Telephony.instance;

// Helper to safely extract fields from different SmsMessage implementations
dynamic _extractField(dynamic obj, String field) {
  try {
    if (obj == null) return null;
    if (obj is Map) return obj[field];
    switch (field) {
      case 'address':
        return obj.address;
      case 'body':
        return obj.body;
      case 'subscriptionId':
        return obj.subscriptionId;
      case 'date':
        return obj.date;
      default:
        return null;
    }
  } catch (e) {
    return null;
  }
}

@pragma('vm:entry-point')
onBackgroundMessage(dynamic message) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  onNewMessage(message);
}

Future<void> initMessagesPlatformState() async {
  debugPrint("Init messages platform state");

  final bool? result = await telephony.requestPhoneAndSmsPermissions;

  if (result != null && result) {
    telephony.listenIncomingSms(
      onNewMessage: onNewMessage,
      onBackgroundMessage: onBackgroundMessage,
    );
  }
}

onNewMessage(dynamic smsMessage) {
  final addr = _extractField(smsMessage, 'address')?.toString() ?? 'unknown';
  debugPrint("Message from: 0 $addr");
  onMessageReceive(smsMessage);
}

onMessageReceive(dynamic smsMessage) async {
  final addr = _extractField(smsMessage, 'address')?.toString() ?? '';
  final body = _extractField(smsMessage, 'body')?.toString() ?? '';
  final subscriptionId = _extractField(smsMessage, 'subscriptionId');
  final date = _extractField(smsMessage, 'date');

  debugPrint("Message from: 1 $addr");

  if (addr != "MPESA") {
    if (addr == "Safaricom" ||
        addr.contains(RegExp(r'SAF_OfaMOTO', caseSensitive: false))) {
      TransactionController().updateWithMessage(
        TransactionMessage(
          body: body,
          subscriptionId: subscriptionId,
          date: date,
        ),
      );
      //
    }

    if (addr == "334") {
      await TransactionController().sort334Reply(smsMessage);
    }

    await TransactionController().sortPleaseCallMe(smsMessage);

    int numb = extract9DigitNumber(addr);
    if (await SQLiteService().getCount(
          "processText",
          appendQuery: "WHERE number LIKE $numb",
        ) <
        1) {
      return;
    }
  }

  if (!messageIsReceived(body)) return;

  SharedPreferencesService sharedPreferencesService =
      SharedPreferencesService();
  bool isActive = await sharedPreferencesService.getRunningStatus() ?? false;

  if (!isActive) return;

  TransactionController().makeTransaction(
    TransactionMessage(
      body: body,
      subscriptionId: subscriptionId,
      date: date,
      address: addr,
    ),
  );
}

Future<List<SmsMessage>> getAllSms({int? limit}) async {
  List<SmsMessage> relevantMessages = await telephony.getInboxSms(
    columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
    filter: SmsFilter.where(SmsColumn.ADDRESS)
        .equals("Safaricom")
        .or(SmsColumn.ADDRESS)
        .equals("MPESA"),
    sortOrder: [
      OrderBy(SmsColumn.DATE, sort: Sort.DESC),
    ],
  );

  return relevantMessages.sublist(0, limit ?? 100);
}

Future<List<SmsMessage>> searchSms(String query) async {
  int end = 20;
  List<SmsMessage> relevantMessages = await telephony.getInboxSms(
    columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
    sortOrder: [
      OrderBy(SmsColumn.DATE, sort: Sort.DESC),
    ],
  );

  relevantMessages = relevantMessages
      .where((element) => element.body!.contains(query))
      .toList();

  if (relevantMessages.length < 20) end = relevantMessages.length;

  return relevantMessages.sublist(0, end);
}

Future<List<SmsMessage>> searchSentSms(
  String address,
  String message,
  int dateToday,
) async {
  debugPrint(
      "Searching sent SMS for \n\taddress: $address, \n\tmessage: $message, \n\tdate: $dateToday");
  List<SmsMessage> messages = await telephony.getSentSms(
    columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
    filter: SmsFilter.where(SmsColumn.ADDRESS)
        .equals(address)
        .and(SmsColumn.BODY)
        .equals(message)
        .and(SmsColumn.DATE)
        .greaterThanOrEqualTo(dateToday.toString()),
    sortOrder: [
      OrderBy(SmsColumn.DATE, sort: Sort.DESC),
    ],
  );

  debugPrint("Found ${messages.length} sent messages matching criteria.");

  return messages;
}

Future<List<SmsMessage>> getAllSince(int lastCheckTime) async {
  List<SmsMessage> relevantMessages = await telephony.getInboxSms(
    columns: [
      SmsColumn.ADDRESS,
      SmsColumn.BODY,
      SmsColumn.DATE,
      SmsColumn.SUBSCRIPTION_ID,
    ],
    filter: SmsFilter.where(SmsColumn.ADDRESS)
        .equals("MPESA")
        .and(SmsColumn.DATE)
        .greaterThanOrEqualTo(lastCheckTime.toString()),
    sortOrder: [
      OrderBy(SmsColumn.DATE, sort: Sort.DESC),
    ],
  );

  return relevantMessages;
}

Future<List> getAllSmsBody() async {
  List<String> smsList = [];
  List<SmsMessage> relevantMessages = await telephony.getInboxSms(
    columns: [SmsColumn.BODY],
    filter: SmsFilter.where(SmsColumn.ADDRESS)
        .equals("MPESA")
        .or(SmsColumn.ADDRESS)
        .equals("Safaricom"),
    sortOrder: [
      OrderBy(SmsColumn.DATE, sort: Sort.DESC),
    ],
  );

  for (int i = 0; i <= relevantMessages.length; i++) {
    smsList.add(relevantMessages[i].body ?? "");
  }

  return smsList;
}

bool messageIsReceived(String messageBody) {
  // //print(messageBody);
  RegExp regex = RegExp(r'\b received \b', caseSensitive: false);
  return regex.hasMatch(messageBody);
}

int extract9DigitNumber(String messageBody) {
  RegExp numberRegex = RegExp(r'\d{9,12}');

  Match? numberMatch = numberRegex.firstMatch(messageBody);
  int? number =
      numberMatch?.group(0) != null ? int.parse(numberMatch!.group(0)!) : null;

  if (number == null) return 0;
  if (number > 799999999) {
    number = number - 254000000000;
  }

  // debugPrint("Number: $number");

  return number;
}

String getReferenceCode(String messageBody) {
  RegExp referenceCodeRegex = RegExp(r'^[\w]*');

  Match? referenceCodeMatch = referenceCodeRegex.firstMatch(messageBody);
  String referenceCode = referenceCodeMatch?.group(0) ?? "";

  // debugPrint("Reference code: $referenceCode");

  return referenceCode;
}

// might be:

// ksh50
// ksh 50
// kshs50
// kshs 50
// 50.00ksh
// 50.00 ksh
// 50.00kshs
// 50.00 kshs
// 50ksh
// 50 ksh
// sh50
// sh 50
// shs50
// shs 50
// 50sh
// 50shs
// 50.00shs
// 50.00 shs
// kes 50
// kes50
// 50kes
// 50 kes
// 50.00 kes
// 50.00kes

// only get the value "50"(might be 500, 5, etc)

int getAmount(String? smsBody) {
  String cleaned = smsBody!.replaceAll(',', '').toLowerCase();
  // remove the first 10 characters of the message, the Trasaction code
  cleaned = cleaned.length > 10 ? cleaned.substring(10) : cleaned;
  RegExp amountRegex = RegExp(
    // r'(?:(((K?)sh(s?)[\s:]?)|kes[\s:]?)(\d{1,6}(?:,\d{3})*(?:\.\d+)?))|(\d{1,6}(?:,\d{3})*(?:\.\d+)?)[\s:]?((K?)sh(s?)|kes)',
    // r'Ksh(\d{1,3}(?:,\d{3})*)',
    r'(?:(((K?)sh(s?)[\s:]?)|kes[\s:]?)(\d{1,6}(?:,\d{3})*(?:\.\d+)?))|(\d{1,6}(?:,\d{3})*(?:\.\d+)?)[\s:]?((K?)sh(s?)|kes)',
    caseSensitive: false,
  );

  //print("FMatch: ${amountRegex.firstMatch(cleaned)?[0]}");

  String? amountMatch =
      amountRegex.firstMatch(cleaned)?[0]!.replaceAll(RegExp(r'[^0-9.]'), '');
  // String? amountWIthCommas = amountMatch?.group(1);
  //print("AmountMatch:  $amountMatch");

  // if (amountWIthCommas == null) return 0; // <-- Fix: return 0 if not found

  if (amountMatch == null) return 0;

  int? amount = int.tryParse(amountMatch!);

  amount ??= double.parse(amountMatch).toInt();

  //print("Amount: -> $amount, $amountMatch");
  return amount ?? 0;
}

String getName(String messageBody) {
  // Capture name gracefully, ignoring a possible masked or clear number starting with 01, 07, or 254
  // that appears right after "from". It skips the number and captures the name until a number follows.
  RegExp nameRegex = RegExp(
    // r'from\s+(?:(?:254|0[17])[\d\*xX\s]+)?\s*([A-Za-z\s]+)\s+\d',
    r"from\s+(?:(?:254|0[17])[\d\*xX\s]+)?\s*([a-zA-Z\s']+)",
    caseSensitive: false,
  );
  Match? nameMatch = nameRegex.firstMatch(messageBody);
  String name = nameMatch?.group(1)?.trim() ?? "";

  if (name.isEmpty) {
    nameRegex = RegExp(r"254[\dxX*]{9,12} ([a-zA-Z\s']+)");
    nameMatch = nameRegex.firstMatch(messageBody);
    name = nameMatch?.group(1)?.trim() ?? "";
  }

  return name;
}

Future<String> sendEvenInBackground(
  String address,
  String message, {
  bool sendFirstPartOnly = false,
  int? simSlot,
  bool checkIfSimilar = true,
}) async {
  if (checkIfSimilar) {
    List similar =
        await searchSentSms(address, message, getTodayMidnightMillis());

    if (similar.isNotEmpty) return "Already sent";
  }

  //print("Sending message to $address, $message");

  List<String> messages = [];
  String status = "Sent";
  int start = 0;
  while (start < message.length) {
    int end = start + 160;
    if (end > message.length) {
      end = message.length;
    }
    messages.add(message.substring(start, end));
    start = end;
  }

  for (String msg in messages) {
    backgroundSms.SmsStatus result =
        await backgroundSms.BackgroundSms.sendMessage(
      phoneNumber: address,
      message: msg,
      simSlot: simSlot,
    ).onError((e, _) {
      //print("ERRRRO: $e");
      DartPluginRegistrant.ensureInitialized();
      return backgroundSms.SmsStatus.failed;
    });
    //print(result);
    if (result == backgroundSms.SmsStatus.sent) {
      // //print("Sent");
    } else {
      // //print("Failed");
      status = "Failed";
    }

    if(sendFirstPartOnly) break;
  }

  return status;
}

Future<int> getBongaBalance(String text) async {
  RegExp bongaRegex =
      RegExp(r'(bonga|balance)[\sa-zA-Z]+\s+(\d+)', caseSensitive: false);
  Match? bongaMatch = bongaRegex.firstMatch(text);
  String? bongaPoints = bongaMatch?.group(2);

  return bongaPoints != null ? int.parse(bongaPoints) : 0;
}

Future<Client?> getMaskedPhoneNumber(TransactionMessage sms) async {
  String body = _extractField(sms, 'body')?.toString() ?? '';
  if (body.isEmpty) return null;

  String name = getName(body);
  // print("Extracted name: $name, body: $body");

  String phoneOrMask = '';

  RegExp regex = RegExp(r'(?:254|0)[17][\d\*xX]{8,12}', caseSensitive: false);
  Match? match = regex.firstMatch(body);
  if (match != null) {
    phoneOrMask = match.group(0)!.replaceAll(RegExp(r'\s+'), '');
  } else {
    return null;
  }

  if (name.isEmpty && phoneOrMask.isEmpty) return null;

  List<Map<String, dynamic>> allClients =
      await SQLiteService().queryAll('clients');

  String normalizedMask = phoneOrMask.replaceAll('+254', '0');
  if (normalizedMask.startsWith('254') && normalizedMask.length >= 11) {
    normalizedMask = '0${normalizedMask.substring(3)}';
  }

  // print("Normalized mask: $normalizedMask");

  String strictPatternStr =
      '^' + normalizedMask.replaceAll(RegExp(r'[^0-9]'), r'\d') + r'$';
  // print("Strict pattern: $strictPatternStr");
  RegExp strictPattern = RegExp(strictPatternStr, caseSensitive: false);
  String loosePatternStr =
      '^' + normalizedMask.replaceAll(RegExp(r'[^0-9]+'), r'.*') + r'$';
  // print("Loose pattern: $loosePatternStr");
  RegExp loosePattern = RegExp(loosePatternStr, caseSensitive: false);

  // print(name);
  var smsNameWords = name
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((e) => e.length > 2)
      .toSet();

  for (var clientMap in allClients) {
    String clientPhone = (clientMap['phoneNumber'] ?? '').toString();
    String clientFirstName =
        (clientMap['firstName'] ?? '').toString().toLowerCase();
    String clientLastName =
        (clientMap['lastName'] ?? '').toString().toLowerCase();

    String normClientPhone = clientPhone.replaceAll('+254', '0');
    if (normClientPhone.startsWith('254') && normClientPhone.length >= 11) {
      normClientPhone = '0${normClientPhone.substring(3)}';
    }

    bool phoneMatches = false;
    if (normalizedMask.contains(RegExp(r'[^0-9]'))) {
      if (strictPattern.hasMatch(normClientPhone) ||
          loosePattern.hasMatch(normClientPhone)) {
        // print(
            // "Phone matches for client ${clientFirstName} ${clientLastName} with phone $normClientPhone");
        phoneMatches = true;
      }
    } else {
      if (normClientPhone == normalizedMask) {
        phoneMatches = true;
      }
    }

    if (phoneMatches) {
      String fullClientName = '$clientFirstName $clientLastName';
      var clientNameWords = fullClientName
          .split(RegExp(r'\s+'))
          .where((e) => e.length > 2)
          .toSet();
      // print("SMS name words: $smsNameWords");
      // print("Client name words: $clientNameWords");

      // If it's a masked number, we MUST have some name overlap to map it confidently
      if (normalizedMask.contains(RegExp(r'[^0-9]'))) {
        if (smsNameWords.intersection(clientNameWords).isNotEmpty) {
          return Client.fromMap(clientMap);
        }
      } else {
        // Direct exact number match, name match is a bonus but optional
        return Client.fromMap(clientMap);
      }
    }
  }

  return null;
}

String? unmaskNumberInMessage(String number, String message) {
  // First, explicitly check for Kenyan/MPesa-like masked numbers (07xx***xxx, 2547xx***xxx, etc.)
  final RegExp mpesaMaskedPattern = RegExp(
    r'(?:254|0|\+254)[17]\d*[\*xX]+[\d\*xX]*',
    caseSensitive: false,
  );

  Match? match = mpesaMaskedPattern.firstMatch(message);
  if (match != null) {
    String maskedToken = match.group(0)!;

    // Normalize both numbers for comparison
    String normNum = number.replaceAll('+', '');
    if (normNum.startsWith('254')) normNum = '0${normNum.substring(3)}';

    String normMask =
        maskedToken.replaceAll('+', '').replaceAll(RegExp(r'x|X|\*'), r'\d');
    if (normMask.startsWith('254')) normMask = '0${normMask.substring(3)}';

    // Check if the provided number actually matches this mask
    if (RegExp('^$normMask\$').hasMatch(normNum)) {
      return message.replaceFirst(maskedToken, number);
    }

    // If it's an M-PESA format but doesn't match the regex, do not replace it blindly.
  }

  // Strip non-numeric characters to safely get the last 3 digits
  final cleanNumber = number.replaceAll(RegExp(r'\D'), '');

  // If the number is too short, we can't reliably find a mask
  if (cleanNumber.length < 3) {
    return null;
  }

  final last3 = cleanNumber.substring(cleanNumber.length - 3);

  final RegExp maskedPattern = RegExp(
    r'(?:\+?\d{1,4}[\s\-]*)?(?:[\*Xx#]{1,4}[\s\-]*)+[\d\*Xx#\s\-]*' +
        last3 +
        r'\b',
  );

  if (!maskedPattern.hasMatch(message)) {
    return null;
  }

  return message.replaceAll(maskedPattern, number);
}

Future<void> getAdvancedSms() async {}
