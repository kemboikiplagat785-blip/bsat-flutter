import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('alternative jobs advance only after first successful-pending result',
      () async {
    final db = await SQLiteService().database;
    final recipient =
        'Phone C queue test ${DateTime.now().microsecondsSinceEpoch}';
    final transactionIds = <int>[];

    try {
      for (var index = 1; index <= 4; index++) {
        transactionIds.add(
          await db.insert('transactions', {
            'status': TransactionStatuses.alternativeDeliveryPending,
            'forwardingJobId': 'queue-test-job-$index-$recipient',
            'forwardingRecipientDeviceName': recipient,
            'alternativeRequestCode': '*123#',
            'alternativeQueueState': 'waiting',
            'firstFailedTimeStamp': index,
            'timeStamp': index,
          }),
        );
      }

      Future<Map<String, dynamic>?> claim(int now) {
        return SQLiteService().claimNextAlternativeDelivery(
          recipientDeviceName: recipient,
          now: now,
          nextAttemptAt: now + 20000,
        );
      }

      final t1 = await claim(1000);
      expect(t1?['id'], transactionIds[0]);

      expect(await claim(1001), isNull);
      final retryT1 = await claim(21000);
      expect(retryT1?['id'], transactionIds[0]);

      await db.update(
        'transactions',
        {'status': TransactionStatuses.forwardedPending},
        where: 'id = ?',
        whereArgs: [transactionIds[0]],
      );
      expect(await claim(42001), isNull);

      await db.update(
        'transactions',
        {
          'status': TransactionStatuses.successfulPending,
          'alternativeQueueState': 'released',
        },
        where: 'id = ?',
        whereArgs: [transactionIds[0]],
      );
      final t2 = await claim(42002);
      expect(t2?['id'], transactionIds[1]);

      await db.update(
        'transactions',
        {'status': TransactionStatuses.doneConfirmed},
        where: 'id = ?',
        whereArgs: [transactionIds[0]],
      );
      expect(await claim(42003), isNull);
      final waitingT2 = await db.query(
        'transactions',
        columns: ['status', 'alternativeQueueState'],
        where: 'id = ?',
        whereArgs: [transactionIds[1]],
        limit: 1,
      );
      expect(waitingT2.single['status'],
          TransactionStatuses.alternativeDeliveryPending);
      expect(waitingT2.single['alternativeQueueState'], 'active');

      await db.update(
        'transactions',
        {
          'status': TransactionStatuses.successfulPending,
          'alternativeQueueState': 'released',
        },
        where: 'id = ?',
        whereArgs: [transactionIds[1]],
      );
      final t3 = await claim(42004);
      expect(t3?['id'], transactionIds[2]);

      await db.update(
        'transactions',
        {
          'status': TransactionStatuses.successfulPending,
          'alternativeQueueState': 'released',
        },
        where: 'id = ?',
        whereArgs: [transactionIds[2]],
      );
      final t4 = await claim(42005);
      expect(t4?['id'], transactionIds[3]);
    } finally {
      for (final id in transactionIds) {
        await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
      }
    }
  });
}
