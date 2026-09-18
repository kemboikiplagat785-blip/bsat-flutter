import 'dart:convert';

import 'package:bsat/components/dialogs/confirm_delete_dialog.dart';
import 'package:bsat/components/dialogs/loading_dialog.dart';
import 'package:bsat/components/dialogs/success_dialog.dart';
import 'package:bsat/services/sms_sevice.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:another_telephony/telephony.dart';

import '../components/chip_input_field.dart';
import '../components/header.dart';
import '../services/sqlite_service.dart';
import '../utils/constants.dart';

class ForwardSmsPage extends StatefulWidget {
  const ForwardSmsPage({super.key});

  @override
  State<ForwardSmsPage> createState() => _ForwardSmsPageState();
}

class _ForwardSmsPageState extends State<ForwardSmsPage> {
  final _sqliteService = SQLiteService();

  final _amountsToForwardTextController = TextEditingController();
  final _whitelistedNumberTextController = TextEditingController();
  final _numberToForwardToTextController = TextEditingController();

  List<int> _whitelistedNumbers = [];
  List<int> _amountsToForward = [];

  List<SubscriptionInfo> sims = [];

  int _dialSim = -1;

  final List<String> _chips = [];

  List<Map<String, dynamic>> _forwards = [];

  String _error = "";

  int _editingId = -1;

  // void _processWhitelist() {
  //   // if (text.length >= 9 && text.length <= 13) {
  //   setState(() {
  //   _sqliteService.insertStuff(, table)
  //     _whitelistedNumbers
  //         .add(int.parse(_whitelistedNumberTextController.text.trim()));
  //     _whitelistedNumberTextController.clear();
  //   });
  //   // }
  // }

  void _processAmountsToForward() {
    setState(() {
      _amountsToForward
          .add(int.parse(_amountsToForwardTextController.text.trim()));
      _amountsToForwardTextController.clear();
    });
  }

  Future<void> getAndProcessCards() async {
    try {
      final subscriptions = await Telephony.instance.getSubscriptionList();

      if (!mounted) return;

      setState(() {
        sims = subscriptions;
      });

      debugPrint("Found ${subscriptions.length} SIM(s)");
    } catch (e) {
      debugPrint("Error getting SIM subscriptions: $e");
    }
  }

  void _removeChip(String chip) {
    setState(() {
      _chips.remove(chip);
    });
  }

  Future<void> _addToForwardedDB() async {
    var row = {
      'dialSim': _dialSim,
      'numberToReceive':
          extract9DigitNumber(_numberToForwardToTextController.text),
      'amounts': jsonEncode(_amountsToForward),
      'isActive': 1,
    };

    await _sqliteService.insertStuff(row, 'forwarded');

    _amountsToForward = [];

    // insertStuff(row, 'forwarded');
  }

  void _addToWhitelistedDB() async {
    var row = {
      'number': extract9DigitNumber(
          _whitelistedNumberTextController.text.replaceAll(' ', '')),
    };

    await _sqliteService.insertStuff(row, 'processText');

    _getData();
  }

  void _removeFromWhitelistDB(String number) async {
    await _sqliteService.deleteWhere(
      'processText',
      'number LIKE ?',
      [int.parse(number)],
      // 'TRUE', []
    );

    // await _sqliteService.

    _getData();
  }

