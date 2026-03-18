import 'dart:ui';

import 'package:bsat/components/dialogs/delete_ussd_dialog.dart';
import 'package:bsat/components/dialogs/make_offer_tutorial_dialog.dart';
import 'package:bsat/components/dialogs/show_error_dialog.dart';
import 'package:bsat/components/tool_button.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_accessibility_service/flutter_accessibility_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sim_data/sim_data.dart';

import '../../components/dialogs/accessibility_permission.dart';
import '../../controllers/transaction_controller.dart';
import '../../models/code_signature.dart';
import '../../services/phone_service.dart';
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
  final TextEditingController _fallbackCodeTextController =
      TextEditingController();
  final TextEditingController _balanceCheckCodeTextController =
      TextEditingController();
  final TextEditingController _bongaPointsPerTransactionTextController =
      TextEditingController();
  final TextEditingController signatureTestNumberController =
      TextEditingController();

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
  bool usesBongaPoints = false;
  bool hasAcceptedProcedure = false;

  bool _fromBothSims = true;
  bool _canRetry = false;

  List allOptions = [];

  Map thisData = {};
  List<Map<String, String>> importantSteps = [];

  CodeSignature signature = CodeSignature(
    id: null,
    ussdCodeId: null,
    usdCode: '',
    acceptedProcedure: null,
    lastProcedure: null,
    importantSteps: [],
  );

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
    if (usesBongaPoints) {
      if (_balanceCheckCodeTextController.text == '') {
        // toast
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Balance check USSD code is required when using bonga points.'),
          ),
        );
        return false;
      }
      if (_bongaPointsPerTransactionTextController.text == '' ||
          int.tryParse(_bongaPointsPerTransactionTextController.text) == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Valid bonga points per transaction is required when using bonga points.',
            ),
          ),
        );
        return false;
      }
      if (_fallbackCodeTextController.text == '') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Fallback USSD code is required when using bonga points.'),
          ),
        );
        return false;
      }
    }
    addCodeToDatabase(
      _codeTextController.text,
      int.parse(_amountTextController.text),
    );
    return true;
  }

  void addCodeToDatabase(String code, int amount) async {
    int codeId = -1;
    if (widget.ruleId >= 0) {
      // signature = signature.copyWith(
      //   ussdCodeId: widget.ruleId,
      //   usdCode: code,
      // );
      codeId = widget.ruleId;

      await _sqliteService.updateStuff(
        {
          'id': widget.ruleId,
          'amount': amount,
          'code': code,
          'fromSim': _fromSim,
          'dialSim': _dialSim,
          'canRetry': _canRetry ? 1 : 0,
          'isAdvanced': isAdvanced ? 1 : 0,
          'usesBongaPoints': usesBongaPoints ? 1 : 0,
          'fallbackCode': _fallbackCodeTextController.text,
          'balanceCheckCode': _balanceCheckCodeTextController.text,
          'bongaPointsPerTransaction':
              int.tryParse(_bongaPointsPerTransactionTextController.text) ?? 0,
        },
        'id = ?',
        [widget.ruleId],
        'ussdCodes',
      );

      // } else {
      //   await _sqliteService.deleteStuff(
      //     widget.ruleId,
      //     'codeSignature',
      //   );
      // }

      // return;
    } else {
      codeId = await _sqliteService.insertStuff(
        {
          'amount': amount,
          'code': code,
          'fromSim': -1,
          'dialSim': _dialSim,
          'canRetry': _canRetry ? 1 : 0,
          'isAdvanced': isAdvanced ? 1 : 0,
          'enabled': 1,
          'usesBongaPoints': usesBongaPoints ? 1 : 0,
          'fallbackCode': _fallbackCodeTextController.text,
          'balanceCheckCode': _balanceCheckCodeTextController.text,
          'bongaPointsPerTransaction':
              int.tryParse(_bongaPointsPerTransactionTextController.text) ?? 0,
        },
        'ussdCodes',
      );
    }

    signature = signature.copyWith(
      ussdCodeId: codeId,
      usdCode: code,
    );

    if (signature.id != null && signature.id! >= 0) {
      await _sqliteService.updateStuff(
        signature.sqlSavableForm(),
        'id = ?',
        [signature.id!],
        'codeSignature',
      );
    } else {
      try {
        int id = await _sqliteService.insertStuff(
          signature.sqlSavableForm(),
          'codeSignature',
        );

      } catch (e) {
      }
    }

    // if (hasAcceptedProcedure) {
    //   // CodeSignature signature = CodeSignature(
    //   //   ussdCodeId: newId,
    //   //   usdCode: code,
    //   //   acceptedProcedure: jsonEncode(acceptedProcedure),
    //   //   importantSteps: importantSteps,
    //   // );
    //   await _sqliteService.insertStuff(
    //     signature.sqlSavableForm(),
    //     'codeSignature',
    //   );
    // }

    _codeTextController.clear();
    _amountTextController.clear();
    _fallbackCodeTextController.clear();
    _balanceCheckCodeTextController.clear();
  }

  bool ussdSyntaxHaasError() {
    RegExp regex = RegExp(r'[^0-9*n#]');

    return regex.hasMatch(_codeTextController.text);
  }

  void processData() async {
    thisData = (await _sqliteService.queryCustom(
      'ussdCodes',
      'id = ?',
      [widget.ruleId],
    ))
        .first;
    _amountTextController.text = thisData['amount'].toString();
    _codeTextController.text = thisData['code'];
    _fromSim = thisData['fromSim'];
    _dialSim = thisData['dialSim'];
    _canRetry = thisData['canRetry'] == 1;
    isAdvanced =
        (thisData['isAdvanced'] != null) ? thisData['isAdvanced'] == 1 : false;

    _fromBothSims = _fromSim < 0 ? true : false;
    usesBongaPoints = (thisData['usesBongaPoints'] != null)
        ? thisData['usesBongaPoints'] == 1
        : false;
    _fallbackCodeTextController.text = thisData['fallbackCode'] ?? '';
    _balanceCheckCodeTextController.text =
        thisData['balanceCheckCode'] ?? '*126*7*1#';
    _bongaPointsPerTransactionTextController.text =
        (thisData['bongaPointsPerTransaction'] != null)
            ? thisData['bongaPointsPerTransaction'].toString()
            : '60';

    signature = CodeSignature.fromMap((await _sqliteService.queryCustom(
      'codeSignature',
      'ussdCodeId = ?',
      [widget.ruleId],
    ))
        .first);


    importantSteps = signature.importantSteps;


    if (mounted) {
      setState(() {
        hasAcceptedProcedure = signature.acceptedProcedure != null &&
            signature.acceptedProcedure!.isNotEmpty;
      });
    }
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
    final theme = Theme.of(context);

    return SafeArea(
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(CupertinoIcons.back, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            widget.ruleId < 0 ? 'New Entry' : 'Edit Entry',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          actions: [
            if (widget.ruleId >= 0)
              IconButton(
                icon: const Icon(CupertinoIcons.trash,
                    color: kErrorColor, size: 20),
                onPressed: () =>
                    deleteUssdDialog(context, widget.ruleId, 'ussdCodes').then(
                  (value) => Navigator.pop(context),
                ),
              ),
          ],
          elevation: 0,
          backgroundColor: Colors.transparent,
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [
            _buildSectionTitle('Trigger Condition'),
            _buildGroup([
              _buildInputTile(
                label: 'Amount (Ksh)',
                controller: _amountTextController,
                keyboardType: TextInputType.number,
                errorText: _errorAmount.isEmpty ? null : _errorAmount,
                icon: CupertinoIcons.money_dollar,
              ),
              _buildSimSelector(
                label: 'Received On',
                selectedSimId: _fromSim,
                isBoth: _fromBothSims,
                onSelect: (id, both) => setState(() {
                  _fromSim = id;
                  _fromBothSims = both;
                }),
              ),
            ]),

            _buildSectionTitle('Execution'),
            _buildGroup([
              _buildInputTile(
                label: 'USSD Code',
                controller: _codeTextController,
                hint: '*180*5*2*n#',
                icon: CupertinoIcons.number,
                errorText: _errorUSSDCode.isEmpty ? null : _errorUSSDCode,
              ),
              _buildSimSelector(
                label: 'Dial Using',
                selectedSimId: _dialSim,
                isBoth: false,
                onSelect: (id, _) => setState(() => _dialSim = id),
              ),
            ]),

            _buildSectionTitle('Automation Options'),
            _buildGroup([
              _buildSwitchTile(
                label: 'Advanced USSD',
                value: isAdvanced,
                onChanged: (val) {
                  if (val) showAccessibilityPermissionDialog(context);
                  setState(() => isAdvanced = val);
                },
              ),
              const Divider(color: Colors.white24),
              _buildSwitchTile(
                label: 'Auto-Retry on Error',
                value: _canRetry,
                onChanged: (val) => setState(() => _canRetry = val),
              ),
            ]),

            _buildSectionTitle('Auto Switch & risk detection'),
            _buildGroup([
              _buildSwitchTile(
                label: 'Use Bonga Points',
                value: usesBongaPoints,
                onChanged: (val) => setState(() => usesBongaPoints = val),
              ),
              if (usesBongaPoints) ...[
                _buildSectionTitle('Bonga Configuration'),
                _buildGroup([
                  _buildInputTile(
                    label:
                        'Emergency USSD Code (if bonga points balance too low)',
                    controller: _fallbackCodeTextController,
                    hint: 'Emergency USSD',
                    icon: CupertinoIcons.refresh_circled,
                  ),
                  _buildInputTile(
                    label: 'Balance Check',
                    controller: _balanceCheckCodeTextController,
                    icon: CupertinoIcons.graph_square,
                  ),
                  _buildInputTile(
                    label: 'Points deducted per Transaction',
                    controller: _bongaPointsPerTransactionTextController,
                    keyboardType: TextInputType.number,
                    icon: CupertinoIcons.bolt_fill,
                  ),
                ]),
              ],
              const Divider(color: Colors.white24),
              _buildSwitchTile(
                label: 'Signature',
                subtitle:
                    'Teach the app to recognize this code\'s USSD responses to detect harmful changes',
                value: signature.isActive ?? false,
                onChanged: (val) => setState(() {
                  hasAcceptedProcedure = val;
                  signature = signature.copyWith(isActive: val);
                  setState(() {});
                }),
              ),
              if (hasAcceptedProcedure && signature.isActive == true) ...[
                Column(
                  children: [
                    _buildSwitchTile(
                      label: 'Auto switch ',
                      subtitle:
                          'When USSD process is changed by Safaricom, use the new USSD code as detected by the app',
                      value: signature.autoSwitch ?? false,
                      onChanged: (val) {
                        setState(() {
                          signature = signature.copyWith(autoSwitch: val);
                        });
                      },
                    ),
                    if (signature.acceptedProcedure != null &&
                        signature.acceptedProcedure!.isNotEmpty)
                      Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.all(16.0),
                                decoration: BoxDecoration(
                                  // 2. The Glass Tint (Semi-transparent white)
                                  borderRadius: BorderRadius.circular(20),
                                  // 3. The "Shine" Border
                                  border: Border.all(
                                    color: Theme.of(context).hintColor,
                                    width: 1.5,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    // Header Row
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          'Option',
                                        ),
                                        Row(
                                          children: const [
                                            Text(
                                              'Text',
                                            ),
                                            SizedBox(width: 20),
                                            Text(
                                              'Important',
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    const Divider(
                                      color: Colors.white24,
                                    ),

                                    // The List Items
                                    ...signature.acceptedProcedure!.map((e) {
                                      int index = signature.acceptedProcedure!
                                          .indexOf(e);

                                      return Theme(
                                        data: ThemeData(),
                                        child: Container(
                                          margin: const EdgeInsets.only(
                                            bottom: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            border: Border(
                                              bottom: BorderSide(
                                                  color: Theme.of(context)
                                                      .hintColor),
                                            ),
                                          ),
                                          child: CheckboxListTile(
                                            contentPadding: EdgeInsets
                                                .zero, // Clean alignment
                                            onChanged: (value) {
                                              setState(() {
                                                if (value == true) {
                                                  importantSteps.add({
                                                    'stepPosition':
                                                        index.toString(),
                                                    'option': CodeSignature
                                                        .extractChosenOption(e),
                                                    'choice': e['choice'] ?? '',
                                                  });
                                                } else {
                                                  importantSteps.removeWhere(
                                                      (step) =>
                                                          step[
                                                              'stepPosition'] ==
                                                          index.toString());
                                                }
                                              });
                                            },
                                            value: importantSteps.any(
                                              (step) =>
                                                  step['stepPosition'] ==
                                                  index.toString(),
                                            ),
                                            controlAffinity: ListTileControlAffinity
                                                .trailing, // Move checkbox to right
                                            title: Text(
                                              CodeSignature.extractChosenOption(
                                                  e),
                                              style:
                                                  const TextStyle(fontSize: 14),
                                            ),
                                            secondary: Text(
                                              e['choice'].toString(),
                                            ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    Container(
                      margin: const EdgeInsets.all(16.0),
                      decoration: BoxDecoration(
                        // color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(kBorderRadius),
                        border: Border.all(
                          color:
                              Theme.of(context).dividerColor.withOpacity(0.1),
                        ),
                      ),
                      child: toolButton(
                        () async {
                          var code = TransactionController().replaceNWithNumber(
                            _codeTextController.text,
                            0722000000,
                          );
                          // PhoneService phoneService = PhoneService();
                          List res = await PhoneService().makeAdvancedRequest(
                            code,
                            _dialSim,
                            isGettingSignature: true,
                          );

                          signature = signature.copyWith(
                            usdCode: _codeTextController.text,
                            acceptedProcedure: res[2],
                            lastProcedure:
                                (res[2] as List?)?.cast<Map<String, dynamic>>(),
                          );

                          setState(() {});

                          if (signature.acceptedProcedure == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Failed to get signature. Please ensure the USSD code is correct and try again. ${signature.toString()}',
                                ),
                              ),
                            );
                            return;
                          }
                        },
                        Icon(CupertinoIcons.shield_lefthalf_fill, color: kWarningColor,),
                        "Click to Edit Signature",
                        context,
                      ),
                    ),
                  ],
                ),
              ],
            ]),
            const SizedBox(height: 32),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => makeOfferTutorialDialog(context),
                    child: Text('Need Help?',
                        style: TextStyle(
                            color: Theme.of(context).hintColor,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimaryColor,
                      foregroundColor: Colors.white,
                      // minimumSize: const Offset(0, 56),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () {
                      // HapticFeedback.mediumImpact();
                      checkForErrorsAndProceed().then(
                        (value) => value ? Navigator.pop(context) : null,
                      );
                    },
                    child: const Text('Save Rule',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // --- UI Construction Helpers ---

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 24),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: kIndigoColor),
      ),
    );
  }

  Widget _buildGroup(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: Theme.of(context).dividerColor.withOpacity(0.05)),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildInputTile({
    required String label,
    required TextEditingController controller,
    String? hint,
    IconData? icon,
    TextInputType? keyboardType,
    String? errorText,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          icon:
              icon != null ? Icon(icon, size: 20, color: kPrimaryColor) : null,
          labelText: label,
          hintText: hint,
          errorText: errorText,
          labelStyle: const TextStyle(fontSize: 14),
          border: InputBorder.none,
          floatingLabelBehavior: FloatingLabelBehavior.auto,
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required String label,
    required bool value,
    String? subtitle,
    required Function(bool) onChanged,
  }) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      activeColor: kPrimaryColor,
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(
                // fontSize: 12,
                fontWeight: FontWeight.w100,
                color: Theme.of(context).hintColor,
              ),
            )
          : null,
      title: Text(
        label,
        style: const TextStyle(
          // fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildSimSelector(
      {required String label,
      required int selectedSimId,
      required bool isBoth,
      required Function(int, bool) onSelect}) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  color: kGrayColor,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(
            children: [
              ...sims.map((s) {
                bool isSelected = !isBoth && s.subscriptionId == selectedSimId;
                return GestureDetector(
                  onTap: () => onSelect(s.subscriptionId, false),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? kPrimaryColor.withOpacity(0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: isSelected
                              ? kPrimaryColor
                              : kGrayColor.withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.sim_card,
                            size: 14, color: isSelected ? kPrimaryColor : null),
                        const SizedBox(width: 4),
                        Text(s.displayName,
                            style: TextStyle(
                                color: isSelected ? kPrimaryColor : null,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                );
              }),
              if (onSelect != null) // Logic for "Both"
                GestureDetector(
                  onTap: () => onSelect(-1, true),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isBoth
                          ? kPrimaryColor.withOpacity(0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: isBoth
                              ? kPrimaryColor
                              : kGrayColor.withOpacity(0.2)),
                    ),
                    child: Text('Both',
                        style: TextStyle(
                            color: isBoth ? kPrimaryColor : kGrayColor,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
