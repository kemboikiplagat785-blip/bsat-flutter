import 'package:bsat/controllers/transaction_controller.dart';
import 'package:bsat/screens/transactions/single_transacton.dart';
import 'package:bsat/utils/constants.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Widget transactionListItem(
    BuildContext context,
    int number,
    int amount,
    String status,
    String reply,
    String date,
    String time,
    int id,
    String code,
    String source,
    int simSubId,
    int canRetry,
    {int? lineLimit,
    bool? selectionMode}) {
  String displayNum =
      number > 10000000 ? number.toString().substring(0, 4) : '0000';

  return Padding(
    padding: const EdgeInsets.only(bottom: kPagePadding / 3),
    child: InkWell(
      onTap: (selectionMode ?? false)
          ? null
          : () {
              Navigator.of(context).push(
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      SingleTransactionPage(id: id),
                  transitionsBuilder: (
                    context,
                    animation,
                    secondaryAnimation,
                    child,
                  ) {
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
        padding: const EdgeInsets.all(kPagePadding / 2),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(kBorderRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: kPagePadding / 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      source,
                      style: kTitleText,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(' 0$displayNum...')
                  ],
                ),
                Text(
                  date,
                  style: TextStyle(
                      color: Theme.of(context).primaryColor.withOpacity(.5)),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      "KSH",
                      // style: textTheme.labelSmall,
                      style: TextStyle(
                          color:
                              Theme.of(context).primaryColor.withOpacity(.5)),
                    ),
                    Text(
                      " $amount",
                      // "10,000",
                      style: TextStyle(
                          color:
                              Theme.of(context).primaryColor.withOpacity(.5)),
                    ),
                  ],
                ),
                Text(
                  time,
                  style: TextStyle(
                      color: Theme.of(context).primaryColor.withOpacity(.5)),
                ),
              ],
            ),
            const SizedBox(height: kPagePadding / 2),
            Text(
              reply,
              // "You have"
              maxLines: lineLimit,
              overflow: lineLimit != null
                  ? TextOverflow.ellipsis
                  : TextOverflow.visible,
            ),
            const SizedBox(height: kPagePadding / 3),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    status == TransactionStatuses.error
                        ? IconButton(
                            onPressed: (selectionMode ?? false)
                                ? null
                                : () async {
                                    // //print("Codes: $code $amount $id $status");
                                    await TransactionController()
                                        .redoTransaction(
                                            id, code, simSubId, canRetry);

                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Transaction redone'),
                                      ),
                                    );
                                  },
                            icon: Icon(
                              size: 15,
                              CupertinoIcons.refresh,
                              color: kErrorColor,
                            ),
                          )
                        : Row(
                            children: [
                              IconButton(
                                onPressed: () async {},
                                icon: Icon(
                                  size: 15,
                                  status == TransactionStatuses.doneConfirmed
                                      ? CupertinoIcons.checkmark_seal_fill
                                      : CupertinoIcons.checkmark,
                                  color: status == TransactionStatuses.secondAttempt
                                      ? kWarningColor
                                      : kPrimaryColor,
                                ),
                              )
                            ],
                          ),
                    IconButton(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(
                            text: "0$number",
                          ),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text('0$number copied to clipboard')),
                        );
                      },
                      icon: Icon(
                        size: 15,
                        Icons.copy_all,
                        color: Theme.of(context).indicatorColor,
                      ),
                    ),
                  ],
                ),
                Icon(CupertinoIcons.chevron_compact_right),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