  void _getData() async {
    _forwards = await _sqliteService.queryAll('forwarded');
    //print("Forwards: $_forwards");
    _whitelistedNumbers = await _sqliteService.queryAll('processText').then(
      (onValue) {
        return onValue
            .map((e) => extract9DigitNumber(e['number'].toString()))
            .toList();
      },
    );

    debugPrint("Forwards: $_forwards");
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    getAndProcessCards();

    _getData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header(context, 'Forward/Process Texts'),
            Padding(
              padding: kPagePaddingInsets,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Forward MPESA messages.',
                      ),
                      SizedBox(height: kPagePadding / 3),
                      InkWell(
                        onTap: () {
                          // Add your onPressed code here!
                          showDialog(
                            context: context,
                            builder: (context) {
                              return AlertDialog(
                                title: Text("How it works"),
                                content: SingleChildScrollView(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                          "Forwarding helps you share the load of processing MPESA transactions between two phones. For example, you can have one phone that receives all MPESA messages and forwards only those with certain amounts to another phone that processes them. This is useful if you have multiple offers to run on different phones or if you want to separate simple and advanced USSDs."),
                                      SizedBox(height: kPagePadding),
                                      Text(
                                          "1. The receiving phone must have BSAT installed."),
                                      SizedBox(height: kPagePadding),
                                      Text(
                                          "2. Set up forwarding rules below. By clicking +"),
                                      SizedBox(height: kPagePadding / 2),
                                      Padding(
                                        padding: kPagePaddingInsets / 2,
                                        child: Text(
                                            "\ta. Enter all the amounts you want to be processed by the receiving phone."),
                                      ),
                                      SizedBox(height: kPagePadding / 2),
                                      Padding(
                                        padding: kPagePaddingInsets / 2,
                                        child: Text(
                                            "\tb. Enter the phone number of the SIM card in the receiving phone."),
                                      ),
                                      SizedBox(height: kPagePadding / 2),
                                      // Text(
                                      //   "3. Set up and have the number (on this phone) that will send the message whitelisted in order for the message to be processed."),
                                      // SizedBox(height: kPagePadding / 2),
                                      // Text("\tc. "),
                                    ],
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () {
                                      Navigator.pop(context);
                                    },
                                    child: Text("Got it"),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                        child: Text(
                          'ⓘ How it works',
                          style: TextStyle(
                            color: kPrimaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: kPagePadding),
                  Container(
                    padding: kPagePaddingInsets,
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(kBorderRadius),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          children: [
                            Text("Forward messages for specific amounts"),
                            SizedBox(height: kPagePadding / 2),
                            ...(_forwards.map((forward) {
                              bool isPaused = (forward['paused'] ?? 0) == 1;
                              return Padding(
                                padding:
                                    const EdgeInsets.only(bottom: kPagePadding),
                                child: Container(
                                  padding: kPagePaddingInsets,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).cardColor,
                                    borderRadius: BorderRadius.circular(
                                      kBorderRadius / 2,
                                    ),
                                    border: isPaused
                                        ? Border.all(
                                            color: Colors.orange, width: 2)
                                        : null,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "To: ${forward['numberToReceive']}",
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        "Amounts: ${jsonDecode(forward['amounts']).join(', ')}",
                                        style:
                                            TextStyle(color: Colors.grey[600]),
                                      ),
                                      if (isPaused)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 4.0),
                                          child: Text(
                                            "PAUSED",
                                            style: TextStyle(
                                                color: Colors.orange,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12),
                                          ),
                                        ),
                                      SizedBox(height: kPagePadding / 2),
                                      Divider(),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          // Edit Button
                                          IconButton(
                                            icon: Icon(CupertinoIcons.pencil,
                                                color: kPrimaryColor),
                                            tooltip: 'Edit',
                                            onPressed: () async {
                                              await showForwardingDialog(
                                                context,
                                                id: forward['id'],
                                              );
                                              _getData();
                                            },
                                          ),
                                          // Pause/Resume Button
                                          IconButton(
                                            icon: Icon(
                                              isPaused
                                                  ? CupertinoIcons.play_circle
                                                  : CupertinoIcons.pause_circle,
                                              color: isPaused
                                                  ? Colors.green
                                                  : Colors.orange,
                                            ),
                                            tooltip:
                                                isPaused ? 'Resume' : 'Pause',
                                            onPressed: () async {
                                              try {
                                                await _sqliteService
                                                    .updateStuff(
                                                  {'paused': isPaused ? 0 : 1},
                                                  'id = ?',
                                                  [forward['id']],
                                                  'forwarded',
                                                );
                                              } catch (e) {
                                                debugPrint(
                                                    "Error updating paused state: $e");
                                              }
                                              _getData();
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                    content: Text(isPaused
                                                        ? "Resumed"
                                                        : "Paused")),
                                              );
                                            },
                                          ),
                                          // Delete Button
                                          IconButton(
                                            icon: Icon(Icons.delete,
                                                color: kErrorColor),
                                            tooltip: 'Delete',
                                            onPressed: () async {
                                              bool delete =
                                                  await showConfirmDeleteDialog(
                                                        context,
                                                        title: 'Warning',
                                                        message:
                                                            'Are you sure you want to delete this forwarding rule?',
                                                      ) ??
                                                      false;

                                              if (!delete) return;
                                              showLoadingDialog(context);
                                              await _sqliteService.deleteWhere(
                                                'forwarded',
                                                'id = ?',
                                                [forward['id']],
                                              );
                                              _getData();
                                              Navigator.pop(context);
                                            },
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList())
                          ],
                        ),
                        InkWell(
                          onTap: () {
                            showForwardingDialog(context);
                          },
                          child: Center(
                            child: Padding(
                              padding: kPagePaddingInsets,
                              child: Center(
                                child: Icon(CupertinoIcons.add_circled),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: kPagePadding),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Whitelist',
                      ),
                      SizedBox(height: kPagePadding / 3),
                      GestureDetector(
                        onTap: () {
                          // Add your onPressed code here!
                          showDialog(
                            context: context,
                            builder: (context) {
                              return AlertDialog(
                                title: Text("How it works"),
                                content: SingleChildScrollView(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                          "Set up this phone to process messages from certain numbers as legitimate MPESA messages."),
                                    ],
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () {
                                      Navigator.pop(context);
                                    },
                                    child: Text("Got it"),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                        child: Text(
                          'ⓘ How it works',
                          style: TextStyle(
                            color: kPrimaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: kPagePadding),
                  Container(
                    padding: kPagePaddingInsets,
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(kBorderRadius),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Numbers that can forward messages to me:"),
                        SizedBox(height: kPagePadding / 3),
                        ChipInputField(
                          chips: _whitelistedNumbers,
                          controller: _whitelistedNumberTextController,
                          onAddChip: () {
                            setState(() {
                              _addToWhitelistedDB();
                            });
                          },
                          onRemoveChip: (chip) {
                            // _whitelistedNumbers.remove(int.parse(chip));
                            _removeFromWhitelistDB(chip);
                          },
                          keyboardType: TextInputType.number,
                          spacing: kPagePadding / 3,
                          borderRadius: kBorderRadius,
                          addIconColor: kPrimaryColor,
                        )
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> showForwardingDialog(
    BuildContext context, {
    int id = -1,
  }) {
    if (id != -1) {
      var editing = _forwards.firstWhere((element) => element['id'] == id);
      _amountsToForward = List<int>.from(jsonDecode(editing['amounts']));
      _numberToForwardToTextController.text =
          editing['numberToReceive'].toString();
      _dialSim = editing['dialSim'];
      _editingId = id;
    } else {
      _amountsToForward = [];
      _numberToForwardToTextController.text = "";
      _dialSim = -1;
      _editingId = -1;
    }

    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("Forward Transaction"),
          content: StatefulBuilder(
            builder: (context, setState) {
              return SingleChildScrollView(
                child: Container(
                  padding: kPagePaddingInsets,
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(kBorderRadius),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize:
                        MainAxisSize.min, // To avoid unnecessary expansion
                    children: [
                      // if (_error.isNotEmpty)
                      Text(
                        _error,
                        style: TextStyle(color: kErrorColor),
                      ),
                      Text("Amounts to forward (Ksh)"),
                      SizedBox(height: kPagePadding / 3),
                      ChipInputField(
                        chips: _amountsToForward,
                        controller: _amountsToForwardTextController,
                        onAddChip: () {
                          setState(() {
                            _processAmountsToForward();
                          });
                        },
                        onRemoveChip: (chip) {
                          setState(() {
                            _amountsToForward.remove(int.parse(chip));
                            //print(_amountsToForward);
                          });
                        },
                        keyboardType: TextInputType.number,
                        spacing: kPagePadding / 3,
                        borderRadius: kBorderRadius,
                        addIconColor: kPrimaryColor,
                      ),
                      SizedBox(height: kPagePadding),
                      Text("Forwarding to (number)"),
                      SizedBox(height: kPagePadding / 3),
                      TextField(
                        controller: _numberToForwardToTextController,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(kBorderRadius),
                          ),
                        ),
                      ),
                      SizedBox(height: kPagePadding),
                      Text("Using SIM"),
                      SizedBox(height: kPagePadding / 3),
                      Row(
                        children: sims.map((s) {
                          return InkWell(
                            onTap: () {
                              setState(() {
                                _dialSim = s.simSlotIndex ?? -1;
                              });
                            },
                            child: Padding(
                              padding: EdgeInsets.only(right: kPagePadding / 2),
                              child: Column(
                                children: [
                                  Text(
                                    s.displayName ?? 'SIM',
                                    style: TextStyle(
                                      color: s.simSlotIndex == _dialSim
                                          ? kPrimaryColor
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(height: kPagePadding / 2),
                                  Icon(
                                    Icons.sim_card_rounded,
                                    size: 40,
                                    color: s.simSlotIndex == _dialSim
                                        ? kPrimaryColor
                                        : kGrayColor,
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                if (_amountsToForwardTextController.text.isNotEmpty) {
                  _amountsToForward
                      .add(int.parse(_amountsToForwardTextController.text));
                }

                if (_amountsToForward.isEmpty ||
                    _numberToForwardToTextController.text.isEmpty ||
                    _dialSim < 0) {
                  setState(() {
                    _error = "Fill in all the fields";
                    setState(() {});
                    // //print(_error);
                  });
                  return;
                }

                showLoadingDialog(context);
                if (id > -1) {
                  await _sqliteService.updateStuff(
                    {
                      'dialSim': _dialSim,
                      'numberToReceive': extract9DigitNumber(
                          _numberToForwardToTextController.text),
                      'amounts': jsonEncode(_amountsToForward),
                      'isActive': 1,
                    },
                    'id = ?',
                    [id],
                    'forwarded',
                  );
                } else {
                  await _addToForwardedDB();
                }
                Navigator.pop(context);
                Navigator.pop(context);
                showSuccessDialog(context,
                    text:
                        "Done.\n\nBe sure to whitelist your number on the other phone.");
                _getData();
              },
              child: Text("Save"),
            ),
          ],
        );
      },
    );
  }
}
