import 'dart:async';

import 'package:bsat/services/shared_preferences_service.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:bsat/utils/transaction_reply.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:another_telephony/telephony.dart';
import 'package:ussd_service/ussd_service.dart';

import '../models/code_signature.dart';

class PhoneService {
  static const platform = MethodChannel('com.bsat.app');
  static bool isRunning = false;
  static final UssdExecutionQueue _executionQueue = UssdExecutionQueue();

  SharedPreferencesService sharedPreferencesService =
      SharedPreferencesService();

  final SQLiteService _sqLiteService = SQLiteService();

  /// return `[ussdResponseMessage, TransactionStatuses.done];`
  ///
  /// or [errorMessage, TransactionStatuses.error];
  Future<List> makeMyRequest(String code, int subscriptionId,
      {int? triesParam = 0}) async {
    return _executionQueue.run(() => _makeMyRequest(code, subscriptionId,
        triesParam: triesParam));
  }

  Future<List> _makeMyRequest(String code, int subscriptionId,
      {int? triesParam = 0}) async {
    String message = "";
    List sims = await getAllSimSubids();

    //print("Making request on sim: $subscriptionId, available sims: $sims");

    if (!(sims.contains(subscriptionId)) || subscriptionId == -1) {
      subscriptionId = (await getAllSimSubids()).first;
    }

    try {
      // print("Making request: $code on sim $subscriptionId");
      String ussdResponseMessage = await UssdService.makeRequest(
        subscriptionId,
        code,
        const Duration(seconds: 10),
      );

      debugPrint(
        "NORMAL USSD DEBUG: code=[$code], "
        "sim=$subscriptionId, "
        "response=[$ussdResponseMessage]",
      );

      // print("Responser: $ussdResponseMessage");

      return [ussdResponseMessage, TransactionStatuses.done];
    } on PlatformException catch (e) {
      debugPrint(
          "error! code: ${e.code} - message: ${e.message} ${e.details}, ussd code: $code, subscriptionId: $subscriptionId");
      message = (e.message ?? '').trim().isNotEmpty
          ? e.message!.trim()
          : e.code;
    } catch (e) {
      // debugPrint("unkwown error!");
      message = e.toString();

      debugPrint("error! $e");
    }
    return [
      message.trim().isEmpty
          ? failedUssdNoReply
          : "Error sending code: $message",
      TransactionStatuses.error,
    ];
  }

  /// Sends the whole of [code] in one call, like [makeMyRequest], but through
  /// the phone's USSD dialog like [makeAdvancedRequest]: the screen wakes for
  /// the session and the accessibility service reads the reply.
  ///
  /// Returns the same as [makeMyRequest].
  Future<List> makeOneCallRequest(String code, int subscriptionId) async {
    return _executionQueue.run(() => _makeOneCallRequest(code, subscriptionId));
  }

  Future<List> _makeOneCallRequest(String code, int subscriptionId) async {
    final sims = await getAllSimSubids();
    if (!(sims.contains(subscriptionId)) || subscriptionId == -1) {
      subscriptionId = sims.first;
    }

    try {
      final response =
          await sendUssdSequence(code, subscriptionId, isOneCall: true);
      final reply = response.isEmpty
          ? ''
          : '${response[0]['lastresponse'] ?? response[0]['value'] ?? ''}';
      debugPrint("ONE CALL USSD DEBUG: code=[$code], "
          "sim=$subscriptionId, response=[$reply]");
      return reply.trim().isEmpty
          ? [failedUssdNoReply, TransactionStatuses.error]
          : [reply, TransactionStatuses.done];
    } on PlatformException catch (e) {
      debugPrint("error! code: ${e.code} - message: ${e.message}, "
          "ussd code: $code, subscriptionId: $subscriptionId");
      return [
        "Error sending code: ${e.message ?? e.code}",
        TransactionStatuses.error,
      ];
    } catch (e) {
      debugPrint("error! $e");
      return ["Error sending code: $e", TransactionStatuses.error];
    }
  }

