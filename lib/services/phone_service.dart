import 'package:bsat/services/shared_preferences_service.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sim_data/sim_data.dart';
import 'package:ussd_service/ussd_service.dart';

import '../models/code_signature.dart';

class PhoneService {
  static const platform = MethodChannel('com.bsat.app');
  static bool isRunning = false;

  SharedPreferencesService sharedPreferencesService =
      SharedPreferencesService();

  final SQLiteService _sqLiteService = SQLiteService();

  /// return `[ussdResponseMessage, TransactionStatuses.done];`
  ///
  /// or [errorMessage, TransactionStatuses.error];
  Future<List> makeMyRequest(String code, int subscriptionId,
      {int? triesParam = 0}) async {
    String message = "";
    List sims = await getAllSimSubids();

    //print("Making request on sim: $subscriptionId, available sims: $sims");

    if (!(sims.contains(subscriptionId)) || subscriptionId == -1) {
      subscriptionId = (await getAllSimSubids()).first;
    }

    try {
      //print("Making request: $code on sim $subscriptionId");
      String ussdResponseMessage = await UssdService.makeRequest(
        subscriptionId,
        code,
        const Duration(seconds: 10),
      );

      //print("Responser: $ussdResponseMessage");

      return [ussdResponseMessage, TransactionStatuses.done];
    } on PlatformException catch (e) {
      debugPrint(
          "error! code: ${e.code} - message: ${e.message} ${e.details}, ussd code: $code, subscriptionId: $subscriptionId");
    } catch (e) {
      // debugPrint("unkwown error!");
      String message = e.toString();

      debugPrint("error! $e");
    }
    return ["Error sending code: $message", TransactionStatuses.error];
  }

  Future<List> makeAdvancedRequest(
    String code,
    int subscriptionId, {
    CodeSignature? codeSignature,
    bool isGettingSignature = false,
  }) async {
    final sims = await getAllSimSubids();
    if (!(sims.contains(subscriptionId)) || subscriptionId == -1) {
      subscriptionId = (await getAllSimSubids()).first;
    }

    try {
      print("Making advanced request: $code on sim $subscriptionId");
      // String? res = await sendUssdSequence(code, subscriptionId);

      List<Map<String, dynamic>> response = await sendUssdSequence(
        code,
        subscriptionId,
        codeSignature: codeSignature,
        isGettingSignature: isGettingSignature,
      );

      String res =
          response[0]['lastresponse'] ?? '${response[0]['value'] ?? ''}';

      print("UssdSession(fl): REsponse: $response");

      // if (res!.contains(RegExp(r'error', caseSensitive: false))) {
      //   return [res, TransactionStatuses.error];
      // } else if (res.contains(RegExp(r'queue', caseSensitive: false))) {
      //   return [res, TransactionStatuses.advancedQueue];
      // }

      if (!isGettingSignature) {
        if (res!.contains(RegExp(
            r'USSD session already in progress|duplicate sessions. rejecting new one',
            caseSensitive: false))) {
          return [res, TransactionStatuses.error];
        }

        if (res!.contains(RegExp(
            r'Offer might have changed',
            caseSensitive: false))) {
          return [res, TransactionStatuses.paused];
        }

        if (res!.contains(RegExp(
            r'Your bundle activation request has failed as the Mobile Number is not active|Pool state',
            caseSensitive: false))) {
          return [res, TransactionStatuses.hasOkoa];
        }

        if (res.contains(RegExp(
            r'Connection code error|connection problem|try again|unable to process|error from application|currently unavailable|failed due to unresolved',
            caseSensitive: false))) {
          return [res, TransactionStatuses.error];
        }
      }

      return [
        res,
        TransactionStatuses.advancedUssd,
        // response[0]['conversation'] ?? [] as List<Map<String, dynamic>>,
        response[0]['conversation'] != null
            ? (response[0]['conversation'] as List)
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
            : [],
      ];
    } catch (e) {
      debugPrint("UssdSession: Error sending code in makeAdvancedRequest: $e");
      return [
        "Error sending code: Advanced Error ${TransactionStatuses.error}",
        TransactionStatuses.error
      ];
    }
  }

