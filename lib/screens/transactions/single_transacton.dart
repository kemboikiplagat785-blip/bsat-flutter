import 'package:bsat/components/dialogs/change%20category_dialog.dart';
import 'package:bsat/components/dialogs/forward_text.dart';
import 'package:bsat/components/header.dart';
import 'package:bsat/services/sms_sevice.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../components/dialogs/confirm_dialog.dart';
import '../../components/dialogs/loading_dialog.dart';
import '../../components/dialogs/success_dialog.dart';
import '../../components/dialogs/till_done_dialogue.dart';
import '../../components/tool_button.dart';
import '../../controllers/transaction_controller.dart';
import '../../services/contacts_service.dart';
import '../../utils/constants.dart';
import '../tasks/edit_task.dart';

class SingleTransactionPage extends StatefulWidget {
  final id;
  const SingleTransactionPage({required this.id, super.key});

  @override
  State<SingleTransactionPage> createState() => _SingleTransactionPageState();
}

class _SingleTransactionPageState extends State<SingleTransactionPage> {
  final _sqliteService = SQLiteService();
  Map<String, dynamic> _details = {};
  bool _canRedial = true;
  // bool _contactExists = false;

  final _contactService = ContactsService();
  bool showFullMpesaMessage = false;
  bool showFullReply = false;

  List toForward = [];

  @override
  void initState() {
    super.initState();

    getStuff();
  }

