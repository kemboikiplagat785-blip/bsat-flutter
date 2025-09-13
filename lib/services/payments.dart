import 'package:bsat/utils/date_ops.dart';
import 'package:flutter/cupertino.dart';

import './shared_preferences_service.dart';
import './sqlite_service.dart';
import './phone_service.dart';
import '../utils/constants.dart';

class PaymentOps {
  final _sqliteHelper = SQLiteService();
  final _phoneService = PhoneService();
  final _sharedPreferencesService = SharedPreferencesService();

  Future<List<String>> payCore(
    int amount,
    int days,
    int subId,
  ) async {
    if (amount <= 0) {
      return ["Invalid amount", TransactionStatuses.error];
    }

    if (days <= 0) {
      return ["Invalid days", TransactionStatuses.error];
    }

    if (subId < 0) {
      return ["Invalid subId", TransactionStatuses.error];
    }

    try {
      final value = await _phoneService.makeMyRequest(
        "*140*$amount*0729286254#",
        subId,
      );

      if (!paymentIsMade(value[0])) {
        return ['Insufficient balance.\n', TransactionStatuses.error];
      }

      int usableUntil = await _sharedPreferencesService.getUsableUntil() ?? 0;

      // debugPrint(
      //     "Usable until: ${getNormalDate(DateTime.fromMillisecondsSinceEpoch(usableUntil))} ${getNormalTime(DateTime.fromMillisecondsSinceEpoch(usableUntil))}");
      if (usableUntil > DateTime.now().millisecondsSinceEpoch) {
        usableUntil += (days * 24 * 60 * 60 * 1000);
      } else {
        usableUntil = DateTime.now().millisecondsSinceEpoch +
            (days * 24 * 60 * 60 * 1000);
      }

      int response = await _sqliteHelper.insertStuff(
        {
          'sim': subId,
          'till': usableUntil,
        },
        'payments',
      );

      String status =
          response > 0 ? TransactionStatuses.done : TransactionStatuses.error;

      setLastUsableTime();
      return [
        '''
          Payment of KSH $amount successful.
        
          Thank you for using BSAT.
        ''',
        status,
      ];
    } catch (e) {
      return ["Unknown error", TransactionStatuses.error];
    }
  }

  Future<bool> hasActiveSubscription() async {
    int lastUsableTime = await _sharedPreferencesService.getUsableUntil() ?? 0;
    return lastUsableTime > DateTime.now().millisecondsSinceEpoch;
  }

  Future<int> setLastUsableTime({int? millisecondsSinceEpochParam}) async {
    int msSinceEpoch =
        millisecondsSinceEpochParam ?? DateTime.now().millisecondsSinceEpoch;

    List<Map<String, dynamic>> payments = await _sqliteHelper.queryCustom(
      'payments',
      'till > ?',
      [msSinceEpoch],
      columns: ['till'],
    );

    for (var pay in payments) {
      if (pay['till'] > msSinceEpoch) {
        msSinceEpoch = pay['till'];
        // break;
      }
    }

    await _sharedPreferencesService.setUsableUntil(msSinceEpoch);
    await _sharedPreferencesService.setRunningStatusStr(
      msSinceEpoch <= DateTime.now().millisecondsSinceEpoch
          ? "Payment required"
          : "Running",
    );

    return msSinceEpoch;
  }

  bool paymentIsMade(String response) {
    return response.toLowerCase().contains("sent") ||
        response.toLowerCase().contains(" successful") ||
        response.toLowerCase().contains(" transferred");
  }

  Future<List<String>> payTokens(int amount, int subId, int tokens) async {
    if (amount <= 0) {
      return ["Invalid amount", TransactionStatuses.error];
    }

    if (subId < 0) {
      return ["Invalid subId", TransactionStatuses.error];
    }

    try {
      final value = await _phoneService.makeMyRequest(
        "*140*$amount*0729286254#",
        subId,
      );

      if (!paymentIsMade(value[0])) {
        return ['Insufficient balance.\n', TransactionStatuses.error];
      }

      tokens += await _sharedPreferencesService.getDeliveryTokens() ?? 0;

      await _sharedPreferencesService.setDeliveryTokens(tokens);

      return [
        '''
          Payment of $tokens tokens successful.
        
          Thank you for using BSAT.
        ''',
        TransactionStatuses.done
      ];
    } catch (e) {
      return ["Unknown error", TransactionStatuses.error];
    }
  }

  Future<bool> deductSingleToken() async {
    int tokens = await _sharedPreferencesService.getDeliveryTokens() ?? 0;

    if (tokens <= 0) {
      return false;
    }

    tokens -= 1;
    // debugPrint("Tokens: $tokens");

    return await _sharedPreferencesService.setDeliveryTokens(tokens);
  }
}
