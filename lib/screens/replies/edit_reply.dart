import 'dart:convert';

import 'package:bsat/components/header.dart';
import 'package:bsat/screens/messaging/whatsapp_screen.dart';
import 'package:bsat/utils/constants.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:another_telephony/telephony.dart';

import '../../services/sqlite_service.dart';

class EditReplyPage extends StatefulWidget {
  final int replyId;

  const EditReplyPage({super.key, required this.replyId});

  @override
  State<EditReplyPage> createState() => _EditReplyPageState();
}

class _EditReplyPageState extends State<EditReplyPage> {
  final TextEditingController _replyTextController = TextEditingController();
  final TextEditingController _amountTextController = TextEditingController();

  final _sqliteService = SQLiteService();

  int _dialSim = -1;

  List<SubscriptionInfo> sims = [];
  List<int> _amountsForReply = [];

  int _characterCount = 0;

  // Radio button selection states
  int _selectedOption = 0;
  String _errorReply = '';

  void _populateFields() async {
    if (widget.replyId >= 0) {
      // Assuming you have a service to query the database
      var replyData = await _sqliteService.queryCustom(
        'replies',
        'id = ?',
        [widget.replyId],
      );

      if (replyData.isNotEmpty) {
        setState(() {
          _amountsForReply =
              List<int>.from(jsonDecode(replyData[0]['amounts'] ?? '[]'));
          _replyTextController.text = replyData[0]['reply'].toString();
          // _amountTextController.text =
          //     replyData[0]['conditionAmount'].toString();
          _selectedOption = replyData[0]['condition'];
          _dialSim = replyData[0]['dialSim'];
        });
      }
    }
  }

  void _processAmountForReply() {
    setState(() {
      _amountsForReply.add(int.parse(_amountTextController.text.trim()));
      _amountTextController.clear();
    });
  }

  Future<bool> _checkAndSave() async {
    if (_replyTextController.text.isEmpty) {
      setState(() {
        _errorReply = ' *Reply required';
      });
      return false;
    }
    if (_dialSim == -1) {
      setState(() {
        _errorReply = ' *Sim card required';
      });
      return false;
    }

    Map<String, dynamic> data = {
      'reply': _replyTextController.text,
      'condition': _selectedOption,
      'dialSim': _dialSim,
      'conditionAmount': 1,
      'amounts': jsonEncode(_amountsForReply),
    };

    if (widget.replyId >= 0) {
      int value = await _sqliteService.updateStuff(
        data,
        'id = ?',
        [widget.replyId],
        'replies',
      );
      return value >= 0;
    } else {
      int value = await _sqliteService.insertStuff(
        data,
        'replies',
      );
      return value >= 0;
    }
  }

  void _getAndProcessCards() async {
    await Telephony.instance.getSubscriptionList().then((value) {
      setState(() {
        sims = value;
      });
      // debugPrint("Got cards");
    });
  }

  void updateDB() async {
    await _sqliteService.addColumnIfNotExists('replies', 'amounts', 'TEXT');
  }

