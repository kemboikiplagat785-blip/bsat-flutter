import 'dart:io';

import 'package:bsat/controllers/transaction_controller.dart';
import 'package:bsat/models/transaction_message.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:bsat/utils/transaction_execution_safety.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfi;
  });

  final sqlite = SQLiteService();

  test('parses the three Safaricom message families by meaning', () {
    final submitted = SafaricomTransactionEvidence.parse(
      'Recommendation for 0712345678 submitted successfully',
    );
    final recommended = SafaricomTransactionEvidence.parse(
      'You have successfully recommended offer to 0712345678',
    );
    final purchased = SafaricomTransactionEvidence.parse(
      'Thank you for choosing Safaricom. You have purchased a gift bundle '
      'worth Ksh 50 for 0712345678. Continue ...',
    );

    expect(submitted?.targetStatus, TransactionStatuses.successfulPending);
    expect(submitted?.recipientNumber, '0712345678');
    expect(
      recommended?.targetStatus,
      TransactionStatuses.doneConfirmed,
    );
    expect(purchased?.targetStatus, TransactionStatuses.doneConfirmed);
    expect(
      SafaricomTransactionEvidence.parse(
        'The transaction was successfully started for 0712345678',
      ),
      isNull,
    );
    expect(
      isAmbiguousTransactionOutcome(
        status: TransactionStatuses.error,
        reply: 'Error sending code: timeout',
      ),
      isTrue,
    );
    expect(
      isAmbiguousTransactionOutcome(
        status: TransactionStatuses.error,
        reply: 'Recommendation failed for 0712345678',
      ),
      isFalse,
    );
  });

  test('does not select an arbitrary Safaricom transaction match', () {
    expect(
      uniqueSafaricomTransactionCandidate([
        {'id': 1},
      ])?['id'],
      1,
    );
    expect(uniqueSafaricomTransactionCandidate(const []), isNull);
    expect(
      uniqueSafaricomTransactionCandidate([
        {'id': 1},
        {'id': 2},
      ]),
      isNull,
    );
  });

  test('unresolved Safaricom messages are durable and deduplicated', () async {
    final db = await sqlite.database;
    const message = 'Recommendation for 0712345678 submitted successfully';
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final firstTransactionId =
        await _insertTransaction(sqlite, TransactionStatuses.error);
    final secondTransactionId =
        await _insertTransaction(sqlite, TransactionStatuses.secondAttempt);
    addTearDown(() async {
      await _deleteTransaction(sqlite, firstTransactionId);
      await _deleteTransaction(sqlite, secondTransactionId);
      await db.delete(
        'safaricomTransactionMessages',
        where: 'smsTimestamp = ? AND body = ?',
        whereArgs: [timestamp, message],
      );
    });
    await sqlite.recordUnresolvedSafaricomMessage(
      body: message,
      smsTimestamp: timestamp,
    );
    await sqlite.recordUnresolvedSafaricomMessage(
      body: message,
      smsTimestamp: timestamp,
    );

    final unresolved = await sqlite.getUnresolvedSafaricomMessages();
    final saved = unresolved.where((row) => row['body'] == message).toList();
    expect(saved, hasLength(1));
    expect(saved.single['smsTimestamp'], timestamp);
    expect(await sqlite.claimTransactionRetry(firstTransactionId), 1);
    expect(
        await sqlite
            .releaseUndispatchedTransactionRetryClaim(firstTransactionId),
        1);
    expect(await sqlite.claimTransactionRetry(secondTransactionId), 1);
    expect(
        await sqlite
            .releaseUndispatchedTransactionRetryClaim(secondTransactionId),
        1);

    await sqlite.resolveSafaricomMessage(
      body: message,
      smsTimestamp: timestamp,
    );
    final afterResolution = await sqlite.getUnresolvedSafaricomMessages();
    expect(afterResolution.where((row) => row['body'] == message), isEmpty);
    expect(await sqlite.claimTransactionRetry(firstTransactionId), 1);
  });

  test('unresolved evidence is replayed after a unique safe match appears',
      () async {
    final db = await sqlite.database;
    const message = 'Recommendation for 0712345678 submitted successfully';
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final firstId = await _insertTransaction(sqlite, TransactionStatuses.error);
    final secondId =
        await _insertTransaction(sqlite, TransactionStatuses.error);
    addTearDown(() async {
      await _deleteTransaction(sqlite, firstId);
      await _deleteTransaction(sqlite, secondId);
      await db.delete(
        'safaricomTransactionMessages',
        where: 'smsTimestamp = ? AND body = ?',
        whereArgs: [timestamp, message],
      );
    });

    await sqlite.recordUnresolvedSafaricomMessage(
      body: message,
      smsTimestamp: timestamp,
    );
    await TransactionController().updateWithMessage(
      TransactionMessage(body: message, date: timestamp),
      retryUnresolvedMessages: false,
      notifyReplies: false,
    );
    expect((await _readTransaction(sqlite, firstId))['status'],
        TransactionStatuses.error);
    expect((await _readTransaction(sqlite, secondId))['status'],
        TransactionStatuses.error);

    await _deleteTransaction(sqlite, secondId);
    await TransactionController().updateWithMessage(
      TransactionMessage(body: message, date: timestamp),
      retryUnresolvedMessages: false,
      notifyReplies: false,
    );
    expect((await _readTransaction(sqlite, firstId))['status'],
        TransactionStatuses.successfulPending);
    expect(
      (await sqlite.getUnresolvedSafaricomMessages()).where(
        (message) =>
            message['smsTimestamp'] == timestamp &&
            message['body'] ==
                'Recommendation for 0712345678 submitted successfully',
      ),
      isEmpty,
    );
  });

  test('submission evidence reconciles errors and second attempts as pending',
      () async {
    for (final oldStatus in [
      TransactionStatuses.error,
      TransactionStatuses.secondAttempt,
    ]) {
      final id = await _insertTransaction(sqlite, oldStatus);
      addTearDown(() => _deleteTransaction(sqlite, id));
      const message = 'Recommendation for 0712345678 submitted successfully';

      expect(
        await sqlite.reconcileSafaricomTransaction(
          transactionId: id,
          targetStatus: TransactionStatuses.successfulPending,
          message: message,
        ),
        1,
      );
      final row = await _readTransaction(sqlite, id);
      expect(row['status'], TransactionStatuses.successfulPending);
      expect(row['canRetry'], 0);
      expect(row['retryState'], 'blocked');
      expect(row['ussdReply'], contains(message));
      expect(row['status'], isNot(TransactionStatuses.doneConfirmed));

      await sqlite.reconcileSafaricomTransaction(
        transactionId: id,
        targetStatus: TransactionStatuses.successfulPending,
        message: message,
      );
      final repeated =
          (await _readTransaction(sqlite, id))['ussdReply'] as String;
      expect(repeated.split(message), hasLength(2));
      expect(repeated, contains('original USSD result'));
    }
  });

  test(
      'both definitive message families confirm error, second attempt, and pending',
      () async {
    const messages = [
      'You have successfully recommended offer to 0712345678',
      'Thank you for choosing Safaricom. You have purchased a gift bundle '
          'worth Ksh 50 for 0712345678. Continue ...',
    ];
    for (final oldStatus in [
      TransactionStatuses.error,
      TransactionStatuses.secondAttempt,
      TransactionStatuses.successfulPending,
    ]) {
      for (final message in messages) {
        final id = await _insertTransaction(sqlite, oldStatus);
        addTearDown(() => _deleteTransaction(sqlite, id));
        expect(
          await sqlite.reconcileSafaricomTransaction(
            transactionId: id,
            targetStatus: TransactionStatuses.doneConfirmed,
            message: message,
          ),
          1,
        );
        final row = await _readTransaction(sqlite, id);
        expect(row['status'], TransactionStatuses.doneConfirmed);
        expect(row['canRetry'], 0);
        expect(row['retryState'], 'blocked');
        expect(row['ussdReply'], contains(message));
      }
    }
  });

  test('pending evidence cannot downgrade confirmation or duplicate history',
      () async {
    final id = await _insertTransaction(
      sqlite,
      TransactionStatuses.doneConfirmed,
      reply: 'confirmed message',
      canRetry: 0,
    );
    addTearDown(() => _deleteTransaction(sqlite, id));

    expect(
      await sqlite.reconcileSafaricomTransaction(
        transactionId: id,
        targetStatus: TransactionStatuses.successfulPending,
        message: 'Recommendation for 0712345678 submitted successfully',
      ),
      0,
    );
    final row = await _readTransaction(sqlite, id);
    expect(row['status'], TransactionStatuses.doneConfirmed);
    expect(row['ussdReply'], 'confirmed message');
    expect(row['canRetry'], 0);
  });

  test('retry dispatch claim is atomic across concurrent workers', () async {
    final id = await _insertTransaction(sqlite, TransactionStatuses.error);
    addTearDown(() => _deleteTransaction(sqlite, id));
    await (await sqlite.database).update(
      'transactions',
      {'retryState': 'ambiguous'},
      where: 'id = ?',
      whereArgs: [id],
    );

    final claims = await Future.wait(
      List.generate(8, (_) => sqlite.claimTransactionRetry(id)),
    );
    expect(claims.where((count) => count == 1), hasLength(1));
    expect((await _readTransaction(sqlite, id))['retryState'], 'claimed');
  });

  test('pre-dispatch recheck blocks newly pending and confirmed evidence',
      () async {
    for (final status in [
      TransactionStatuses.successfulPending,
      TransactionStatuses.doneConfirmed,
    ]) {
      final id = await _insertTransaction(sqlite, TransactionStatuses.error);
      addTearDown(() => _deleteTransaction(sqlite, id));
      expect(await sqlite.claimTransactionRetry(id), 1);
      await sqlite.reconcileSafaricomTransaction(
        transactionId: id,
        targetStatus: status,
        message: 'Safaricom evidence $status',
      );
      expect(await sqlite.beginTransactionRetryDispatch(id), 0);
      final row = await _readTransaction(sqlite, id);
      expect(row['status'], status);
      expect(row['ussdReply'], contains('Safaricom evidence'));
    }
  });

  test('restart releases only claims known not to have reached dispatch',
      () async {
    final unstartedId =
        await _insertTransaction(sqlite, TransactionStatuses.error);
    final startedId =
        await _insertTransaction(sqlite, TransactionStatuses.error);
    addTearDown(() async {
      await _deleteTransaction(sqlite, unstartedId);
      await _deleteTransaction(sqlite, startedId);
    });
    expect(await sqlite.claimTransactionRetry(unstartedId), 1);
    expect(await sqlite.claimTransactionRetry(startedId), 1);
    expect(await sqlite.beginTransactionRetryDispatch(startedId), 1);

    await sqlite.recoverAbandonedTransactionRetryClaims(await sqlite.database);

    expect(
        (await _readTransaction(sqlite, unstartedId))['retryState'], 'ready');
    expect(await sqlite.claimTransactionRetry(unstartedId), 1);
    expect((await _readTransaction(sqlite, startedId))['retryState'],
        'dispatching');
    expect(await sqlite.claimTransactionRetry(startedId), 0);
  });

  test('stale pause cannot replace pending or confirmed evidence', () async {
    for (final status in [
      TransactionStatuses.successfulPending,
      TransactionStatuses.doneConfirmed,
    ]) {
      final id = await _insertTransaction(sqlite, TransactionStatuses.error);
      addTearDown(() => _deleteTransaction(sqlite, id));
      await sqlite.reconcileSafaricomTransaction(
        transactionId: id,
        targetStatus: status,
        message: 'Safaricom evidence $status',
      );
      expect(
        await sqlite.updateRetryTransactionIfEligible(
          id,
          {
            'status': TransactionStatuses.paused,
            'ussdReply': 'Offer window closed',
          },
        ),
        0,
      );
      final row = await _readTransaction(sqlite, id);
      expect(row['status'], status);
      expect(row['ussdReply'], contains('Safaricom evidence'));
    }
  });

  test('repeated confirmation and out-of-order submission are idempotent',
      () async {
    final id = await _insertTransaction(sqlite, TransactionStatuses.error);
    addTearDown(() => _deleteTransaction(sqlite, id));
    const confirmation =
        'You have successfully recommended offer to 0712345678';
    for (var i = 0; i < 2; i++) {
      expect(
        await sqlite.reconcileSafaricomTransaction(
          transactionId: id,
          targetStatus: TransactionStatuses.doneConfirmed,
          message: confirmation,
        ),
        1,
      );
    }
    expect(
      await sqlite.reconcileSafaricomTransaction(
        transactionId: id,
        targetStatus: TransactionStatuses.successfulPending,
        message: 'Recommendation for 0712345678 submitted successfully',
      ),
      0,
    );
    final row = await _readTransaction(sqlite, id);
    expect(row['status'], TransactionStatuses.doneConfirmed);
    expect((row['ussdReply'] as String).split(confirmation), hasLength(2));
  });

  test('replayed duplicate confirmation matches the already confirmed row',
      () async {
    final id = await _insertTransaction(sqlite, TransactionStatuses.error);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    addTearDown(() async {
      await _deleteTransaction(sqlite, id);
      await sqlite.deleteWhere(
        'safaricomTransactionMessages',
        'smsTimestamp = ?',
        [timestamp],
      );
    });
    const confirmation =
        'You have successfully recommended offer to 0712345678';
    final controller = TransactionController();
    final sms = TransactionMessage(body: confirmation, date: timestamp);
    await controller.updateWithMessage(
      sms,
      retryUnresolvedMessages: false,
      notifyReplies: false,
    );
    await controller.updateWithMessage(
      sms,
      retryUnresolvedMessages: false,
      notifyReplies: false,
    );

    final row = await _readTransaction(sqlite, id);
    expect(row['status'], TransactionStatuses.doneConfirmed);
    expect((row['ussdReply'] as String).split(confirmation), hasLength(2));
    expect(await sqlite.getUnresolvedSafaricomMessages(), isEmpty);
  });

  test('alternative result persistence cannot replace Safaricom evidence',
      () async {
    final id = await _insertTransaction(sqlite, TransactionStatuses.error);
    addTearDown(() => _deleteTransaction(sqlite, id));
    await sqlite.reconcileSafaricomTransaction(
      transactionId: id,
      targetStatus: TransactionStatuses.successfulPending,
      message: 'Recommendation for 0712345678 submitted successfully',
    );
    expect(
      await sqlite.updateTransactionUnlessSafaricomSuccess(
        id,
        {
          'status': TransactionStatuses.alternativeFailed,
          'ussdReply': 'Late alternative error',
        },
      ),
      0,
    );
    final row = await _readTransaction(sqlite, id);
    expect(row['status'], TransactionStatuses.successfulPending);
    expect(row['ussdReply'], contains('Recommendation for'));
  });

  test('stale transaction merge cannot discard confirmed Safaricom history',
      () async {
    final originalId = await _insertTransaction(
      sqlite,
      TransactionStatuses.doneConfirmed,
      reply: 'Definitive Safaricom confirmation',
      canRetry: 0,
    );
    final replacementId = await _insertTransaction(
      sqlite,
      TransactionStatuses.error,
      reply: 'Late USSD error',
    );
    addTearDown(() async {
      await _deleteTransaction(sqlite, originalId);
      await _deleteTransaction(sqlite, replacementId);
    });

    expect(
      await sqlite.mergeTransactionUnlessSafaricomSuccess(
        originalId,
        replacementId,
        {
          'id': originalId,
          'transactionId': 'MERGED',
          'number': 712345678,
          'amount': 50,
          'timeStamp': DateTime.now().millisecondsSinceEpoch,
          'status': TransactionStatuses.error,
          'ussdReply': 'Late USSD error',
          'canRetry': 3,
        },
      ),
      isFalse,
    );
    expect((await _readTransaction(sqlite, originalId))['ussdReply'],
        'Definitive Safaricom confirmation');
    expect((await _readTransaction(sqlite, replacementId))['status'],
        TransactionStatuses.error);
  });

  test('queued retry is blocked after pending or confirmed evidence', () async {
    for (final oldStatus in [
      TransactionStatuses.error,
      TransactionStatuses.secondAttempt,
    ]) {
      for (final targetStatus in [
        TransactionStatuses.successfulPending,
        TransactionStatuses.doneConfirmed,
      ]) {
        final id = await _insertTransaction(sqlite, oldStatus);
        addTearDown(() => _deleteTransaction(sqlite, id));
        expect(
          await sqlite.reconcileSafaricomTransaction(
            transactionId: id,
            targetStatus: targetStatus,
            message:
                'Safaricom evidence ${DateTime.now().microsecondsSinceEpoch}',
          ),
          1,
        );
        expect(await sqlite.claimTransactionRetry(id), 0);
      }
    }
  });

  test('transaction reconciliation leaves independent scheduled tasks intact',
      () async {
    final db = await sqlite.database;
    final id = await _insertTransaction(sqlite, TransactionStatuses.error);
    final taskId = await db.insert('tasks', {
      'code': '*180*0712345678#',
      'number': 712345678,
      'amount': 50,
      'duration': 3,
      'startDate': DateTime.now().millisecondsSinceEpoch,
      'nextTaskDate': DateTime.now().millisecondsSinceEpoch,
    });
    addTearDown(() async {
      await _deleteTransaction(sqlite, id);
      await db.delete('tasks', where: 'id = ?', whereArgs: [taskId]);
    });

    await sqlite.reconcileSafaricomTransaction(
      transactionId: id,
      targetStatus: TransactionStatuses.doneConfirmed,
      message: 'You have successfully recommended offer to 0712345678',
    );
    final tasks = await db.query('tasks', where: 'id = ?', whereArgs: [taskId]);
    expect(tasks, hasLength(1));
  });

  test('late retry error cannot replace a confirmation received in flight',
      () async {
    final id = await _insertTransaction(sqlite, TransactionStatuses.error);
    addTearDown(() => _deleteTransaction(sqlite, id));
    expect(await sqlite.claimTransactionRetry(id), 1);

    const confirmation =
        'You have successfully recommended offer to 0712345678';
    await sqlite.reconcileSafaricomTransaction(
      transactionId: id,
      targetStatus: TransactionStatuses.doneConfirmed,
      message: confirmation,
    );
    final completion = await sqlite.completeTransactionRetry(
      transactionId: id,
      resultStatus: TransactionStatuses.error,
      reply: 'Error sending code: timeout',
      ambiguousOutcome: true,
      fields: {'canRetry': 5},
    );

    expect(completion?['updated'], isFalse);
    final row = await _readTransaction(sqlite, id);
    expect(row['status'], TransactionStatuses.doneConfirmed);
    expect(row['retryState'], 'blocked');
    expect(row['canRetry'], 0);
    expect(row['ussdReply'], contains(confirmation));
    expect(row['ussdReply'], isNot(contains('Error sending code')));
  });

  test('ambiguous error outcomes remain eligible for repeated retry', () async {
    final retryableId = await _insertTransaction(
      sqlite,
      TransactionStatuses.error,
    );
    addTearDown(() => _deleteTransaction(sqlite, retryableId));
    expect(await sqlite.claimTransactionRetry(retryableId), 1);
    expect(await sqlite.beginTransactionRetryDispatch(retryableId), 1);
    final retryableCompletion = await sqlite.completeTransactionRetry(
      transactionId: retryableId,
      resultStatus: TransactionStatuses.error,
      reply: 'Recommendation failed for 0712345678',
      fields: {'canRetry': 3},
    );
    expect(retryableCompletion?['updated'], isTrue);
    expect(
        (await _readTransaction(sqlite, retryableId))['retryState'], 'ready');
    expect(await sqlite.claimTransactionRetry(retryableId), 1);

    final ambiguousId = await _insertTransaction(
      sqlite,
      TransactionStatuses.error,
    );
    addTearDown(() => _deleteTransaction(sqlite, ambiguousId));
    expect(await sqlite.claimTransactionRetry(ambiguousId), 1);
    expect(await sqlite.beginTransactionRetryDispatch(ambiguousId), 1);
    await sqlite.completeTransactionRetry(
      transactionId: ambiguousId,
      resultStatus: TransactionStatuses.error,
      reply: 'Error sending code: timeout',
      ambiguousOutcome: true,
      fields: {'canRetry': 3},
    );
    expect(
        (await _readTransaction(sqlite, ambiguousId))['retryState'], 'ready');
    expect(await sqlite.claimTransactionRetry(ambiguousId), 1);
  });

  test('automatic retry selection ignores error retry flags and ambiguity',
      () async {
    final eligibleId = await _insertTransaction(
      sqlite,
      TransactionStatuses.error,
      canRetry: 3,
    );
    final ambiguousId = await _insertTransaction(
      sqlite,
      TransactionStatuses.error,
      canRetry: 3,
    );
    final exhaustedId = await _insertTransaction(
      sqlite,
      TransactionStatuses.error,
      canRetry: 100,
    );
    addTearDown(() async {
      await _deleteTransaction(sqlite, eligibleId);
      await _deleteTransaction(sqlite, ambiguousId);
      await _deleteTransaction(sqlite, exhaustedId);
    });
    final db = await sqlite.database;
    await db.update(
      'transactions',
      {'retryState': 'ambiguous', 'ussdReply': 'Error sending code:'},
      where: 'id = ?',
      whereArgs: [ambiguousId],
    );

    final candidates = await sqlite.getAutomaticRetryCandidates(
      isAutoRetrying: true,
      retryLimit: 6,
      today: '2099-01-01',
    );
    final candidateIds = candidates.map((row) => row['id']).toSet();
    expect(candidateIds, contains(eligibleId));
    expect(candidateIds, contains(ambiguousId));
    expect(candidateIds, contains(exhaustedId));
  });

  test('version 21 upgrade preserves rows and startup recovery is conservative',
      () async {
    final temporaryDirectory =
        await Directory.systemTemp.createTemp('bsat-retry-upgrade-');
    final databasePath = path.join(temporaryDirectory.path, 'upgrade.db');
    final service = SQLiteService();
    final oldDb = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 21,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE transactions (
              id INTEGER PRIMARY KEY,
              transactionId TEXT,
              number INTEGER,
              amount INTEGER,
              timeStamp INTEGER,
              status TEXT,
              forwardingRecipientDeviceName TEXT,
              alternativeRequestCode TEXT,
              retryState TEXT NOT NULL DEFAULT 'ready',
              retryStartedAt INTEGER,
              ussdReply TEXT
            )
          ''');
          await db.insert('transactions', {
            'id': 1,
            'transactionId': 'OLD-READY',
            'number': 712345678,
            'amount': 50,
            'timeStamp': DateTime.now().millisecondsSinceEpoch,
            'status': TransactionStatuses.error,
            'retryState': 'claimed',
          });
          await db.insert('transactions', {
            'id': 2,
            'transactionId': 'OLD-UNKNOWN',
            'number': 712345678,
            'amount': 50,
            'timeStamp': DateTime.now().millisecondsSinceEpoch,
            'status': TransactionStatuses.error,
            'retryState': 'dispatching',
          });
        },
      ),
    );
    await oldDb.close();

    final upgraded = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 22,
        onUpgrade: service.onUpgrade,
      ),
    );
    try {
      expect(await upgraded.getVersion(), 22);
      await service.ensureCriticalSchema(upgraded);
      await service.recoverAbandonedTransactionRetryClaims(upgraded);
      final retryColumns = await upgraded.rawQuery(
        "PRAGMA table_info('transactions')",
      );
      expect(
        retryColumns.map((column) => column['name']),
        contains('retryClaimOwner'),
      );
      final rows = await upgraded.query('transactions', orderBy: 'id');
      expect(rows, hasLength(2));
      expect(rows[0]['transactionId'], 'OLD-READY');
      expect(rows[0]['retryState'], 'ready');
      expect(rows[1]['transactionId'], 'OLD-UNKNOWN');
      expect(rows[1]['retryState'], 'dispatching');
    } finally {
      await upgraded.close();
      await temporaryDirectory.delete(recursive: true);
    }
  });
}

Future<int> _insertTransaction(
  SQLiteService sqlite,
  String status, {
  String reply = 'original USSD result',
  int canRetry = 1,
}) async {
  final db = await sqlite.database;
  return db.insert('transactions', {
    'transactionId': 'SAF${DateTime.now().microsecondsSinceEpoch}',
    'number': 712345678,
    'amount': 50,
    'timeStamp': DateTime.now().millisecondsSinceEpoch,
    'status': status,
    'ussdReply': reply,
    'canRetry': canRetry,
    'retryState': 'ready',
  });
}

Future<Map<String, dynamic>> _readTransaction(
  SQLiteService sqlite,
  int id,
) async {
  final rows = await sqlite.queryCustom('transactions', 'id = ?', [id]);
  return rows.single;
}

Future<void> _deleteTransaction(SQLiteService sqlite, int id) async {
  await sqlite.deleteStuff(id, 'transactions');
}
