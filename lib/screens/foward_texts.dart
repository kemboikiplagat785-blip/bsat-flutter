import 'dart:convert';

import 'package:bsat/components/dialogs/confirm_dialog.dart';
import 'package:bsat/components/dialogs/loading_dialog.dart';
import 'package:bsat/services/sms_sevice.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:sim_data/sim_data.dart';

import '../components/chip_input_field.dart';
import '../components/header.dart';
import '../services/sqlite_service.dart';
import '../utils/constants.dart';

class ForwardTextsPage extends StatefulWidget {
  const ForwardTextsPage({super.key});

  @override
  State<ForwardTextsPage> createState() => _ForwardTextsPageState();
}

class _ForwardTextsPageState extends State<ForwardTextsPage> {
  var _sqliteService = SQLiteService();

  var _amountsToForwardTextController = TextEditingController();
  var _whitelistedNumberTextController = TextEditingController();
  var _numberToForwardToTextController = TextEditingController();

  List<int> _whitelistedNumbers = [];
  List<int> _amountsToForward = [];

  List<SimCard> sims = [];

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

  void getAndProcessCards() async {
    await SimDataPlugin.getSimData().then((value) {
      setState(() {
        sims = value.cards;
      });
      // debugPrint("Got cards");
    });
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
    print("Forwards: $_forwards");
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
                              return Padding(
                                padding:
                                    const EdgeInsets.only(bottom: kPagePadding),
                                child: Container(
                                  padding: kPagePaddingInsets,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).cardColor,
                                    borderRadius: BorderRadius.circular(
                                        kBorderRadius / 2),
                                  ),
                                  child: Column(
                                    // mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              "Amounts: ${jsonDecode(forward['amounts'])}",
                                              overflow: TextOverflow.ellipsis,
                                              softWrap: true,
                                              maxLines: 3,
                                              // style: textTheme.caption,
                                            ),
                                          ),
                                          InkWell(
                                            onTap: () async {
                                              // _amountsToForward =
                                              //     jsonDecode(forward['amounts']);
                                              // _forwards.remove(forward);
                                              await showForwardingDialog(
                                                context,
                                                id: forward['id'],
                                              );
                                              _getData();
                                            },
                                            child: Icon(
                                              Icons.edit,
                                              color: kPrimaryColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: kPagePadding / 2),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'Forwarding to: ${forward['numberToReceive']}',
                                            // style: textTheme.headline6,
                                          ),
                                          GestureDetector(
                                            onTap: () async {
                                              bool delete =
                                                  await showConfirmDialog(
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
                                            child: Icon(
                                              Icons.delete,
                                              color: kErrorColor,
                                            ),
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
                            print(_amountsToForward);
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
                                _dialSim = s.slotIndex;
                              });
                            },
                            child: Padding(
                              padding: EdgeInsets.only(right: kPagePadding / 2),
                              child: Column(
                                children: [
                                  Text(
                                    s.displayName,
                                    style: TextStyle(
                                      color: s.slotIndex == _dialSim
                                          ? kPrimaryColor
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(height: kPagePadding / 2),
                                  Icon(
                                    Icons.sim_card_rounded,
                                    size: 40,
                                    color: s.slotIndex == _dialSim
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
                    // print(_error);
                  });
                  return;
                }

                if (id > -1) {
                  showLoadingDialog(context);
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
                  Navigator.pop(context);
                } else {
                  await _addToForwardedDB();
                }
                Navigator.pop(context);
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