  Future<List> makeAdvancedRequest(
    String code,
    int subscriptionId, {
    CodeSignature? codeSignature,
    bool isGettingSignature = false,
  }) async {
    return _executionQueue.run(() => _makeAdvancedRequest(
          code,
          subscriptionId,
          codeSignature: codeSignature,
          isGettingSignature: isGettingSignature,
        ));
  }

  Future<List> _makeAdvancedRequest(
    String code,
    int subscriptionId, {
    CodeSignature? codeSignature,
    bool isGettingSignature = false,
  }) async {
    debugPrint(
        "USSD DEBUG: makeAdvancedRequest received code=[$code], subscriptionId=$subscriptionId");
    debugPrint("USSD DEBUG: makeAdvancedRequest caller stack:");
    debugPrint(
        "USSD DEBUG: CALLER STACK => ${StackTrace.current.toString().replaceAll("\n", " | ")}");
    final sims = await getAllSimSubids();
    if (!(sims.contains(subscriptionId)) || subscriptionId == -1) {
      subscriptionId = (await getAllSimSubids()).first;
    }

    try {
      // String? res = await sendUssdSequence(code, subscriptionId);

      List<Map<String, dynamic>> response = await sendUssdSequence(
        code,
        subscriptionId,
        codeSignature: codeSignature,
        isGettingSignature: isGettingSignature,
      );

      String res =
          response[0]['lastresponse'] ?? '${response[0]['value'] ?? ''}';

      // if (res!.contains(RegExp(r'error', caseSensitive: false))) {
      //   return [res, TransactionStatuses.error];
      // } else if (res.contains(RegExp(r'queue', caseSensitive: false))) {
      //   return [res, TransactionStatuses.advancedQueue];
      // }

      debugPrint("Advanced USSD response: $res");

      if (response[0]['offerChanged'] == true) {
        await _flagSignatureCompromised(codeSignature);
        return [res, TransactionStatuses.offerChanged];
      }

      if (!isGettingSignature) {
        if (res.contains(RegExp(
            r'USSD session already in progress|duplicate sessions. rejecting new one',
            caseSensitive: false))) {
          // The serialized executor should make this exceptional. Keep the
          // response distinguishable so callers never treat it as a carrier
          // failure or successful transaction.
          return [res, TransactionStatuses.advancedQueue];
        }

        if (res.contains(RegExp(
            r'Invalid choice|Try again',
            caseSensitive: false))) {
          return [res, TransactionStatuses.paused];
        }

        if (res.contains(RegExp(
            r'Your bundle activation request has failed as the Mobile Number is not active|Pool state',
            caseSensitive: false))) {
          return [res, TransactionStatuses.hasOkoa];
        }

        if (res.contains(RegExp(
            r'Request cannot be completed at the moment|Connection code error|connection problem|try again|unable to process|error from application|currently unavailable|failed due to unresolved',
            caseSensitive: false))) {
          return [res, TransactionStatuses.error];
        }
      }

      String status = TransactionStatuses.advancedUssd;

      if (res.trim().isEmpty) {
        status = TransactionStatuses.error;
        res = failedUssdNoReply;
      }

      return [
        res,
        status,
        // response[0]['conversation'] ?? [] as List<Map<String, dynamic>>,
        response[0]['conversation'] != null
            ? (response[0]['conversation'] as List)
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
            : [],
        response[0]['signatureComplete'] == true,
      ];
    } catch (e, stackTrace) {
      debugPrint("UssdSession: Error sending code in makeAdvancedRequest: $e");
      debugPrint("UssdSession: StackTrace: $stackTrace");

      return [
        "Error sending code: $e",
        TransactionStatuses.error,
      ];
    }
  }

  Future<void> _flagSignatureCompromised(CodeSignature? signature) async {
    final id = signature?.id;
    if (id == null) return;
    try {
      // The menu changed for every offer dialing this code.
      await _sqLiteService.updateStuff(
        {'mightBeCompromised': 1},
        'id = ? OR usdCode = ?',
        [id, signature!.usdCode],
        'codeSignature',
      );
    } catch (e) {
      debugPrint('Could not flag signature $id: $e');
    }
  }

