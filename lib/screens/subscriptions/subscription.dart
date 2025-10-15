import 'package:bsat/components/dialogs/refresh_dialog.dart';
import 'package:bsat/services/shared_preferences_service.dart';
import 'package:bsat/utils/date_ops.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:sim_data/sim_data.dart';

import '../../components/dialogs/choose_payment_card_dialog.dart';
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
  List<SimCard> sims = [];

  String expDate = "No active plan";
  bool isExpired = false;

  int tokenBalance = 0;

  bool autoRenew = false;

  final paymentOps = PaymentOps();

  @override
  void initState() {
    super.initState();

    _sharedPreferencesService.getAutoRenew().then((value) {
      setState(() {
        autoRenew = value ?? false;
      });
    });

    _recheckPlanExpiry();

    SimDataPlugin.getSimData().then((value) {
      setState(() {
        sims = value.cards;
        // debugPrint("Got cards");
      });
    });
  }

  Future<void> _recheckPlanExpiry() async {
    await _sharedPreferencesService.getUsableUntil().then(
          (value) => setState(
            () {
              isExpired = (value ?? 0) <= DateTime.now().millisecondsSinceEpoch;
              expDate =
                  "Plan expires on: ${getNormalDate(DateTime.fromMillisecondsSinceEpoch(value ?? 0))} ${getNormalTime(DateTime.fromMillisecondsSinceEpoch(value ?? 0))}";
            },
          ),
        );

    tokenBalance = await _sharedPreferencesService.getDeliveryTokens() ?? 0;

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    var size = MediaQuery.of(context).size;

    return Scaffold(
      body: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          header(context, "Payments & subscriptions"),
          const SizedBox(height: kPagePadding),
          Padding(
            padding: kPagePaddingInsets,
            child: Container(
              padding: kPagePaddingInsets,
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(kBorderRadius),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          (isExpired ) ? "No Daily Active Plan" : expDate,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: (!isExpired) ? kPrimaryColor : kErrorColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          "Token balance: $tokenBalance",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: (tokenBalance > 0) ? kPrimaryColor : kErrorColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kPagePadding / 2),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(kBorderRadius),
              ),
              child: Row(
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
                  const Text("Enable Autorenew"),
                ],
              ),
            ),
          ),
          const Spacer(flex: 2),
          const Text(
            'Tokens',
          ),
          const Spacer(),
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
                      SimCard? sim = await chooseSim(context, sims);

                      if (sim == null) {
                        return;
                      }

                      await paymentOps.payTokens(
                        s['value'],
                        sim.subscriptionId,
                        s['amount'],
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
                                  ? Theme.of(context).indicatorColor.withValues(
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
                                    style: TextStyle(color: Theme.of(context).hintColor),
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
          const Spacer(flex: 2),
          const Text(
            'Expiry plans',
          ),
          const Spacer(),
          Padding(
            padding: kPagePaddingInsets,
            child: Row(
              children: kSubscriptions.map((s) {
                return Expanded(
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        chosenSubId = s["id"];
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
                              color: s["id"] == chosenSubId
                                  ? Theme.of(context).indicatorColor.withValues(
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
                                    style: TextStyle(color: Theme.of(context).hintColor),
                                  ),
                                  TextSpan(
                                    text: '${s["value"]}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: s["id"] == chosenSubId
                                          ? Theme.of(context).indicatorColor
                                          : Theme.of(context).focusColor,
                                      // color: s["id"] == chosenSubId
                                      //     ? kIndigoColor
                                      //     : ,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: kPagePadding * 1.5),
                            s["id"] == chosenSubId
                                ? Icon(
                                    CupertinoIcons.checkmark_alt_circle_fill,
                                    color: Theme.of(context).indicatorColor,
                                  )
                                : Container(),
                            Text(
                              s["details"],
                              style: TextStyle(
                                color: s["id"] == chosenSubId
                                    ? Theme.of(context).indicatorColor
                                    : null,
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
          const Spacer(flex: 2),
          InkWell(
            onTap: () async {
              // debugPrint(sims);
              for (var i in sims) {
                // debugPrint(i.carrierName);
              }
              await choosePaymentCardDialog(
                context,
                sims,
                kSubscriptions
                    .where((element) => element["id"] == chosenSubId)
                    .first["value"],
                kSubscriptions
                    .where((element) => element["id"] == chosenSubId)
                    .first["durationDays"],
                isExpired ? "" : expDate,
              );
              refreshDialog(context, () async {
                await _recheckPlanExpiry();
                Navigator.pop(context);
              });
            },
            child: Container(
              padding: kPagePaddingInsets,
              decoration: BoxDecoration(
                color: chosenSubId >= kSubscriptions.length || chosenSubId < 0
                    ? Theme.of(context).cardColor
                    : null,
                borderRadius: BorderRadius.circular(kBorderRadius / 2),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).indicatorColor.withOpacity(0.4),
                    spreadRadius: 1,
                  ),
                ],
              ),
              width: size.width - (kPagePadding * 2),
              child: Center(
                child: Text(
                  'Choose Plan & Pay',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color:
                        chosenSubId >= 0 && chosenSubId < kSubscriptions.length
                            ? kLightColor
                            : null,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: kPagePadding),
        ],
      ),
    );
  }
}
