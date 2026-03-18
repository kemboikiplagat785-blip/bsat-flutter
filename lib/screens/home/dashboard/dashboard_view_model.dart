import 'dart:async';

import 'package:bsat/controllers/transaction_controller.dart';
import 'package:bsat/services/background_service.dart';
import 'package:bsat/services/payments.dart';
import 'package:bsat/services/phone_service.dart';
import 'package:bsat/services/shared_preferences_service.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:bsat/utils/date_ops.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../services/kill_switch_service.dart';

class DashboardViewModel extends ChangeNotifier {
  final _sqliteService = SQLiteService();
  final _phoneService = PhoneService();
  final _sharedPreferencesService = SharedPreferencesService();

  Timer? _reloadTimer;

  bool isLightMode = true;

  // UI state
  bool showToolsSection = true;
  bool verboseMode = true;
  bool hideBalance = true;
  bool hideCommission = true;

  // Flags and metadata
  String userName = 'Bingwa';
  bool hasActiveSubscription = true;
  bool autoRetry = true;
  bool offersMightHaveChanged = false;

  // Financials
  String airtimeBalance = '...';
  double estimatedCommission = 0.0;

  // Counts
  int transactionToday = 0;
  int successfulCount = 0;
  int successfulConfirmedCount = 0;
  int errorCount = 0;
  int failedCount = 0;
  int timedOutCount = 0;
  int forwardedCount = 0;
  int unavailableCount = 0;
  int pausedCount = 0;
  int advancedCount = 0;
  int okoaCount = 0;
  int blacklistedCount = 0;

  KillswitchConfig? killswitchConfig;

  List<Map<String, dynamic>> recentTransactions = [];

  Future<void> initialize() async {
    // housekeeping
    initializeBackgroundService();
    FlutterBackgroundService().invoke('setAsForeground');
    WakelockPlus.enable();
    _sqliteService.addColumnIfNotExists(
      'ussdCodes',
      'enabled',
      'INTEGER',
      defaultValue: 1,
    );

    await reload();
    await refreshBalances();

    _reloadTimer = Timer.periodic(const Duration(seconds: 3), (_) => reload());
  }

  void setPrefs() async {
    if(await _sharedPreferencesService.getCanAutoSwitch() == null){
      await _sharedPreferencesService.setCanAutoSwitch(true);
    }
     if(await _sharedPreferencesService.getUseSignature() == null){
      await _sharedPreferencesService.setUseSignature(true);
    }
  }

