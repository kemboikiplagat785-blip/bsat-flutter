import 'dart:async';

import 'package:bsat/components/dialogs/confirm_delete_dialog.dart';
import 'package:bsat/components/dialogs/success_dialog.dart';
import 'package:bsat/components/transaction_list_item.dart';
import 'package:bsat/screens/dashboard/dashboard_tools.dart';
import 'package:bsat/screens/transactions/transaction_history.dart';
import 'package:bsat/utils/constants.dart';
import 'package:bsat/utils/date_ops.dart';
import 'package:bsat/utils/numbers.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:widgets_easier/widgets_easier.dart';

import '../../../components/app_paused.dart';
import '../../../components/dialogs/change category_dialog.dart';
import '../../../components/no_subscription.dart';
import '../../../components/tool_button.dart';
import 'dashboard_view_model.dart';
import '../settings/settings.dart';

/// Main dashboard surface: greets the agent, shows KPIs, and links to tools.
class DashBoardPage extends StatefulWidget {
  const DashBoardPage({super.key});

  @override
  State<DashBoardPage> createState() => _DashBoardPageState();
}

class _DashBoardPageState extends State<DashBoardPage>
    with WidgetsBindingObserver {
  late final DashboardViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    // Set up the shared view model and start background data loading.
    _viewModel = DashboardViewModel();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_viewModel.initialize());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_viewModel.setAppActive(true));
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        unawaited(_viewModel.setAppActive(false));
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<DashboardViewModel>.value(
      value: _viewModel,
      child: Consumer<DashboardViewModel>(
        builder: (context, vm, child) {
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
                              '${getGreeting(withEmoji: true)}, ${vm.userName}',
                              style: const TextStyle(fontSize: 18),
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
                                    vm.reload();
                                    vm.refreshBalances();
                                  },
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          GestureDetector(
                                            onTap: vm.toggleHideBalance,
                                            child: Icon(
                                              vm.hideBalance
                                                  ? CupertinoIcons.eye
                                                  : CupertinoIcons.eye_slash,
                                              size: 16,
                                            ),
                                          ),
                                          IconButton(
                                            onPressed: () {
                                              vm.reload();
                                              vm.refreshBalances();
                                            },
                                            icon: const Icon(
                                              CupertinoIcons.refresh,
                                              size: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Text('Ksh   '),
                                          Text(
                                            vm.hideBalance
                                                ? '...'
                                                : Numbers.formatNumber(
                                                    int.tryParse(vm
                                                            .airtimeBalance) ??
                                                        0,
                                                  ),
                                            style:
                                                textTheme.headlineLarge!.merge(
                                              TextStyle(
                                                color: Theme.of(context)
                                                    .indicatorColor,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: kPagePadding / 2),
                                      const Text('Airtime'),
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
                                    vm.reload();
                                    vm.refreshBalances();
                                  },
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          GestureDetector(
                                            onTap: vm.toggleHideCommission,
                                            child: Icon(
                                              vm.hideCommission
                                                  ? CupertinoIcons.eye
                                                  : CupertinoIcons.eye_slash,
                                              size: 16,
                                            ),
                                          ),
                                          IconButton(
                                            onPressed: () {
                                              vm.reload();
                                              vm.refreshBalances();
                                            },
                                            icon: const Icon(
                                              CupertinoIcons.refresh,
                                              size: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Text('Ksh '),
                                          Text(
                                            vm.hideCommission
                                                ? '...'
                                                : Numbers.formatNumber(
                                                    int.parse(
                                                      vm.estimatedCommission
                                                          .toStringAsFixed(0),
                                                    ),
                                                  ),
                                            style:
                                                textTheme.headlineLarge!.merge(
                                              TextStyle(
                                                color: Theme.of(context)
                                                    .indicatorColor,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: kPagePadding / 2),
                                      const Text('Est. Commission'),
                                      const SizedBox(height: kPagePadding),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: kPagePadding),
                        vm.hasActiveSubscription
                            ? const SizedBox()
                            : noBalanceButton(context),
                        vm.isRunning
                            ? const SizedBox()
                            : appPausedButton(context),
                        vm.autoRetry
                            ? const SizedBox()
                            : appPausedButton(
                                context,
                                text: 'Auto retry is disabled. Click to enable',
                              ),
                        vm.offersMightHaveChanged
                            ? appPausedButton(
                                context,
                                text:
                                    'Offers might have changed. Click to resume',
                                onTap: () async {
                                  if ((await showConfirmDeleteDialog(
                                        context,
                                        title: 'Warning',
                                        message:
                                            'Make sure you have checked the offers and they are correct before resuming.',
                                      )) ??
                                      false) {
                                    await vm.acknowledgeOffersChecked();
                                    showSuccessDialog(context, text: 'Resumed');
                                  }
                                  vm.reload();
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
                                            transitionsBuilder: (context,
                                                animation,
                                                secondaryAnimation,
                                                child) {
                                              return CupertinoPageTransition(
                                                primaryRouteAnimation:
                                                    animation,
                                                secondaryRouteAnimation:
                                                    secondaryAnimation,
                                                linearTransition: true,
                                                child: child,
                                              );
                                            },
                                          ),
                                        )
                                        .then((value) => vm.reload());
                                  },
                                  Icon(
                                    vm.verboseMode
                                        ? CupertinoIcons.eye_slash
                                        : CupertinoIcons.eye,
                                    size: 0,
                                  ),
                                  "All (${vm.transactionToday}) >",
                                  context,
                                  withBorder: true,
                                ),
                                toolButton(
                                  vm.toggleVerbose,
                                  Icon(
                                    vm.verboseMode
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
                            Container(
                              width: double.infinity,
                              child: Wrap(
                                alignment: WrapAlignment.center,
                                runSpacing: kPagePadding / 4,
                                children: [
                                  toolButton(
                                    () {
                                      Navigator.of(context)
                                          .push(
                                            PageRouteBuilder(
                                              pageBuilder: (context, animation,
                                                      secondaryAnimation) =>
                                                  const TransactionHistoryPage(
                                                query: TransactionStatuses
                                                    .doneConfirmed,
                                              ),
                                              transitionsBuilder: (context,
                                                  animation,
                                                  secondaryAnimation,
                                                  child) {
                                                return CupertinoPageTransition(
                                                  primaryRouteAnimation:
                                                      animation,
                                                  secondaryRouteAnimation:
                                                      secondaryAnimation,
                                                  linearTransition: true,
                                                  child: child,
                                                );
                                              },
                                            ),
                                          )
                                          .then((value) => vm.reload());
                                    },
                                    const Icon(
                                        CupertinoIcons.checkmark_seal_fill,
                                        color: kPrimaryColor,
                                        size: 14),
                                    vm.successfulConfirmedCount.toString(),
                                    otherText: vm.verboseMode
                                        ? "successful(confirmed)"
                                        : null,
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
                                              transitionsBuilder: (context,
                                                  animation,
                                                  secondaryAnimation,
                                                  child) {
                                                return CupertinoPageTransition(
                                                  primaryRouteAnimation:
                                                      animation,
                                                  secondaryRouteAnimation:
                                                      secondaryAnimation,
                                                  linearTransition: true,
                                                  child: child,
                                                );
                                              },
                                            ),
                                          )
                                          .then((value) => vm.reload());
                                    },
                                    const Icon(CupertinoIcons.checkmark_alt,
                                        color: kWarningColor, size: 14),
                                    vm.successfulCount.toString(),
                                    otherText: vm.verboseMode
                                        ? "successful(pending)"
                                        : null,
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
                                                query: TransactionStatuses
                                                    .advancedUssd,
                                              ),
                                              transitionsBuilder: (context,
                                                  animation,
                                                  secondaryAnimation,
                                                  child) {
                                                return CupertinoPageTransition(
                                                  primaryRouteAnimation:
                                                      animation,
                                                  secondaryRouteAnimation:
                                                      secondaryAnimation,
                                                  linearTransition: true,
                                                  child: child,
                                                );
                                              },
                                            ),
                                          )
                                          .then((value) => vm.reload());
                                    },
                                    Icon(
                                      CupertinoIcons.phone_circle_fill,
                                      color: kPrimaryColor,
                                      size: 14,
                                    ),
                                    vm.advancedCount.toString(),
                                    otherText:
                                        vm.verboseMode ? "advanced" : null,
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
                                                query: TransactionStatuses
                                                    .forwarded,
                                              ),
                                              transitionsBuilder: (context,
                                                  animation,
                                                  secondaryAnimation,
                                                  child) {
                                                return CupertinoPageTransition(
                                                  primaryRouteAnimation:
                                                      animation,
                                                  secondaryRouteAnimation:
                                                      secondaryAnimation,
                                                  linearTransition: true,
                                                  child: child,
                                                );
                                              },
                                            ),
                                          )
                                          .then((value) => vm.reload());
                                    },
                                    Icon(
                                      CupertinoIcons.arrow_turn_right_up,
                                      color: kPrimaryColor,
                                      size: 14,
                                    ),
                                    vm.forwardedCount.toString(),
                                    otherText:
                                        vm.verboseMode ? "forwarded" : null,
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
                                                query: TransactionStatuses
                                                    .secondAttempt,
                                              ),
                                              transitionsBuilder: (context,
                                                  animation,
                                                  secondaryAnimation,
                                                  child) {
                                                return CupertinoPageTransition(
                                                  primaryRouteAnimation:
                                                      animation,
                                                  secondaryRouteAnimation:
                                                      secondaryAnimation,
                                                  linearTransition: true,
                                                  child: child,
                                                );
                                              },
                                            ),
                                          )
                                          .then((value) => vm.reload());
                                    },
                                    const Icon(
                                        CupertinoIcons.arrow_2_circlepath,
                                        color: kWarningColor,
                                        size: 14),
                                    vm.failedCount.toString(),
                                    otherText: vm.verboseMode
                                        ? "second attempt"
                                        : null,
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
                                                query:
                                                    TransactionStatuses.paused,
                                              ),
                                              transitionsBuilder: (context,
                                                  animation,
                                                  secondaryAnimation,
                                                  child) {
                                                return CupertinoPageTransition(
                                                  primaryRouteAnimation:
                                                      animation,
                                                  secondaryRouteAnimation:
                                                      secondaryAnimation,
                                                  linearTransition: true,
                                                  child: child,
                                                );
                                              },
                                            ),
                                          )
                                          .then((value) => vm.reload());
                                    },
                                    Icon(
                                      CupertinoIcons.pause_circle_fill,
                                      color: Theme.of(context).hintColor,
                                      size: 14,
                                    ),
                                    vm.pausedCount.toString(),
                                    otherText: vm.verboseMode ? "paused" : null,
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
                                                query:
                                                    TransactionStatuses.hasOkoa,
                                              ),
                                              transitionsBuilder: (context,
                                                  animation,
                                                  secondaryAnimation,
                                                  child) {
                                                return CupertinoPageTransition(
                                                  primaryRouteAnimation:
                                                      animation,
                                                  secondaryRouteAnimation:
                                                      secondaryAnimation,
                                                  linearTransition: true,
                                                  child: child,
                                                );
                                              },
                                            ),
                                          )
                                          .then((value) => vm.reload());
                                    },
                                    Icon(
                                      Icons.sailing_rounded,
                                      color: kDullColor,
                                      size: 14,
                                    ),
                                    vm.okoaCount.toString(),
                                    otherText: vm.verboseMode ? "okoa" : null,
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
                                              transitionsBuilder: (context,
                                                  animation,
                                                  secondaryAnimation,
                                                  child) {
                                                return CupertinoPageTransition(
                                                  primaryRouteAnimation:
                                                      animation,
                                                  secondaryRouteAnimation:
                                                      secondaryAnimation,
                                                  linearTransition: true,
                                                  child: child,
                                                );
                                              },
                                            ),
                                          )
                                          .then((value) => vm.reload());
                                    },
                                    Icon(
                                      CupertinoIcons.exclamationmark_triangle,
                                      color: Theme.of(context).indicatorColor,
                                      size: 14,
                                    ),
                                    vm.unavailableCount.toString(),
                                    otherText: vm.verboseMode
                                        ? "unavailable offers"
                                        : null,
                                    context,
                                    withBorder: true,
                                    accentColor:
                                        Theme.of(context).indicatorColor,
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
                                              transitionsBuilder: (context,
                                                  animation,
                                                  secondaryAnimation,
                                                  child) {
                                                return CupertinoPageTransition(
                                                  primaryRouteAnimation:
                                                      animation,
                                                  secondaryRouteAnimation:
                                                      secondaryAnimation,
                                                  linearTransition: true,
                                                  child: child,
                                                );
                                              },
                                            ),
                                          )
                                          .then((value) => vm.reload());
                                    },
                                    const Icon(
                                      Icons.person_off_outlined,
                                      color: kWarningColor,
                                      size: 14,
                                    ),
                                    vm.blacklistedCount.toString(),
                                    otherText:
                                        vm.verboseMode ? "blacklisted" : null,
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
                                                query:
                                                    TransactionStatuses.error,
                                              ),
                                              transitionsBuilder: (context,
                                                  animation,
                                                  secondaryAnimation,
                                                  child) {
                                                return CupertinoPageTransition(
                                                  primaryRouteAnimation:
                                                      animation,
                                                  secondaryRouteAnimation:
                                                      secondaryAnimation,
                                                  linearTransition: true,
                                                  child: child,
                                                );
                                              },
                                            ),
                                          )
                                          .then((value) => vm.reload());
                                    },
                                    const Icon(CupertinoIcons.xmark_circle_fill,
                                        color: kErrorColor, size: 14),
                                    vm.errorCount.toString(),
                                    otherText: vm.verboseMode ? "errors" : null,
                                    context,
                                    withBorder: true,
                                    accentColor: kErrorColor,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: kPagePadding / 2),
                            vm.recentTransactions.isNotEmpty
                                ? transactionListItem(
                                    context,
                                    vm.recentTransactions[0]['number'],
                                    vm.recentTransactions[0]['amount'],
                                    vm.recentTransactions[0]['status'],
                                    vm.recentTransactions[0]['ussdReply'],
                                    vm.recentTransactions[0]['date'],
                                    vm.recentTransactions[0]['time'],
                                    vm.recentTransactions[0]['id'],
                                    vm.recentTransactions[0]['ussdDialed'],
                                    vm.recentTransactions[0]['source'],
                                    vm.recentTransactions[0]['simSubId'],
                                    vm.recentTransactions[0]['canRetry'] ?? 0,
                                    lineLimit: 1,
                                  )
                                : const Text("No transactions today :("),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: kPagePadding),
                  InkWell(
                    onTap: vm.toggleToolsSection,
                    child: Padding(
                      padding: EdgeInsets.all(kPagePadding),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "My tools",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Icon(vm.showToolsSection
                              ? CupertinoIcons.chevron_up
                              : CupertinoIcons.chevron_down)
                        ],
                      ),
                    ),
                  ),
                  if (vm.showToolsSection)
                    DashboardToolsSection(onReload: vm.reload),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

