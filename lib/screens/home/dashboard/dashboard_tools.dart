import 'package:bsat/components/dialogs/use_another_phone_dialog.dart';
import 'package:bsat/components/tool_button.dart';
import 'package:bsat/screens/blacklist.dart';
import 'package:bsat/screens/dialpad.dart';
import 'package:bsat/screens/inbox.dart';
import 'package:bsat/screens/messaging/send_message_page.dart';
import 'package:bsat/screens/offers/offers.dart';
import 'package:bsat/screens/online_management/online_management.dart';
import 'package:bsat/screens/replies/replies.dart';
import 'package:bsat/screens/settings/about.dart';
import 'package:bsat/screens/settings/settings.dart';
import 'package:bsat/screens/stats/statistics.dart';
import 'package:bsat/screens/subscriptions/subscription.dart';
import 'package:bsat/screens/tasks/tasks.dart';
import 'package:bsat/screens/transactions/transaction_history.dart';
import 'package:bsat/services/shared_preferences_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Collection of “My tools” shortcuts used on the dashboard.
class DashboardToolsSection extends StatelessWidget {
  const DashboardToolsSection({
    super.key,
    required this.onReload,
  });

  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    // Keep this widget presentation-only; it surfaces navigation shortcuts and
    // calls back into the parent to refresh state after returning from flows.
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
          borderRadius: BorderRadius.circular(kBorderRadius / 2),
          image: DecorationImage(
            image: const AssetImage('assets/images/mesh.png'),
            fit: BoxFit.cover,
            opacity: 0.05,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(),
            const SizedBox(height: kPagePadding),
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
                        .then((value) => onReload());

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
                        .then((value) => onReload());
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
                        .then((value) => onReload());
                  },
                  Icon(Icons.precision_manufacturing_outlined,
                      color: Theme.of(context).indicatorColor),
                  "Scheduler",
                  context,
                ),
                toolButton(
                  () {
                    showUseAnotherPhoneDialog(context);
                  },
                  Icon(
                    CupertinoIcons.phone_arrow_up_right,
                    color: Theme.of(context).indicatorColor,
                  ),
                  "Forward SMS (online/offline)",
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
                        .then((value) => onReload());
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
                          (value) => onReload(),
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
                        .then((value) => onReload());
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
                                    const SendMessagePage(),
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
                        .then((value) => onReload());
                  },
                  const Icon(
                    CupertinoIcons.paperplane,
                    color: kIndigoColor,
                  ),
                  "Send Message",
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
                        .then((value) => onReload());
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
                        .then((value) => onReload());
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
              spacing: kPagePadding / 4,
              children: [
                if (kDebugMode)
                  toolButton(
                    () async {
                      if (kDebugMode) {
                        SharedPreferencesService().printAll();
                      }
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
                        .then((value) => onReload());
                  },
                  Icon(CupertinoIcons.money_dollar,
                      color: Theme.of(context).indicatorColor),
                  "Subscription",
                  context,
                ),
                toolButton(
                  () async {
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
                        .then((value) => onReload());
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
                        .then((value) => onReload());
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
                                    const OnlineManagementScreen(),
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
                          (value) => onReload(),
                        );
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