  Future<void> reload() async {
    killswitchConfig = await KillswitchService.evaluateKillswitch();

    userName = await _sharedPreferencesService.getUserName() ?? 'Bingwa';

    isLightMode = await _sharedPreferencesService.getThemeMode() == 'light';

    // final expiry = await _sharedPreferencesService.getUsableUntil() ?? 0;
    final tokenBal = await _sharedPreferencesService.getDeliveryTokens() ?? 0;
    offersMightHaveChanged =
        await _sharedPreferencesService.getOffersMightHaveChanged() ?? false;

    autoRetry = (await _sharedPreferencesService.canAutoRetrySms() ?? true) ||
        (await _sharedPreferencesService.canAutoRetryData() ?? false);

    int expiry = (await Payment.getHighestTierPayment()).till;

    hasActiveSubscription =
        (expiry > DateTime.now().millisecondsSinceEpoch) || tokenBal > 0;

    if (DateTime.now().millisecondsSinceEpoch < 1772097346000 &&
        !hasActiveSubscription) {
      // print(
      //     "Subscription expiry: ${DateTime.fromMillisecondsSinceEpoch(expiry)}, hasActiveSubscription: $hasActiveSubscription");

      PaymentOps.start1DayOnlinePlusFreeTrial();
    }

    successfulCount = await _sqliteService.getCount(
      'transactions',
      appendQuery:
          "WHERE (status = '${TransactionStatuses.done}') AND date = '${getNormalDate(DateTime.now())}'",
    );

    successfulConfirmedCount = await _sqliteService.getCount(
      'transactions',
      appendQuery:
          "WHERE status = '${TransactionStatuses.doneConfirmed}' AND date = '${getNormalDate(DateTime.now())}'",
    );

    errorCount = await _sqliteService.getCount(
      'transactions',
      appendQuery:
          "WHERE status = '${TransactionStatuses.error}' AND date = '${getNormalDate(DateTime.now())}'",
    );

    failedCount = await _sqliteService.getCount(
      'transactions',
      appendQuery:
          "WHERE ( status = '${TransactionStatuses.secondAttempt}' ) AND date = '${getNormalDate(DateTime.now())}'",
    );

    timedOutCount = await _sqliteService.getCount(
      'transactions',
      appendQuery:
          "WHERE status = '${TransactionStatuses.timedOut}' AND date = '${getNormalDate(DateTime.now())}'",
    );

    unavailableCount = await _sqliteService.getCount(
      'transactions',
      appendQuery:
          "WHERE status = '${TransactionStatuses.unavailableOffer}' AND date = '${getNormalDate(DateTime.now())}'",
    );

    forwardedCount = await _sqliteService.getCount(
      'transactions',
      appendQuery:
          "WHERE status = '${TransactionStatuses.forwarded}' AND date = '${getNormalDate(DateTime.now())}'",
    );

    pausedCount = await _sqliteService.getCount(
      'transactions',
      appendQuery:
          "WHERE status = '${TransactionStatuses.paused}' AND date = '${getNormalDate(DateTime.now())}'",
    );

    advancedCount = await _sqliteService.getCount(
      'transactions',
      appendQuery:
          "WHERE (status = '${TransactionStatuses.advancedUssd}' OR status = '${TransactionStatuses.advancedQueue}')  AND date = '${getNormalDate(DateTime.now())}'",
    );

    okoaCount = await _sqliteService.getCount(
      'transactions',
      appendQuery:
          "WHERE status = '${TransactionStatuses.hasOkoa}' AND date = '${getNormalDate(DateTime.now())}'",
    );

    blacklistedCount = await _sqliteService.getCount(
      'transactions',
      appendQuery:
          "WHERE status = '${TransactionStatuses.blacklisted}' AND date = '${getNormalDate(DateTime.now())}'",
    );

    final todays = await _sqliteService.queryDay(
      'transactions',
      getNormalDate(DateTime.now()),
      limit: 1,
    );
    recentTransactions = todays;

    transactionToday = await _sqliteService.getCount(
      'transactions',
      args: [getNormalDate(DateTime.now())],
      appendQuery: 'WHERE date = ?',
    );

    notifyListeners();
  }

  Future<void> refreshBalances() async {
    if (!hideBalance) {
      airtimeBalance = '...';
      final bal = await _phoneService.getAirtimeBalance();
      airtimeBalance = bal.toString();
    }

    if (!hideCommission) {
      estimatedCommission =
          await TransactionController().getThisWeekCommision();
    }
    notifyListeners();
  }

  void toggleHideBalance() {
    hideBalance = !hideBalance;
    refreshBalances();
  }

  void toggleHideCommission() {
    hideCommission = !hideCommission;
    refreshBalances();
  }

  void toggleVerbose() {
    verboseMode = !verboseMode;
    notifyListeners();
  }

  void toggleToolsSection() {
    showToolsSection = !showToolsSection;
    notifyListeners();
  }

  Future<void> acknowledgeOffersChecked() async {
    await _sharedPreferencesService.setOffersMightHaveChanged(false);
    offersMightHaveChanged = false;
    notifyListeners();
  }

  Future<void> setAppActive(bool isActive) async {
    await _sharedPreferencesService.setAppIsActiveState(isActive);
  }

  @override
  void dispose() {
    _reloadTimer?.cancel();
    super.dispose();
  }
}
