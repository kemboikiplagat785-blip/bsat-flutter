import 'package:bsat/components/dialogs/confirm_delete_dialog.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../utils/constants.dart';
import '../tool_button.dart';

Future<String?> showChangeCategoryDialog(BuildContext context,
    {int transactionCount = 1}) {
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
            Text('Change the category of $transactionCount transaction(s) to:'),
            const SizedBox(height: kPagePadding / 2),
            Wrap(
              spacing: 10,
              runSpacing: 5,
              children: [
                toolButton(
                  () async {
                    if ((await showConfirmDeleteDialog(context,
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
                    if ((await showConfirmDeleteDialog(context,
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
                    if ((await showConfirmDeleteDialog(context,
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
                    if ((await showConfirmDeleteDialog(context,
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
                    if ((await showConfirmDeleteDialog(context,
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
                // New: Paused
                toolButton(
                  () async {
                    if ((await showConfirmDeleteDialog(context,
                            message: 'Change category to Paused?')) ??
                        false) {
                      Navigator.of(context).pop(TransactionStatuses.paused);
                    }
                  },
                  Icon(
                    CupertinoIcons.pause_circle_fill,
                    color: kWarningColor,
                    size: 14,
                  ),
                  'Paused',
                  context,
                  withBorder: true,
                  textSize: 12,
                  accentColor: kWarningColor,
                ),

                // New: Timed Out
                // toolButton(
                //   () async {
                //     if ((await showConfirmDialog(context,
                //             message: 'Change category to Timed out?')) ??
                //         false) {
                //       Navigator.of(context).pop(TransactionStatuses.timedOut);
                //     }
                //   },
                //   Icon(
                //     CupertinoIcons.timer,
                //     color: kWarningColor,
                //     size: 14,
                //   ),
                //   'Timed out',
                //   context,
                //   withBorder: true,
                //   textSize: 12,
                //   accentColor: kWarningColor,
                // ),

                // New: Unavailable Offer
                toolButton(
                  () async {
                    if ((await showConfirmDeleteDialog(context,
                            message:
                                'Change category to Unavailable offer?')) ??
                        false) {
                      Navigator.of(context)
                          .pop(TransactionStatuses.unavailableOffer);
                    }
                  },
                  Icon(
                    CupertinoIcons.exclamationmark_triangle,
                    color: Colors.white,
                    size: 14,
                  ),
                  'Unavailable',
                  context,
                  withBorder: true,
                  textSize: 12,
                  accentColor: Colors.white,
                ),

                // New: Has Okoa
                toolButton(
                  () async {
                    if ((await showConfirmDeleteDialog(context,
                            message: 'Change category to Has Okoa?')) ??
                        false) {
                      Navigator.of(context).pop(TransactionStatuses.hasOkoa);
                    }
                  },
                  const Icon(
                    Icons.sailing_rounded,
                    color: kDullColor,
                    size: 14,
                  ),
                  'Has Okoa',
                  context,
                  withBorder: true,
                  textSize: 12,
                  accentColor: Colors.white,
                ),

                // New: Blacklisted
                toolButton(
                  () async {
                    if ((await showConfirmDeleteDialog(context,
                            message: 'Change category to Blacklisted?')) ??
                        false) {
                      Navigator.of(context)
                          .pop(TransactionStatuses.blacklisted);
                    }
                  },
                  const Icon(
                    Icons.person_off_outlined,
                    color: kWarningColor,
                    size: 14,
                  ),
                  'Blacklisted',
                  context,
                  withBorder: true,
                  textSize: 12,
                  accentColor: kErrorColor,
                ),
                toolButton(
                  () async {
                    if ((await showConfirmDeleteDialog(context,
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

                // New: Advanced Queue
                // toolButton(
                //   () async {
                //     if ((await showConfirmDialog(context,
                //             message: 'Change category to Advanced queue?')) ??
                //         false) {
                //       Navigator.of(context)
                //           .pop(TransactionStatuses.advancedQueue);
                //     }
                //   },
                //   Icon(
                //     CupertinoIcons.arrow_right_circle_fill,
                //     color: kIndigoColor,
                //     size: 14,
                //   ),
                //   'Advanced queue',
                //   context,
                //   withBorder: true,
                //   textSize: 12,
                //   accentColor: kIndigoColor,
                // ),
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
