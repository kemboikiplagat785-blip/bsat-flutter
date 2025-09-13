import 'package:bsat/components/dialogs/confirm_dialog.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../utils/constants.dart';
import '../tool_button.dart';

Future<String?> showChangeCategoryDialog(BuildContext context) {
  return showDialog<String>(
    barrierDismissible: false,
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Change Category'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Change the category of your transactions(s) to:'),
            const SizedBox(height: kPagePadding / 2),
            Wrap(
              spacing: 10,
              runSpacing: 5,
              children: [
                toolButton(
                  () async {
                    if ((await showConfirmDialog(context,
                            message: 'Change category to advanced?')) ??
                        false) {
                      Navigator.of(context)
                          .pop(TransactionStatuses.advancedUssd);
                    }
                  },
                  Icon(
                    CupertinoIcons.phone_circle_fill,
                    color: kPrimaryColor,
                    size: 14,
                  ),
                  'Advanced',
                  context,
                  withBorder: true,
                  textSize: 12,
                  accentColor: kPrimaryColor,
                ),
                toolButton(
                  () async {
                    if ((await showConfirmDialog(context,
                            message:
                                'Change category to Successful (confirmed)?')) ??
                        false) {
                      Navigator.of(context)
                          .pop(TransactionStatuses.doneConfirmed);
                    }
                  },
                  Icon(
                    CupertinoIcons.checkmark_seal_fill,
                    color: kPrimaryColor,
                    size: 14,
                  ),
                  'Successful(confirmed)',
                  context,
                  withBorder: true,
                  textSize: 12,
                  accentColor: kPrimaryColor,
                ),
                toolButton(
                  () async {
                    if ((await showConfirmDialog(context,
                            message:
                                'Change category to Successful (unconfirmed)?')) ??
                        false) {
                      Navigator.of(context).pop(TransactionStatuses.done);
                    }
                  },
                  Icon(
                    CupertinoIcons.checkmark,
                    color: kWarningColor,
                    size: 14,
                  ),
                  'Successful(pending)',
                  context,
                  withBorder: true,
                  textSize: 12,
                  accentColor: kPrimaryColor,
                ),
                toolButton(
                  () async {
                    if ((await showConfirmDialog(context,
                            message: 'Change category to Forwarded?')) ??
                        false) {
                      Navigator.of(context).pop(TransactionStatuses.forwarded);
                    }
                  },
                  Icon(
                    CupertinoIcons.arrow_up_right,
                    color: kPrimaryColor,
                    size: 14,
                  ),
                  'Forwarded',
                  context,
                  withBorder: true,
                  textSize: 12,
                  accentColor: kPrimaryColor,
                ),
                toolButton(
                  () async {
                    if ((await showConfirmDialog(context,
                            message:
                                'Change category to Failed (second attempt)?')) ??
                        false) {
                      Navigator.of(context)
                          .pop(TransactionStatuses.secondAttempt);
                    }
                  },
                  Icon(
                    CupertinoIcons.repeat,
                    color: kWarningColor,
                    size: 14,
                  ),
                  'Second Attempt',
                  context,
                  withBorder: true,
                  textSize: 12,
                  accentColor: kWarningColor,
                ),
                toolButton(
                  () async {
                    if ((await showConfirmDialog(context,
                            message: 'Change category to Error?')) ??
                        false) {
                          // await SQLiteService().updateStuff({'status': }, where, whereArgs, table)
                      Navigator.of(context).pop(TransactionStatuses.error);
                    }
                  },
                  Icon(
                    CupertinoIcons.xmark,
                    color: kErrorColor,
                    size: 14,
                  ),
                  'Error',
                  context,
                  withBorder: true,
                  textSize: 12,
                  accentColor: kErrorColor,
                ),
              ],
            )
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: Text('Cancel'),
          ),
        ],
      );
    },
  );
}