  @override
  void initState() {
    super.initState();
    updateDB();
    _getAndProcessCards();
    _populateFields();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            header(context, "Edit Reply"),
            SingleChildScrollView(
              child: Padding(
                padding: kPagePaddingInsets,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: kPagePadding),
                    // Radio buttons
                    Container(
                      padding: kPagePaddingInsets,
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(kBorderRadius),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Trigger condition',
                          ),
                          RadioListTile(
                            title: const Text(
                                'On successful purchase (message confirmed)'),
                            // leading: Radio<int>(
                            value:
                                TransactionStatuses.doneConfirmedMap.keys.first,
                            groupValue: _selectedOption,
                            onChanged: (int? value) {
                              setState(() {
                                _selectedOption = value!;
                              });
                            },
                            // ),
                          ),
                          RadioListTile(
                            title: const Text('On pending purchase'),
                            // leading: Radio<int>(
                            value: TransactionStatuses.doneMap.keys.first,
                            groupValue: _selectedOption,
                            onChanged: (int? value) {
                              setState(() {
                                _selectedOption = value!;
                              });
                            },
                            // ),
                          ),

                          RadioListTile(
                            title: const Text('On Safaricom system error'),
                            // leading: Radio<int>(
                            value: TransactionStatuses.errorMap.keys.first,
                            groupValue: _selectedOption,
                            onChanged: (int? value) {
                              setState(() {
                                _selectedOption = value!;
                              });
                            },
                            // ),
                          ),
                          RadioListTile(
                            title: const Text('On second purchase attempt'),
                            value:
                                TransactionStatuses.secondAttemptMap.keys.first,
                            groupValue: _selectedOption,
                            onChanged: (int? value) {
                              setState(() {
                                _selectedOption = value!;
                              });
                            },
                          ),
                          // ),
                          RadioListTile(
                            title: const Text('On unavailable offer'),
                            // tileColor: Theme.of(context).colorScheme.primary,

                            // leading: Radio<int>(
                            value: TransactionStatuses
                                .unavailableOfferMap.keys.first,
                            groupValue: _selectedOption,
                            onChanged: (int? value) {
                              setState(() {
                                _selectedOption = value!;
                              });
                            },
                            // ),
                          ),
                          RadioListTile(
                            title: const Text('Blacklisted number'),
                            // leading: Radio<int>(
                            value:
                                TransactionStatuses.blacklistedMap.keys.first,
                            groupValue: _selectedOption,
                            onChanged: (int? value) {
                              setState(() {
                                _selectedOption = value!;
                              });
                            },
                          ),
                          RadioListTile(
                            title: const Text('App paused'),
                            // leading: Radio<int>(
                            value: TransactionStatuses.pausedMap.keys.first,
                            groupValue: _selectedOption,
                            onChanged: (int? value) {
                              setState(() {
                                _selectedOption = value!;
                              });
                            },
                          ),
                          RadioListTile(
                            title: const Text('Advanced'),
                            // leading: Radio<int>(
                            value:
                                TransactionStatuses.advancedUssdMap.keys.first,
                            groupValue: _selectedOption,
                            onChanged: (int? value) {
                              setState(() {
                                _selectedOption = value!;
                              });
                            },
                          ),
                          RadioListTile(
                            title: const Text('Has Okoa'),
                            // leading: Radio<int>(
                            value: TransactionStatuses.hasOkoaMap.keys.first,
                            groupValue: _selectedOption,
                            onChanged: (int? value) {
                              setState(() {
                                _selectedOption = value!;
                              });
                            },
                          ),
                          RadioListTile(
                            title: const Text('Forwarded'),
                            // leading: Radio<int>(
                            value: TransactionStatuses.forwardedMap.keys.first,
                            groupValue: _selectedOption,
                            onChanged: (int? value) {
                              setState(() {
                                _selectedOption = value!;
                              });
                            },
                          ),
                          RadioListTile(
                            title: const Text('Forwarded (online)'),
                            // leading: Radio<int>(
                            value: TransactionStatuses
                                .forwardedOnlineMap.keys.first,
                            groupValue: _selectedOption,
                            onChanged: (int? value) {
                              setState(() {
                                _selectedOption = value!;
                              });
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: kPagePadding),

                    Container(
                      padding: kPagePaddingInsets,
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(kBorderRadius),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Amount condition (optional):'),
                          if (_amountsForReply.isNotEmpty)
                            Wrap(
                              spacing: 8.0,
                              children: _amountsForReply.map((amount) {
                                return Chip(
                                  backgroundColor: Theme.of(context).cardColor,
                                  label: Text(amount.toString()),
                                  deleteIcon: const Icon(Icons.close),
                                  onDeleted: () {
                                    setState(() {
                                      _amountsForReply.remove(amount);
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                          const SizedBox(height: kPagePadding / 2),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _amountTextController,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    hintText: 'Enter amount',
                                    border: const OutlineInputBorder(),
                                  ),
                                  onSubmitted: (value) {
                                    setState(() {
                                      _processAmountForReply();
                                    });
                                  },
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add),
                                onPressed: () {
                                  if (_amountTextController.text.isNotEmpty) {
                                    _processAmountForReply();
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: kPagePadding / 2),
                        ],
                      ),
                    ),

                    const SizedBox(height: kPagePadding),

                    Container(
                      padding: kPagePaddingInsets,
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(kBorderRadius),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Reply:'),
                          const SizedBox(height: kPagePadding / 2),
                          TextField(
                            controller: _replyTextController,
                            decoration: InputDecoration(
                              hintText: 'Enter your reply',
                              errorText:
                                  _errorReply.isEmpty ? null : _errorReply,
                              border: const OutlineInputBorder(),
                            ),
                            onChanged: (value) {
                              setState(() {
                                _characterCount = value.length;
                              });
                            },
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                "$_characterCount/160",
                                style: TextStyle(fontWeight: FontWeight.w100),
                              ),
                            ],
                          ),
                          const SizedBox(height: kPagePadding / 2),
                          Text(
                            '''Use: 
                              \n \t$interpunct grti? - greeting (Good morning, Good afternoon, ...)
                              \n \t$interpunct numb? - customer's number 
                              \n \t$interpunct fnam? - customer's first name 
                              \n \t$interpunct lnam? - customer's last name 
                              \n \t$interpunct amnt? - amount received
                              \n \t$interpunct date? - date today
                              \n \t$interpunct time? - time now
                              \n \t$interpunct dayw? - day of the week \n
                              \n For example: "Hello fnam? lnam?, there's no offer for Ksh amnt?.
                            ''',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: kPagePadding / 2),
                    Container(
                      padding: kPagePaddingInsets,
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(kBorderRadius),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Using',
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: sims.map((s) {
                                  return InkWell(
                                    onTap: () {
                                      setState(() {
                                        _dialSim = s.subscriptionId ?? -1;
                                      });
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                          right: kPagePadding / 2),
                                      child: Column(
                                        children: [
                                          Text(
                                            s.displayName ?? 'SIM',
                                            style: TextStyle(
                                              color:
                                                  s.subscriptionId == _dialSim
                                                      ? kPrimaryColor
                                                      : null,
                                            ),
                                          ),
                                          const SizedBox(
                                              height: kPagePadding / 2),
                                          Icon(
                                            Icons.sim_card_rounded,
                                            size: 40,
                                            color: s.subscriptionId == _dialSim
                                                ? kPrimaryColor
                                                : kGrayColor,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                              GestureDetector(
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) => WhatsappScreen(),
                                    ),
                                  );
                                },
                                child: Image.asset(
                                  "assets/icons/whatsapp.png",
                                  width: 40,
                                  height: 40,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Save button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () {
                            _checkAndSave().then((value) {
                              if (value) {
                                Navigator.pop(context);
                                Navigator.pop(context);
                              }
                            });
                          },
                          child: const Text('Save'),
                        ),
                      ],
                    ),
                    const SizedBox(height: kPagePadding * 2),
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
