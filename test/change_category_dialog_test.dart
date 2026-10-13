import 'package:bsat/components/dialogs/change_category_dialog.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets(
      'forwarded pending and successful options return canonical statuses',
      (tester) async {
    String? selectedStatus;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              selectedStatus = await showChangeCategoryDialog(context);
            },
            child: const Text('Open categories'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open categories'));
    await tester.pumpAndSettle();
    expect(find.text('Forwarded (Pending)'), findsOneWidget);
    expect(find.text('Forwarded (Successful)'), findsOneWidget);

    await tester.tap(find.text('Forwarded (Pending)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ok'));
    await tester.pumpAndSettle();
    expect(selectedStatus, TransactionStatuses.forwardedPending);

    await tester.tap(find.text('Open categories'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forwarded (Successful)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ok'));
    await tester.pumpAndSettle();
    expect(selectedStatus, TransactionStatuses.forwardedConfirmed);
  });

  test('single and bulk category persistence changes only selected rows',
      () async {
    final db = await SQLiteService().database;
    final marker =
        'manual-forward-category-${DateTime.now().microsecondsSinceEpoch}';
    final ids = <int>[];
    try {
      for (var index = 0; index < 3; index++) {
        ids.add(await db.insert('transactions', {
          'status': TransactionStatuses.done,
          'transactionId': '$marker-$index',
          'forwardingJobId': 'preserve-job-$index',
          'forwardingRecipientDeviceName': 'preserve-recipient-$index',
          'timeStamp': DateTime.now().millisecondsSinceEpoch,
        }));
      }

      await SQLiteService().updateStuff(
        {'status': TransactionStatuses.forwardedPending},
        'id = ?',
        [ids[0]],
        'transactions',
      );
      await SQLiteService().updateStuff(
        {'status': TransactionStatuses.forwardedConfirmed},
        'id IN (?, ?)',
        [ids[1], ids[2]],
        'transactions',
      );

      final rows = await db.query(
        'transactions',
        where: 'id IN (?, ?, ?)',
        whereArgs: ids,
        orderBy: 'id ASC',
      );
      expect(rows.map((row) => row['status']), [
        TransactionStatuses.forwardedPending,
        TransactionStatuses.forwardedConfirmed,
        TransactionStatuses.forwardedConfirmed,
      ]);
      expect(rows.map((row) => row['forwardingJobId']), [
        'preserve-job-0',
        'preserve-job-1',
        'preserve-job-2',
      ]);
      expect(rows.map((row) => row['forwardingRecipientDeviceName']), [
        'preserve-recipient-0',
        'preserve-recipient-1',
        'preserve-recipient-2',
      ]);
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
