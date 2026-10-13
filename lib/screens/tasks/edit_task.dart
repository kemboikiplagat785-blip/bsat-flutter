import 'package:bsat/components/dialogs/delete_ussd_dialog.dart';
import 'package:bsat/components/dialogs/show_error_dialog.dart';
import 'package:bsat/components/dialogs/success_dialog.dart';
import 'package:bsat/components/header.dart';
import 'package:bsat/controllers/transaction_controller.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:another_telephony/telephony.dart';

import '../../utils/date_ops.dart';
import '../../utils/offer_time_window.dart';

class EditTaskPage extends StatefulWidget {
  final int taskId;

  final int? number;
  final int? dialSim;
  final String? offer;
  final int? amount;

  const EditTaskPage({
    required this.taskId,
    super.key,
    this.number,
    this.dialSim,
    this.offer,
    this.amount,
  });

  @override
  State<EditTaskPage> createState() => _EditTaskPageState();
}

class _EditTaskPageState extends State<EditTaskPage> {
  final _sqliteService = SQLiteService();

  final _numberTextController = TextEditingController();
  final _durationTextController = TextEditingController();

  bool _deleteAfterRunning = false;

  int nextTaskDate = 0;

  int _dialSim = -1;

  List<SubscriptionInfo> sims = [];

  List myOffers = [];

  String? _selectedItem;
  int? _selectedOfferId;
  int? _selectedVariantId;

  String _selectedOffer = "";
  int _selectedAmount = 0;

  var _selectedDate = DateTime.now()
      .add(const Duration(days: 1))
      .copyWith(hour: 0, minute: 0, second: 0, millisecond: 0, microsecond: 0);
  String date = "";

  void _getAndProcessCards() async {
    await Telephony.instance.getSubscriptionList().then((value) {
      setState(() {
        sims = value;
      });
      // debugPrint("Got cards");
    });
  }