  Future<int> getAirtimeBalance({int subscriptionId = -9}) async {
    try {
      if (subscriptionId == -9) {
        subscriptionId = await mostCommonDialSim();
      }

      final res = await makeMyRequest("*144#", subscriptionId);
      final raw = res.isNotEmpty ? res[0] : '';
      return airtimeBalExtract(raw.toString());
    } catch (e) {
      debugPrint('getAirtimeBalance error: $e');
      return 0;
    }
  }

  Future<Set<dynamic>> getAllDialSims() async {
    return await _sqLiteService
        .queryAll('ussdCodes')
        .then((value) => value.map((val) => val['dialSim']).toSet());
  }

  Future<int> mostCommonDialSim() async {
    Set<dynamic> numbers = await getAllDialSims();
    if (numbers.isEmpty) return -1;

    // 1. Map to store counts: { number: frequency }
    Map<int, int> counts = {};
    for (var n in numbers) {
      if (n is! int) continue; // offers saved without a SIM
      counts[n] = (counts[n] ?? 0) + 1;
    }

    // 2. Find the entry with the highest frequency
    int maxCount = 0;
    int? mode;

    counts.forEach((number, frequency) {
      if (frequency > maxCount) {
        maxCount = frequency;
        mode = number;
      }
    });

    return mode ?? -1;
  }

  Future<List<int>> getAllSimSubids() async {
    final subscriptions = await Telephony.instance.getSubscriptionList();

    return subscriptions
        .map((subscription) => subscription.subscriptionId)
        .whereType<int>()
        .toList();
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
    bool isOneCall = false,
  }) async {
    isRunning = true;
    final signature = codeSignature;
    var procedure = <Map<String, String>>[];
    var autoSwitch = false;
    // Only this code's own, fully recorded, switched-on signature is enforced.
    if (!isGettingSignature &&
        signature != null &&
        signature.isActive == true &&
        signature.isUsableFor(fullCode) &&
        (await SharedPreferencesService().getUseSignature() ?? true)) {
      procedure = CodeSignature.wireProcedure(signature.acceptedProcedure);
      autoSwitch = signature.autoSwitch == true &&
          (await SharedPreferencesService().getCanAutoSwitch() ?? true);
    }
    try {
      debugPrint(
          "UssdSession(fl): Sending USSD code: $fullCode on sim with subscriptionId: $subscriptionId, signature steps: ${procedure.length}, autoSwitch: $autoSwitch");
      final result = await platform.invokeMethod(
        'runUssdSequence',
        {
          "sequence": fullCode,
          "subscriptionId": subscriptionId,
          "acceptedProcedure": procedure,
          "autoSwitch": autoSwitch,
          "isGettingSignature": isGettingSignature,
          "isOneCall": isOneCall,
        },
      );
      debugPrint(
          "UssdSession(fl): Result: $result for code: $fullCode on sim with subscriptionId: $subscriptionId");

      if (result == null) return <Map<String, dynamic>>[];

      if (result is List) {
        return result.map<Map<String, dynamic>>((item) {
          if (item is Map) {
            return Map<String, dynamic>.from(item);
          }
          return {"value": item};
        }).toList();
      }

      if (result is Map) {
        return [Map<String, dynamic>.from(result)];
      }

// Fallback: wrap primitive/string result
      return [
        {"value": result}
      ];
    } finally {
      isRunning = false;
    }
  }
}

/// Serializes all app initiated USSD calls through one executor. The task
/// remains active until the platform call completes (including timeout/error),
/// then the next queued task is started automatically.
class UssdExecutionQueue {
  Future<void> _tail = Future<void>.value();
  int _pending = 0;

  int get pendingCount => _pending;

  Future<T> run<T>(Future<T> Function() task) {
    _pending++;
    final result = Completer<T>();
    final scheduled = _tail.then((_) async {
      PhoneService.isRunning = true;
      try {
        result.complete(await task());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      } finally {
        _pending--;
        PhoneService.isRunning = _pending > 0;
      }
    });
    _tail = scheduled.catchError((Object _) {});
    return result.future;
  }
}
