import 'dart:ui';

import 'package:another_telephony/telephony.dart';
import 'package:background_sms/background_sms.dart' as backgroundSms;
import 'package:bsat/controllers/transaction_controller.dart';
import 'package:bsat/services/shared_preferences_service.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/date_ops.dart';
import 'package:flutter/material.dart';
import 'package:telephony_sms/telephony_sms.dart';

final telephony = Telephony.instance;

@pragma('vm:entry-point')
onBackgroundMessage(SmsMessage message) async {
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

onNewMessage(SmsMessage smsMessage) {
  debugPrint("Message from: 0 ${smsMessage.address}");
  onMessageReceive(smsMessage);
}

onMessageReceive(SmsMessage smsMessage) async {
  debugPrint("Message from: 1 ${smsMessage.address}");

  if (smsMessage.address != "MPESA") {
    if (smsMessage.address == "Safaricom" ||
        smsMessage.address!
            .contains(RegExp(r'SAF_OfaMOTO', caseSensitive: false))) {
      TransactionController().updateWithMessage(smsMessage);
    }
    int numb = extract9DigitNumber(smsMessage.address ?? "");
    if (await SQLiteService().getCount(
          "processText",
          appendQuery: "WHERE number LIKE $numb",
        ) <
        1) {
      return;
    }
  }

  if (!messageIsReceived(smsMessage.body!)) return;

  SharedPreferencesService sharedPreferencesService =
      SharedPreferencesService();
  bool isActive = await sharedPreferencesService.getRunningStatus() ?? false;

  if (!isActive) return;

  TransactionController().makeTransaction(smsMessage);
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
  // print(messageBody);
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

  print("FMatch: ${amountRegex.firstMatch(cleaned)?[0]}");

  String? amountMatch =
      amountRegex.firstMatch(cleaned)?[0]!.replaceAll(RegExp(r'[^0-9.]'), '');
  // String? amountWIthCommas = amountMatch?.group(1);
  print("AmountMatch:  $amountMatch");

  // if (amountWIthCommas == null) return 0; // <-- Fix: return 0 if not found

  if(amountMatch == null) return 0;

  int? amount = int.tryParse(amountMatch!);

  amount ??= double.parse(amountMatch).toInt();

  print("Amount: -> $amount, $amountMatch");
  return amount ?? 0;
}

String getName(String messageBody) {
  RegExp nameRegex = RegExp(r'from ([A-Za-z\s]+) \d');
  Match? nameMatch = nameRegex.firstMatch(messageBody);
  String name = nameMatch?.group(1)?.trim() ?? "";

  if (name.isEmpty) {
    nameRegex = RegExp(r'254\d{9,12} ([A-Za-z\s]+)');
    nameMatch = nameRegex.firstMatch(messageBody);
    name = nameMatch?.group(1)?.trim() ?? "";
  }

  return name;
}

Future<String> sendEvenInBackground(
  String address,
  String message, {
  int? simSlot,
  bool checkIfSimilar = true,
}) async {
  if (checkIfSimilar) {
    List similar =
        await searchSentSms(address, message, getTodayMidnightMillis());

    if (similar.isNotEmpty) return "Already sent";
  }

  print("Sending message to $address, $message");

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
      print("ERRRRO: $e");
      return backgroundSms.SmsStatus.failed;
    });
    print(result);
    if (result == backgroundSms.SmsStatus.sent) {
      // print("Sent");
    } else {
      // print("Failed");
      status = "Failed";
    }
  }

  return status;
}

Future<int> getBongaBalance(String text) async {
  RegExp bongaRegex = RegExp(r'(bonga|balance)[\sa-zA-Z]+\s+(\d+)', caseSensitive: false);
  Match? bongaMatch = bongaRegex.firstMatch(text);
  String? bongaPoints = bongaMatch?.group(2);

  return bongaPoints != null ? int.parse(bongaPoints) : 0;
}

Future<void> getAdvancedSms() async {}
