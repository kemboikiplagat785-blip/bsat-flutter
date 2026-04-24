import 'package:another_telephony/telephony.dart';
import 'package:bsat/services/sms_sevice.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:bsat/utils/date_ops.dart';
import 'package:flutter/material.dart';
import 'package:bsat/controllers/transaction_controller.dart';


class ConfirmTransactionsPage extends StatefulWidget {
  const ConfirmTransactionsPage({super.key});

  @override
  State<ConfirmTransactionsPage> createState() => _ConfirmTransactionsPageState();
}

class _ConfirmTransactionsPageState extends State<ConfirmTransactionsPage> {
  DateTime _start = DateTime.now().subtract(const Duration(hours: 6));
  DateTime _end = DateTime.now();
  bool _retryingAll = false;


  bool _loading = true;
  List<_MappedItem> _items = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);

    try {
      final processRows = await SQLiteService().queryAll(
        'processText',
        columns: ['number'],
      );

      final senderTargets = <String>{'MPESA'};

      for (final row in processRows) {
        final raw = (row['number'] ?? '').toString().trim();
        final digits = raw.replaceAll(RegExp(r'\D'), '');
        if (digits.isEmpty) continue;

        // Requested: add 254 prefix when searching
        if (digits.startsWith('254') && digits.length >= 12) {
          senderTargets.add(digits);
          senderTargets.add('+$digits');
        } else if (digits.startsWith('0') && digits.length >= 10) {
          senderTargets.add('254${digits.substring(1)}');
          senderTargets.add(digits);
        } else if (digits.length == 9) {
          senderTargets.add('254$digits');
          senderTargets.add('0$digits');
        } else {
          senderTargets.add(digits);
        }
      }

      SmsFilter smsFilter =
      SmsFilter.where(SmsColumn.ADDRESS).equals(senderTargets.first);
      final rest = senderTargets.skip(1).toList();
      for (final sender in rest) {
        smsFilter = smsFilter.or(SmsColumn.ADDRESS).equals(sender);
      }

      final sms = await telephony.getInboxSms(
        columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
        filter: smsFilter
            .and(SmsColumn.DATE)
            .greaterThanOrEqualTo(_start.millisecondsSinceEpoch.toString())
            .and(SmsColumn.BODY)
            .like('%received%'),
        sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
      );

      final messagesInRange = sms.where((m) {
        final d = m.date ?? 0;
        return d >= _start.millisecondsSinceEpoch &&
            d <= _end.millisecondsSinceEpoch;
      }).toList();

      final txRows = await SQLiteService().queryCustom(
        'transactions',
        'timeStamp >= ? AND timeStamp <= ?',
        [_start.millisecondsSinceEpoch, _end.millisecondsSinceEpoch],
        columns: [
          'id',
          'transactionId',
          'number',
          'amount',
          'status',
          'timeStamp',
          'initialMessage',
        ],
        orderBy: 'timeStamp DESC',
      );

      final byTxId = <String, List<Map<String, dynamic>>>{};
      for (final tx in txRows) {
        final id = (tx['transactionId'] ?? '').toString().trim().toUpperCase();
        if (id.isEmpty) continue;
        byTxId.putIfAbsent(id, () => []).add(tx);
      }

      final mapped = <_MappedItem>[];
      for (final m in messagesInRange) {
        final code = getMpesaCode(m.body ?? '').trim().toUpperCase();
        Map<String, dynamic>? matched;
        if (code.isNotEmpty && byTxId.containsKey(code)) {
          matched = byTxId[code]!.first;
        }
        mapped.add(_MappedItem(sms: m, code: code, transaction: matched));
      }

      // Red/unprocessed first, then newest first
      mapped.sort((a, b) {
        if (a.unmatched != b.unmatched) return a.unmatched ? -1 : 1;
        return (b.sms.date ?? 0).compareTo(a.sms.date ?? 0);
      });

      if (!mounted) return;
      setState(() {
        _items = mapped;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _retryOne(_MappedItem item) async {
    final body = item.sms.body ?? '';
    if (body.isEmpty) return;

    await TransactionController().makeTransactionGivenSmsBody(
      body,
      address: item.sms.address,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Retried message')),
    );
  }

  Future<void> _retryAllUnprocessed() async {
    final unprocessed = _items.where((e) => e.unmatched).toList();
    if (unprocessed.isEmpty || _retryingAll) return;

    setState(() => _retryingAll = true);
    try {
      for (final item in unprocessed) {
        final body = item.sms.body ?? '';
        if (body.isEmpty) continue;
        await TransactionController().makeTransactionGivenSmsBody(
          body,
          address: item.sms.address,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Retried ${unprocessed.length} unprocessed')),
      );
      await _reload();
    } finally {
      if (mounted) setState(() => _retryingAll = false);
    }
  }


  Future<void> _pickDateTime({
    required bool isStart,
  }) async {
    final current = isStart ? _start : _end;
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2015, 1),
      lastDate: DateTime(2101, 1),
    );
    if (pickedDate == null) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (pickedTime == null) return;

    final combined = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    setState(() {
      if (isStart) {
        _start = combined;
        if (_start.isAfter(_end)) _end = _start.add(const Duration(minutes: 1));
      } else {
        _end = combined;
        if (_end.isBefore(_start)) _start = _end.subtract(const Duration(minutes: 1));
      }
    });

    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Confirm transactions')),
      body: Column(
        children: [
          Padding(
            padding: kPagePaddingInsets,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => _pickDateTime(isStart: true),
                  child: Text('From: ${getNormalDate(_start)} ${getNormalTime(_start)}'),
                ),
                OutlinedButton(
                  onPressed: () => _pickDateTime(isStart: false),
                  child: Text('To: ${getNormalDate(_end)} ${getNormalTime(_end)}'),
                ),
                FilledButton.icon(
                  onPressed: (_loading || _retryingAll || _items.where((e) => e.unmatched).isEmpty)
                      ? null
                      : _retryAllUnprocessed,
                  icon: _retryingAll
                      ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Icon(Icons.refresh),
                  label: Text('Retry all unprocessed (${_items.where((e) => e.unmatched).length})'),
                ),
                FilledButton(
                  onPressed: _reload,
                  child: const Text('Refresh'),
                ),
              ],
            ),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: ListView.separated(
                padding: kPagePaddingInsets,
                itemCount: _items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final item = _items[i];
                  final unmatched = item.transaction == null;

                  return Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: unmatched ? Colors.red : Colors.transparent,
                        width: unmatched ? 1.8 : 0,
                      ),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Code: ${item.code.isEmpty ? "N/A" : item.code}',
                                style: const TextStyle(fontWeight: FontWeight.bold)),

                            Align(
                              alignment: Alignment.centerRight,
                              child: OutlinedButton.icon(
                                onPressed: () => _retryOne(item),
                                icon: const Icon(Icons.refresh),
                                label: const Text('Retry'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(item.sms.body ?? ''),
                        const SizedBox(height: 8),
                        Text(
                          item.transaction == null
                              ? 'No coupled transaction'
                              : 'Matched tx #${item.transaction!['id']} | ${item.transaction!['status']} | Ksh ${item.transaction!['amount']}',
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _MappedItem {
  final SmsMessage sms;
  final String code;
  final Map<String, dynamic>? transaction;

  bool get unmatched => transaction == null;

  _MappedItem({
    required this.sms,
    required this.code,
    required this.transaction,
  });
}
