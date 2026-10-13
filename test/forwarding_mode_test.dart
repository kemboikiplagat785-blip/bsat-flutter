import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:bsat/utils/forwarding_mode.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('offline SMS handoff maps only successful handoffs to plain forwarded',
      () {
    expect(offlineForwardingStatusForHandoff('Sent'),
        TransactionStatuses.forwarded);
    expect(offlineForwardingStatusForHandoff('Already sent'),
        TransactionStatuses.forwarded);
    expect(offlineForwardingStatusForHandoff('Failed'), isNull);
    expect(offlineForwardingStatusForHandoff(''), isNull);
    expect(offlineForwardingStatusForHandoff('Sent'),
        isNot(TransactionStatuses.forwardedPending));
    expect(offlineForwardingStatusForHandoff('Sent'),
        isNot(TransactionStatuses.forwardedConfirmed));
  });

  test('exact plain forwarded category excludes online forwarding statuses',
      () async {
    final db = await SQLiteService().database;
    final marker = 'forwarding-category-${DateTime.now().microsecondsSinceEpoch}';
    final ids = <int>[];
    try {
      for (final status in [
        TransactionStatuses.forwarded,
        TransactionStatuses.forwardedPending,
        TransactionStatuses.forwardedConfirmed,
        TransactionStatuses.forwardedOnline,
        TransactionStatuses.forwarded,
      ]) {
        final isLegacyOnlineMarker = status == TransactionStatuses.forwarded &&
            ids.isNotEmpty;
        ids.add(await db.insert('transactions', {
          'status': status,
          'transactionId': '$marker-${ids.length}',
          if (isLegacyOnlineMarker) ...{
            'forwardingJobId': '$marker-job',
            'forwardingRecipientDeviceName': 'Destination phone',
          },
          'timeStamp': DateTime.now().millisecondsSinceEpoch,
        }));
      }

      final rows = await SQLiteService().queryCustom(
        'transactions',
        "status = ? AND forwardingJobId IS NULL AND "
            "COALESCE(forwardingRecipientDeviceName, '') = ''",
        [TransactionStatuses.forwarded],
        columns: ['id', 'status'],
      );
      final matchingRows = rows.where((row) => ids.contains(row['id']));
      expect(matchingRows.map((row) => row['status']),
          [TransactionStatuses.forwarded]);
    } finally {
      if (ids.isNotEmpty) {
        await db.delete(
          'transactions',
          where: 'id IN (${List.filled(ids.length, '?').join(',')})',
          whereArgs: ids,
        );
      }
    }
  });
}
