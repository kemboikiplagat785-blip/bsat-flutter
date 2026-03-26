import 'dart:math';

import './shared_preferences_service.dart';
import './sqlite_service.dart';
import './phone_service.dart';
import '../utils/constants.dart';
import '../utils/date_ops.dart';

class PaymentOps {
  final _sqliteHelper = SQLiteService();
  final _phoneService = PhoneService();
  final _sharedPreferencesService = SharedPreferencesService();

  Future<List<String>> payCore(
    int amount,
    int days,
    int subId,
    int planId,
    String tier,
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
      List<int> numbers = [0702015937, 0729286254, 0110382792];

      int numberIndex = Random().nextInt(numbers.length);

      String code = "*140*$amount*0${numbers[numberIndex]}#";


      final value = await _phoneService.makeMyRequest(
        code,
        subId,
      );

      if (!paymentIsMade(value[0])) {
        return ['Insufficient balance.\n', TransactionStatuses.error];
      }
      int usableUntil = (await Payment.getPaymentByTier(tier)).till;
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
          'plan_id': planId,
          'amount': amount,
          'type': tier,
          'payment_date': DateTime.now().millisecondsSinceEpoch,
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
    Payment highestTierPayment = await Payment.getHighestTierPayment();
    return highestTierPayment.till > DateTime.now().millisecondsSinceEpoch;
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

  Future<List<String>> payTokens(int amount, int subId, int tokens,
      {int planId = -1}) async {
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

      await _sqliteHelper.insertStuff(
        {
          'sim': subId,
          'till':
              0,
          'plan_id': planId,
          'amount': amount,
          'type': 'token',
          'token_count': tokens,
          'payment_date': DateTime.now().millisecondsSinceEpoch,
        },
        'payments',
      );

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

  Future<List<String>> autoRenewSubscription() async {
    Map? lastPlan = (await SQLiteService()
        .queryAll('payments', limit: 1, orderBy: 'id DESC')).firstOrNull ?? {};

    int planId;
    int subId;
    int amount;

    if (lastPlan != null && lastPlan.isNotEmpty) {
      planId = lastPlan['plan_id'] ?? -1;
      subId = lastPlan['sim'] ?? -1;
      amount = lastPlan['amount'] ?? -1;
    } else {
      // default values if no last plan found
      planId = 3;
      amount = 20;

      subId = (await SQLiteService()
          .queryAll('ussdCodes', limit: 1, orderBy: 'id DESC'))[0]['dialSim'];
    }


    return await payCore(
      amount,
      1,
      subId,
      planId,
      lastPlan['type'] ?? 'Online',
    );
  }


  static void start1DayOnlinePlusFreeTrial() async {
    int id = await SQLiteService().insertStuff(
      {
        'sim': -1,
        'till': DateTime.now().millisecondsSinceEpoch + (24 * 60 * 60 * 1000),
        'plan_id': 6,
        'amount': 25,
        'type': 'Online +',
        'payment_date': DateTime.now().millisecondsSinceEpoch,
      },
      'payments',
    );
  }

  // update online server about payment info
}

class Payment {
  final int id;
  final int sim;
  final int till;
  final int planId;
  final int amount;
  final String type;
  final int paymentDate;

  Payment({
    required this.id,
    required this.sim,
    required this.till,
    required this.planId,
    required this.amount,
    required this.type,
    required this.paymentDate,
  });

  factory Payment.fromMap(Map<String, dynamic> m) {
    // print("Creating Payment from map: $m");
    return Payment(
      id: m['id'],
      sim: m['sim'],
      till: m['till'],
      planId: m['plan_id'],
      amount: m['amount'],
      type: m['type'],
      paymentDate: m['payment_date'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sim': sim,
      'till': till,
      'plan_id': planId,
      'amount': amount,
      'type': type,
      'payment_date': paymentDate,
    };
  }

  Payment copyWith({
    int? id,
    int? sim,
    int? till,
    int? planId,
    int? amount,
    String? type,
    int? paymentDate,
  }) {
    return Payment(
      id: id ?? this.id,
      sim: sim ?? this.sim,
      till: till ?? this.till,
      planId: planId ?? this.planId,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      paymentDate: paymentDate ?? this.paymentDate,
    );
  }

  static Future<Payment> getLastPayment() async {
    // This method can be used to fetch the last payment from the database if needed
    // For now, it just returns the current instance

      Map<String, dynamic> lastPlan = 
      (await SQLiteService().queryAll(
        'payments',
        limit: 1,
        orderBy: 'id DESC',
      ))[0];

    Payment res = Payment.fromMap(lastPlan
    );

    return res;
  }

  static Future<Payment> getHighestTierPayment() async {
    // get tier of highestplanId that has not expired
    List<Map<String, dynamic>> payments = await SQLiteService().queryCustom(
      'payments',
      'till > ?',
      [DateTime.now().millisecondsSinceEpoch],
      orderBy: 'plan_id DESC, till DESC',
    );

    // also delete any payments that have expired
    await SQLiteService().deleteWhere(
      'payments',
      'till <= ?',
      [DateTime.now().millisecondsSinceEpoch],
    );

    // also delete plans that expire more than 40 days after today
    // as it may be a result of wrong date input by user or some bug in code logic
    await SQLiteService().deleteWhere(
      'payments',
      'till > ?',
      [DateTime.now().millisecondsSinceEpoch + 40 * 24 * 60 * 60 * 1000],
    );

    if (payments.isEmpty) {
      // default to free tier if no active payments found
      return Payment.fromMap({
        'id': -1,
        'sim': -1,
        'till': 365 * 24 * 60 * 60 * 1000,
        'plan_id': 0,
        'amount': 0,
        'type': 'Free',
        'payment_date': 0,
      });
    }

    return Payment.fromMap(payments[0]);
  }

  static Future<Payment> getPaymentByTier(String tier) async {
    List<Map<String, dynamic>> payments = await SQLiteService().queryCustom(
      'payments',
      'type = ? AND till > ?',
      [tier, DateTime.now().millisecondsSinceEpoch],
      orderBy: 'plan_id DESC',
    );

    if (payments.isEmpty) {
      // return a default payment if no active payments found for the tier
      return Payment.fromMap({
        'id': -1,
        'sim': -1,
        'till': DateTime.now().millisecondsSinceEpoch,
        'plan_id': 0,
        'amount': 0,
        'type': tier,
        'payment_date': 0,
      });
    }

    return Payment.fromMap(payments[0]);
  }

}
