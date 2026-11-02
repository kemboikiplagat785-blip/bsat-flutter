import 'package:bsat/components/chip_input_field.dart';
import 'package:bsat/services/lan/lan_forwarding_rules.dart';
import 'package:bsat/utils/constants.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Adds or edits one LAN forwarding rule: a trusted LAN device and the
/// MPESA amounts forwarded to it. The LAN counterpart of "Forward MPESA
/// Messages"; it saves locally only (no backend, no Online account).
class LanForwardingRuleEditor extends StatefulWidget {
  final LanForwardingRuleStore store;

  /// Devices a rule may point at: the trusted LAN pairings.
  final List<String> trustedDeviceNames;

  /// The rule to edit; null adds a new one.
  final LanForwardingRule? rule;

  const LanForwardingRuleEditor({
    super.key,
    required this.store,
    required this.trustedDeviceNames,
    this.rule,
  });

  @override
  State<LanForwardingRuleEditor> createState() =>
      _LanForwardingRuleEditorState();
}

class _LanForwardingRuleEditorState extends State<LanForwardingRuleEditor> {
  final _amountController = TextEditingController();
  late String? _deviceName = widget.rule?.deviceName ??
      (widget.trustedDeviceNames.length == 1
          ? widget.trustedDeviceNames.single
          : null);
  late final List<int> _amounts = [...?widget.rule?.amounts];
  String? _error;
  bool _saving = false;

  /// A rule from Online management keeps its device here.
  bool get _deviceLocked => widget.rule != null && !widget.rule!.lanOnly;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _addAmount() {
    final amount = int.tryParse(_amountController.text.trim());
    setState(() {
      if (amount == null || amount <= 0) {
        _error = 'Enter a whole amount greater than zero.';
        return;
      }
      if (!_amounts.contains(amount)) _amounts.add(amount);
      _amountController.clear();
      _error = null;
    });
  }

  Future<void> _save() async {
    if (_amountController.text.trim().isNotEmpty) _addAmount();
    final device = _deviceName;
    if (device == null) {
      setState(() => _error = 'Choose the LAN device to forward to.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final rule = widget.rule;
      if (rule == null) {
        await widget.store.create(deviceName: device, amounts: _amounts);
      } else {
        await widget.store
            .update(rule.id, deviceName: device, amounts: _amounts);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on LanRuleException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not save the rule: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final names = {
      ...widget.trustedDeviceNames,
      if (widget.rule != null) widget.rule!.deviceName,
    }.toList()
      ..sort();
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        title: Text(
          widget.rule == null ? 'Add LAN Rule' : 'Edit LAN Rule',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(kPagePadding),
        children: [
          Text('Forward To', style: theme.textTheme.bodyLarge),
          const SizedBox(height: kPagePadding / 2),
          if (_deviceLocked)
            Text(
              '${widget.rule!.deviceName} (Online device; change it in '
              'Online management)',
              style: const TextStyle(fontWeight: FontWeight.bold),
            )
          else
            for (final name in names)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  tileColor: theme.cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(kBorderRadius),
                    side: BorderSide(
                      color: name == _deviceName
                          ? kPrimaryColor
                          : Colors.grey.withValues(alpha: 0.15),
                      width: name == _deviceName ? 2 : 1,
                    ),
                  ),
                  leading: Icon(
                    name == _deviceName
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: kPrimaryColor,
                  ),
                  title: Text(name,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  onTap: () => setState(() => _deviceName = name),
                ),
              ),
          const SizedBox(height: kPagePadding),
          const Text('Amounts to forward (Ksh)'),
          const SizedBox(height: kPagePadding / 2),
          ChipInputField(
            key: const Key('lanRuleAmounts'),
            chips: _amounts,
            controller: _amountController,
            onAddChip: _addAmount,
            onRemoveChip: (chip) =>
                setState(() => _amounts.remove(int.parse(chip))),
            keyboardType: TextInputType.number,
            spacing: kPagePadding / 3,
            borderRadius: kBorderRadius,
            addIconColor: kPrimaryColor,
          ),
          if (_error != null) ...[
            const SizedBox(height: kPagePadding),
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          ],
          const SizedBox(height: kPagePadding * 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: kPagePadding),
              OutlinedButton(
                key: const Key('lanRuleSave'),
                onPressed: _saving ? null : _save,
                child: const Text('Save',
                    style: TextStyle(color: kPrimaryColor)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
