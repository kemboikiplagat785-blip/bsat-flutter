import 'package:another_telephony/telephony.dart';
import 'package:bsat/services/sms_sevice.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:bsat/utils/date_ops.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:bsat/controllers/transaction_controller.dart';
import 'package:flutter/services.dart';

class ConfirmTransactionsPage extends StatefulWidget {
  const ConfirmTransactionsPage({super.key});

  @override
  State<ConfirmTransactionsPage> createState() =>
      _ConfirmTransactionsPageState();
}

class _ConfirmTransactionsPageState extends State<ConfirmTransactionsPage> {
  DateTime _start = DateTime.now().subtract(const Duration(hours: 6));
  DateTime _end = DateTime.now();

  /// When false, [_end] follows the current time on every reload so new
  /// messages and freshly retried transactions are picked up.
  bool _endPinned = false;
  bool _retryingAll = false;

  bool _loading = true;
  String? _error;
  List<_MappedItem> _items = [];

  /// Message keys currently being retried, to block double taps.
  final Set<String> _retrying = {};

  static const int _sqlChunkSize = 500;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  static bool _isReceivedMessage(String body) =>
      body.toLowerCase().contains('received');

  Future<Set<String>> _senderTargets() async {
    final processRows = await SQLiteService().queryAll(
      'processText',
      columns: ['number'],
    );

    final senderTargets = <String>{'MPESA'};
    for (final row in processRows) {
      final raw = (row['number'] ?? '').toString().trim();
      final digits = raw.replaceAll(RegExp(r'\D'), '');
      if (digits.isEmpty) continue;

      if (digits.startsWith('254') && digits.length >= 12) {
        senderTargets.add(digits);
        senderTargets.add('+$digits');
        senderTargets.add('0${digits.substring(3)}');
      } else if (digits.startsWith('0') && digits.length >= 10) {
        senderTargets.add('254${digits.substring(1)}');
        senderTargets.add('+254${digits.substring(1)}');
        senderTargets.add(digits);
      } else if (digits.length == 9) {
        senderTargets.add('254$digits');
        senderTargets.add('+254$digits');
        senderTargets.add('0$digits');
      } else {
        senderTargets.add(digits);
      }
    }
    return senderTargets;
  }

  /// Queries the inbox once per sender. The telephony filter builder joins
  /// conditions without parentheses (and its `inValues` binds the whole list
  /// as one argument), so an OR-chain of senders followed by AND date/body
  /// would only apply the date and body conditions to the last sender.
  Future<List<SmsMessage>> _fetchMessages(Set<String> senders) async {
    final startMs = _start.millisecondsSinceEpoch.toString();
    final endMs = _end.millisecondsSinceEpoch.toString();

    final results = await Future.wait(senders.map(
      (sender) => telephony.getInboxSms(
        columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
        filter: SmsFilter.where(SmsColumn.ADDRESS)
            .equals(sender)
            .and(SmsColumn.DATE)
            .greaterThanOrEqualTo(startMs)
            .and(SmsColumn.DATE)
            .lessThanOrEqualTo(endMs)
            .and(SmsColumn.BODY)
            .like('%received%'),
        sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
      ),
    ));

    return results
        .expand((list) => list)
        .where((m) => _isReceivedMessage(m.body ?? ''))
        .toList();
  }

