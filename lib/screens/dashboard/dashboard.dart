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
  final bool isDashboard;

  const DashBoardPage({super.key, this.isDashboard = false});
  // const DashBoardPage({super.key});

  @override
  State<DashBoardPage> createState() => _DashBoardPageState();
}

class _DashBoardPageState extends State<DashBoardPage>
    with WidgetsBindingObserver {
  late final DashboardViewModel _viewModel;
  final ScrollController _chipsScrollController = ScrollController();

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
    _chipsScrollController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _viewModel.dispose();
    super.dispose();
  }

  void _scrollChips() {
    if (_chipsScrollController.hasClients) {
      _chipsScrollController.animateTo(
        _chipsScrollController.offset + 200,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
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
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${getGreeting(withEmoji: true)}',
                              style: const TextStyle(fontSize: 14),
                            ),
                            Text(
                              vm.userName,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Image.asset(
                          'assets/icons/icon.png',
                          width: 60,
                          height: 60,
                        ),
                      ],
                    ),
                  ),
                  // const SizedBox(height: kPagePadding),
                  Container(
                    margin: kPagePaddingInsets,
                    padding: kPagePaddingInsets,
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withOpacity(.05),
                      borderRadius: BorderRadius.circular(kBorderRadius),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(kPagePadding),
                          decoration: BoxDecoration(
                            image: DecorationImage(
                                image: AssetImage(
                                  'assets/images/mesh_distorted.png',
                                ),
                                fit: BoxFit.cover,
                                opacity: 0.3),
                            borderRadius: BorderRadius.circular(kBorderRadius),
                            color: Theme.of(context).scaffoldBackgroundColor,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.9),
                                // Theme.of(context)
                                //     .hintColor
                                //     .withOpacity(0.9),
                                blurRadius: 0,
                                offset: const Offset(2, 2),
                              ),
                              // BoxShadow(
                              //   color: Theme.of(context)
                              //       .hintColor
                              //       .withOpacity(0.3),
                              //   blurRadius: 0,
                              //   offset: const Offset(-2, -2),
                              // ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  // Container(
                                  //   padding: const EdgeInsets.all(kPagePadding),
                                  //   decoration: BoxDecoration(
                                  //     color: Theme.of(context)
                                  //         .cardColor
                                  //         .withOpacity(0.2),
                                  //     borderRadius:
                                  //         BorderRadius.circular(kBorderRadius),
                                  //   ),
                                  //   child: Icon(
                                  //     Icons.sim_card,
                                  //     // color: Colors.white,
                                  //     size: 16,
                                  //   ),
                                  // ),
                                  // const SizedBox(width: kPagePadding),
                                  const Text(
                                    "Airtime Balance",
                                    style: TextStyle(
                                      // color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(width: kPagePadding),
                                  Text(
                                    vm.hideBalance
                                        ? 'KES ****'
                                        : 'KES ${Numbers.formatNumber(int.tryParse(vm.airtimeBalance) ?? 0)}',
                                    style: const TextStyle(
                                      // color: Colors.white,
                                      // fontSize: 32,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -1,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: kPagePadding),

                              // const SizedBox(height: 24),
                              // Container(
                              //   height: 1,
                              //   color: Theme.of(context).cardColor.withOpacity(0.2),
                              // ),
                              // const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    "Est. Commission",
                                    style: TextStyle(
                                      // color: Colors.white70,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(width: kPagePadding),
                                  Text(
                                    vm.hideCommission
                                        ? 'KES ***'
                                        : 'KES ${Numbers.formatNumber(int.parse(vm.estimatedCommission.toStringAsFixed(0)))}',
                                    style: const TextStyle(
                                      // color: Colors.white,
                                      // fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  // Icon(
                                  //   vm.hideCommission
                                  //       ? CupertinoIcons.eye
                                  //       : CupertinoIcons.eye_slash,
                                  //   color: Colors.white54,
                                  //   size: 12,
                                  // ),
                                ],
                              ),
                              const SizedBox(height: kPagePadding),

                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  IconButton(
                                    onPressed: () {
                                      vm.toggleHideBalance();
                                      vm.toggleHideCommission();
                                    },
                                    icon: Icon(
                                      vm.hideBalance
                                          ? CupertinoIcons.eye
                                          : CupertinoIcons.eye_slash,
                                      color: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.color ??
                                          Colors.white,
                                      size: 13,
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () {
                                      vm.reload();
                                      vm.refreshBalances();
                                    },
                                    icon: const Icon(
                                      CupertinoIcons.refresh,
                                      color: kDarkerGreen,
                                      size: 13,
                                    ),
                                    padding: EdgeInsets.zero,
                                    // constraints: const BoxConstraints(
                                    //   minWidth: 40,
                                    //   minHeight: 40,
                                    // ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: kPagePadding * 2),
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
                            const SizedBox(height: kPagePadding),
                            Container(
                              width: double.infinity,
                              // height: 60, // Fixed height for the scrollable row
                              child: Stack(
                                children: [
                                  SingleChildScrollView(
                                    controller: _chipsScrollController,
                                    scrollDirection: Axis.horizontal,
                                    physics: const BouncingScrollPhysics(),
                                    padding: const EdgeInsets.only(
                                        right:
                                            60), // Padding to avoid overlap with scroll button
                                    child: Row(
                                      children: [
                                        toolButton(
                                          () {
                                            Navigator.of(context)
                                                .push(
                                                  PageRouteBuilder(
                                                    pageBuilder: (context,
                                                            animation,
                                                            secondaryAnimation) =>
                                                        const TransactionHistoryPage(
                                                      query: TransactionStatuses
                                                          .doneConfirmed,
                                                    ),
                                                    transitionsBuilder:
                                                        (context,
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
                                              CupertinoIcons
                                                  .checkmark_seal_fill,
                                              color: kPrimaryColor,
                                              size: 14),
                                          vm.successfulConfirmedCount
                                              .toString(),
                                          otherText: vm.verboseMode
                                              ? "successful(confirmed)"
                                              : null,
                                          context,
                                          withBorder: true,
                                          accentColor: kDarkerGreen,
                                        ),
                                        const SizedBox(width: kPagePadding / 4),
                                        toolButton(
                                          () {
                                            Navigator.of(context)
                                                .push(
                                                  PageRouteBuilder(
                                                    pageBuilder: (context,
                                                            animation,
                                                            secondaryAnimation) =>
                                                        const TransactionHistoryPage(
                                                      query: TransactionStatuses
                                                          .done,
                                                    ),
                                                    transitionsBuilder:
                                                        (context,
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
                                              CupertinoIcons.checkmark_alt,
                                              color: kWarningColor,
                                              size: 14),
                                          vm.successfulCount.toString(),
                                          otherText: vm.verboseMode
                                              ? "successful(pending)"
                                              : null,
                                          context,
                                          withBorder: true,
                                          accentColor: kDarkerGreen,
                                        ),
                                        const SizedBox(width: kPagePadding / 4),
                                        toolButton(
                                          () {
                                            Navigator.of(context)
                                                .push(
                                                  PageRouteBuilder(
                                                    pageBuilder: (context,
                                                            animation,
                                                            secondaryAnimation) =>
                                                        const TransactionHistoryPage(
                                                      query: TransactionStatuses
                                                          .advancedUssd,
                                                    ),
                                                    transitionsBuilder:
                                                        (context,
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
                                          otherText: vm.verboseMode
                                              ? "advanced"
                                              : null,
                                          context,
                                          withBorder: true,
                                          accentColor: kDarkerGreen,
                                        ),
                                        const SizedBox(width: kPagePadding / 4),
                                        toolButton(
                                          () {
                                            Navigator.of(context)
                                                .push(
                                                  PageRouteBuilder(
                                                    pageBuilder: (context,
                                                            animation,
                                                            secondaryAnimation) =>
                                                        const TransactionHistoryPage(
                                                      query: TransactionStatuses
                                                          .forwarded,
                                                    ),
                                                    transitionsBuilder:
                                                        (context,
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
                                          otherText: vm.verboseMode
                                              ? "forwarded"
                                              : null,
                                          context,
                                          withBorder: true,
                                          accentColor: kDarkerGreen,
                                        ),
                                        const SizedBox(width: kPagePadding / 4),
                                        toolButton(
                                          () {
                                            Navigator.of(context)
                                                .push(
                                                  PageRouteBuilder(
                                                    pageBuilder: (context,
                                                            animation,
                                                            secondaryAnimation) =>
                                                        const TransactionHistoryPage(
                                                      query: TransactionStatuses
                                                          .secondAttempt,
                                                    ),
                                                    transitionsBuilder:
                                                        (context,
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
                                                    pageBuilder: (context,
                                                            animation,
                                                            secondaryAnimation) =>
                                                        const TransactionHistoryPage(
                                                      query: TransactionStatuses
                                                          .paused,
                                                    ),
                                                    transitionsBuilder:
                                                        (context,
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
                                          otherText:
                                              vm.verboseMode ? "paused" : null,
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
                                                    pageBuilder: (context,
                                                            animation,
                                                            secondaryAnimation) =>
                                                        const TransactionHistoryPage(
                                                      query: TransactionStatuses
                                                          .hasOkoa,
                                                    ),
                                                    transitionsBuilder:
                                                        (context,
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
                                          otherText:
                                              vm.verboseMode ? "okoa" : null,
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
                                                    pageBuilder: (context,
                                                            animation,
                                                            secondaryAnimation) =>
                                                        const TransactionHistoryPage(
                                                      query: TransactionStatuses
                                                          .unavailableOffer,
                                                    ),
                                                    transitionsBuilder:
                                                        (context,
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
                                            CupertinoIcons
                                                .exclamationmark_triangle,
                                            color: Theme.of(context)
                                                .indicatorColor,
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
                                                    pageBuilder: (context,
                                                            animation,
                                                            secondaryAnimation) =>
                                                        const TransactionHistoryPage(
                                                      query: 'blacklist',
                                                    ),
                                                    transitionsBuilder:
                                                        (context,
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
                                          otherText: vm.verboseMode
                                              ? "blacklisted"
                                              : null,
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
                                                    pageBuilder: (context,
                                                            animation,
                                                            secondaryAnimation) =>
                                                        const TransactionHistoryPage(
                                                      query: TransactionStatuses
                                                          .error,
                                                    ),
                                                    transitionsBuilder:
                                                        (context,
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
                                              CupertinoIcons.xmark_circle_fill,
                                              color: kErrorColor,
                                              size: 14),
                                          vm.errorCount.toString(),
                                          otherText:
                                              vm.verboseMode ? "errors" : null,
                                          context,
                                          withBorder: true,
                                          accentColor: kErrorColor,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Positioned(
                                    right: 0,
                                    top: 0,
                                    bottom: 0,
                                    child: Container(
                                      padding: const EdgeInsets.only(left: 20),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.centerLeft,
                                          end: Alignment.centerRight,
                                          colors: [
                                            Theme.of(context)
                                                .cardColor
                                                .withOpacity(0.0),
                                            Theme.of(context).cardColor,
                                          ],
                                          stops: const [0.0, 0.4],
                                        ),
                                      ),
                                      child: IconButton(
                                        onPressed: _scrollChips,
                                        icon: const Icon(
                                            CupertinoIcons.chevron_right,
                                            size: 20),
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: kPagePadding),
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
