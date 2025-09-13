import 'package:bsat/components/dialogs/delete_ussd_dialog.dart';
import 'package:bsat/components/dialogs/make_offer_tutorial_dialog.dart';
import 'package:bsat/components/dialogs/show_error_dialog.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_accessibility_service/flutter_accessibility_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sim_data/sim_data.dart';

import '../../components/dialogs/accessibility_permission.dart';
import '../../services/sqlite_service.dart';
import '../../utils/constants.dart';

class EditOfferPage extends StatefulWidget {
  final int ruleId;

  const EditOfferPage({
    super.key,
    this.ruleId = -1,
  });

  @override
  State<EditOfferPage> createState() => _EditOfferPageState();
}

class _EditOfferPageState extends State<EditOfferPage> {
  final TextEditingController _amountTextController = TextEditingController();
  final TextEditingController _codeTextController = TextEditingController();

  final _sqliteService = SQLiteService();

  List sims = [];

  int _fromSim = -1;
  int _dialSim = -1;

  String _errorAmount = '';
  String _errorUSSDCode = '';
  String _errorUSSDSyntax = '';
  String _errorDialSim = '';
  String _errorFromSim = '';

  bool isAdvanced = false;

  bool _fromBothSims = true;
  bool _canRetry = false;

  List allOptions = [];

  Map thisData = {};

  void getAndProcessCards() async {
    await SimDataPlugin.getSimData().then((value) {
      setState(() {
        sims = value.cards;
      });
      // debugPrint("Got cards");
    });
  }

  Future<bool> checkAccessibilityPermission() async {
    final status =
        await FlutterAccessibilityService.isAccessibilityPermissionEnabled();

    if (status) {
      debugPrint("Accessibility permission is granted.");
      return true;
    } else {
      return await FlutterAccessibilityService.requestAccessibilityPermission();
    }
  }

  Future<bool> checkForErrorsAndProceed() async {
    if (_amountTextController.text == '') {
      setState(() {
        _errorAmount = " *Required";
      });
      return false;
    } else {
      setState(() {
        _errorAmount = "";
      });
    }
    if (_fromSim < 0 && !_fromBothSims) {
      setState(() {
        _errorFromSim = " *Select one";
      });
      return false;
    } else {
      setState(() {
        _errorFromSim = "";
      });
    }
    if (_codeTextController.text == '') {
      setState(() {
        _errorUSSDCode = " *Required";
      });
      return false;
    } else {
      setState(() {
        _errorUSSDCode = "";
      });
    }
    if (ussdSyntaxHaasError()) {
      setState(() {
        _errorUSSDSyntax = " Code has error";
      });
      return false;
    } else {
      setState(() {
        _errorUSSDSyntax = "";
      });
    }

    if (_dialSim < 0) {
      setState(() {
        _errorDialSim = " *Select one";
      });
      return false;
    } else {
      setState(() {
        _errorDialSim = "";
      });
    }
    addCodeToDatabase(
      _codeTextController.text,
      int.parse(_amountTextController.text),
    );
    return true;
  }

  void addCodeToDatabase(String code, int amount) async {
    if (widget.ruleId > 0) {
      await _sqliteService.updateStuff(
        {
          'id': widget.ruleId,
          'amount': amount,
          'code': code,
          'fromSim': _fromSim,
          'dialSim': _dialSim,
          'canRetry': _canRetry ? 1 : 0,
          'isAdvanced': isAdvanced ? 1 : 0,
        },
        'id = ?',
        [widget.ruleId],
        'ussdCodes',
      );

      return;
    }
    _sqliteService.insertStuff(
      {
        'amount': amount,
        'code': code,
        'fromSim': -1,
        'dialSim': _dialSim,
        'canRetry': _canRetry ? 1 : 0,
        'isAdvanced': isAdvanced ? 1 : 0,
        'enabled': 1,
      },
      'ussdCodes',
    ).then((value) {
      _codeTextController.clear();
      _amountTextController.clear();
    });
  }

  bool ussdSyntaxHaasError() {
    RegExp regex = RegExp(r'[^0-9*n#]');

    return regex.hasMatch(_codeTextController.text);
  }

  void processData() {
    _sqliteService.queryCustom(
      'ussdCodes',
      'id = ?',
      [widget.ruleId],
    ).then((value) {
      _amountTextController.text = value[0]['amount'].toString();
      _codeTextController.text = value[0]['code'];
      _fromSim = value[0]['fromSim'];
      _dialSim = value[0]['dialSim'];
      _canRetry = value[0]['canRetry'] == 1;
      isAdvanced = (value[0]['isAdvanced'] != null)
          ? value[0]['isAdvanced'] == 1
          : false;

      _fromBothSims = _fromSim < 0 ? true : false;
    });
  }

  @override
  void initState() {
    super.initState();

    getAndProcessCards();

    if (widget.ruleId >= 0) {
      processData();
    }
  }

