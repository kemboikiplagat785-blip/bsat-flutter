import 'dart:ui';

import 'package:bsat/components/dialogs/delete_ussd_dialog.dart';
import 'package:bsat/components/dialogs/make_offer_tutorial_dialog.dart';
import 'package:bsat/components/tool_button.dart';
import 'package:bsat/screens/online_management/search_device.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_accessibility_service/flutter_accessibility_service.dart';
import 'package:sim_data/sim_data.dart';

import '../../components/device_card.dart';
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
  final TextEditingController _offerNameController = TextEditingController();
  List<Map<String, dynamic>> _codeEntries = [];
  Set<String> _originalCodes = {};
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

  bool _hasChanges = false;

  bool isAdvanced = false;
  bool usesBongaPoints = false;
  bool hasAcceptedProcedure = false;

  List<Map<String, dynamic>> forwardingDevices = [];

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
    isActive: false,
    autoSwitch: true,
  );

  void getAndProcessCards() async {
    await SimDataPlugin.getSimData().then((value) {
      if (mounted) {
        setState(() {
          sims = value.cards;
        });
      }
      // debugPrint("Got cards");
    });
  }

  void getDevices() async {
    final devices = await _sqliteService.queryAll('forwardingDevices');
    if (mounted) {
      setState(() {
        forwardingDevices = devices;
      });
    }
  }

  Map<String, dynamic> _createCodeEntry({
    String code = '',
    String start = '',
    String end = '',
    String alternativeUssdCode = '',
    String runAltOn = '',
    bool hasAlternativeCode = false,
    bool altIsAdvanced = false,
    String altDelayMinutes = '0',
  }) {
    final entry = <String, dynamic>{
      'code': TextEditingController(text: code),
      'start': TextEditingController(text: start),
      'end': TextEditingController(text: end),
      'alternativeUssdCode': TextEditingController(text: alternativeUssdCode),
      'runAltOn': TextEditingController(text: runAltOn),
      'altDelayMinutes': TextEditingController(text: altDelayMinutes),
      'hasAlternativeCode': hasAlternativeCode,
      'altIsAdvanced': altIsAdvanced,
    };

    for (final key in [
      'code',
      'start',
      'end',
      'alternativeUssdCode',
      'runAltOn',
      'altDelayMinutes',
    ]) {
      (entry[key] as TextEditingController).addListener(() {
        if (mounted) {
          setState(() => _hasChanges = true);
        } else {
          _hasChanges = true;
        }
      });
    }

    return entry;
  }

  TextEditingController _entryController(
    Map<String, dynamic> entry,
    String key,
  ) {
    return entry[key] as TextEditingController;
  }

  void _setEntryHasAlt(Map<String, dynamic> entry, bool value) {
    setState(() {
      entry['hasAlternativeCode'] = value;
      _hasChanges = true;
      if (!value) {
        _entryController(entry, 'alternativeUssdCode').clear();
        _entryController(entry, 'runAltOn').clear();
        _entryController(entry, 'altDelayMinutes').text = '0';
        entry['altIsAdvanced'] = false;
      }
    });
  }

  void _setEntryAltAdvanced(Map<String, dynamic> entry, bool value) {
    setState(() {
      entry['altIsAdvanced'] = value;
      _hasChanges = true;
    });
  }

  void _removeCodeEntry(int index) {
    final entry = _codeEntries[index];
    _entryController(entry, 'code').dispose();
    _entryController(entry, 'start').dispose();
    _entryController(entry, 'end').dispose();
    _entryController(entry, 'alternativeUssdCode').dispose();
    _entryController(entry, 'runAltOn').dispose();
    _entryController(entry, 'altDelayMinutes').dispose();
    setState(() {
      _codeEntries.removeAt(index);
      _hasChanges = true;
    });
  }

  void _clearCodeEntries() {
    for (final entry in _codeEntries) {
      _entryController(entry, 'code').dispose();
      _entryController(entry, 'start').dispose();
      _entryController(entry, 'end').dispose();
      _entryController(entry, 'alternativeUssdCode').dispose();
      _entryController(entry, 'runAltOn').dispose();
      _entryController(entry, 'altDelayMinutes').dispose();
    }
    _codeEntries.clear();
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

  int? _parseAmount(String text) {
    final asInt = int.tryParse(text);
    if (asInt != null) return asInt;
    final asDouble = double.tryParse(text);
    if (asDouble != null) return asDouble.round();
    return null;
  }

  Future<bool> checkForErrorsAndProceed() async {
    final int? parsedAmount = _parseAmount(_amountTextController.text);

    if (_amountTextController.text == '' || parsedAmount == null) {
      setState(() {
        _errorAmount = _amountTextController.text == ''
            ? " *Required"
            : " *Enter a valid whole number";
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
    // Validate code entries
    if (_codeEntries.isEmpty) {
      setState(() {
        _errorUSSDCode = " *Required";
      });
      return false;
    }

    for (var entry in _codeEntries) {
      final codeText = _entryController(entry, 'code').text;
      if (codeText.isEmpty) {
        setState(() {
          _errorUSSDCode = " *Required";
        });
        return false;
      }
      if (RegExp(r'[^0-9*n#]').hasMatch(codeText)) {
        setState(() {
          _errorUSSDSyntax = " Code has error";
        });
        return false;
      }

      if (entry['hasAlternativeCode'] == true) {
        final altCode = _entryController(entry, 'alternativeUssdCode').text;
        if (altCode.isNotEmpty && RegExp(r'[^0-9*n#]').hasMatch(altCode)) {
          setState(() {
            _errorUSSDSyntax = " Code has error";
          });
          return false;
        }

        final delayText = _entryController(entry, 'altDelayMinutes').text;
        final delayValue = int.tryParse(delayText);
        if (delayText.isNotEmpty && (delayValue == null || delayValue < 0)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Alternative delay must be a whole number of minutes (0 or more).',
              ),
            ),
          );
          return false;
        }
      }
    }

    setState(() {
      _errorUSSDCode = '';
      _errorUSSDSyntax = '';
    });

    // Ensure no overlapping timeframes among codes for this offer
    if (_hasOverlappingCodeTimes()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Code timeframes overlap. Please adjust times.'),
        ),
      );
      return false;
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
    await addCodeToDatabase(parsedAmount);
    return true;
  }

  bool _timeOverlapPairs(int aStart, int aEnd, int bStart, int bEnd) {
    List<List<int>> aRanges = [];
    if (aStart <= aEnd) {
      aRanges.add([aStart, aEnd]);
    } else {
      aRanges.add([aStart, 1440]);
      aRanges.add([0, aEnd]);
    }
    List<List<int>> bRanges = [];
    if (bStart <= bEnd) {
      bRanges.add([bStart, bEnd]);
    } else {
      bRanges.add([bStart, 1440]);
      bRanges.add([0, bEnd]);
    }

    for (var ar in aRanges) {
      for (var br in bRanges) {
        if (!(ar[1] <= br[0] || br[1] <= ar[0])) return true;
      }
    }
    return false;
  }

  bool _hasOverlappingCodeTimes() {
    for (int i = 0; i < _codeEntries.length; i++) {
      final ei = _codeEntries[i];
      final s1 = ei['start']?.text ?? '';
      final e1 = ei['end']?.text ?? '';
      if (s1.isEmpty || e1.isEmpty) continue;
      final aStart = int.tryParse(s1.split(':')[0]) ?? 0;
      final aMin = int.tryParse(s1.split(':')[1]) ?? 0;
      final aEnd = int.tryParse(e1.split(':')[0]) ?? 0;
      final aEndMin = int.tryParse(e1.split(':')[1]) ?? 0;
      final aStartM = aStart * 60 + aMin;
      final aEndM = aEnd * 60 + aEndMin;

      for (int j = i + 1; j < _codeEntries.length; j++) {
        final ej = _codeEntries[j];
        final s2 = ej['start']?.text ?? '';
        final e2 = ej['end']?.text ?? '';
        if (s2.isEmpty || e2.isEmpty) continue;
        final bStart = int.tryParse(s2.split(':')[0]) ?? 0;
        final bMin = int.tryParse(s2.split(':')[1]) ?? 0;
        final bEnd = int.tryParse(e2.split(':')[0]) ?? 0;
        final bEndMin = int.tryParse(e2.split(':')[1]) ?? 0;
        final bStartM = bStart * 60 + bMin;
        final bEndM = bEnd * 60 + bEndMin;

        if (_timeOverlapPairs(aStartM, aEndM, bStartM, bEndM)) return true;
      }
    }
    return false;
  }

  Future<void> addCodeToDatabase(int amount) async {
    int codeId = -1;
    final offerRow = {
      'amount': amount,
      'offerName': _offerNameController.text.isNotEmpty
          ? _offerNameController.text
          : 'Ksh $amount',
      'fromSim': _fromSim,
      'dialSim': _dialSim,
      'canRetry': _canRetry ? 1 : 0,
      'isAdvanced': isAdvanced ? 1 : 0,
      'usesBongaPoints': usesBongaPoints ? 1 : 0,
      'fallbackCode': _fallbackCodeTextController.text,
      'balanceCheckCode': _balanceCheckCodeTextController.text,
      'bongaPointsPerTransaction':
          int.tryParse(_bongaPointsPerTransactionTextController.text) ?? 0,
    };

    if (widget.ruleId >= 0) {
      codeId = widget.ruleId;

      await _sqliteService.updateStuff(
        offerRow,
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
          ...offerRow,
          'fromSim': -1,
          'enabled': 1,
        },
        'ussdCodes',
      );
    }

    signature = signature.copyWith(
      ussdCodeId: codeId,
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
      } catch (e) {}
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
    _offerNameController.clear();
    // save variants: delete existing and insert new ones
    try {
      await _sqliteService.deleteWhere('ussdCodeVariants', 'ussdCodeId = ?', [codeId]);
    } catch (e) {}

    // prepare new variants list to insert
    final List<Map<String, dynamic>> newVariants = [];
    for (var entry in _codeEntries) {
      final codeText = _entryController(entry, 'code').text;
      final s = _entryController(entry, 'start').text;
      final e = _entryController(entry, 'end').text;
      if (codeText.isEmpty) continue;
      newVariants.add({
        'code': codeText,
        'start': s,
        'end': e,
        'hasAlternativeCode': entry['hasAlternativeCode'] == true,
        'alternativeUssdCode': _entryController(entry, 'alternativeUssdCode').text,
        'runAltOn': _entryController(entry, 'runAltOn').text,
        'altIsAdvanced': entry['altIsAdvanced'] == true,
        'altDelayMinutes':
            int.tryParse(_entryController(entry, 'altDelayMinutes').text) ?? 0,
      });
    }

    // insert new variants for this offer
    for (var nv in newVariants) {
      try {
        await _sqliteService.insertStuff(
          {
            'ussdCodeId': codeId,
            'code': nv['code'],
            'startTime': nv['start']!.isNotEmpty ? nv['start'] : null,
            'endTime': nv['end']!.isNotEmpty ? nv['end'] : null,
            'alternativeUssdCode': (nv['hasAlternativeCode'] == true &&
                    (nv['alternativeUssdCode'] ?? '').toString().isNotEmpty)
                ? nv['alternativeUssdCode']
                : null,
            'runAltOn': (nv['hasAlternativeCode'] == true &&
                    (nv['runAltOn'] ?? '').toString().isNotEmpty)
                ? nv['runAltOn']
                : null,
            'altIsAdvanced': (nv['hasAlternativeCode'] == true &&
                    nv['altIsAdvanced'] == true)
                ? 1
                : 0,
            'altDelayMinutes':
                nv['hasAlternativeCode'] == true ? nv['altDelayMinutes'] : 0,
          },
          'ussdCodeVariants',
        );
      } catch (e) {}
    }

    // propagate non-amount changes to other offers that originally shared any of the original codes
    Set<int> affectedIds = {};
    if (_originalCodes.isNotEmpty) {
      final placeholders = List.filled(_originalCodes.length, '?').join(',');
      try {
        final rows = await _sqliteService.rawQueryInput(
            'SELECT DISTINCT ussdCodeId FROM ussdCodeVariants WHERE code IN ($placeholders)',
            _originalCodes.toList());
        for (var r in rows) {
          final otherId = r['ussdCodeId'] as int;
          if (otherId != codeId) affectedIds.add(otherId);
        }
      } catch (e) {}
    }

    for (var otherId in affectedIds) {
      try {
        await _sqliteService.updateStuff(
          {
            ...offerRow,
            'enabled': 1,
          },
          'id = ?',
          [otherId],
          'ussdCodes',
        );

        // replace their variants with the newVariants (keeping their amount unchanged)
        try {
          await _sqliteService.deleteWhere('ussdCodeVariants', 'ussdCodeId = ?', [otherId]);
        } catch (e) {}

        for (var nv in newVariants) {
          try {
            await _sqliteService.insertStuff(
              {
                'ussdCodeId': otherId,
                'code': nv['code'],
                'startTime': nv['start']!.isNotEmpty ? nv['start'] : null,
                'endTime': nv['end']!.isNotEmpty ? nv['end'] : null,
                'alternativeUssdCode': (nv['hasAlternativeCode'] == true &&
                        (nv['alternativeUssdCode'] ?? '')
                            .toString()
                            .isNotEmpty)
                    ? nv['alternativeUssdCode']
                    : null,
                'runAltOn': (nv['hasAlternativeCode'] == true &&
                        (nv['runAltOn'] ?? '').toString().isNotEmpty)
                    ? nv['runAltOn']
                    : null,
                'altIsAdvanced': (nv['hasAlternativeCode'] == true &&
                        nv['altIsAdvanced'] == true)
                    ? 1
                    : 0,
                'altDelayMinutes': nv['hasAlternativeCode'] == true
                    ? nv['altDelayMinutes']
                    : 0,
              },
              'ussdCodeVariants',
            );
          } catch (e) {}
        }
      } catch (e) {}
    }
    _hasChanges = false;
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
      limit: 1,
    ))
        .first;
    _amountTextController.text = thisData['amount'].toString();
    _offerNameController.text = thisData['offerName'] ?? 'Ksh ${thisData['amount']}';
    // load variants for this ussd code row
    _clearCodeEntries();
    List<Map<String, dynamic>> variants = [];
    try {
      variants = await _sqliteService.queryCustom(
        'ussdCodeVariants',
        'ussdCodeId = ?',
        [widget.ruleId],
      );
    } catch (e) {}

    if (variants.isEmpty) {
      _codeEntries.add(
        _createCodeEntry(
          alternativeUssdCode: thisData['alternativeUssdCode'] ?? '',
          runAltOn: thisData['runAltOn'] ?? '',
          altIsAdvanced: (thisData['altIsAdvanced'] != null)
              ? thisData['altIsAdvanced'] == 1
              : false,
          hasAlternativeCode: (thisData['alternativeUssdCode'] ?? '')
              .toString()
              .isNotEmpty,
          altDelayMinutes: (thisData['altDelayMinutes'] ?? 0).toString(),
        ),
      );
    } else {
      for (var v in variants) {
        _codeEntries.add(
          _createCodeEntry(
            code: v['code'] ?? '',
            start: v['startTime'] ?? '',
            end: v['endTime'] ?? '',
            alternativeUssdCode: v['alternativeUssdCode'] ?? '',
            runAltOn: v['runAltOn'] ?? '',
            hasAlternativeCode: (v['alternativeUssdCode'] ?? '')
                .toString()
                .isNotEmpty,
            altIsAdvanced: (v['altIsAdvanced'] != null)
                ? v['altIsAdvanced'] == 1
                : false,
            altDelayMinutes: (v['altDelayMinutes'] ?? 0).toString(),
          ),
        );
        if ((v['code'] ?? '').toString().isNotEmpty) {
          _originalCodes.add(v['code'].toString());
        }
      }
    }
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

    var rawSignature = (await _sqliteService.queryCustom(
      'codeSignature',
      'ussdCodeId = ?',
      [widget.ruleId],
      limit: 1,
    ));

    final loadedSignature =
        CodeSignature.fromMap(rawSignature.isEmpty ? {} : rawSignature.first);

    signature = signature.copyWith(
      id: loadedSignature.id,
      ussdCodeId: loadedSignature.ussdCodeId,
      usdCode: loadedSignature.usdCode,
      acceptedProcedure: loadedSignature.acceptedProcedure,
      lastProcedure: loadedSignature.lastProcedure,
      importantSteps: loadedSignature.importantSteps,
      isActive: loadedSignature.isActive,
      autoSwitch: loadedSignature.autoSwitch,
    );

    importantSteps = signature.importantSteps;

    if (mounted) {
      setState(() {
        hasAcceptedProcedure = signature.acceptedProcedure != null &&
            signature.acceptedProcedure!.isNotEmpty;
      });
    }
  }

  void _addChangeListeners() {
    _amountTextController.addListener(() => setState(() => _hasChanges = true));
    _codeTextController.addListener(() => setState(() => _hasChanges = true));
    _fallbackCodeTextController
        .addListener(() => setState(() => _hasChanges = true));
    _balanceCheckCodeTextController
        .addListener(() => setState(() => _hasChanges = true));
    _bongaPointsPerTransactionTextController
        .addListener(() => setState(() => _hasChanges = true));
    signatureTestNumberController
        .addListener(() => setState(() => _hasChanges = true));
    _offerNameController.addListener(() => setState(() => _hasChanges = true));
    // ensure at least one code entry exists
    if (_codeEntries.isEmpty) {
      _codeEntries.add(_createCodeEntry());
    }
  }

  @override
  void dispose() {
    _amountTextController.dispose();
    _codeTextController.dispose();
    _fallbackCodeTextController.dispose();
    _balanceCheckCodeTextController.dispose();
    _bongaPointsPerTransactionTextController.dispose();
    signatureTestNumberController.dispose();
    _offerNameController.dispose();
    _clearCodeEntries();
    super.dispose();
  }

  Future<void> _handleBackPress() async {
    if (!_hasChanges) {
      Navigator.pop(context);
      return;
    }

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Unsaved Changes'),
        content: const Text('Do you want to save your changes before leaving?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Discard'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save', style: TextStyle(color: kPrimaryColor)),
          ),
        ],
      ),
    );

    if (shouldSave == true) {
      final saved = await checkForErrorsAndProceed();
      if (saved && mounted) {
        Navigator.pop(context);
      }
    } else if (shouldSave == false && mounted) {
      Navigator.pop(context);
    }
  }

  @override
  void initState() {
    super.initState();

    getAndProcessCards();
    getDevices();
    _addChangeListeners();

    if (widget.ruleId >= 0) {
      processData();
      _hasChanges = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        _handleBackPress();
      },
      child: SafeArea(
        child: Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(CupertinoIcons.back, size: 20),
              onPressed: _handleBackPress,
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
                      deleteUssdDialog(context, widget.ruleId, 'ussdCodes')
                          .then(
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
              _buildSectionTitle('Basics'),
              _buildGroup([
                Padding(
                  padding: kPagePaddingInsets,
                  child: Row(children: [Text('On Receiving')]),
                ),
                _buildInputTile(
                  label: 'Amount (Ksh)',
                  controller: _amountTextController,
                  keyboardType: TextInputType.number,
                  errorText: _errorAmount.isEmpty ? null : _errorAmount,
                  icon: CupertinoIcons.money_dollar,
                ),
                _buildInputTile(
                  label: 'Offer Name',
                  controller: _offerNameController,
                  hint: '1gb 24hrs',
                  icon: CupertinoIcons.tag,
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
                const Divider(color: Colors.white24),
                Padding(
                  padding: kPagePaddingInsets,
                  child: Row(children: [Text('Dial')]),
                ),
                // Multiple USSD codes with per-code start/end times
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('USSD Codes', style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      if (_errorUSSDCode.isNotEmpty)
                        Text(_errorUSSDCode, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 8),
                      ..._codeEntries.asMap().entries.map((e) {
                        final idx = e.key;
                        final entry = e.value;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _entryController(entry, 'code'),
                                      decoration: InputDecoration(
                                        labelText: 'USSD Code',
                                        hintText: '*180*5*2*n#',
                                        border: InputBorder.none,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(CupertinoIcons.trash, color: kErrorColor),
                                    onPressed: () {
                                      _removeCodeEntry(idx);
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(child: _buildTimeTile(label: 'Start', controller: _entryController(entry, 'start'))),
                                  const SizedBox(width: 8),
                                  Expanded(child: _buildTimeTile(label: 'End', controller: _entryController(entry, 'end'))),
                                ],
                              ),
                              const SizedBox(height: 8),
                              _buildSwitchTile(
                                label: 'Has Alternative Code',
                                value: entry['hasAlternativeCode'] == true,
                                onChanged: (val) => _setEntryHasAlt(entry, val),
                              ),
                              if (entry['hasAlternativeCode'] == true) ...[
                                Padding(
                                  padding: kPagePaddingInsets,
                                  child: const Text(
                                      'Use this alternative only while the variant is active.'),
                                ),
                                _buildInputTile(
                                  label: 'Alternative USSD Code',
                                  controller: _entryController(entry, 'alternativeUssdCode'),
                                  hint: '*180*5*2*n#',
                                  icon: CupertinoIcons.number,
                                ),
                                _buildSwitchTile(
                                  label: 'Alternative Code is Advanced',
                                  value: entry['altIsAdvanced'] == true,
                                  onChanged: (val) => _setEntryAltAdvanced(entry, val),
                                ),
                                _buildInputTile(
                                  label: 'Run Alternative After (minutes)',
                                  controller: _entryController(entry, 'altDelayMinutes'),
                                  hint: '0 = run immediately on failure',
                                  keyboardType: TextInputType.number,
                                  icon: CupertinoIcons.timer,
                                ),
                                _buildRunAltOnSelector(entry),
                              ],
                            ],
                          ),
                        );
                      }).toList(),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _codeEntries.add(_createCodeEntry());
                              _hasChanges = true;
                            });
                          },
                          icon: const Icon(CupertinoIcons.plus),
                          label: const Text('Add Code'),
                        ),
                      ),
                    ],
                  ),
                ),
                _buildSimSelector(
                  label: 'Dial Using',
                  selectedSimId: _dialSim,
                  isBoth: false,
                  onSelect: (id, _) => setState(() => _dialSim = id),
                ),
                const Divider(color: Colors.white24),
                _buildSwitchTile(
                  label: 'Advanced USSD',
                  value: isAdvanced,
                  onChanged: (val) {
                    if (val) showAccessibilityPermissionDialog(context);
                    _hasChanges = true;
                    setState(() => isAdvanced = val);
                  },
                ),
              ]),

              _buildSectionTitle('Error detection and avoidance'),
              _buildGroup([
                _buildSwitchTile(
                  label: 'Auto-Retry on Error',
                  value: _canRetry,
                  onChanged: (val) {
                    _hasChanges = true;
                    setState(() => _canRetry = val);
                  },
                ),
                const Divider(color: Colors.white24, height: 1),
                _buildSwitchTile(
                  label: 'Uses Bonga Points',
                  value: usesBongaPoints,
                  onChanged: (val) {
                    _hasChanges = true;
                    setState(() => usesBongaPoints = val);
                  },
                ),
                if (usesBongaPoints) ...[
                  Padding(
                    padding: kPagePaddingInsets,
                    child: Text(
                      'Configure the USSD codes and points required for using bonga points as a fallback when you doen\'t have enough bonga points to complete the transaction.',
                      style: TextStyle(
                        color: Theme.of(context).hintColor,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  _buildInputTile(
                    label:
                        'Emergency USSD Code (if bonga points balance too low)',
                    controller: _fallbackCodeTextController,
                    hint: 'Emergency USSD',
                    icon: CupertinoIcons.refresh_circled,
                  ),
                  _buildInputTile(
                    label: 'USSD Balance Check',
                    controller: _balanceCheckCodeTextController,
                    icon: CupertinoIcons.graph_square,
                  ),
                  _buildInputTile(
                    label: 'Points deducted per Transaction',
                    controller: _bongaPointsPerTransactionTextController,
                    keyboardType: TextInputType.number,
                    icon: CupertinoIcons.bolt_fill,
                  ),
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
                    _hasChanges = true;
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
                        value: signature.autoSwitch ?? true,
                        onChanged: (val) {
                          _hasChanges = true;
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
                                          Text(
                                            'Text',
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      const Divider(
                                        color: Colors.white24,
                                      ),

                                      ...signature.acceptedProcedure!.map((e) {
                                        return Padding(
                                          padding: kPagePaddingInsets,
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                CodeSignature
                                                    .extractChosenOption(
                                                  e,
                                                ),
                                              ),
                                              Text(
                                                e['choice'].toString(),
                                              ),
                                            ],
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
                            var code =
                                TransactionController().replaceNWithNumber(
                              _codeTextController.text,
                              0722000000,
                            );
                            // PhoneService phoneService = PhoneService();
                            List res = await PhoneService().makeAdvancedRequest(
                              code,
                              _dialSim,
                              isGettingSignature: true,
                            );

                            final acceptedProcedure =
                                (res.length > 2 ? res[2] as List? : null)
                                    ?.cast<Map<String, dynamic>>();

                            signature = signature.copyWith(
                              usdCode: _codeTextController.text,
                              acceptedProcedure: acceptedProcedure,
                              lastProcedure: acceptedProcedure,
                            );

                            print("Signature: $signature");

                            setState(() {});

                            if (acceptedProcedure == null) {
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
                          Icon(
                            CupertinoIcons.shield_lefthalf_fill,
                            color: kWarningColor,
                          ),
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
                      child: Text(
                        'Need Help?',
                        style: TextStyle(
                          color: Theme.of(context).hintColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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
          color: kIndigoColor,
        ),
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

  Widget _buildTimeTile({required String label, required TextEditingController controller}) {
    return InkWell(
      onTap: () async {
        // parse current value
        int initHour = 0;
        int initMinute = 0;
        if (controller.text.isNotEmpty && controller.text.contains(':')) {
          try {
            initHour = int.parse(controller.text.split(':')[0]);
            initMinute = int.parse(controller.text.split(':')[1]);
          } catch (e) {}
        }

        int selectedHour = initHour;
        int selectedMinute = initMinute;

        await showModalBottomSheet(
          context: context,
          isScrollControlled: false,
          backgroundColor: Theme.of(context).cardColor,

          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          builder: (ctx) {
            return SizedBox(
              height: 300,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            setState(() {
                              controller.text = '';
                              _hasChanges = true;
                            });
                          },
                          child: const Text('Clear'),
                        ),
                        Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
                        TextButton(
                          onPressed: () {
                            final hh = selectedHour.toString().padLeft(2, '0');
                            final mm = selectedMinute.toString().padLeft(2, '0');
                            setState(() {
                              controller.text = '$hh:$mm';
                              _hasChanges = true;
                            });
                            Navigator.of(ctx).pop();
                          },
                          child: const Text('Set'),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: CupertinoPicker(
                            scrollController: FixedExtentScrollController(initialItem: selectedHour),
                            itemExtent: 32,
                            onSelectedItemChanged: (i) => selectedHour = i,
                            children: List.generate(24, (i) => Center(child: Text(i.toString().padLeft(2, '0')))),
                          ),
                        ),
                        Expanded(
                          child: CupertinoPicker(
                            scrollController: FixedExtentScrollController(initialItem: selectedMinute),
                            itemExtent: 32,
                            onSelectedItemChanged: (i) => selectedMinute = i,
                            children: List.generate(60, (i) => Center(child: Text(i.toString().padLeft(2, '0')))),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            );
          },
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(
                  controller.text.isNotEmpty ? controller.text : 'Any time',
                  style: TextStyle(color: Theme.of(context).hintColor),
                ),
              ],
            ),
            const Icon(CupertinoIcons.clock, color: kPrimaryColor),
          ],
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

  void showDevicePicker(TextEditingController controller) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Select Device'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  leading: const Icon(CupertinoIcons.device_phone_portrait),
                  title: const Text('This Device'),
                  onTap: () {
                    setState(() {
                      controller.text = '';
                      _hasChanges = true;
                    });
                    Navigator.pop(context);
                  },
                ),
                ...forwardingDevices.map(
                  (device) {
                    return ListTile(
                      leading: const Icon(Icons.devices),
                      title: Text(device['device_name'] ?? 'Unknown'),
                      subtitle: Text(device['owner_email'] ?? ''),
                      onTap: () {
                        setState(() {
                          controller.text = device['device_name'];
                          _hasChanges = true;
                        });
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
                // add device icon
                IconButton(
                  icon: const Icon(CupertinoIcons.plus_app),
                  onPressed: () async {
                    // open device management screen
                    var device = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => SearchDevicePage(),
                      ),
                    );

                    if (device != null) {
                      Navigator.pop(context); // close the picker dialog
                      setState(() {
                        controller.text = device['device_name'];
                        _hasChanges = true;
                      });
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRunAltOnSelector(Map<String, dynamic> entry) {
    final controller = _entryController(entry, 'runAltOn');
    Map<String, dynamic>? selectedDevice;
    if (controller.text.isNotEmpty) {
      try {
        selectedDevice = forwardingDevices.firstWhere(
          (d) => d['device_name'] == controller.text,
        );
      } catch (e) {}
    }

    return InkWell(
      onTap: () => showDevicePicker(controller),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Run the code on',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).hintColor,
              ),
            ),
            const SizedBox(height: 8),
            if (selectedDevice != null) ...[
              deviceCard(
                context: context,
                deviceName: selectedDevice['device_name'] ?? 'Unknown',
                deviceDetails: selectedDevice['owner_email'],
                iconData: Icons.devices,
              ),
              const SizedBox(height: 8),
            ] else if (controller.text.isNotEmpty) ...[
              Row(
                children: [
                  const Icon(Icons.devices, color: kPrimaryColor),
                  const SizedBox(width: 8),
                  Text(
                    controller.text,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ] else ...[
              Row(
                children: [
                  const Icon(CupertinoIcons.device_phone_portrait,
                      color: kPrimaryColor),
                  const SizedBox(width: 8),
                  const Text(
                    'This Device',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}