  void getStuff() async {
    if (!mounted) return;
    _details = await _sqliteService.queryOne('transactions', widget.id);

    SchedulerBinding.instance.addPostFrameCallback((_) {
      setState(() {});
      _canRedial = true;
    });

    toForward = await _sqliteService.queryCustom(
      "forwarded",
      "(amounts LIKE ? OR amounts LIKE ? OR amounts LIKE ? OR amounts LIKE ?)",
      [
        '[${_details['amount']},%',
        '%,${_details['amount']},%',
        '%,${_details['amount']}]',
        '[${_details['amount']}]',
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header(context, '0${_details["number"]}'),
            // const Spacer(flex: 3),
            Padding(
              padding: kPagePaddingInsets,
              child: Container(
                padding: kPagePaddingInsets,
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(kBorderRadius),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  CupertinoIcons.phone_fill,
                                  color: Theme.of(context).indicatorColor,
                                  size: 14,
                                ),
                                const SizedBox(width: kPagePadding / 4),
                                Text(
                                  '0${_details["number"]}',
                                  // style: textTheme.headlineLarge!.merge(
                                  //   const TextStyle(color: kPrimaryColor),
                                  // ),
                                ),
                              ],
                            ),
                            const SizedBox(height: kPagePadding / 2),
                            Row(
                              children: [
                                Icon(
                                  Icons.dialpad,
                                  color: Theme.of(context).indicatorColor,
                                  size: 14,
                                ),
                                const SizedBox(width: kPagePadding / 4),
                                Text(
                                  'KSH ${_details["amount"]}',
                                ),
                              ],
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  CupertinoIcons.timer,
                                  color: Theme.of(context).indicatorColor,
                                  size: 14,
                                ),
                                const SizedBox(width: kPagePadding / 4),
                                Text(
                                  '${_details["time"]} ${_details["date"]}',
                                ),
                              ],
                            ),
                            const SizedBox(height: kPagePadding / 2),
                            Row(
                              children: [
                                Icon(
                                  Icons.money_rounded,
                                  color: Theme.of(context).indicatorColor,
                                  size: 14,
                                ),
                                const SizedBox(width: kPagePadding / 4),
                                Text(
                                  '${_details["ussdDialed"]}',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: kPagePadding),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Reply',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          onPressed: () {
                            setState(() {
                              showFullReply = !showFullReply;
                            });
                          },
                          icon: Icon(showFullReply
                              ? Icons.expand_less
                              : Icons.expand_more),
                        ),
                      ],
                    ),
                    Text(
                      '${_details["ussdReply"]}',
                      maxLines: showFullReply ? null : 1,
                    ),
                    const SizedBox(height: kPagePadding),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'MPESA Text',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          onPressed: () {
                            setState(() {
                              showFullMpesaMessage = !showFullMpesaMessage;
                            });
                          },
                          icon: Icon(showFullMpesaMessage
                              ? Icons.expand_less
                              : Icons.expand_more),
                        ),
                      ],
                    ),
                    Text(
                      '${_details["initialMessage"]}',
                      maxLines: showFullMpesaMessage ? null : 1,
                    ),
                    const SizedBox(height: kPagePadding * 2),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            toolButton(
                              () async {
                                tillDoneDialogue(
                                  context,
                                  Padding(
                                    padding: kPagePaddingInsets,
                                    child: Text("Redialing"),
                                  ),
                                  () async {
                                    await TransactionController()
                                        .redoTransaction(
                                      _details["id"],
                                      _details["ussdDialed"],
                                      _details["simSubId"],
                                      _details["canRetry"],
                                    );

                                    getStuff();
                                  },
                                );
                              },
                              Icon(
                                CupertinoIcons.phone_arrow_up_right,
                                color: kPrimaryColor,
                                size: 14,
                              ),
                              "Redial",
                              context,
                              textSize: 13,
                            ),
                            toolButton(
                              () {
                                Navigator.of(context).push(
                                  PageRouteBuilder(
                                    pageBuilder: (
                                      context,
                                      animation,
                                      secondaryAnimation,
                                    ) =>
                                        EditTaskPage(
                                      taskId: -2,
                                      number: _details['number'],
                                      dialSim: _details['simSubId'],
                                      amount: _details['amount'],
                                      offer: _details['ussdDialed'],
                                    ),
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
                                );
                              },
                              Icon(
                                Icons.precision_manufacturing_outlined,
                                color: kErrorColor,
                                size: 14,
                              ),
                              "Automate Task",
                              context,
                              textSize: 13,
                            ),
                            toolButton(
                              () async {
                                int numb = toForward.isNotEmpty
                                    ? toForward[0]['numberToReceive']
                                    : 0;
                                await showForwardTextDialog(
                                  context,
                                  _details['initialMessage'],
                                  numb,
                                );
                              },
                              Icon(
                                Icons.send_outlined,
                                color: Theme.of(context).indicatorColor,
                                size: 14,
                              ),
                              "Forward MPESA message",
                              context,
                              textSize: 13,
                            ),
                          ],
                        ),
                        // Text('${_details["ussdReply"]}'),
                        const SizedBox(height: kPagePadding / 2),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            toolButton(
                              () async {
                                await Clipboard.setData(
                                  ClipboardData(
                                    text: "0${_details['number']}",
                                  ),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(
                                          '0${_details['number']} copied to clipboard')),
                                );
                              },
                              Icon(
                                Icons.copy,
                                color: Theme.of(context).indicatorColor,
                                size: 14,
                              ),
                              "Number",
                              context,
                              textSize: 13,
                            ),
                            toolButton(
                              () async {
                                await Clipboard.setData(
                                  ClipboardData(
                                    text: "${_details['ussdDialed']}",
                                  ),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(
                                          '${_details['ussdDialed']} copied to clipboard')),
                                );
                              },
                              Icon(
                                Icons.copy,
                                color: Theme.of(context).indicatorColor,
                                size: 14,
                              ),
                              "USSD",
                              context,
                              textSize: 13,
                            ),
                            toolButton(
                              () async {
                                await Clipboard.setData(
                                  ClipboardData(
                                    text: "${_details['initialMessage']}",
                                  ),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content:
                                        Text('Message copied to clipboard'),
                                  ),
                                );
                              },
                              Icon(
                                Icons.copy,
                                color: Theme.of(context).indicatorColor,
                                size: 14,
                              ),
                              "MPESA Message",
                              context,
                              textSize: 13,
                            ),
                            toolButton(
                              () async {
                                await Clipboard.setData(
                                  ClipboardData(
                                    text: "${_details['ussdReply']}",
                                  ),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('USSD Reply copied'),
                                  ),
                                );
                              },
                              Icon(
                                Icons.copy,
                                color: Theme.of(context).indicatorColor,
                                size: 14,
                              ),
                              "Reply",
                              context,
                              textSize: 13,
                            ),
                          ],
                        ),
                        // Text('${_details["ussdReply"]}'),
                        // const SizedBox(height: kPagePadding),

                        const SizedBox(height: kPagePadding / 2),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            toolButton(
                              () async {
                                String? status =
                                    await showChangeCategoryDialog(context);

                                if (status != null && status.isNotEmpty) {
                                  await _sqliteService.updateStuff(
                                    {
                                      'status': status,
                                    },
                                    'id = ?',
                                    [_details['id']],
                                    'transactions',
                                  );

                                  showSuccessDialog(
                                      context, 'Category changed to $status');

                                  Future.delayed(const Duration(seconds: 3),
                                      () {
                                    // print("Action executed after 3 seconds!");
                                    Navigator.pop(context);
                                    // your action here
                                  });
                                }
                              },
                              Icon(
                                Icons.satellite_alt_rounded,
                                color: Theme.of(context).indicatorColor,
                                size: 14,
                              ),
                              "Change Category",
                              context,
                              textSize: 13,
                            ),
                            toolButton(
                              () async {
                                await TransactionController()
                                    .addNumberToBlacklist(_details['number']);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      '0${_details['number']} added to blacklist',
                                    ),
                                  ),
                                );
                              },
                              Icon(
                                Icons.person_add_disabled_outlined,
                                color: Theme.of(context).indicatorColor,
                                size: 14,
                              ),
                              "Blacklist",
                              context,
                              textSize: 13,
                            ),
                            toolButton(
                              () async {
                                await tillDoneDialogue(
                                    context, Text("Adding to contacts"),
                                    () async {
                                  await _contactService.addNewContact(
                                    _details['source'],
                                    '0${_details["number"]}',
                                  );
                                  // Navigator.pop(context);
                                });
                                Navigator.pop(context);
                              },
                              Icon(
                                CupertinoIcons.person_add,
                                color: Theme.of(context).indicatorColor,
                                size: 14,
                              ),
                              "Save contact",
                              context,
                              textSize: 13,
                            ),
                            toolButton(
                              () async {
                                // await tillDoneDialogue(
                                //     context, Text("Adding to contacts"),
                                //     () async {
                                //   await _contactService.addNewContact(
                                //     _details['source'],
                                //     '0${_details["number"]}',
                                //   );
                                //   // Navigator.pop(context);
                                // });
                                // Navigator.pop(context);
                                if ((await showConfirmDialog(
                                      context,
                                      title: 'Warning',
                                      message:
                                          'Are you sure you want to reverse this transaction?',
                                    ) ??
                                    false)) {
                                  await tillDoneDialogue(
                                      context, Text("Reversing message"),
                                      () async {
                                    String trimmedMessage =
                                        _details["initialMessage"]
                                                    .toString()
                                                    .length >
                                                160
                                            ? _details["initialMessage"]
                                                .toString()
                                                .substring(0, 160)
                                            : _details["initialMessage"]
                                                .toString();

                                    sendEvenInBackground('456', trimmedMessage);
                                  }).then((value) async {
                                    if ((await showConfirmDialog(
                                          context,
                                          title: 'Done',
                                          message:
                                              'Delete this transaction too?',
                                          btnText: 'Delete',
                                        )) ??
                                        false) {
                                      showLoadingDialog(context);
                                      await _sqliteService.deleteStuff(
                                        _details["id"],
                                        "transactions",
                                      );
                                      Navigator.pop(context);
                                      Navigator.pop(context);
                                      showSuccessDialog(
                                        context,
                                        'Deleted',
                                        text: 'Transaction deleted',
                                      );
                                    }
                                    {}
                                  });
                                  return;
                                }
                              },
                              Icon(
                                CupertinoIcons.exclamationmark_octagon,
                                color: kErrorColor,
                                size: 14,
                              ),
                              "Reverse message",
                              context,
                              textSize: 13,
                            ),
                            toolButton(
                              () async {
                                showLoadingDialog(context);
                                await _sqliteService.deleteStuff(
                                  _details["id"],
                                  "transactions",
                                );

                                Navigator.pop(context);
                                Navigator.pop(context);
                              },
                              Icon(
                                CupertinoIcons.trash,
                                color: kErrorColor,
                                size: 14,
                              ),
                              "Delete",
                              context,
                              textSize: 13,
                            ),
                          ],
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
