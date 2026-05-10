import 'dart:async';

import 'package:bsat/components/dialogs/confirm_delete_dialog.dart';
import 'package:bsat/components/dialogs/success_dialog.dart';
import 'package:bsat/components/transaction_list_item.dart';
import 'package:bsat/screens/home/dashboard/dashboard_tools.dart';
import 'package:bsat/screens/stats/statistics.dart';
import 'package:bsat/screens/transactions/transaction_history.dart';
import 'package:bsat/utils/constants.dart';
import 'package:bsat/utils/date_ops.dart';
import 'package:bsat/utils/numbers.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:widgets_easier/widgets_easier.dart';

import '../../../../components/app_paused.dart';
import '../../../../components/dialogs/change_category_dialog.dart';
import '../../../../components/no_subscription.dart';
import '../../../../components/tool_button.dart';
import 'dashboard_view_model.dart';
import '../../settings/settings.dart';

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
  bool _canScrollLeft = false;
  bool _canScrollRight = true;

  @override
  void initState() {
    super.initState();
    // Set up the shared view model and start background data loading.
    _viewModel = DashboardViewModel();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_viewModel.initialize());

    _chipsScrollController.addListener(_scrollListener);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollListener();
    });
  }

  void _scrollListener() {
    if (_chipsScrollController.hasClients) {
      setState(() {
        _canScrollLeft = _chipsScrollController.position.pixels > 0;
        _canScrollRight = _chipsScrollController.position.pixels <
            _chipsScrollController.position.maxScrollExtent;
      });
    }
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

  void _scrollChips({bool goRight = true}) {
    // get postion of scroll position to hide buttons when at the end or beginning

    if (_chipsScrollController.hasClients) {
      _chipsScrollController.animateTo(
        goRight
            ? _chipsScrollController.offset + 200
            : _chipsScrollController.offset - 200,
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
                        GestureDetector(
                          onTap: () {
                            DeviceInfoPlugin()
                                .deviceInfo
                                .then((info) => print(info));
                          },
                          child: Image.asset(
                            'assets/icons/icon.png',
                            width: 60,
                            height: 60,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // const SizedBox(height: kPagePadding),
                  Container(
                    padding: kPagePaddingInsets,
                    child: GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
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
                        );
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(kPagePadding),
                        decoration: BoxDecoration(
                          image: DecorationImage(
                            image: AssetImage(
                              'assets/images/mesh_distorted.png',
                            ),
                            fit: BoxFit.cover,
                            opacity: vm.isLightMode ? 0.4 : 0.9,
                          ),
                          borderRadius: BorderRadius.circular(kBorderRadius),
                          // color: Theme.of(context).cardColor,
                          border: Border(
                            bottom: BorderSide(
                              color: kIndigoColor,
                              // Theme.of(context)
                              //     .hintColor
                              //     .withOpacity(0.9),
                              // blurRadius: 0,
                              // offset: const Offset(5, 5),
                              width: 3,
                            ),
                            right: BorderSide(
                              color: kIndigoColor,
                              // Theme.of(context)
                              //     .hintColor
                              //     .withOpacity(0.9),
                              // blurRadius: 0,
                              // offset: const Offset(5, 5),
                              width: 3,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  "Airtime Balance",
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: kPagePadding),
                                Row(
                                  children: [
                                    Text(
                                      vm.hideBalance
                                          ? 'KES ****'
                                          : 'KES ${Numbers.formatNumber(int.tryParse(vm.airtimeBalance) ?? 0)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -1,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      onTap: () => vm.toggleHideBalance(),
                                      child: Container(
                                        padding: kPagePaddingInsets / 3,
                                        decoration: BoxDecoration(
                                          color: Theme.of(context)
                                              .scaffoldBackgroundColor
                                              .withOpacity(0.8),
                                          borderRadius:
                                              BorderRadius.circular(500),
                                          border: Border.all(
                                            color: Theme.of(context).cardColor,
                                            width: 1,
                                          ),
                                        ),
                                        child: Icon(
                                          vm.hideBalance
                                              ? CupertinoIcons.eye
                                              : CupertinoIcons.eye_slash,
                                          color: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium
                                                  ?.color ??
                                              Colors.white,
                                          size: 14,
                                        ),
                                      ),
                                    ),
                                  ],
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
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  "Est. Commission",
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: kPagePadding),
                                Row(
                                  children: [
                                    Text(
                                      vm.hideCommission
                                          ? 'KES ***'
                                          : 'KES ${Numbers.formatNumber(int.parse(vm.estimatedCommission.toStringAsFixed(0)))}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      decoration: BoxDecoration(
                                          color: Theme.of(context)
                                              .scaffoldBackgroundColor
                                              .withOpacity(0.8),
                                          borderRadius:
                                              BorderRadius.circular(500)),
                                      child: GestureDetector(
                                        onTap: () => vm.toggleHideCommission(),
                                        child: Container(
                                          padding: kPagePaddingInsets / 3,
                                          decoration: BoxDecoration(
                                              border: Border.all(
                                                color:
                                                    Theme.of(context).cardColor,
                                                width: 1,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(500)),
                                          child: Icon(
                                            vm.hideCommission
                                                ? CupertinoIcons.eye
                                                : CupertinoIcons.eye_slash,
                                            color: Theme.of(context)
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.color ??
                                                Colors.white,
                                            size: 14,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: kPagePadding * 2),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  CupertinoIcons.graph_square,
                                  color: kPrimaryColor,
                                  size: 30,
                                ),
                                const SizedBox(width: kPagePadding),
                                GestureDetector(
                                  onTap: () {
                                    vm.reload();
                                    vm.refreshBalances();
                                  },
                                  child: Container(
                                    padding: kPagePaddingInsets / 2,
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .scaffoldBackgroundColor
                                          .withOpacity(0.8),
                                      borderRadius: BorderRadius.circular(500),
                                      border: Border.all(
                                        color: Theme.of(context).cardColor,
                                        width: 1,
                                      ),
                                    ),
                                    child: const Icon(
                                      CupertinoIcons.refresh,
                                      color: kDarkerGreen,
                                      size: 13,
                                      fill: 1,
                                      weight: 700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  Container(
                    // margin: kPagePaddingInsets,
                    padding:
                        const EdgeInsets.symmetric(horizontal: kPagePadding),
                    decoration: BoxDecoration(
                      // color: Theme.of(context).primaryColor.withOpacity(.05),
                      borderRadius: BorderRadius.circular(kBorderRadius),
                    ),
                    child: Column(
                      children: [
                        const SizedBox(height: kPagePadding * 2),
                        vm.hasActiveSubscription
                            ? const SizedBox()
                            : noBalanceButton(context),
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
                      ],
                    ),
                  ),
                  // const SizedBox(height: kPagePadding),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: kPagePadding),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "History",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
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
                                .then(
                                  (value) => vm.reload(),
                                );
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
                      ],
                    ),
                  ),
                  Container(
                    margin: kPagePaddingInsets,
                    padding: kPagePaddingInsets / 3,
                    decoration: BoxDecoration(
                      // color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(kBorderRadius),
                      border: Border.all(
                        color: Theme.of(context).primaryColor.withOpacity(.2),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        const SizedBox(height: kPagePadding),
                        Wrap(
                          runSpacing: kPagePadding / 2,
                          spacing: kPagePadding / 2,
                          alignment: WrapAlignment.center,
                          children: [
                            ...([
                              {
                                'count': vm.successfulConfirmedCount,
                                'icon': const Icon(
                                    CupertinoIcons.checkmark_seal_fill,
                                    color: kPrimaryColor,
                                    size: 14),
                                'query': TransactionStatuses.doneConfirmed,
                                'label': 'successful(confirmed)',
                                'accentColor': kDarkerGreen,
                              },
                              {
                                'count': vm.errorCount,
                                'icon': const Icon(
                                    CupertinoIcons.xmark_circle_fill,
                                    color: kErrorColor,
                                    size: 14),
                                'query': TransactionStatuses.error,
                                'label': 'errors',
                                'accentColor': kErrorColor,
                              },
                              {
                                'count': vm.successfulCount,
                                'icon': const Icon(CupertinoIcons.checkmark_alt,
                                    color: kWarningColor, size: 14),
                                'query': TransactionStatuses.done,
                                'label': 'successful(pending)',
                                'accentColor': kDarkerGreen,
                              },
                              {
                                'count': vm.advancedCount,
                                'icon': const Icon(
                                    CupertinoIcons.phone_circle_fill,
                                    color: kPrimaryColor,
                                    size: 14),
                                'query': TransactionStatuses.advancedUssd,
                                'label': 'advanced',
                                'accentColor': kDarkerGreen,
                              },
                              {
                                'count': vm.forwardedCount,
                                'icon': const Icon(
                                    CupertinoIcons.arrow_turn_right_up,
                                    color: kPrimaryColor,
                                    size: 14),
                                'query': TransactionStatuses.forwarded,
                                'label': 'forwarded',
                                'accentColor': kDarkerGreen,
                              },
                              {
                                'count': vm.failedCount,
                                'icon': const Icon(
                                    CupertinoIcons.arrow_2_circlepath,
                                    color: kWarningColor,
                                    size: 14),
                                'query': TransactionStatuses.secondAttempt,
                                'label': 'second attempt',
                                'accentColor': kWarningColor,
                              },
                              {
                                'count': vm.pausedCount,
                                'icon': Icon(CupertinoIcons.pause_circle_fill,
                                    color: Theme.of(context).hintColor,
                                    size: 14),
                                'query': TransactionStatuses.paused,
                                'label': 'paused',
                                'accentColor': kWarningColor,
                              },
                              {
                                'count': vm.okoaCount,
                                'icon': const Icon(Icons.sailing_rounded,
                                    color: kDullColor, size: 14),
                                'query': TransactionStatuses.hasOkoa,
                                'label': 'okoa',
                                'accentColor': kBgColor,
                              },
                              {
                                'count': vm.unavailableCount,
                                'icon': Icon(
                                    CupertinoIcons.exclamationmark_triangle,
                                    color: Theme.of(context).indicatorColor,
                                    size: 14),
                                'query': TransactionStatuses.unavailableOffer,
                                'label': 'unavailable offers',
                                'accentColor': Theme.of(context).indicatorColor,
                              },
                              {
                                'count': vm.blacklistedCount,
                                'icon': const Icon(Icons.person_off_outlined,
                                    color: kWarningColor, size: 14),
                                'query': 'blacklist',
                                'label': 'blacklisted',
                                'accentColor': kErrorColor,
                              },
                              {
                                'count': vm.maskedCount,
                                'icon': const Icon(Icons.masks, color: kDullColor, size: 14),
                                'query': TransactionStatuses.masked,
                                'label': 'masked',
                                'accentColor': kErrorColor,
                              },
                            ]
                                // ..sort(
                                //         (a, b) => (b['count'] as int)
                                //             .compareTo(a['count'] as int),
                                //       )
                                )
                                .where((filter) => (filter['count'] as int) > 0)
                                .map((filter) {
                              return toolButton(
                                () {
                                  Navigator.of(context)
                                      .push(
                                        PageRouteBuilder(
                                          pageBuilder: (context, animation,
                                                  secondaryAnimation) =>
                                              TransactionHistoryPage(
                                            query: filter['query'] as String,
                                          ),
                                          transitionsBuilder: (context,
                                              animation,
                                              secondaryAnimation,
                                              child) {
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
                                      .then((value) => vm.reload());
                                },
                                filter['icon'] as Icon,
                                filter['count'].toString(),
                                otherText: vm.verboseMode
                                    ? filter['label'] as String
                                    : null,
                                context,
                                withBorder: true,
                                accentColor: filter['accentColor'] as Color?,
                                borderColor: filter['accentColor'] as Color?,
                              );
                            }).toList()
                          ],
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
                                vm.recentTransactions[0]["ussdReply"],
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text("No transactions today"),
                                ],
                              ),
                      ],
                    ),
                  ),

                  Padding(
                    padding: EdgeInsets.all(kPagePadding),
                    child: const Text(
                      "My tools",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (vm.showToolsSection)
                    DashboardToolsSection(onReload: vm.reload),
                  const SizedBox(height: kPagePadding * 7),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
