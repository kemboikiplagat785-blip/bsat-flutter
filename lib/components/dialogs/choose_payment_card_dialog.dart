import 'package:bsat/components/dialogs/proceed_to_buy.dart';
import 'package:flutter/material.dart';
import 'package:sim_data/sim_data.dart';

import '../../utils/constants.dart';

Future<void> choosePaymentCardDialog(
  BuildContext context,
  List<SimCard> sims,
  int amount,
  int days,
  String expiryDate,
) {
  return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            'Choose sim card.',
            // style: const TextStyle(
            //   color: kDullColor,
            // ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Select a sim card to use for payment of ksh $amount"),
              Container(
                padding: kPagePaddingInsets,
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(kBorderRadius),
                ),
                child: Row(
                  // children: cards,
                  children: sims.map((s) {
                    return Expanded(
                      child: InkWell(
                        onTap: () async {
                          // if (!s.carrierName.contains(
                          //     RegExp(r'Safaricom', caseSensitive: false))) {
                          //   showErrorDialog(context, 'Invalid Sim Card',
                          //       'Use a valid Safaricom sim card');
                          //   return;
                          // }
                          await proceedToPayDialog(context, amount, days,
                              s.subscriptionId, s.displayName, expiryDate);
                        },
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.displayName),
                            const SizedBox(height: kPagePadding / 2),
                            const Icon(
                              Icons.sim_card_rounded,
                              size: 40,
                              color: kPrimaryColor,
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            )
          ],
        );
      });
}
