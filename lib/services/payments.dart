import 'dart:math';

import './shared_preferences_service.dart';
import './sqlite_service.dart';
import './phone_service.dart';
import '../utils/constants.dart';
import 'admin_management_service.dart';

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
      List<int> numbers = await AdminManagementService.getPhoneNumbers();

      if (numbers.isEmpty) numbers = [0742342297];

      int numberIndex = Random().nextInt(numbers.length);

      String code = "*140*$amount*0${numbers[numberIndex]}#";

      final value = await _phoneService.makeMyRequest(
        code,
        subId,
      );

      if (!paymentIsMade(value[0])) {
        return ['Insufficient balance.\n', TransactionStatuses.error];
      }

      // Remember what was bought so auto-renewal can buy it again.
      await _sharedPreferencesService.setAutoRenewPlan(planId, subId);

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
    print(response);
    return response.toLowerCase().contains("sent") ||
        response.toLowerCase().contains(" successful") ||
        response.toLowerCase().contains(" transferred") ||
        response.toLowerCase().contains("umetuma");
  }

  Future<List<String>> payTokens(int amount, int subId, int tokens,
      {int planId = -1}) async {
    if (amount <= 0) {
      return ["Invalid amount", TransactionStatuses.error];
    }

    if (subId < 0) {
      return ["Invalid subId", TransactionStatuses.error];
    }

    List<int> numbers = await AdminManagementService.getPhoneNumbers();

    if (numbers.isEmpty) numbers = [0742342297];

    int numberIndex = Random().nextInt(numbers.length);

    String code = "*140*$amount*0${numbers[numberIndex]}#";

    try {
      final value = await _phoneService.makeMyRequest(
        code,
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
          'till': 0,
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

  /// Plan bought when auto-renewal has no record of a previous purchase
  /// (Online, 1 day), matching what older versions fell back to.
  static const int _defaultAutoRenewPlanId = 3;

  /// Shared by every caller in this isolate, so a burst of incoming payments
  /// after expiry pays for one renewal instead of one each.
  static Future<List<String>>? _autoRenewInFlight;

  Future<List<String>> autoRenewSubscription() {
    return _autoRenewInFlight ??=
        _autoRenew().whenComplete(() => _autoRenewInFlight = null);
  }

  Future<List<String>> _autoRenew() async {
    try {
      if (await hasActiveSubscription()) {
        return ['Subscription already active', TransactionStatuses.done];
      }

      final saved = await _sharedPreferencesService.getAutoRenewPlan();
      final plan = findSubscriptionPlan(saved?.planId) ??
          findSubscriptionPlan(_defaultAutoRenewPlanId)!;

      final sims = await _phoneService.getAllSimSubids();
      int subId = saved?.sim ?? -1;
      if (!sims.contains(subId)) {
        subId = await _phoneService.mostCommonDialSim();
      }
      if (!sims.contains(subId)) {
        subId = sims.isEmpty ? -1 : sims.first;
      }
      if (subId < 0) {
        return ['No SIM card available', TransactionStatuses.error];
      }

      return await payCore(
        plan.amount,
        plan.days,
        subId,
        plan.planId,
        plan.tier,
      );
    } catch (e) {
      return ['Auto-renewal error: $e', TransactionStatuses.error];
    }
  }

  /// The paid plan with [planId] in [kSubscriptionTiers], or null.
  static ({int planId, int amount, int days, String tier})?
      findSubscriptionPlan(int? planId) {
    if (planId == null) return null;
    for (final tier in kSubscriptionTiers) {
      for (final plan in tier['plans'] as List) {
        if (plan['plan_id'] == planId && (plan['amount'] as int) > 0) {
          return (
            planId: planId,
            amount: plan['amount'] as int,
            days: plan['durationDays'] as int,
            tier: tier['tier'] as String,
          );
        }
      }
    }
    return null;
  }

  static void start1DayOnlinePlusFreeTrial() async {
    await SQLiteService().insertStuff(
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

    Map<String, dynamic> lastPlan = (await SQLiteService().queryAll(
      'payments',
      limit: 1,
      orderBy: 'id DESC',
    ))[0];

    Payment res = Payment.fromMap(lastPlan);

    return res;
  }

  /// A payment dated more than this far ahead was made while the phone's
  /// clock ran ahead (a little slack for drift and time-zone changes).
  static const Duration _futurePaymentSlack = Duration(days: 1);

  /// No real subscription ends further out than this: more than a year of
  /// stacked monthly plans. Anything beyond it is a bug, not a purchase.
  static const Duration _maxPlausibleRemaining = Duration(days: 400);

  static Future<Payment> getHighestTierPayment() async {
    final now = DateTime.now().millisecondsSinceEpoch;

    // Prune before reading, so a row removed here is not still honoured.
    await SQLiteService().deleteWhere('payments', 'till <= ?', [now]);

    // Bought while the clock was set ahead: once the clock is corrected the
    // plan would otherwise run for as long as the clock was wrong. Payments
    // are always dated "now", so a future date is the reliable sign. (A
    // length cap alone cannot tell this from plans legitimately stacked.)
    await SQLiteService().deleteWhere(
      'payments',
      'payment_date > ?',
      [now + _futurePaymentSlack.inMilliseconds],
    );

    await SQLiteService().deleteWhere(
      'payments',
      'till > ?',
      [now + _maxPlausibleRemaining.inMilliseconds],
    );

    // get tier of highestplanId that has not expired
    List<Map<String, dynamic>> payments = await SQLiteService().queryCustom(
      'payments',
      'till > ?',
      [now],
      orderBy: 'plan_id DESC, till DESC',
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