  /// Looks up transactions by M-PESA code regardless of when they were
  /// processed. Filtering transactions by `timeStamp` (processing time) while
  /// filtering SMS by arrival time made processed messages look unprocessed.
  Future<Map<String, Map<String, dynamic>>> _transactionsByCode(
    Iterable<String> codes,
  ) async {
    final unique = codes.where((c) => c.isNotEmpty).toSet().toList();
    final byCode = <String, Map<String, dynamic>>{};

    for (var i = 0; i < unique.length; i += _sqlChunkSize) {
      final end = (i + _sqlChunkSize) < unique.length
          ? i + _sqlChunkSize
          : unique.length;
      final chunk = unique.sublist(i, end);
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await SQLiteService().queryCustom(
        'transactions',
        'UPPER(TRIM(transactionId)) IN ($placeholders)',
        chunk,
        columns: ['id', 'transactionId', 'number', 'amount', 'status'],
        orderBy: 'id ASC',
      );
      for (final tx in rows) {
        final id = (tx['transactionId'] ?? '').toString().trim().toUpperCase();
        if (id.isEmpty) continue;
        byCode.putIfAbsent(id, () => tx);
      }
    }
    return byCode;
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
      if (!_endPinned) _end = DateTime.now();
    });

    try {
      final senders = await _senderTargets();
      final messages = await _fetchMessages(senders);

      final codes = [
        for (final m in messages)
          getMpesaCode(m.body ?? '').trim().toUpperCase(),
      ];
      final byCode = await _transactionsByCode(codes);

      final mapped = <_MappedItem>[];
      for (var i = 0; i < messages.length; i++) {
        final code = codes[i];
        mapped.add(_MappedItem(
          sms: messages[i],
          code: code,
          transaction: code.isEmpty ? null : byCode[code],
        ));
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
    } catch (e, st) {
      debugPrint('Check transactions reload failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load messages: $e';
      });
    }
  }

  /// Re-checks the database right before dispatching so a message that was
  /// processed in the meantime is never sent twice. The receipt-claim guard in
  /// TransactionController only covers messages whose sender is "MPESA", not
  /// messages from forwarding numbers.
  Future<bool> _alreadyProcessed(_MappedItem item) async {
    if (item.code.isEmpty) return false;
    final existing = await _transactionsByCode([item.code]);
    return existing.containsKey(item.code);
  }

  /// Returns true if the message was dispatched, false if it was skipped.
  Future<bool> _dispatch(_MappedItem item) async {
    final body = item.sms.body ?? '';
    if (body.isEmpty) return false;
    if (!_retrying.add(item.key)) return false;
    try {
      if (await _alreadyProcessed(item)) return false;
      debugPrint('Retrying message: ${item.sms.address} | $body');
      await TransactionController().makeTransactionGivenSmsBody(
        body,
        address: item.sms.address,
      );
      return true;
    } finally {
      _retrying.remove(item.key);
    }
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _retryOne(_MappedItem item) async {
    if (_retrying.contains(item.key) || _retryingAll) return;
    setState(() {}); // show the item as busy
    try {
      final sent = await _dispatch(item);
      _showSnack(
          sent ? 'Message processed' : 'Already processed, not sent again');
    } catch (e) {
      _showSnack('Retry failed: $e');
    }
    if (mounted) await _reload();
  }

  Future<void> _retryAllUnprocessed() async {
    final unprocessed = _items.where((e) => e.unmatched).toList();
    if (unprocessed.isEmpty || _retryingAll) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Process unprocessed messages?'),
        content: Text(
          'This will process ${unprocessed.length} message(s) now and send '
          'the purchases to the customers.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Process'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _retryingAll = true);
    var sent = 0;
    var skipped = 0;
    var failed = 0;
    try {
      for (final item in unprocessed) {
        try {
          if (await _dispatch(item)) {
            sent++;
          } else {
            skipped++;
          }
        } catch (e) {
          failed++;
          debugPrint('Retry failed for ${item.code}: $e');
        }
      }
      _showSnack(
        'Processed $sent'
        '${skipped > 0 ? ', skipped $skipped already processed' : ''}'
        '${failed > 0 ? ', $failed failed' : ''}',
      );
    } finally {
      if (mounted) setState(() => _retryingAll = false);
    }
    if (mounted) await _reload();
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
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (pickedTime == null || !mounted) return;

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
        if (_start.isAfter(_end)) {
          _end = _start.add(const Duration(minutes: 1));
          _endPinned = true;
        }
      } else {
        _end = combined;
        _endPinned = true;
        if (_end.isBefore(_start)) {
          _start = _end.subtract(const Duration(minutes: 1));
        }
      }
    });

    await _reload();
  }

  void _unpinEnd() {
    setState(() => _endPinned = false);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final unprocessedCount = _items.where((e) => e.unmatched).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Check transactions')),
      body: Column(
        children: [
          Padding(
            padding: kPagePaddingInsets,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: () => _pickDateTime(isStart: true),
                  child: Text(
                      'From: ${getNormalDate(_start)} ${getNormalTime(_start)}'),
                ),
                OutlinedButton(
                  onPressed: () => _pickDateTime(isStart: false),
                  child: Text(_endPinned
                      ? 'To: ${getNormalDate(_end)} ${getNormalTime(_end)}'
                      : 'To: Now'),
                ),
                if (_endPinned)
                  IconButton(
                    tooltip: 'Set end time to now',
                    onPressed: _loading ? null : _unpinEnd,
                    icon: const Icon(Icons.close),
                  ),
                FilledButton.icon(
                  onPressed: (_loading || _retryingAll || unprocessedCount == 0)
                      ? null
                      : _retryAllUnprocessed,
                  icon: _retryingAll
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: Text('Retry all unprocessed ($unprocessedCount)'),
                ),
                FilledButton(
                  onPressed: (_loading || _retryingAll) ? null : _reload,
                  child: const Text('Refresh'),
                ),
              ],
            ),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: kPagePaddingInsets,
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ),
            )
          else if (_items.isEmpty)
            const Expanded(
              child: Center(
                child: Text('No received messages in this period'),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: kPagePaddingInsets,
                itemCount: _items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final item = _items[i];
                  final unmatched = item.unmatched;
                  final busy = _retrying.contains(item.key);

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
                            Text(
                                'Code: ${item.code.isEmpty ? "N/A" : item.code}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            Row(
                              children: [
                                // Only unprocessed messages can be retried;
                                // retrying a processed one would resend it.
                                if (unmatched)
                                  busy
                                      ? const Padding(
                                          padding: EdgeInsets.all(12),
                                          child: SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2),
                                          ),
                                        )
                                      : IconButton(
                                          tooltip: 'Process this message',
                                          onPressed: _retryingAll
                                              ? null
                                              : () => _retryOne(item),
                                          icon: const Icon(
                                              CupertinoIcons.refresh),
                                        ),
                                IconButton(
                                  tooltip: 'Copy message',
                                  onPressed: () {
                                    final body = item.sms.body ?? '';
                                    if (body.isEmpty) return;
                                    Clipboard.setData(
                                        ClipboardData(text: body));
                                    _showSnack('Copied message to clipboard');
                                  },
                                  icon: const Icon(CupertinoIcons.doc),
                                ),
                              ],
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

  /// Identifies the message for in-flight retry tracking.
  String get key =>
      code.isNotEmpty ? code : '${sms.address}|${sms.date}|${sms.body}';

  _MappedItem({
    required this.sms,
    required this.code,
    required this.transaction,
  });
}
