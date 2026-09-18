import 'package:flutter/material.dart';

import '../../services/payments.dart';
import '../../utils/constants.dart';
import 'loading_dialog.dart';
import 'show_error_dialog.dart';
import 'success_dialog.dart';

Future<bool?> proceedToPayDialog(
  BuildContext context,
  int amount,
  int days,
  int subId,
  String name,
  String expiryDate,
  int planId,
  String tier,
) {
  var textTheme = Theme.of(context).textTheme;
  return showDialog<bool>(
    barrierDismissible: false,
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Important!',
              style: textTheme.titleLarge,
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            expiryDate == ""
                ? Container()
                : Text('You have an active plan valid till $expiryDate.\n'),
            Text(
                'The app will deduct airtime worth KSH $amount from your current balance. Continue?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: kErrorColor),
            ),
          ),
          TextButton(
            onPressed: () async {
              showLoadingDialog(context);

              await PaymentOps()
                  .payCore(amount, days, subId, planId, tier)
                  // _phoneService
                  //     .makeMyRequest("*140*${amount}*0702015937#",
                  //         s.subscriptionId)
                  .then((value) {
                Navigator.pop(context);
                Navigator.pop(context);
                Navigator.pop(context);
                // //print("VAls: ${value}");
                if (value[1] == TransactionStatuses.error) {
                  showErrorDialog(
                    context,
                    "Error paying KSH $amount: ",
                    value[0],
                  );
                  // showSuccessDialog(context, "Payment made successfully.");
                } else {
                  showSuccessDialog(context,
                      text: "Payment of KSH $amount made successfully.");
                }
              });
            },
            child: const Text('Proceed'),
          ),
        ],
      );
    },
  ).then((value) => value ?? false);
}
