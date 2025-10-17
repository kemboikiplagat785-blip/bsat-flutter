import 'dart:async';

import 'package:bsat/components/dialogs/confirm_dialog.dart';
import 'package:bsat/components/dialogs/success_dialog.dart';
import 'package:bsat/components/transaction_list_item.dart';
import 'package:bsat/controllers/transaction_controller.dart';
import 'package:bsat/screens/blacklist.dart';
import 'package:bsat/screens/subscriptions/subscription.dart';
import 'package:bsat/screens/offers/offers.dart';
import 'package:bsat/screens/dialpad.dart';
import 'package:bsat/screens/foward_texts.dart';
import 'package:bsat/screens/inbox.dart';
import 'package:bsat/screens/online_management.dart';
import 'package:bsat/screens/transactions/transaction_history.dart';
import 'package:bsat/screens/replies/replies.dart';
import 'package:bsat/screens/settings/about.dart';
import 'package:bsat/screens/stats/statistics.dart';
import 'package:bsat/screens/tasks/tasks.dart';
import 'package:bsat/services/background_service.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:bsat/utils/date_ops.dart';
import 'package:bsat/utils/numbers.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:widgets_easier/widgets_easier.dart';

import 'package:wakelock_plus/wakelock_plus.dart';

import '../components/app_paused.dart';
import '../components/dialogs/change category_dialog.dart';
import '../components/no_subscription.dart';
import '../components/tool_button.dart';
import '../services/phone_service.dart';
import '../services/shared_preferences_service.dart';

import '../data/fake.dart';
import 'settings/coming_soon.dart';
import 'settings/settings.dart';

// import 'dart:async';

class DashBoardPage extends StatefulWidget {
  const DashBoardPage({super.key});

  @override
  State<DashBoardPage> createState() => _DashBoardPageState();
}

