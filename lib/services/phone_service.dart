import 'package:bsat/services/shared_preferences_service.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sim_data/sim_data.dart';
import 'package:ussd_service/ussd_service.dart';

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
    int numb = 0;
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
      debugPrint("error! code: ${e.code} - message: ${e.message} ${e.details}");
    } catch (e) {
      // debugPrint("unkwown error!");
      String message = e.toString();

      debugPrint("error! $e");
    }
    return ["Error sending code: $message", TransactionStatuses.error];
  }

  Future<List> makeAdvancedRequest(String code, int subscriptionId) async {
    final sims = await getAllSimSubids();
    if (!(sims.contains(subscriptionId)) || subscriptionId == -1) {
      subscriptionId = (await getAllSimSubids()).first;
    }

    try {
      String? res = await sendUssdSequence(code, subscriptionId);

      // if (res!.contains(RegExp(r'error', caseSensitive: false))) {
      //   return [res, TransactionStatuses.error];
      // } else if (res.contains(RegExp(r'queue', caseSensitive: false))) {
      //   return [res, TransactionStatuses.advancedQueue];
      // }
      if (res!.contains(
          RegExp(r'USSD session already in progress|duplicate sessions. rejecting new one', caseSensitive: false))) {
        return [res, TransactionStatuses.error];
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

      return [res, TransactionStatuses.advancedUssd];
    } catch (e) {
      debugPrint("UssdSession: Error sending code in makeAdvancedRequest: $e");
      return [
        "Error sending code: Advanced Error ${TransactionStatuses.error}",
        TransactionStatuses.error
      ];
    }
  }

  Future<int> getAirtimeBalance({int? subscriptionId}) async {
    return await getAllDialSims().then((value) async =>
        await makeMyRequest("*144#", subscriptionId ?? value.first)
            .then((value) => airtimeBalExtract(value[0])));
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

  static Future<String?> sendUssdSequence(
      String fullCode, int subscriptionId) async {
    isRunning = true;
    //print("UssdSession(fl): sendUssdSequence: $fullCode, $subscriptionId");
    try {
      final result = await platform.invokeMethod(
        'runUssdSequence',
        {"sequence": fullCode, "subscriptionId": subscriptionId},
      );
      // //print("UssdSession(fl): Result: $result");
      return result;
    } finally {
      isRunning = false;
    }
  }
}
