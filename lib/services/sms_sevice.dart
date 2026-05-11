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
  // debugPrint("Init messages platform state");

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
  final body =
      (_extractField(smsMessage, 'body')?.toString() ?? '').replaceAll("'", "");
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
    } else if (addr == "334") {
      await TransactionController().sortMessageContent(smsMessage);
    } else {
      await TransactionController().sortClientText(smsMessage);
    }

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
  final int actualLimit = limit ?? 100;

  // 1. Fetch DB numbers efficiently
  final List<Map<String, dynamic>> dbRows = await SQLiteService().queryAll(
    'processText',
    columns: ['number'],
  );

  final Iterable<String> dbNumbers = dbRows
      .map((row) => row['number'].toString())
      .where((numStr) => numStr.isNotEmpty);

  // 2. Combine all target addresses
  final List<String> targetAddresses = [
    "Safaricom",
    "MPESA",
    "SAF_OfaMOTO",
    "334",
    "REVERSAL",
    "456",
    "ETOPUP"
  ];

  // Add DB numbers (capped at 900 to avoid Android SQLite limits)
  targetAddresses.addAll(dbNumbers.take(900));

  if (targetAddresses.isEmpty) return [];

  // 3. DYNAMICALLY BUILD THE FILTER
  // Start with the first address
  SmsFilter filter =
      SmsFilter.where(SmsColumn.ADDRESS).equals(targetAddresses.first);

  // Loop through the rest and chain .or() automatically
  for (int i = 1; i < targetAddresses.length; i++) {
    filter = filter.or(SmsColumn.ADDRESS).equals(targetAddresses[i]);
  }

  // 4. Fetch the SMS using the dynamic filter
  List<SmsMessage> relevantMessages = await telephony.getInboxSms(
    columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
    filter: filter,
    sortOrder: [
      OrderBy(SmsColumn.DATE, sort: Sort.DESC),
    ],
  );

  // 5. Safely return the requested amount
  return relevantMessages.take(actualLimit).toList();
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

// ...existing code...
int extract9DigitNumber(String messageBody) {
  final RegExp numberRegex = RegExp(r'\d{9,12}');
  final List<Match> matches = numberRegex.allMatches(messageBody).toList();

  if (matches.isEmpty) return 0;

  // If at least 2 matches exist, use the second one; otherwise use the first.
  final Match selectedMatch = matches.length >= 2 ? matches[1] : matches[0];

  int? number = int.tryParse(selectedMatch.group(0) ?? '');
  if (number == null) return 0;

  if (number > 799999999) {
    number = number - 254000000000;
  }

  return number;
}
// ...existing code...

String getMpesaCode(String messageBody) {
  RegExp strictMpesaRegex =
      RegExp(r'\b(?=[A-Z0-9]*[A-Z])(?=[A-Z0-9]*[0-9])[A-Z0-9]{10}\b');

  RegExp fallbackRegex = RegExp(r'\b[A-Z0-9]{10}\b');

  Match? strictMatch = strictMpesaRegex.firstMatch(messageBody);
  if (strictMatch != null) {
    return strictMatch.group(0)!;
  }

  Match? fallbackMatch = fallbackRegex.firstMatch(messageBody);
  return fallbackMatch?.group(0) ?? "";
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

  // remove all apostrophes from the message body to avoid issues with names like O'Connor
  messageBody = messageBody.replaceAll("'", "");

  Match? nameMatch = nameRegex.firstMatch(messageBody);
  String name = nameMatch?.group(1)?.trim() ?? "";

  if (name.isEmpty) {
    nameRegex = RegExp(r"254[\dxX*]{9,12} ([a-zA-Z\s']+)");
    nameMatch = nameRegex.firstMatch(messageBody);
    name = nameMatch?.group(1)?.trim() ?? "";
  }

  return name;
}

Future<String> sendEvenInBackground(String address, String message,
    {bool sendFirstPartOnly = false,
    int? simSlot,
    bool checkIfSimilar = true}) async {
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

    if (sendFirstPartOnly) break;
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

  // 2. Create a "Positional" Pattern
// This replaces EVERY non-digit character with exactly one \d
  String positionalPatternStr = '^' +
      normalizedMask.split('').map((char) {
        return RegExp(r'[0-9]').hasMatch(char) ? char : r'\d';
      }).join() +
      r'$';

  RegExp positionalPattern = RegExp(positionalPatternStr);

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
      // Check if lengths match FIRST, then check regex
      if (normClientPhone.length == normalizedMask.length &&
          positionalPattern.hasMatch(normClientPhone)) {
        phoneMatches = true;
      }
    } else {
      phoneMatches = (normClientPhone == normalizedMask);
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
  // 1. Normalize the provided number (Remove +254 or 254, replace with 0)
  String normNum =
      number.replaceAll(RegExp(r'[^\d+]'), ''); // Keep only digits and +
  if (normNum.startsWith('+254')) {
    normNum = '0${normNum.substring(4)}';
  } else if (normNum.startsWith('254')) {
    normNum = '0${normNum.substring(3)}';
  }

  // Ensure number is long enough to have a first 4 and last 3
  if (normNum.length < 7) return null;

  // 2. Extract First 4 and Last 3 digits
  String first4 = normNum.substring(0, 4);
  String last3 = normNum.substring(normNum.length - 3);

  // 3. Find any masked number in the message
  // (Looks for +254, 254, or 0 followed by digits, asterisks/X, and ending with digits)
  final RegExp maskedPattern = RegExp(
    r'(?:\+?254|0)\d*[\*xX]+\d+\b',
    caseSensitive: false,
  );

  for (Match match in maskedPattern.allMatches(message)) {
    String maskedToken = match.group(0)!;

    // 4. Normalize the masked token found in the message
    String normMask = maskedToken.toUpperCase();
    if (normMask.startsWith('+254')) {
      normMask = '0${normMask.substring(4)}';
    } else if (normMask.startsWith('254')) {
      normMask = '0${normMask.substring(3)}';
    }

    // 5. Compare the First 4 and Last 3
    if (normMask.startsWith(first4) && normMask.endsWith(last3)) {
      // It's a perfect match! Replace it in the original message.
      return message.replaceFirst(maskedToken, number);
    }
  }

  // Return null if no matching masks were found
  return null;
}

String replaceNumberInMessage(
    String oldNumber, String newNumber, String message, String bsatMessage) {
  // using regex to replace all occurrences of oldNumber with newNumber, but only if oldNumber is not part of a larger number (e.g. 0712345678 should not match 07123456789)
  final RegExp regex =
      RegExp(r'(?<!\d)' + RegExp.escape(oldNumber) + r'(?!\d)');
  String? updatedMessage = message.replaceAll(regex, newNumber);
  // append "Altered by BSAT" to the end of the message if a replacement was made
  if (updatedMessage != message) {
    updatedMessage = "$bsatMessage $updatedMessage";
  }
  return updatedMessage;
}

Future<void> getAdvancedSms() async {}
