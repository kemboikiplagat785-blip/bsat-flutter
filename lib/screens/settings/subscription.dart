import 'package:bsat/components/dialogs/refresh_dialog.dart';
import 'package:bsat/services/shared_preferences_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:another_telephony/telephony.dart';

import '../../components/dialogs/choose_sim.dart';
import '../../components/header.dart';
import '../../services/payments.dart';
import '../../utils/constants.dart';

class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key});

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  final _sharedPreferencesService = SharedPreferencesService();
  int chosenSubId = 7;

  int chosenTokenId = 7;

  List<Widget> theSubs = [];
  List<SubscriptionInfo> sims = [];

  String expDate = "No active plan";
  bool isExpired = false;
  String planName = "Free";

  int tokenBalance = 0;

  bool autoRenew = false;

  final paymentOps = PaymentOps();

  Payment _lastPayment = Payment(
    id: -1,
    sim: -1,
    till: -1,
    planId: -1,
    amount: -1,
    type: "",
    paymentDate: -1,
  );

  @override
  void initState() {
    super.initState();

    _sharedPreferencesService.getAutoRenew().then((value) {
      setState(() {
        autoRenew = value ?? false;
      });
    });

    _recheckPlanExpiry();

    Telephony.instance.getSubscriptionList().then((value) {
      setState(() {
        sims = value;
        // debugPrint("Got cards");
      });
    });
  }

  Future<void> _recheckPlanExpiry() async {
    _lastPayment = await Payment.getHighestTierPayment();

    // print("All Paymets: ${await SQLiteService().queryAll('payments', orderBy: 'id DESC')}");

    tokenBalance = await _sharedPreferencesService.getDeliveryTokens() ?? 0;

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            header(context, "Payments & subscriptions"),
            const SizedBox(height: kPagePadding),
            Container(
              margin: kPagePaddingInsets,
              padding: kPagePaddingInsets,
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(kBorderRadius),
                border: Border.all(
                  color: Colors.orange.withValues(alpha: 0.5),
                  width: 1.5,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.orange.shade700,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Before purchasing, verify that your SIM card supports Sambaza (airtime transfer). Dial *140*5*number# to test transferring airtime to another number.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.orange.shade900,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: kPagePadding),
            subscriptionStatus(),
            const SizedBox(height: kPagePadding),

            const Text(
              'Tokens (Used for Offline and Online requests)',
            ),
            // const Spacer(),
            Padding(
              padding: kPagePaddingInsets,
              child: Row(
                children: kTokens.map((s) {
                  return Expanded(
                    child: InkWell(
                      onTap: () async {
                        setState(() {
                          // chosenSubId = s["id"];
                          chosenTokenId = s["id"];
                        });
                        SubscriptionInfo? sim = await chooseSim(context, sims);

                        if (sim == null) {
                          return;
                        }

                        final subscriptionId = sim.subscriptionId;
                        if (subscriptionId == null) {
                          return;
                        }

                        await paymentOps.payTokens(
                          s['value'],
                          subscriptionId,
                          s['amount'],
                          planId: s['id'],
                        );

                        refreshDialog(context, () async {
                          await _recheckPlanExpiry();
                          Navigator.pop(context);
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(3.0),
                        child: Container(
                          padding: kPagePaddingInsets,
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius:
                                BorderRadius.circular(kBorderRadius / 2),
                            boxShadow: [
                              BoxShadow(
                                spreadRadius: 2,
                                color: s["id"] == chosenTokenId
                                    ? Theme.of(context)
                                        .indicatorColor
                                        .withValues(
                                          alpha: 0.4,
                                        )
                                    : Colors.transparent,
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              RichText(
                                textAlign: TextAlign.center,
                                text: TextSpan(
                                  children: [
                                    TextSpan(
                                      text: 'KSH ',
                                      style: TextStyle(
                                          color: Theme.of(context).hintColor),
                                    ),
                                    TextSpan(
                                      text: '${s["value"]}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: s["id"] == chosenTokenId
                                            ? Theme.of(context).indicatorColor
                                            : Theme.of(context).focusColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: kPagePadding * 1.5),
                              s["id"] == chosenTokenId
                                  ? Icon(
                                      CupertinoIcons.checkmark_alt_circle_fill,
                                      color: Theme.of(context).indicatorColor,
                                    )
                                  : Container(),
                              Text(
                                '${s["amount"]} tokens',
                                style: TextStyle(
                                  // color: ,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: kPagePadding),
            const Text(
              'Subscription Plans',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: kPagePadding),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: kPagePadding),
              itemCount: kSubscriptionTiers.length,
              itemBuilder: (context, index) {
                final tier = kSubscriptionTiers[index];
                final plans = tier['plans'] as List;

                return Container(
                  margin: const EdgeInsets.only(bottom: kPagePadding),
                  padding: kPagePaddingInsets,
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(kBorderRadius),
                    border: Border.all(
                      color: (tier['color'] as Color).withValues(alpha: 0.5),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tier['tier'],
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          // color: tier['color'],
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...((tier['features'] as List).map((f) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                Icon(Icons.check_circle_outline,
                                    size: 16,
                                    color: (tier['color'] as Color)
                                        .withValues(alpha: 0.8)),
                                const SizedBox(width: 8),
                                Expanded(
                                    child: Text(f,
                                        style: const TextStyle(fontSize: 12))),
                              ],
                            ),
                          ))),
                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: plans.map<Widget>((plan) {
                          final isSelected = chosenSubId == plan['plan_id'];
                          final isFree = plan['amount'] == 0;

                          return InkWell(
                            onTap: () async {
                              if (!isFree) {
                                setState(() {
                                  chosenSubId = plan['plan_id'];
                                });

                                Map<String, dynamic> selectedPlan;
                                try {
                                  selectedPlan = kSubscriptionTiers
                                      .expand((tier) => tier['plans'] as List)
                                      .firstWhere((plan) =>
                                          plan['plan_id'] == chosenSubId);
                                } catch (e) {
                                  return; // No plan selected
                                }

                                // await choosePaymentCardDialog(
                                //   context,
                                //   sims,
                                //   selectedPlan["amount"],
                                //   selectedPlan["durationDays"],
                                //   isExpired ? "" : expDate,
                                //   selectedPlan['plan_id'],
                                //   tier['tier'],
                                // );

                                SubscriptionInfo? chosen =
                                    await chooseSim(context, sims);

                                if (chosen == null) {
                                  return;
                                }
                                final subscriptionId = chosen.subscriptionId;
                                if (subscriptionId == null) {
                                  return;
                                }
                                await paymentOps.payCore(
                                  plan['amount'],
                                  plan['durationDays'],
                                  subscriptionId,
                                  plan['plan_id'],
                                  tier['tier'],
                                );
                                refreshDialog(context, () async {
                                  await _recheckPlanExpiry();
                                  Navigator.pop(context);
                                });
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? tier['color']
                                    : (tier['color'] as Color)
                                        .withValues(alpha: 0.1),
                                borderRadius:
                                    BorderRadius.circular(kBorderRadius),
                                border: isSelected
                                    ? Border.all(color: tier['color'], width: 2)
                                    : null,
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    plan['durationString'],
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: isSelected ? Colors.white : null,
                                    ),
                                  ),
                                  if (!isFree)
                                    Text(
                                      "Ksh ${plan['amount']}",
                                      style: TextStyle(
                                        fontSize: 12,
                                        color:
                                            isSelected ? Colors.white70 : null,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: kPagePadding),
          ],
        ),
      ),
    );
  }

  Widget subscriptionStatus() {
    return Padding(
      padding: kPagePaddingInsets,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(kBorderRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4), // Adds subtle elevation
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- RECEIPT HEADER ---
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Text(
                "SUBSCRIPTION RECEIPT",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.color
                      ?.withValues(alpha: 0.5),
                ),
              ),
            ),

            // --- DASHED DIVIDER ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final boxWidth = constraints.constrainWidth();
                  const dashWidth = 6.0;
                  final dashCount = (boxWidth / (2 * dashWidth)).floor();
                  return Flex(
                    direction: Axis.horizontal,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(dashCount, (_) {
                      return SizedBox(
                        width: dashWidth,
                        height: 1.5,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                              color: Colors.grey.withValues(alpha: 0.3)),
                        ),
                      );
                    }),
                  );
                },
              ),
            ),

            // --- PLAN DETAILS (ITEMIZED) ---
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Status",
                          style: TextStyle(color: Colors.grey)),
                      Text(
                        isExpired ? "No Active Plan" : "Active",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isExpired ? kErrorColor : kPrimaryColor,
                        ),
                      ),
                    ],
                  ),
                  if (!isExpired) const SizedBox(height: 12),
                  if (!isExpired)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Plan Type",
                            style: TextStyle(color: Colors.grey)),
                        Text(
                          _lastPayment.type,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  if (!isExpired) const SizedBox(height: 12),
                  if (!isExpired)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Expiry Date",
                            style: TextStyle(color: Colors.grey)),
                        Text(
                          DateTime.fromMillisecondsSinceEpoch(_lastPayment.till)
                                  .toString()
                                  .split('.')[
                              0], // Strips microseconds for a cleaner receipt
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                ],
              ),
            ),

            // --- DASHED DIVIDER ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final boxWidth = constraints.constrainWidth();
                  const dashWidth = 6.0;
                  final dashCount = (boxWidth / (2 * dashWidth)).floor();
                  return Flex(
                    direction: Axis.horizontal,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(dashCount, (_) {
                      return SizedBox(
                        width: dashWidth,
                        height: 1.5,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                              color: Colors.grey.withValues(alpha: 0.3)),
                        ),
                      );
                    }),
                  );
                },
              ),
            ),

            // --- TOTAL / BALANCE ---
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Token Balance",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text(
                    "$tokenBalance",
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: (tokenBalance > 0) ? kPrimaryColor : kErrorColor,
                    ),
                  ),
                ],
              ),
            ),

            // --- RECEIPT FOOTER / TOGGLE ---
            Container(
              decoration: BoxDecoration(
                color: Colors.grey.withValues(
                    alpha: 0.05), // Gives it a slight "footer" shade
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(kBorderRadius),
                  bottomRight: Radius.circular(kBorderRadius),
                ),
              ),
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Checkbox(
                    value: autoRenew,
                    semanticLabel: "Enable Autorenew",
                    onChanged: (bool? value) {
                      setState(() {
                        autoRenew = value ?? false;
                        _sharedPreferencesService.setAutoRenew(autoRenew);
                      });
                    },
                  ),
                  const Text(
                    "Enable Autorenew",
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
