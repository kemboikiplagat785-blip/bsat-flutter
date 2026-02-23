import 'package:another_telephony/telephony.dart';
import 'package:bsat/controllers/transaction_controller.dart';
import 'package:bsat/services/sms_sevice.dart';
import 'package:bsat/utils/date_ops.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flutter/foundation.dart';

import '../components/dialogs/till_done_dialogue.dart';
import '../utils/constants.dart';

class InboxPage extends StatefulWidget {
  const InboxPage({super.key});

  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> {
  List<SmsMessage> smsList = [];

  bool loading = true;
  final Set<int> _selected = {};
  bool selectionMode = false;

  @override
  void initState() {
    super.initState();

    int limit = 400;

    if (kDebugMode) {
      limit = 20;
    }

    getAllSms(limit: limit).then((value) {
      setState(() {
        smsList = value;
        loading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    var textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: RawScrollbar(
        thumbColor: kPrimaryColor,
        // wider
        thickness: 8,
        thumbVisibility: true,
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(kBorderRadius),
                    bottomRight: Radius.circular(kBorderRadius),
                  ),
                  color: Theme.of(context).cardColor,
                ),
                child: Column(
                  children: [
                    const SizedBox(height: kPagePadding * 2),
                    Padding(
                      padding: kPagePaddingInsets,
                      child: _selected.isEmpty
                          ? Row(
                              children: [
                                IconButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  icon: const Icon(
                                    CupertinoIcons.back,
                                    size: 14,
                                  ),
                                ),
                                const SizedBox(width: kPagePadding / 2),
                                Text(
                                  'Inbox',
                                  style: textTheme.titleLarge,
                                ),
                              ],
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    IconButton(
                                      onPressed: () => setState(() => _selected.clear()),
                                      icon: const Icon(Icons.close),
                                    ),
                                    const SizedBox(width: 8),
                                    Text('${_selected.length} selected'),
                                  ],
                                ),
                                Row(
                                  children: [
                                    IconButton(
                                      tooltip: 'Retry selected',
                                      onPressed: _retrySelected,
                                      icon: const Icon(Icons.refresh),
                                    ),
                                    IconButton(
                                      tooltip: 'Copy numbers',
                                      onPressed: _copySelectedNumbers,
                                      icon: const Icon(Icons.copy),
                                    ),
                                  ],
                                )
                              ],
                            ),
                    ),
                    Padding(
                      padding: kPagePaddingInsets,
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Search messages...',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(kBorderRadius),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                        ),
                        onChanged: (value) async {
                          smsList = await searchSms(value);
                          setState(() {});
                        },
                      ),
                    )
                  ],
                ),
              ),
              const SizedBox(height: kPagePadding),
              loading
                  ? loadingWidget()
                  : Container(
                      padding: kPagePaddingInsets,
                      child: ListView.builder(
                        itemCount: smsList.length,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemBuilder: (context, index) {
                          final item = smsList[index];
                          final selected = _selected.contains(index);
                          return GestureDetector(
                            onLongPress: () {
                              setState(() {
                                if (selected) {
                                  _selected.remove(index);
                                } else {
                                  _selected.add(index);
                                }
                              });
                            },
                            onTap: () {
                              if (_selected.isNotEmpty) {
                                setState(() {
                                  if (selected) _selected.remove(index);
                                  else _selected.add(index);
                                });
                              } else {
                                int number = extract9DigitNumber(item.body ?? "");
                                Clipboard.setData(ClipboardData(text: '0$number'));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('0$number copied to clipboard')),
                                );
                              }
                            },
                            child: Container(
                              color: selected ? Theme.of(context).highlightColor : Theme.of(context).cardColor,
                              child: smsListItem(item, textTheme, index, selected),
                            ),
                          );
                        },
                        // children: smsList.map((listItem) {
                        //   return smsListItem(listItem, textTheme);
                        // }).toList(),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Container smsListItem(SmsMessage listItem, TextTheme textTheme, int index, bool selected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: kPagePadding),
      child: Column(
        children: [
          const SizedBox(height: kPagePadding),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  if (selected)
                    const Padding(
                      padding: EdgeInsets.only(right: 8.0),
                      child: Icon(
                        Icons.check_box,
                        size: 18,
                      ),
                    ),
                  Text(
                    listItem.address ?? "",
                    style: textTheme.titleLarge,
                  ),
                ],
              ),
              Text(
                  '${getNormalTime(DateTime.fromMillisecondsSinceEpoch(listItem.date ?? 0))} $interpunct ${getNormalDate(DateTime.fromMillisecondsSinceEpoch(listItem.date ?? 0))}'
                  // '${}',
                  ),
            ],
          ),
          const SizedBox(height: kPagePadding / 2),
          Text(listItem.body ?? ""),
          const SizedBox(height: kPagePadding / 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  if (listItem.address == "MPESA")
                    colouredButton(
                      () {
                        tillDoneDialogue(
                          context,
                          Padding(
                            padding: kPagePaddingInsets,
                            child: Text("Redialing"),
                          ),
                          () async {
                            onMessageReceive(listItem);

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Redialed')),
                            );
                          },
                        );
                      },
                      kPrimaryColor,
                      kPrimaryColor.withOpacity(.2),
                      Icon(
                        Icons.refresh,
                        color: kPrimaryColor,
                        size: 16,
                      ),
                    ),
                  SizedBox(width: kPagePadding / 4),
                  colouredButton(
                    () async {
                      int number = extract9DigitNumber(listItem.body ?? "");
                      // onMessageReceive(listItem);
                      // tillDoneDialogue(context, Text("Adding to blacklist"), () async {
                      await TransactionController().changeBlackListStatus(
                        number,
                      );

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('0$number added to blacklist')),
                      );
                    },
                    kErrorColor,
                    kErrorColor.withOpacity(.2),
                    Icon(
                      Icons.block,
                      color: kErrorColor,
                      size: 16,
                    ),
                  ),
                  SizedBox(width: kPagePadding / 4),
                  colouredButton(
                    () async {
                      // onMessageReceive(listItem);
                      await launchUrl(
                        Uri(
                          scheme: 'tel',
                          path: "0${extract9DigitNumber(listItem.body ?? "")}",
                        ),
                      );
                    },
                    kErrorColor,
                    Theme.of(context).indicatorColor.withOpacity(.05),
                    Icon(
                      Icons.call,
                      color: kPrimaryColor,
                      size: 16,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () async {
                  int number = extract9DigitNumber(listItem.body ?? "");

                  await Clipboard.setData(
                    ClipboardData(
                      text: "0$number",
                    ),
                  );

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('0$number copied to clipboard')),
                  );
                },
                child: Text(
                  'Copy number',
                  style: TextStyle(
                      color: Theme.of(context).indicatorColor,
                      fontWeight: FontWeight.w900),
                ),
              )
            ],
          ),
          const SizedBox(height: kPagePadding / 3),
        ],
      ),
    );
  }

  Widget loadingWidget() {
    return const Center(
      child: Text(
        'loading...',
      ),
    );
  }

  Widget colouredButton(
    Function onTap,
    Color fgColor,
    Color bgColor,
    Widget content,
  ) {
    return GestureDetector(
      onTap: () {
        onTap();
      },
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(kBorderRadius / 2),
        ),
        padding: kPagePaddingInsets / 3,
        child: content,
      ),
    );
  }

  void _retrySelected() {
    if (_selected.isEmpty) return;
    for (final i in _selected) {
      if (i >= 0 && i < smsList.length) {
        final msg = smsList[i];
        onMessageReceive(msg);
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Retried ${_selected.length} messages')));
    setState(() => _selected.clear());
  }

  void _copySelectedNumbers() async {
    if (_selected.isEmpty) return;
    final numbers = <String>[];
    for (final i in _selected) {
      if (i >= 0 && i < smsList.length) {
        final msg = smsList[i];
        final n = extract9DigitNumber(msg.body ?? "");
        numbers.add('0$n');
      }
    }
    final text = numbers.join(', ');
    await Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied ${numbers.length} numbers')));
    setState(() => _selected.clear());
  }
}