  Future<int> getAirtimeBalance({int subscriptionId = -9}) async {
    try {
      if (subscriptionId == -9) {
        final subs = await getAllSimSubids();
        if (subs.isEmpty) return 0;
        subscriptionId = subs.first;
      }

      final res = await makeMyRequest("*144#", subscriptionId);
      print("getAirtimeBalance: USSD response: ${res[0]}");
      final raw = res.isNotEmpty ? res[0] : '';
      return airtimeBalExtract(raw.toString());
    } catch (e, st) {
      debugPrint('getAirtimeBalance error: $e');
      return 0;
    }
  }

  Future<Set<dynamic>> getAllDialSims() async {
    return await _sqLiteService
        .queryAll('ussdCodes')
        .then((value) => value.map((val) => val['dialSim']).toSet());
  }

  Future<List<int>> getAllSimSubids() async {
    return await SimDataPlugin.getSimData().then(
        (simData) => simData.cards.map((card) => card.subscriptionId).toList());
  }

  int airtimeBalExtract(String leString) {
    RegExp amountRegex = RegExp(r'(\d+\.\d+)KSH', caseSensitive: false);
    RegExpMatch? amountMatch = amountRegex.firstMatch(leString);
    return amountMatch?.group(1) != null
        ? double.parse(amountMatch!.group(1)!).truncate()
        : 0;
  }

  /// returns List<Map<String, dynamic>>
  /// each list has:
  /// - "lastresponse": String
  /// - "conversation": List<Map<String, String>> (map of step response to next input)
  /// - "timeout": bool (true if timed out waiting for response)
  static Future<List<Map<String, dynamic>>> sendUssdSequence(
    String fullCode,
    int subscriptionId, {
    CodeSignature? codeSignature,
    bool isGettingSignature = false,
  }) async {
    isRunning = true;
    bool generalUseCodeSignature = false;
    bool generalAutoSwitch = false; // You can make this configurable if needed
    //print("UssdSession(fl): sendUssdSequence: $fullCode, $subscriptionId");
    if(codeSignature != null) {
      generalUseCodeSignature = await SharedPreferencesService().getUseSignature() ?? false;
      generalAutoSwitch = await SharedPreferencesService().getCanAutoSwitch() ?? false;

    }
// You can make this configurable if needed
    try {
      // print(
      //     "UssdSession(fl): Sending USSD code: $fullCode on sim with subscriptionId: $subscriptionId, precedure:${CodeSignature.simpleProcedure(
      //         codeSignature?.acceptedProcedure ?? [])}");
      final result = await platform.invokeMethod(
        'runUssdSequence',
        {
          "sequence": fullCode,
          "subscriptionId": subscriptionId,
          "acceptedProcedure": generalUseCodeSignature ? CodeSignature.simpleProcedure(
              codeSignature?.acceptedProcedure ?? []) : [],
          "autoSwitch": (codeSignature?.autoSwitch ?? false) && generalAutoSwitch,
          "isGettingSignature": isGettingSignature,
        },
      );
      // print(
      //     "UssdSession(fl): Result: $result for code: $fullCode on sim with subscriptionId: $subscriptionId");

      //     print("Result data type: ${result.runtimeType}");

      if (result == null) return <Map<String, dynamic>>[];

      if (result is List) {
        return result.map<Map<String, dynamic>>((item) {
          if (item is Map) return Map<String, dynamic>.from(item);
          return {"value": item};
        }).toList();
      }

      // // If platform returned a single map-like object
      // if (result is Map) {
      //   return [Map<String, dynamic>.from(result)];
      // }

      // Fallback: wrap primitive/string result
      if (result is String || result is num || result is bool) {
        return [
          {"value": result}
        ];
      }

      return [Map<String, dynamic>.from(result)];
    } finally {
      isRunning = false;
    }
  }
}