  Future<void> _selectDate(BuildContext context) async {
    await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2015, 8),
      lastDate: DateTime(2101),
    ).then((value) {
      setState(() {
        _selectedDate = value ?? _selectedDate;
        date = getNormalDate(_selectedDate);
      });
      return null;
    });
    // debugPrint("changed date");
  }

  Future<void> _showTimePicker(BuildContext context) async {
    await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDate),
    ).then((value) {
      setState(() {
        _selectedDate = DateTime(
          _selectedDate.year,
          _selectedDate.month,
          _selectedDate.day,
          value!.hour,
          value.minute,
        );
        date = getNormalDate(_selectedDate);
      });
    });
  }

  Future<void> _getMyOffers() async {
    final rows = await _sqliteService.rawQueryInput('''
      SELECT u.id AS offerId, v.id AS variantId, u.amount, v.code,
        v.startTime, v.endTime, u.dialSim
      FROM ussdCodes u
      JOIN ussdCodeVariants v ON u.id = v.ussdCodeId
      WHERE u.amount IS NOT NULL
        AND v.code IS NOT NULL AND TRIM(v.code) != ''
      ORDER BY u.amount, v.startTime, v.code
    ''', []);
    if (!mounted) return;
    setState(() {
      myOffers = rows;
      _matchSelectedOffer();
    });
  }

  void _matchSelectedOffer() {
    if (myOffers.isEmpty) return;
    if (_selectedVariantId != null) {
      final selectedVariant = myOffers
          .cast<Map<String, dynamic>>()
          .where((offer) =>
              int.tryParse(offer['variantId']?.toString() ?? '') ==
              _selectedVariantId)
          .firstOrNull;
      if (selectedVariant != null) {
        _selectedOfferId = int.tryParse(selectedVariant['offerId'].toString());
        _selectedItem = _selectedVariantId.toString();
        return;
      }
      _selectedVariantId = null;
      _selectedOfferId = null;
      _selectedItem = null;
    }
    final normalizedCode =
        TransactionController().getCodeFromUssd(_selectedOffer);
    final match = myOffers.cast<Map<String, dynamic>>().where((offer) {
      final amount = int.tryParse(offer['amount']?.toString() ?? '');
      return amount == _selectedAmount &&
          TransactionController().getCodeFromUssd(
                offer['code']?.toString() ?? '',
              ) ==
              normalizedCode;
    }).firstOrNull;
    if (match != null) {
      _selectedOfferId = int.tryParse(match['offerId'].toString());
      _selectedVariantId = int.tryParse(match['variantId'].toString());
      _selectedItem = _selectedVariantId.toString();
    }
  }

  Future<bool> _checkAndSave() async {
    await _sqliteService.addColumnIfNotExists('tasks', 'offer', 'TEXT');
    await _sqliteService.addColumnIfNotExists('tasks', 'number', 'INTEGER');
    await _sqliteService.addColumnIfNotExists('tasks', 'amount', 'INTEGER');
    await _sqliteService.addColumnIfNotExists(
        'tasks', 'deleteAfterRunning', 'INTEGER');

    if (_dialSim < 0 ||
        _selectedOfferId == null ||
        _selectedVariantId == null ||
        _numberTextController.text.isEmpty ||
        _durationTextController.text.isEmpty) {
      return false;
    }

    if (widget.taskId >= 0) {
      int value = await _sqliteService.updateStuff(
        {
          'id': widget.taskId,
          'code': _selectedOffer.replaceAll(
              RegExp(r'n'), _numberTextController.text),
          'dialSim': _dialSim,
          'duration': int.parse(_durationTextController.text),
          'startDate': _selectedDate.millisecondsSinceEpoch,
          'timeOfDay': getNormalTime(_selectedDate),
          'nextTaskDate': _selectedDate.millisecondsSinceEpoch,
          'offer': _selectedOffer,
          'offerId': _selectedOfferId,
          'offerVariantId': _selectedVariantId,
          'amount': _selectedAmount,
          'number': int.parse(_numberTextController.text),
          'deleteAfterRunning': _deleteAfterRunning ? 1 : 0,
        },
        'id = ?',
        [widget.taskId],
        'tasks',
      );
      return value >= 0;
    } else {
      int value = await _sqliteService.insertStuff(
        {
          'code': _selectedOffer.replaceAll(
              RegExp(r'n'), _numberTextController.text),
          'dialSim': _dialSim,
          'duration': int.parse(_durationTextController.text),
          'startDate': _selectedDate.millisecondsSinceEpoch,
          'timeOfDay': getNormalTime(_selectedDate),
          'nextTaskDate': _selectedDate.millisecondsSinceEpoch,
          'offer': _selectedOffer,
          'offerId': _selectedOfferId,
          'offerVariantId': _selectedVariantId,
          'amount': _selectedAmount,
          'number': int.parse(_numberTextController.text),
          'deleteAfterRunning': _deleteAfterRunning ? 1 : 0,
        },
        'tasks',
      );
      return value >= 0;
      // return true;
    }
  }

  void _populateFields() async {
    if (widget.taskId >= 0) {
      _sqliteService.queryCustom(
        'tasks',
        'id = ?',
        [widget.taskId],
      ).then((value) {
        _numberTextController.text = "0${value[0]['number']}";
        _durationTextController.text = value[0]['duration'].toString();
        _dialSim = value[0]['dialSim'];
        nextTaskDate = value[0]['nextTaskDate'];
        _selectedDate = toDateTime(
          getNormalDate(
              DateTime.fromMillisecondsSinceEpoch(value[0]['startDate'])),
          getNormalTime(
              DateTime.fromMillisecondsSinceEpoch(value[0]['startDate'])),
          delim: "/",
        );
        date = getNormalDate(_selectedDate);
        _selectedOffer = value[0]['offer'] ?? "";
        _selectedAmount = value[0]['amount'] ?? 0;
        _selectedOfferId = int.tryParse(value[0]['offerId']?.toString() ?? '');
        _selectedVariantId =
            int.tryParse(value[0]['offerVariantId']?.toString() ?? '');
        _selectedItem = _selectedVariantId?.toString();
        _matchSelectedOffer();
        _deleteAfterRunning = value[0]['deleteAfterRunning'] == 1;
        setState(() {});
      });
    } else if (widget.taskId == -2) {
      _numberTextController.text = "0${widget.number.toString()}";
      _dialSim = widget.dialSim ?? sims[0].subscriptionId ?? -1;
      _durationTextController.text = "1";
      _selectedDate =
          DateTime.fromMillisecondsSinceEpoch(getTodayMidnightMillis()).add(
        const Duration(days: 1),
      );
      _selectedOffer = widget.offer ?? '';
      _selectedItem = null;
      _selectedAmount = widget.amount ?? 0;
      _matchSelectedOffer();
      _deleteAfterRunning = true;

      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    date = getNormalDate(_selectedDate);
    _populateFields();
    _getAndProcessCards();

    _getMyOffers();

    Permission.scheduleExactAlarm.request();
  }

  @override
  Widget build(BuildContext context) {
    // Permission.scheduleExactAlarm.st
    return SafeArea(
      child: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header(context, 'Edit Task'),
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
                      const Text(
                        'Offer',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: kPagePadding / 2),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedItem,
                        items:
                            myOffers.cast<Map<String, dynamic>>().map((offer) {
                          return DropdownMenuItem<String>(
                            value: offer['variantId'].toString(),
                            child: Text(
                              formatTaskOfferLabel(
                                amount: offer['amount'],
                                code: offer['code'],
                                startTime: offer['startTime'],
                                endTime: offer['endTime'],
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          final selected = myOffers
                              .cast<Map<String, dynamic>>()
                              .where((offer) =>
                                  offer['variantId'].toString() == value)
                              .firstOrNull;
                          if (selected == null) return;
                          setState(() {
                            _selectedItem = value;
                            _selectedOfferId =
                                int.tryParse(selected['offerId'].toString());
                            _selectedVariantId =
                                int.tryParse(selected['variantId'].toString());
                            _selectedAmount = int.tryParse(
                                  selected['amount']?.toString() ?? '',
                                ) ??
                                0;
                            _selectedOffer = selected['code'].toString();

                            if (_dialSim < 0) {
                              _dialSim = int.tryParse(
                                    selected['dialSim']?.toString() ?? '',
                                  ) ??
                                  -1;

                              debugPrint("Dial SIM set to $_dialSim");
                            }
                          });
                        },
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(kBorderRadius),
                          ),
                        ),
                      ),
                      const SizedBox(height: kPagePadding),
                      const Text(
                        'Number',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: kPagePadding / 2),
                      SizedBox(
                        child: TextField(
                          // keyboardType: TextInputType.number,
                          controller: _numberTextController,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(kBorderRadius),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: kPagePadding),
                      const Text(
                        'On SIM',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: kPagePadding / 2),
                      Row(
                        children: sims.map((s) {
                          return InkWell(
                            onTap: () {
                              final subscriptionId = s.subscriptionId;
                              if (subscriptionId != null) {
                                setState(() {
                                  _dialSim = subscriptionId;
                                });
                              }
                              // mustUseBothSimsDialog(context);
                            },
                            child: Padding(
                              padding: const EdgeInsets.only(
                                  right: kPagePadding / 2),
                              child: Column(
                                children: [
                                  Text(
                                    s.displayName ?? 'SIM',
                                    style: TextStyle(
                                      color: s.subscriptionId == _dialSim
                                          ? kPrimaryColor
                                          : kDullColor,
                                    ),
                                  ),
                                  const SizedBox(height: kPagePadding / 2),
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
                      const SizedBox(height: kPagePadding),
                      const Text(
                        'Starting on',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: kPagePadding / 2),
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () async {
                              await _selectDate(context);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(kPagePadding / 4),
                              decoration: BoxDecoration(
                                color: kPrimaryColorLight,
                                borderRadius:
                                    BorderRadius.circular(kBorderRadius),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    date,
                                    // style: textTheme.labelSmall,
                                  ),
                                  const SizedBox(width: 3),
                                  const Icon(
                                    CupertinoIcons.chevron_compact_down,
                                    color: kPrimaryColor,
                                    size: 14,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: kPagePadding / 2),
                          GestureDetector(
                            onTap: () async {
                              await _showTimePicker(context);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(kPagePadding / 4),
                              decoration: BoxDecoration(
                                color: kPrimaryColorLight,
                                borderRadius:
                                    BorderRadius.circular(kBorderRadius),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    getNormalTime(_selectedDate),
                                    // style: textTheme.labelSmall,
                                  ),
                                  const SizedBox(width: 3),
                                  const Icon(
                                    CupertinoIcons.chevron_compact_down,
                                    color: kPrimaryColor,
                                    size: 14,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: kPagePadding),
                      const Text(
                        'Repeat for (number of days)',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: kPagePadding / 2),
                      SizedBox(
                        child: TextField(
                          keyboardType: TextInputType.number,
                          controller: _durationTextController,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(kBorderRadius),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: kPagePadding),
                      const Text('Delete this task after it runs'),
                      CheckboxListTile(
                        value: _deleteAfterRunning,
                        onChanged: (value) {
                          setState(() {
                            _deleteAfterRunning = value!;
                          });
                        },
                        title: const Text('Delete after running'),
                      ),
                      const SizedBox(height: kPagePadding),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: kPagePadding),
              // Spacer(),
              Padding(
                padding: kPagePaddingInsets,
                child: Flex(
                  mainAxisAlignment: MainAxisAlignment.end,
                  direction: Axis.horizontal,
                  children: [
                    widget.taskId >= 0
                        ? Flexible(
                            child: IconButton(
                              onPressed: () {
                                deleteUssdDialog(
                                        context, widget.taskId, 'tasks')
                                    .then(
                                  (value) {
                                    Navigator.pop(context);
                                  },
                                );
                              },
                              icon: const Icon(Icons.delete_forever),
                            ),
                          )
                        : Container(),
                    const SizedBox(width: kPagePadding),
                    Flexible(
                      flex: 3,
                      child: TextButton(
                        onPressed: () async {
                          await _checkAndSave().then((value) {
                            // debugPrint('$value');
                            if (value) {
                              showSuccessDialog(context,
                                      text: 'Saved Sucessfully')
                                  .then(
                                (value) => Navigator.pop(context),
                              );
                            } else {
                              showErrorDialog(
                                context,
                                'Error',
                                'Check if all fields are filled',
                              );
                            }
                          });
                        },
                        child: const Text('Save'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