  @override
  Widget build(BuildContext context) {
    var textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(context, textTheme),
            Padding(
              padding: kPagePaddingInsets,
              child: Column(
                // mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'When I receive',
                    style: textTheme.titleSmall!.merge(kTitleText),
                  ),
                  const SizedBox(height: kPagePadding / 2),
                  Container(
                    padding: kPagePaddingInsets,
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(kBorderRadius),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Ksh',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              _errorAmount,
                              style: const TextStyle(color: kErrorColor),
                            ),
                          ],
                        ),
                        const SizedBox(height: kPagePadding / 2),
                        SizedBox(
                          // width: 70,
                          // height: kInputElementHeight + kPagePadding * 2,
                          child: TextField(
                            keyboardType: TextInputType.number,
                            controller: _amountTextController,
                            decoration: InputDecoration(
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(kBorderRadius),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: kPagePadding),
                        Row(
                          children: [
                            const Text(
                              'In SIM',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              _errorFromSim,
                              style: textTheme.labelMedium!.merge(
                                const TextStyle(color: kErrorColor),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: kPagePadding / 2),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Column(
                              children: [
                                Row(
                                  children: sims.map((s) {
                                    return InkWell(
                                      onTap: () {
                                        setState(() {
                                          _fromBothSims = true;
                                          // _fromSim = s.subscriptionId;
                                        });
                                        // mustUseBothSimsDialog(context);
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                            right: kPagePadding / 2),
                                        child: Column(
                                          children: [
                                            Text(
                                              s.displayName,
                                              style: TextStyle(
                                                color:
                                                    s.subscriptionId == _fromSim
                                                        ? kPrimaryColor
                                                        : null,
                                              ),
                                            ),
                                            const SizedBox(
                                                height: kPagePadding / 2),
                                            Icon(
                                              Icons.sim_card_rounded,
                                              size: 40,
                                              color:
                                                  s.subscriptionId == _fromSim
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
                            Column(
                              children: [
                                const Text(
                                  'Both',
                                  style: TextStyle(color: kDullColor),
                                ),
                                Checkbox(
                                  activeColor: kPrimaryColor,
                                  value: _fromBothSims,
                                  onChanged: (value) {
                                    setState(() {
                                      _fromBothSims = true;
                                      _fromSim = -1;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: kPagePadding),
                  Text(
                    'Dial',
                    style: textTheme.titleSmall!.merge(kTitleText),
                  ),
                  const SizedBox(height: kPagePadding / 2),
                  Container(
                    padding: kPagePaddingInsets,
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(kBorderRadius),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Text(
                              'USSD Code',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              _errorUSSDCode,
                              style: textTheme.labelMedium!.merge(
                                const TextStyle(color: kErrorColor),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: kPagePadding / 2),
                        SizedBox(
                          // width: 70,
                          // height: kInputElementHeight + kPagePadding * 2,
                          child: TextField(
                            controller: _codeTextController,
                            decoration: InputDecoration(
                              hintText: '*180*5*2*n*6*1#',
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(kBorderRadius),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: kPagePadding / 4),
                        Row(
                          children: [
                            Text(
                              '** Use \'n\' for number.',
                              style: textTheme.labelMedium,
                            ),
                            Text(
                              _errorUSSDSyntax,
                              style: textTheme.labelMedium!.merge(
                                const TextStyle(color: kErrorColor),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: kPagePadding / 2),
                        CheckboxListTile(
                          value: isAdvanced,
                          onChanged: (val) async {
                            if (val!) {
                              showAccessibilityPermissionDialog(context);
                            }
                            setState(() {
                              isAdvanced = val;
                            });
                          },
                          title: Text('Advanced USSD'),
                        ),
                        const SizedBox(height: kPagePadding),
                        Row(
                          children: [
                            const Text(
                              'On SIM',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              _errorDialSim,
                              style: const TextStyle(color: kErrorColor),
                            ),
                          ],
                        ),
                        const SizedBox(height: kPagePadding / 2),
                        Row(
                          children: sims.map((s) {
                            return InkWell(
                              onTap: () {
                                setState(() {
                                  _dialSim = s.subscriptionId;
                                });
                              },
                              child: Padding(
                                padding: const EdgeInsets.only(
                                    right: kPagePadding / 2),
                                child: Column(
                                  children: [
                                    Text(
                                      s.displayName,
                                      style: TextStyle(
                                        color: s.subscriptionId == _dialSim
                                            ? kPrimaryColor
                                            : null,
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
                        CheckboxListTile(
                          activeColor: kPrimaryColor,
                          value: _canRetry,
                          title: Text(
                              'Automatically retry after error (Not recommended for SMS)'),
                          onChanged: (value) {
                            setState(() {
                              _canRetry = !_canRetry;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: kPagePadding),
                  // Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          // checkForErrorsAndProceed();
                          makeOfferTutorialDialog(context);
                        },
                        child: const Text(
                          'Help',
                          style: TextStyle(color: kErrorColor),
                        ),
                      ),
                      const SizedBox(width: kPagePadding),
                      TextButton(
                        onPressed: () {
                          checkForErrorsAndProceed().then(
                            (value) => value ? Navigator.pop(context) : value,
                          );
                        },
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Container _header(BuildContext context, TextTheme textTheme) {
    return Container(
      // padding: const EdgeInsets.only(bottom: kPagePadding),
      decoration: BoxDecoration(
        // image: DecorationImage(
        //   image: AssetImage('assets/images/card_bg.png'),
        //   fit: BoxFit.cover,
        // ),
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
            padding: kPagePaddingInsets / 4,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
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
                      widget.ruleId < 0 ? 'New USSD Entry' : 'Edit USSD Entry',
                      style: textTheme.titleLarge,
                    ),
                  ],
                ),
                widget.ruleId >= 0
                    ? IconButton(
                        onPressed: () {
                          deleteUssdDialog(context, widget.ruleId, 'ussdCodes')
                              .then((value) => Navigator.pop(context));
                        },
                        icon: const Icon(
                          CupertinoIcons.trash,
                          color: kErrorColor,
                        ),
                      )
                    : const SizedBox(width: 2),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