class _DashBoardPageState extends State<DashBoardPage>
    with WidgetsBindingObserver {
  List<dynamic> _transactionList = [];

  List<Widget> _transactionListItems = [];

  var _sqliteService = SQLiteService();
  final _phoneService = PhoneService();
  final _sharedPreferencesService = SharedPreferencesService();

  int transactionToday = 0;

  bool lastPage = false;
  bool codesSet = false;
  bool _hasActiveSubscription = true;
  bool _isRunning = false;
  bool _autoRetry = true;

  bool verboseMode = true;
  bool showToolsSection = true;

  int _errorCount = 0;
  int _successfulCount = 0;
  int _successfulConfirmedCount = 0;
  int _failedCount = 0;
  int _timedOutCount = 0;
  int _forwardedCount = 0;
  int _unavailableCount = 0;
  int _pausedCount = 0;
  int _advancedCount = 0;
  int _okoaCount = 0;
  int _blacklistedCount = 0;

  String _airtimeBal = "...";
  bool _hideBal = true;
  bool _hideCommission = true;
  double estimatedComission = 0.0;

  bool _offersMightHaveChanged = false;

  Timer? _reloadTimer;

  @override
  void initState() {
    super.initState();

    reload();

    initializeBackgroundService();
    _getBal();

    // print('Initing satet');
    FlutterBackgroundService().invoke('setAsForeground');

    _reloadTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      reload();
    });

    WakelockPlus.enable();

    WidgetsBinding.instance.addObserver(this);

    _sqliteService.addColumnIfNotExists(
      'ussdCodes',
      'enabled',
      'INTEGER',
      defaultValue: 1,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        print("app in resumed");
        _sharedPreferencesService.setAppIsActiveState(true);
        break;
      case AppLifecycleState.inactive:
        print("app in inactive");
      case AppLifecycleState.paused:
        print("app in paused");
      case AppLifecycleState.detached:
        print("app in detached");
      case AppLifecycleState.hidden:
        _sharedPreferencesService.setAppIsActiveState(false);
        break;
    }
  }

  void getAllUSSDCodes() async {
    await _sqliteService.queryAll('ussdCodes').then(
      (value) {
        codesSet = value.length > 0;
      },
    );
  }

  void reload() async {
    if (!mounted) return;

    int expiry = await _sharedPreferencesService.getUsableUntil() ?? 0;
    int tokenBal = await _sharedPreferencesService.getDeliveryTokens() ?? 0;

    _offersMightHaveChanged =
        await _sharedPreferencesService.getOffersMightHaveChanged() ?? false;

    _hasActiveSubscription =
        (expiry > DateTime.now().millisecondsSinceEpoch) || tokenBal > 0;

    if (!mounted) return;
    setState(() {});
    _sqliteService
        .getCount(
      'transactions',
      args: [getNormalDate(DateTime.now())],
      appendQuery: 'WHERE date = ?',
    )
        .then((value) {
      if (transactionToday == value) {
        return;
      }
    });

    getAllUSSDCodes();

    _isRunning = (await _sharedPreferencesService.isSmsRunning() ?? false) ||
        (await _sharedPreferencesService.isDataRunning() ?? false);
    _autoRetry = (await _sharedPreferencesService.canAutoRetrySms() ?? true) ||
        (await _sharedPreferencesService.canAutoRetryData() ?? false);

    _successfulCount = await _sqliteService.getCount(
      'transactions',
      appendQuery:
          "WHERE (status = '${TransactionStatuses.done}') AND date = '${getNormalDate(DateTime.now())}'",
    );

    _successfulConfirmedCount = await _sqliteService.getCount(
      'transactions',
      appendQuery:
          "WHERE status = '${TransactionStatuses.doneConfirmed}' AND date = '${getNormalDate(DateTime.now())}'",
    );

    _errorCount = await _sqliteService.getCount(
      'transactions',
      appendQuery:
          "WHERE status = '${TransactionStatuses.error}' AND date = '${getNormalDate(DateTime.now())}'",
    );

    _failedCount = await _sqliteService.getCount(
      'transactions',
      appendQuery:
          "WHERE ( status = '${TransactionStatuses.secondAttempt}' ) AND date = '${getNormalDate(DateTime.now())}'",
    );

    _timedOutCount = await _sqliteService.getCount(
      'transactions',
      appendQuery:
          "WHERE status = '${TransactionStatuses.timedOut}' AND date = '${getNormalDate(DateTime.now())}'",
    );

    _unavailableCount = await _sqliteService.getCount(
      'transactions',
      appendQuery:
          "WHERE status = '${TransactionStatuses.unavailableOffer}' AND date = '${getNormalDate(DateTime.now())}'",
    );

    _forwardedCount = await _sqliteService.getCount(
      'transactions',
      appendQuery:
          "WHERE status = '${TransactionStatuses.forwarded}' AND date = '${getNormalDate(DateTime.now())}'",
    );

    _pausedCount = await _sqliteService.getCount(
      'transactions',
      appendQuery:
          "WHERE status = '${TransactionStatuses.paused}' AND date = '${getNormalDate(DateTime.now())}'",
    );

    _advancedCount = await _sqliteService.getCount(
      'transactions',
      appendQuery:
          "WHERE (status = '${TransactionStatuses.advancedUssd}' OR status = '${TransactionStatuses.advancedQueue}')  AND date = '${getNormalDate(DateTime.now())}'",
    );

    _okoaCount = await _sqliteService.getCount(
      'transactions',
      appendQuery:
          "WHERE status = '${TransactionStatuses.hasOkoa}' AND date = '${getNormalDate(DateTime.now())}'",
    );

    _blacklistedCount = await _sqliteService.getCount(
      'transactions',
      appendQuery:
          "WHERE status = '${TransactionStatuses.blacklisted}' AND date = '${getNormalDate(DateTime.now())}'",
    );

    await _sqliteService
        .queryDay(
      'transactions',
      getNormalDate(DateTime.now()),
      limit: 1,
    )
        .then(
      (value) {
        if (!mounted) return;
        _transactionListItems.clear();
        for (var i in value) {
          _transactionListItems.add(transactionListItem(
            context,
            i['number'],
            i['amount'],
            i['status'],
            i['ussdReply'],
            i['date'],
            i['time'],
            i['id'],
            i['ussdDialed'],
            i['source'],
            i['simSubId'],
            i['canRetry'] ?? 0,
            lineLimit: 1,
          ));
        }
      },
    );

    _sqliteService
        .getCount(
      'transactions',
      args: [getNormalDate(DateTime.now())],
      appendQuery: 'WHERE date = ?',
    )
        .then((value) {
      if (mounted && transactionToday != value) {
        setState(() {
          transactionToday = value;
        });
      }
    });

    _offersMightHaveChanged =
        await _sharedPreferencesService.getOffersMightHaveChanged() ?? false;

    setState(() {});
  }

  void _getBal() async {
    if (!mounted) return;
    if (!_hideBal) {
      _airtimeBal = "...";

      _phoneService.getAirtimeBalance().then((value) {
        if (!mounted) return;

        _airtimeBal = value.toString();
        setState(() {});
      });
    }

    if (!_hideCommission) {
      estimatedComission = await TransactionController().getThisWeekCommision();
      setState(() {});
    }
  }

  @override
  void dispose() {
    _reloadTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: kPagePadding * 2),
            Container(
              padding: kPagePaddingInsets,
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(.05),
                borderRadius: BorderRadius.circular(kBorderRadius),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(
                        '${getGreeting(withEmoji: true)}, Bingwa',
                        // style: textTheme.titleLarge,
                        style: TextStyle(
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: kPagePadding),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Container(
                          decoration: ShapeDecoration(
                            shape: SolidBorder(
                              width: 1,
                              borderRadius: BorderRadius.circular(12),
                              gradient: LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  Theme.of(context).indicatorColor,
                                  Colors.transparent,
                                  Theme.of(context).indicatorColor,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                          ),
                          child: GestureDetector(
                            onTap: () {
                              reload();
                              _getBal();
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _hideBal = !_hideBal;
                                        });
                                        _getBal();
                                      },
                                      child: Icon(
                                        _hideBal
                                            ? CupertinoIcons.eye
                                            : CupertinoIcons.eye_slash,
                                        size: 16,
                                        // color: Colors.white,
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () {
                                        reload();
                                        _getBal();
                                      },
                                      icon: const Icon(
                                        CupertinoIcons.refresh,
                                        size: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    // const SizedBox(width: kPagePadding / 3),
                                    const Text('Ksh   '),
                                    Text(
                                      _hideBal
                                          ? '...'
                                          : Numbers.formatNumber(
                                              int.tryParse(_airtimeBal) ?? 0),
                                      // '2,334,507.00',
                                      style: textTheme.headlineLarge!.merge(
                                        TextStyle(
                                            color: Theme.of(context)
                                                .indicatorColor),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: kPagePadding / 2),
                                const Text(
                                  'Airtime',
                                ),
                                const SizedBox(height: kPagePadding),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: kPagePadding / 2),
                      Expanded(
                        child: Container(
                          decoration: ShapeDecoration(
                            shape: SolidBorder(
                              width: 1,
                              borderRadius: BorderRadius.circular(12),
                              gradient: LinearGradient(
                                colors: [
                                  Theme.of(context).indicatorColor,
                                  Colors.transparent,
                                  Theme.of(context).indicatorColor,
                                  Colors.transparent,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                          ),
                          child: GestureDetector(
                            onTap: () {
                              reload();
                              _getBal();
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          // _airtimeBal = '...';
                                          _hideCommission = !_hideCommission;
                                        });
                                        _getBal();
                                        // _airtimeBal = '...';
                                      },
                                      child: Icon(
                                        _hideCommission
                                            ? CupertinoIcons.eye
                                            : CupertinoIcons.eye_slash,
                                        size: 16,
                                        // color: Colors.white,
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () {
                                        reload();
                                        _getBal();
                                      },
                                      icon: const Icon(
                                        CupertinoIcons.refresh,
                                        size: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    // const SizedBox(width: kPagePadding / 3),
                                    const Text('Ksh '),
                                    Text(
                                      _hideCommission
                                          ? '...'
                                          : Numbers.formatNumber(
                                              int.parse(
                                                estimatedComission
                                                    .toStringAsFixed(0),
                                              ),
                                            ),
                                      style: textTheme.headlineLarge!.merge(
                                        TextStyle(
                                            color: Theme.of(context)
                                                .indicatorColor),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: kPagePadding / 2),
                                const Text(
                                  'Est. Commission',
                                ),
                                const SizedBox(height: kPagePadding),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: kPagePadding),
                  _hasActiveSubscription
                      ? const SizedBox()
                      : noBalanceButton(context),
                  !_isRunning ? appPausedButton(context) : const SizedBox(),
                  _autoRetry
                      ? const SizedBox()
                      : appPausedButton(
                          context,
                          text: 'Auto retry is disabled. Click to enable',
                        ),
                  _offersMightHaveChanged
                      ? appPausedButton(
                          context,
                          text: 'Offers might have changed. Click to resume',
                          onTap: () async {
                            if ((await showConfirmDialog(
                                  context,
                                  title: 'Warning',
                                  message:
                                      'Make sure you have checked the offers and they are correct before resuming.',
                                )) ??
                                false) {
                              _sharedPreferencesService
                                  .setOffersMightHaveChanged(false);

                              showSuccessDialog(context, 'Resumed');
                            }
                            reload();
                          },
                        )
                      : const SizedBox(),
                  Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          toolButton(
                            () {
                              Navigator.of(context)
                                  .push(
                                    PageRouteBuilder(
                                      pageBuilder: (context, animation,
                                              secondaryAnimation) =>
                                          const TransactionHistoryPage(),
                                      transitionsBuilder: (context, animation,
                                          secondaryAnimation, child) {
                                        return CupertinoPageTransition(
                                          primaryRouteAnimation: animation,
                                          secondaryRouteAnimation:
                                              secondaryAnimation,
                                          linearTransition: true,
                                          child: child,
                                        );
                                      },
                                    ),
                                  )
                                  .then((value) => reload());
                            },
                            Icon(
                              verboseMode
                                  ? CupertinoIcons.eye_slash
                                  : CupertinoIcons.eye,
                              size: 0,
                            ),
                            "All ($transactionToday) >",
                            context,
                            withBorder: true,
                          ),
                          toolButton(
                            () {
                              setState(() {
                                verboseMode = !verboseMode;
                              });
                            },
                            Icon(
                              verboseMode
                                  ? CupertinoIcons.eye_slash
                                  : CupertinoIcons.eye,
                              size: 14,
                            ),
                            "",
                            context,
                            withBorder: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: kPagePadding / 2),
                      // make wrpa fit full width
                      // crossAxisAlignment: CrossAxisAlignment.start,
                      // mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      // mainAxisSize: MainAxisSize.max,

                      Container(
                        width: double.infinity,
                        child: Wrap(
                          // crossAxisAlignment: WrapCrossAlignment.start,
                          alignment: verboseMode
                              ? WrapAlignment.center
                              : WrapAlignment.center,
                          runSpacing: kPagePadding / 4,

                          // mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            toolButton(
                              () {
                                Navigator.of(context)
                                    .push(
                                      PageRouteBuilder(
                                        pageBuilder: (context, animation,
                                                secondaryAnimation) =>
                                            const TransactionHistoryPage(
                                          query:
                                              TransactionStatuses.doneConfirmed,
                                        ),
                                        transitionsBuilder: (context, animation,
                                            secondaryAnimation, child) {
                                          return CupertinoPageTransition(
                                            primaryRouteAnimation: animation,
                                            secondaryRouteAnimation:
                                                secondaryAnimation,
                                            linearTransition: true,
                                            child: child,
                                          );
                                        },
                                      ),
                                    )
                                    .then(
                                      (value) => reload(),
                                    );
                              },
                              const Icon(CupertinoIcons.checkmark_seal_fill,
                                  color: kPrimaryColor, size: 14),
                              _successfulConfirmedCount.toString(),
                              otherText:
                                  verboseMode ? "successful(confirmed)" : null,
                              context,
                              withBorder: true,
                              accentColor: kPrimaryColor,
                            ),
                            const SizedBox(width: kPagePadding / 4),
                            toolButton(
                              () {
                                Navigator.of(context)
                                    .push(
                                      PageRouteBuilder(
                                        pageBuilder: (context, animation,
                                                secondaryAnimation) =>
                                            const TransactionHistoryPage(
                                          query: TransactionStatuses.done,
                                        ),
                                        transitionsBuilder: (context, animation,
                                            secondaryAnimation, child) {
                                          return CupertinoPageTransition(
                                            primaryRouteAnimation: animation,
                                            secondaryRouteAnimation:
                                                secondaryAnimation,
                                            linearTransition: true,
                                            child: child,
                                          );
                                        },
                                      ),
                                    )
                                    .then(
                                      (value) => reload(),
                                    );
                              },
                              const Icon(CupertinoIcons.checkmark_alt,
                                  color: kWarningColor, size: 14),
                              _successfulCount.toString(),
                              otherText:
                                  verboseMode ? "successful(pending)" : null,
                              context,
                              withBorder: true,
                              accentColor: kPrimaryColor,
                            ),
                            const SizedBox(width: kPagePadding / 4),
                            toolButton(
                              () {
                                Navigator.of(context)
                                    .push(
                                      PageRouteBuilder(
                                        pageBuilder: (context, animation,
                                                secondaryAnimation) =>
                                            const TransactionHistoryPage(
                                          query:
                                              TransactionStatuses.advancedUssd,
                                        ),
                                        transitionsBuilder: (context, animation,
                                            secondaryAnimation, child) {
                                          return CupertinoPageTransition(
                                            primaryRouteAnimation: animation,
                                            secondaryRouteAnimation:
                                                secondaryAnimation,
                                            linearTransition: true,
                                            child: child,
                                          );
                                        },
                                      ),
                                    )
                                    .then(
                                      (value) => reload(),
                                    );
                              },
                              Icon(
                                CupertinoIcons.phone_circle_fill,
                                color: kPrimaryColor,
                                size: 14,
                              ),
                              _advancedCount.toString(),
                              otherText: verboseMode ? "advanced" : null,
                              context,
                              withBorder: true,
                              accentColor: kPrimaryColor,
                            ),
                            const SizedBox(width: kPagePadding / 4),
                            toolButton(
                              () {
                                Navigator.of(context)
                                    .push(
                                      PageRouteBuilder(
                                        pageBuilder: (context, animation,
                                                secondaryAnimation) =>
                                            const TransactionHistoryPage(
                                          query:
                                              TransactionStatuses.forwarded,
                                        ),
                                        transitionsBuilder: (context, animation,
                                            secondaryAnimation, child) {
                                          return CupertinoPageTransition(
                                            primaryRouteAnimation: animation,
                                            secondaryRouteAnimation:
                                                secondaryAnimation,
                                            linearTransition: true,
                                            child: child,
                                          );
                                        },
                                      ),
                                    )
                                    .then(
                                      (value) => reload(),
                                    );
                              },
                              Icon(
                                CupertinoIcons.arrow_turn_right_up,
                                color: kPrimaryColor,
                                size: 14,
                              ),
                              _forwardedCount.toString(),
                              otherText: verboseMode ? "forwarded" : null,
                              context,
                              withBorder: true,
                              accentColor: kPrimaryColor,
                            ),
                            const SizedBox(width: kPagePadding / 4),
                            toolButton(
                              () {
                                Navigator.of(context)
                                    .push(
                                      PageRouteBuilder(
                                        pageBuilder: (context, animation,
                                                secondaryAnimation) =>
                                            const TransactionHistoryPage(
                                          query:
                                              TransactionStatuses.secondAttempt,
                                        ),
                                        transitionsBuilder: (context, animation,
                                            secondaryAnimation, child) {
                                          return CupertinoPageTransition(
                                            primaryRouteAnimation: animation,
                                            secondaryRouteAnimation:
                                                secondaryAnimation,
                                            linearTransition: true,
                                            child: child,
                                          );
                                        },
                                      ),
                                    )
                                    .then(
                                      (value) => reload(),
                                    );
                              },
                              const Icon(CupertinoIcons.arrow_2_circlepath,
                                  color: kWarningColor, size: 14),
                              _failedCount.toString(),
                              otherText: verboseMode ? "second attempt" : null,
                              context,
                              withBorder: true,
                              accentColor: kWarningColor,
                            ),
                            const SizedBox(width: kPagePadding / 4),
                            toolButton(
                              () {
                                Navigator.of(context)
                                    .push(
                                      PageRouteBuilder(
                                        pageBuilder: (context, animation,
                                                secondaryAnimation) =>
                                            const TransactionHistoryPage(
                                          query: TransactionStatuses.paused,
                                        ),
                                        transitionsBuilder: (context, animation,
                                            secondaryAnimation, child) {
                                          return CupertinoPageTransition(
                                            primaryRouteAnimation: animation,
                                            secondaryRouteAnimation:
                                                secondaryAnimation,
                                            linearTransition: true,
                                            child: child,
                                          );
                                        },
                                      ),
                                    )
                                    .then(
                                      (value) => reload(),
                                    );
                              },
                              Icon(
                                CupertinoIcons.pause_circle_fill,
                                color: Theme.of(context).hintColor,
                                size: 14,
                              ),
                              _pausedCount.toString(),
                              otherText: verboseMode ? "paused" : null,
                              context,
                              withBorder: true,
                              accentColor: kWarningColor,
                            ),
                            const SizedBox(width: kPagePadding / 4),
                            toolButton(
                              () {
                                Navigator.of(context)
                                    .push(
                                      PageRouteBuilder(
                                        pageBuilder: (context, animation,
                                                secondaryAnimation) =>
                                            const TransactionHistoryPage(
                                          query: TransactionStatuses.hasOkoa,
                                        ),
                                        transitionsBuilder: (context, animation,
                                            secondaryAnimation, child) {
                                          return CupertinoPageTransition(
                                            primaryRouteAnimation: animation,
                                            secondaryRouteAnimation:
                                                secondaryAnimation,
                                            linearTransition: true,
                                            child: child,
                                          );
                                        },
                                      ),
                                    )
                                    .then(
                                      (value) => reload(),
                                    );
                              },
                              Icon(
                                Icons.sailing_rounded,
                                color: kDullColor,
                                size: 14,
                              ),
                              _okoaCount.toString(),
                              otherText: verboseMode ? "okoa" : null,
                              context,
                              withBorder: true,
                              accentColor: kBgColor,
                            ),
                            const SizedBox(width: kPagePadding / 4),
                            toolButton(
                              () {
                                Navigator.of(context)
                                    .push(
                                      PageRouteBuilder(
                                        pageBuilder: (context, animation,
                                                secondaryAnimation) =>
                                            const TransactionHistoryPage(
                                          query: TransactionStatuses
                                              .unavailableOffer,
                                        ),
                                        transitionsBuilder: (context, animation,
                                            secondaryAnimation, child) {
                                          return CupertinoPageTransition(
                                            primaryRouteAnimation: animation,
                                            secondaryRouteAnimation:
                                                secondaryAnimation,
                                            linearTransition: true,
                                            child: child,
                                          );
                                        },
                                      ),
                                    )
                                    .then(
                                      (value) => reload(),
                                    );
                              },
                              Icon(
                                CupertinoIcons.exclamationmark_triangle,
                                color: Theme.of(context).indicatorColor,
                                size: 14,
                              ),
                              _unavailableCount.toString(),
                              otherText:
                                  verboseMode ? "unavailable offers" : null,
                              context,
                              withBorder: true,
                              accentColor: Theme.of(context).indicatorColor,
                            ),
                            const SizedBox(width: kPagePadding / 4),
                            toolButton(
                              () {
                                Navigator.of(context)
                                    .push(
                                      PageRouteBuilder(
                                        pageBuilder: (context, animation,
                                                secondaryAnimation) =>
                                            const TransactionHistoryPage(
                                          query: 'blacklist',
                                        ),
                                        transitionsBuilder: (context, animation,
                                            secondaryAnimation, child) {
                                          return CupertinoPageTransition(
                                            primaryRouteAnimation: animation,
                                            secondaryRouteAnimation:
                                                secondaryAnimation,
                                            linearTransition: true,
                                            child: child,
                                          );
                                        },
                                      ),
                                    )
                                    .then(
                                      (value) => reload(),
                                    );
                              },
                              const Icon(
                                Icons.person_off_outlined,
                                color: kWarningColor,
                                size: 14,
                              ),
                              _blacklistedCount.toString(),
                              otherText: verboseMode ? "blacklisted" : null,
                              context,
                              withBorder: true,
                              accentColor: kErrorColor,
                            ),
                            const SizedBox(width: kPagePadding / 4),
                            toolButton(
                              () {
                                Navigator.of(context)
                                    .push(
                                      PageRouteBuilder(
                                        pageBuilder: (context, animation,
                                                secondaryAnimation) =>
                                            const TransactionHistoryPage(
                                          query: TransactionStatuses.error,
                                        ),
                                        transitionsBuilder: (context, animation,
                                            secondaryAnimation, child) {
                                          return CupertinoPageTransition(
                                            primaryRouteAnimation: animation,
                                            secondaryRouteAnimation:
                                                secondaryAnimation,
                                            linearTransition: true,
                                            child: child,
                                          );
                                        },
                                      ),
                                    )
                                    .then(
                                      (value) => reload(),
                                    );
                              },
                              const Icon(CupertinoIcons.xmark_circle_fill,
                                  color: kErrorColor, size: 14),
                              _errorCount.toString(),
                              otherText: verboseMode ? "errors" : null,
                              context,
                              withBorder: true,
                              accentColor: kErrorColor,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: kPagePadding / 2),
                      _transactionListItems.isNotEmpty
                          ? _transactionListItems[0]
                          : const Text("No transactions today :("),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: kPagePadding),
            InkWell(
              onTap: () {
                setState(() {
                  showToolsSection = !showToolsSection;
                });
              },
              child: Padding(
                padding: EdgeInsets.all(kPagePadding),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "My tools",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Icon(showToolsSection
                        ? CupertinoIcons.chevron_up
                        : CupertinoIcons.chevron_down)
                  ],
                ),
              ),
            ),
            if (showToolsSection) StatelessDashboard(reload),
          ],
        ),
      ),
    );
  }
}

class StatelessDashboard extends StatelessWidget {
  final Function reload;
  const StatelessDashboard(this.reload, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: kPagePadding,
        right: kPagePadding,
        bottom: kPagePadding * 2,
      ),
      child: Container(
        padding: kPagePaddingInsets / 2,
        decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withOpacity(.05),
            borderRadius: BorderRadius.circular(kBorderRadius / 2)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(),
            const Text("Automation tools"),
            const SizedBox(height: kPagePadding / 2),
            Wrap(
              runSpacing: kPagePadding / 2,
              alignment: WrapAlignment.spaceBetween,
              spacing: kPagePadding / 4,
              children: [
                toolButton(
                  () {
                    Navigator.of(context)
                        .push(
                          PageRouteBuilder(
                            pageBuilder:
                                (context, animation, secondaryAnimation) =>
                                    const OffersPage(),
                            transitionsBuilder: (context, animation,
                                secondaryAnimation, child) {
                              return CupertinoPageTransition(
                                primaryRouteAnimation: animation,
                                secondaryRouteAnimation: secondaryAnimation,
                                linearTransition: true,
                                child: child,
                              );
                            },
                          ),
                        )
                        .then((value) => reload());

                    // if (kDebugMode) {
                    //   DummyDataInserter().insertFakeTransactions(5);
                    // }
                  },
                  const Icon(Icons.auto_awesome_mosaic_outlined,
                      color: kErrorColor),
                  "Offers",
                  context,
                ),
                toolButton(
                  () {
                    Navigator.of(context)
                        .push(
                          PageRouteBuilder(
                            pageBuilder:
                                (context, animation, secondaryAnimation) =>
                                    RepliesPage(),
                            transitionsBuilder: (context, animation,
                                secondaryAnimation, child) {
                              return CupertinoPageTransition(
                                primaryRouteAnimation: animation,
                                secondaryRouteAnimation: secondaryAnimation,
                                linearTransition: true,
                                child: child,
                              );
                            },
                          ),
                        )
                        .then((value) => reload());
                  },
                  const Icon(CupertinoIcons.circle_grid_hex, color: kDullColor),
                  "Replies",
                  context,
                ),
                toolButton(
                  () {
                    Navigator.of(context)
                        .push(
                          PageRouteBuilder(
                            pageBuilder:
                                (context, animation, secondaryAnimation) =>
                                    const TaskManagerPage(),
                            transitionsBuilder: (context, animation,
                                secondaryAnimation, child) {
                              return CupertinoPageTransition(
                                primaryRouteAnimation: animation,
                                secondaryRouteAnimation: secondaryAnimation,
                                linearTransition: true,
                                child: child,
                              );
                            },
                          ),
                        )
                        .then((value) => reload());
                  },
                  Icon(Icons.precision_manufacturing_outlined,
                      color: Theme.of(context).indicatorColor),
                  "Scheduler",
                  context,
                ),
                toolButton(
                  () {
                    Navigator.of(context)
                        .push(
                          PageRouteBuilder(
                            pageBuilder:
                                (context, animation, secondaryAnimation) =>
                                    const ForwardTextsPage(),
                            transitionsBuilder: (context, animation,
                                secondaryAnimation, child) {
                              return CupertinoPageTransition(
                                primaryRouteAnimation: animation,
                                secondaryRouteAnimation: secondaryAnimation,
                                linearTransition: true,
                                child: child,
                              );
                            },
                          ),
                        )
                        .then((value) => reload());
                  },
                  Icon(CupertinoIcons.phone_arrow_up_right,
                      color: Theme.of(context).indicatorColor),
                  "Use another phone",
                  context,
                ),
              ],
            ),
            const SizedBox(height: kPagePadding),
            const Text("Data"),
            const SizedBox(height: kPagePadding / 2),
            Wrap(
              runSpacing: kPagePadding / 2,
              runAlignment: WrapAlignment.spaceBetween,
              // alignment: WrapAlignment.spaceBetween,
              spacing: kPagePadding / 4,
              children: [
                toolButton(
                  () {
                    Navigator.of(context)
                        .push(
                          PageRouteBuilder(
                            pageBuilder:
                                (context, animation, secondaryAnimation) =>
                                    const TransactionHistoryPage(),
                            transitionsBuilder: (context, animation,
                                secondaryAnimation, child) {
                              return CupertinoPageTransition(
                                primaryRouteAnimation: animation,
                                secondaryRouteAnimation: secondaryAnimation,
                                linearTransition: true,
                                child: child,
                              );
                            },
                          ),
                        )
                        .then((value) => reload());
                  },
                  const Icon(CupertinoIcons.clock, color: kPrimaryColor),
                  "History",
                  context,
                ),
                toolButton(
                  () {
                    Navigator.of(context)
                        .push(
                          PageRouteBuilder(
                            pageBuilder:
                                (context, animation, secondaryAnimation) =>
                                    const StatisticsPage(),
                            transitionsBuilder: (context, animation,
                                secondaryAnimation, child) {
                              return CupertinoPageTransition(
                                primaryRouteAnimation: animation,
                                secondaryRouteAnimation: secondaryAnimation,
                                linearTransition: true,
                                child: child,
                              );
                            },
                          ),
                        )
                        .then(
                          (value) => reload(),
                        );
                  },
                  const Icon(
                    Icons.auto_graph_rounded,
                    color: kDullColor,
                  ),
                  "Stats",
                  context,
                ),
                toolButton(
                  () {
                    Navigator.of(context)
                        .push(
                          PageRouteBuilder(
                            pageBuilder:
                                (context, animation, secondaryAnimation) =>
                                    DialPadScreen(),
                            transitionsBuilder: (context, animation,
                                secondaryAnimation, child) {
                              return CupertinoPageTransition(
                                primaryRouteAnimation: animation,
                                secondaryRouteAnimation: secondaryAnimation,
                                linearTransition: true,
                                child: child,
                              );
                            },
                          ),
                        )
                        .then((value) => reload());
                  },
                  const Icon(
                    Icons.dialpad_outlined,
                    color: kErrorColor,
                  ),
                  "DialPad",
                  context,
                ),
                toolButton(
                  () {
                    Navigator.of(context)
                        .push(
                          PageRouteBuilder(
                            pageBuilder:
                                (context, animation, secondaryAnimation) =>
                                    const InboxPage(),
                            transitionsBuilder: (context, animation,
                                secondaryAnimation, child) {
                              return CupertinoPageTransition(
                                primaryRouteAnimation: animation,
                                secondaryRouteAnimation: secondaryAnimation,
                                linearTransition: true,
                                child: child,
                              );
                            },
                          ),
                        )
                        .then((value) => reload());
                  },
                  const Icon(CupertinoIcons.mail, color: kWarningColor),
                  "Inbox",
                  context,
                ),
                toolButton(
                  () {
                    Navigator.of(context)
                        .push(
                          PageRouteBuilder(
                            pageBuilder:
                                (context, animation, secondaryAnimation) =>
                                    BlacklistPage(),
                            transitionsBuilder: (context, animation,
                                secondaryAnimation, child) {
                              return CupertinoPageTransition(
                                primaryRouteAnimation: animation,
                                secondaryRouteAnimation: secondaryAnimation,
                                linearTransition: true,
                                child: child,
                              );
                            },
                          ),
                        )
                        .then((value) => reload());
                  },
                  Icon(Icons.person_off_outlined,
                      color: Theme.of(context).indicatorColor),
                  "Blacklist",
                  context,
                ),
              ],
            ),
            const SizedBox(height: kPagePadding),
            const Text("Me and BSAT"),
            const SizedBox(height: kPagePadding / 2),
            Wrap(
              runSpacing: kPagePadding / 2,
              // alignment: WrapAlignment.spaceBetween,
              spacing: kPagePadding / 4,
              children: [
                // toolButton(
                //   () {},
                //   const Icon(CupertinoIcons.person,
                //       color: kPrimaryColor),
                //   "Profile",
                // ),
                if (kDebugMode)
                  toolButton(
                    () {
                      // Navigator.of(context).push(
                      //   PageRouteBuilder(
                      //     pageBuilder: (context, animation,
                      //             secondaryAnimation) =>
                      //         const BarChartSample6(),
                      //     transitionsBuilder: (context, animation,
                      //         secondaryAnimation, child) {
                      //       return CupertinoPageTransition(
                      //         primaryRouteAnimation: animation,
                      //         secondaryRouteAnimation:
                      //             secondaryAnimation,
                      //         linearTransition: true,
                      //         child: child,
                      //       );
                      //     },
                      //   ),
                      // );

                      // throw Exception();

                      // DummyDataInserter().insertFakeTransactions(20);

                      showChangeCategoryDialog(context);
                    },
                    const Icon(CupertinoIcons.globe, color: kIndigoColor),
                    "Test",
                    context,
                  ),
                toolButton(
                  () {
                    Navigator.of(context)
                        .push(
                          PageRouteBuilder(
                            pageBuilder:
                                (context, animation, secondaryAnimation) =>
                                    const SubscriptionPage(),
                            transitionsBuilder: (context, animation,
                                secondaryAnimation, child) {
                              return CupertinoPageTransition(
                                primaryRouteAnimation: animation,
                                secondaryRouteAnimation: secondaryAnimation,
                                linearTransition: true,
                                child: child,
                              );
                            },
                          ),
                        )
                        .then((value) => reload());
                  },
                  Icon(CupertinoIcons.money_dollar,
                      color: Theme.of(context).indicatorColor),
                  "Subscription",
                  context,
                ),
                toolButton(
                  () async {
                    // sendReply('Testing', '254714951041');
                    // showRetryDialog(context);
                    Navigator.of(context)
                        .push(
                          PageRouteBuilder(
                            pageBuilder:
                                (context, animation, secondaryAnimation) =>
                                    const AboutPage(),
                            transitionsBuilder: (context, animation,
                                secondaryAnimation, child) {
                              return CupertinoPageTransition(
                                primaryRouteAnimation: animation,
                                secondaryRouteAnimation: secondaryAnimation,
                                linearTransition: true,
                                child: child,
                              );
                            },
                          ),
                        )
                        .then((value) => reload());
                  },
                  const Icon(Icons.stairs_outlined, color: kDullColor),
                  "About BSAT",
                  context,
                ),
                toolButton(
                  () {
                    Navigator.of(context)
                        .push(
                          PageRouteBuilder(
                            pageBuilder:
                                (context, animation, secondaryAnimation) =>
                                    const SettingsPage(),
                            transitionsBuilder: (context, animation,
                                secondaryAnimation, child) {
                              return CupertinoPageTransition(
                                primaryRouteAnimation: animation,
                                secondaryRouteAnimation: secondaryAnimation,
                                linearTransition: true,
                                child: child,
                              );
                            },
                          ),
                        )
                        .then((value) => reload());
                  },
                  const Icon(CupertinoIcons.gear, color: kPrimaryColor),
                  "Settings",
                  context,
                ),
                toolButton(
                  () {
                    Navigator.of(context)
                        .push(
                          PageRouteBuilder(
                            pageBuilder:
                                (context, animation, secondaryAnimation) =>
                                    // const OnlineManagementScreen(),
                            ComingSoonPage(),
                            transitionsBuilder: (context, animation,
                                secondaryAnimation, child) {
                              return CupertinoPageTransition(
                                primaryRouteAnimation: animation,
                                secondaryRouteAnimation: secondaryAnimation,
                                linearTransition: true,
                                child: child,
                              );
                            },
                          ),
                        )
                        .then((value) => reload());
                  },
                  const Icon(
                    CupertinoIcons.globe,
                    color: kWarningColor,
                  ),
                  "Online management",
                  context,
                ),
              ],
            ),
            const SizedBox(height: kPagePadding),
          ],
        ),
      ),
    );
  }
}
