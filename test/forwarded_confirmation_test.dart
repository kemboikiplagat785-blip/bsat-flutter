import 'dart:async';

import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:bsat/utils/forwarding_confirmation_retry.dart';
import 'package:bsat/utils/forwarding_display.dart';
import 'package:bsat/utils/forwarding_identifiers.dart';
import 'package:bsat/utils/forwarding_owner_id.dart';
import 'package:bsat/controllers/transaction_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const int forwardingConfirmationProtocolVersion =
    kForwardingConfirmationProtocolVersion;
const _originOwnerId = '11111111-1111-4111-8111-111111111111';
const _confirmationOwnerId = '22222222-2222-4222-8222-222222222222';
const _otherOriginOwnerId = '33333333-3333-4333-8333-333333333333';
const _otherConfirmationOwnerId = '44444444-4444-4444-8444-444444444444';

Future<void> _insertCompletedForwardedJob(
  Database db, {
  required String jobId,
  required String originOwnerId,
  required int localTransactionId,
}) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  await db.insert('forwardedSmsJobs', {
    'forwardingJobId': jobId,
    'protocolVersion': forwardingConfirmationProtocolVersion,
    'originOwnerId': originOwnerId,
    'localTransactionId': localTransactionId,
    'state': 'completed',
    'createdAt': now,
    'updatedAt': now,
  });
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SQLiteService sqlite;
  late Database testDatabase;

  setUp(() async {
    final schemaService = SQLiteService();
    testDatabase = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 23,
        onCreate: schemaService.onCreate,
      ),
    );
    await schemaService.ensureCriticalSchema(testDatabase);
    sqlite = SQLiteService(databaseOverride: testDatabase);
  });

  tearDown(() async {
    if (testDatabase.isOpen) await testDatabase.close();
  });

  test('transaction deletion atomically cancels only its confirmation job',
      () async {
    final db = await sqlite.database;
    final suffix = DateTime.now().microsecondsSinceEpoch;
    final deletedJob = 'delete-confirmation-$suffix';
    final retainedJob = 'retain-confirmation-$suffix';
    final deletedId = await db.insert('transactions', {
      'status': TransactionStatuses.forwardedPending,
      'forwardingJobId': deletedJob,
      'confirmationOwnerId': _confirmationOwnerId,
    });
    final retainedId = await db.insert('transactions', {
      'status': TransactionStatuses.forwardedPending,
      'forwardingJobId': retainedJob,
      'confirmationOwnerId': _confirmationOwnerId,
    });
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final jobId in [deletedJob, retainedJob]) {
      await db.insert('forwardedSmsJobs', {
        'forwardingJobId': jobId,
        'protocolVersion': forwardingConfirmationProtocolVersion,
        'originOwnerId': _originOwnerId,
        'localTransactionId': jobId == deletedJob ? deletedId : retainedId,
        'state': 'completed',
        'createdAt': now,
        'updatedAt': now,
      });
    }
    await sqlite.queueForwardingConfirmation(
      forwardingJobId: deletedJob,
      recipientDeviceName: 'paired-device',
      protocolVersion: forwardingConfirmationProtocolVersion,
      originOwnerId: _originOwnerId,
      confirmationOwnerId: _confirmationOwnerId,
      localTransactionId: deletedId,
      transactionId: deletedId.toString(),
    );
    await sqlite.queueForwardingConfirmation(
      forwardingJobId: retainedJob,
      recipientDeviceName: 'paired-device',
      protocolVersion: forwardingConfirmationProtocolVersion,
      originOwnerId: _originOwnerId,
      confirmationOwnerId: _confirmationOwnerId,
      localTransactionId: retainedId,
      transactionId: retainedId.toString(),
    );
    await db.insert('incomingReceiptClaims', {
      'receiptCode': 'receipt-$suffix',
      'localTransactionId': retainedId,
      'state': 'claimed',
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
    await db.insert('forwardingSubmissionClaims', {
      'forwardingJobId': deletedJob,
      'leaseExpiresAt': DateTime.now().millisecondsSinceEpoch + 60000,
    });

    try {
      final claimedAttempt = (await sqlite.claimDueForwardingConfirmation(
        forwardingJobId: deletedJob,
        now: DateTime.now().millisecondsSinceEpoch,
        leaseUntil: DateTime.now().millisecondsSinceEpoch + 120000,
      ))!;
      expect(claimedAttempt, 1);
      expect(
        await sqlite.isForwardingConfirmationAttemptActive(
          forwardingJobId: deletedJob,
          attempt: claimedAttempt,
          originOwnerId: _originOwnerId,
          confirmationOwnerId: _confirmationOwnerId,
          localTransactionId: deletedId,
        ),
        isTrue,
      );

      expect(
        await sqlite
            .deleteTransactions(where: 'id = ?', whereArgs: [deletedId]),
        1,
      );
      expect(await sqlite.getForwardingConfirmation(deletedJob), isNull);
      expect(
        await sqlite.isForwardingConfirmationAttemptActive(
          forwardingJobId: deletedJob,
          attempt: claimedAttempt,
          originOwnerId: _originOwnerId,
          confirmationOwnerId: _confirmationOwnerId,
          localTransactionId: deletedId,
        ),
        isFalse,
      );
      expect(
        await sqlite.claimDueForwardingConfirmation(
          forwardingJobId: deletedJob,
          now: DateTime.now().millisecondsSinceEpoch + 300000,
          leaseUntil: DateTime.now().millisecondsSinceEpoch + 420000,
        ),
        isNull,
      );

      // A worker holding the pre-deletion attempt cannot reschedule it, and
      // even an overlapping enqueue cannot recreate the canceled outbox row.
      await sqlite.scheduleForwardingConfirmationRetry(
        deletedJob,
        attempt: claimedAttempt,
        nextAttemptAt: DateTime.now().millisecondsSinceEpoch,
      );
      await sqlite.queueForwardingConfirmation(
        forwardingJobId: deletedJob,
        recipientDeviceName: 'paired-device',
        transactionId: deletedId.toString(),
      );
      expect(
        await sqlite.queueForwardingConfirmationIfAbsent(
          forwardingJobId: deletedJob,
          recipientDeviceName: 'paired-device',
        ),
        isFalse,
      );
      expect(await sqlite.getForwardingConfirmation(deletedJob), isNull);

      expect(await sqlite.getForwardingConfirmation(retainedJob), isNotNull);
      expect(
        await sqlite.claimDueForwardingConfirmation(
          forwardingJobId: retainedJob,
          now: DateTime.now().millisecondsSinceEpoch,
          leaseUntil: DateTime.now().millisecondsSinceEpoch + 120000,
        ),
        1,
      );
      expect(
        await db.query('forwardingSubmissionClaims',
            where: 'forwardingJobId = ?', whereArgs: [deletedJob]),
        hasLength(1),
      );
      expect(
        await db.query('incomingReceiptClaims',
            where: 'receiptCode = ?', whereArgs: ['receipt-$suffix']),
        hasLength(1),
      );
      expect(
        await db
            .query('transactions', where: 'id = ?', whereArgs: [retainedId]),
        hasLength(1),
      );
    } finally {
      await db.delete('transactions',
          where: 'id IN (?, ?)', whereArgs: [deletedId, retainedId]);
      await db.delete('forwardingConfirmations',
          where: 'forwardingJobId IN (?, ?)',
          whereArgs: [deletedJob, retainedJob]);
      await db.delete('cancelledForwardingConfirmations',
          where: 'forwardingJobId = ?', whereArgs: [deletedJob]);
      await db.delete('forwardingSubmissionClaims',
          where: 'forwardingJobId = ?', whereArgs: [deletedJob]);
      await db.delete('incomingReceiptClaims',
          where: 'receiptCode = ?', whereArgs: ['receipt-$suffix']);
    }
  });

  test('transaction deletion handles missing job IDs and preserves predicate',
      () async {
    final db = await sqlite.database;
    final firstId = await db.insert('transactions', {
      'status': TransactionStatuses.error,
      'timeStamp': 200,
    });
    final secondId = await db.insert('transactions', {
      'status': TransactionStatuses.secondAttempt,
      'timeStamp': 300,
    });
    final outsideStatusId = await db.insert('transactions', {
      'status': TransactionStatuses.doneConfirmed,
      'timeStamp': 300,
    });
    final outsideTimeId = await db.insert('transactions', {
      'status': TransactionStatuses.error,
      'timeStamp': 100,
    });
    try {
      expect(
        await sqlite.deleteTransactions(
          where: 'timeStamp >= ? AND status IN (?, ?)',
          whereArgs: [
            200,
            TransactionStatuses.error,
            TransactionStatuses.secondAttempt
          ],
        ),
        2,
      );
      for (final id in [firstId, secondId]) {
        expect(await db.query('transactions', where: 'id = ?', whereArgs: [id]),
            isEmpty);
      }
      for (final id in [outsideStatusId, outsideTimeId]) {
        expect(await db.query('transactions', where: 'id = ?', whereArgs: [id]),
            hasLength(1));
      }
    } finally {
      await db.delete('transactions',
          where: 'id IN (?, ?, ?, ?)',
          whereArgs: [firstId, secondId, outsideStatusId, outsideTimeId]);
    }
  });

  test('whitespace-padded legacy job ID cannot cancel a different job',
      () async {
    final db = testDatabase;
    final suffix = DateTime.now().microsecondsSinceEpoch;
    final canonicalJob = 'legacy-$suffix';
    final paddedJob = ' $canonicalJob ';
    final paddedOwnerId = await db.insert('transactions', {
      'status': TransactionStatuses.forwardedPending,
      'forwardingJobId': paddedJob,
    });
    final canonicalOwnerId = await db.insert('transactions', {
      'status': TransactionStatuses.forwardedPending,
      'forwardingJobId': canonicalJob,
    });
    await sqlite.queueForwardingConfirmation(
      forwardingJobId: paddedJob,
      recipientDeviceName: 'legacy-device',
    );
    await sqlite.queueForwardingConfirmation(
      forwardingJobId: canonicalJob,
      recipientDeviceName: 'current-device',
    );

    try {
      expect(
        await sqlite.deleteTransactions(
          where: 'id = ?',
          whereArgs: [paddedOwnerId],
        ),
        1,
      );
      expect(await sqlite.getForwardingConfirmation(paddedJob), isNull);
      expect(await sqlite.getForwardingConfirmation(canonicalJob), isNotNull);
      expect(
        await db.query('cancelledForwardingConfirmations',
            where: 'forwardingJobId = ?', whereArgs: [paddedJob]),
        hasLength(1),
      );
      expect(
        await db.query('cancelledForwardingConfirmations',
            where: 'forwardingJobId = ?', whereArgs: [canonicalJob]),
        isEmpty,
      );
      expect(
        await sqlite.claimDueForwardingConfirmation(
          forwardingJobId: canonicalJob,
          now: DateTime.now().millisecondsSinceEpoch,
          leaseUntil: DateTime.now().millisecondsSinceEpoch + 120000,
        ),
        1,
      );
      expect(
        await db.query('transactions',
            where: 'id = ?', whereArgs: [canonicalOwnerId]),
        hasLength(1),
      );
    } finally {
      await db.delete('transactions',
          where: 'id IN (?, ?)', whereArgs: [paddedOwnerId, canonicalOwnerId]);
      await db.delete('forwardingConfirmations',
          where: 'forwardingJobId IN (?, ?)',
          whereArgs: [paddedJob, canonicalJob]);
      await db.delete('cancelledForwardingConfirmations',
          where: 'forwardingJobId = ?', whereArgs: [paddedJob]);
    }
  });

  test('duplicate job owner keeps the shared confirmation for its survivor',
      () async {
    final db = testDatabase;
    final jobId = 'duplicate-owner-${DateTime.now().microsecondsSinceEpoch}';
    final deletedOwnerId = await db.insert('transactions', {
      'status': TransactionStatuses.forwardedPending,
      'forwardingJobId': jobId,
      'originOwnerId': _originOwnerId,
    });
    final survivingOwnerId = await db.insert('transactions', {
      'status': TransactionStatuses.forwardedPending,
      'forwardingJobId': jobId,
      'originOwnerId': _originOwnerId,
    });
    await sqlite.queueForwardingConfirmation(
      forwardingJobId: jobId,
      recipientDeviceName: 'paired-device',
    );

    try {
      expect(
        await sqlite.deleteTransactions(
          where: 'id = ?',
          whereArgs: [deletedOwnerId],
        ),
        1,
      );
      expect(await sqlite.getForwardingConfirmation(jobId), isNotNull);
      expect(
        await db.query('cancelledForwardingConfirmations',
            where: 'forwardingJobId = ?', whereArgs: [jobId]),
        isEmpty,
      );
      expect(
        await db.query('transactions',
            where: 'id = ?', whereArgs: [survivingOwnerId]),
        hasLength(1),
      );
    } finally {
      await db.delete('transactions',
          where: 'id IN (?, ?)', whereArgs: [deletedOwnerId, survivingOwnerId]);
      await db.delete('forwardingConfirmations',
          where: 'forwardingJobId = ?', whereArgs: [jobId]);
    }
  });

  test('late final ACK cannot confirm survivor of deleted legacy duplicate',
      () async {
    final db = await sqlite.database;
    final jobId = 'legacy-late-ack-${DateTime.now().microsecondsSinceEpoch}';
    final deletedId = await db.insert('transactions', {
      'status': TransactionStatuses.forwardedPending,
      'forwardingJobId': jobId,
    });
    final survivorId = await db.insert('transactions', {
      'status': TransactionStatuses.forwardedPending,
      'forwardingJobId': jobId,
    });
    try {
      expect(
        await sqlite.deleteTransactions(
          where: 'id = ?',
          whereArgs: [deletedId],
        ),
        1,
      );
      final result = await sqlite.applyForwardedSmsConfirmation(
        forwardingJobId: jobId,
        protocolVersion: forwardingConfirmationProtocolVersion,
        originOwnerId: _originOwnerId,
        awaitingTopUp: false,
      );
      expect(result, ForwardedSmsConfirmationApplyResult.missing);
      expect(result.canAcknowledge, isFalse);
      final survivor = await db.query(
        'transactions',
        columns: ['status'],
        where: 'id = ?',
        whereArgs: [survivorId],
      );
      expect(survivor.single['status'], TransactionStatuses.forwardedPending);
    } finally {
      await db.delete('transactions', where: 'id = ?', whereArgs: [survivorId]);
    }
  });

  test('verified origin owner updates only its row under a duplicate job ID',
      () async {
    final db = await sqlite.database;
    final jobId = 'owner-scoped-${DateTime.now().microsecondsSinceEpoch}';
    final intendedId = await db.insert('transactions', {
      'status': TransactionStatuses.forwardedPending,
      'forwardingJobId': jobId,
      'originOwnerId': _originOwnerId,
    });
    final unrelatedId = await db.insert('transactions', {
      'status': TransactionStatuses.forwardedPending,
      'forwardingJobId': jobId,
      'originOwnerId': _otherOriginOwnerId,
    });
    try {
      final result = await sqlite.applyForwardedSmsConfirmation(
        forwardingJobId: jobId,
        protocolVersion: forwardingConfirmationProtocolVersion,
        originOwnerId: _originOwnerId,
        awaitingTopUp: false,
      );
      expect(result, ForwardedSmsConfirmationApplyResult.applied);
      final rows = await db.query(
        'transactions',
        columns: ['id', 'status'],
        where: 'forwardingJobId = ?',
        whereArgs: [jobId],
      );
      expect(rows.singleWhere((row) => row['id'] == intendedId)['status'],
          TransactionStatuses.forwardedConfirmed);
      expect(rows.singleWhere((row) => row['id'] == unrelatedId)['status'],
          TransactionStatuses.forwardedPending);
    } finally {
      await db.delete('transactions',
          where: 'id IN (?, ?)', whereArgs: [intendedId, unrelatedId]);
    }
  });

  test('receipt ACK is bound to the queued confirmation owner', () async {
    final db = await sqlite.database;
    final jobId = 'receipt-owner-${DateTime.now().microsecondsSinceEpoch}';
    final ownerOne = await db.insert('transactions', {
      'status': TransactionStatuses.doneConfirmed,
      'forwardingJobId': jobId,
      'confirmationOwnerId': _confirmationOwnerId,
      'alternativeRequestCode': 'alt-one',
    });
    final ownerTwo = await db.insert('transactions', {
      'status': TransactionStatuses.doneConfirmed,
      'forwardingJobId': jobId,
      'confirmationOwnerId': _otherConfirmationOwnerId,
      'alternativeRequestCode': 'alt-two',
    });
    await _insertCompletedForwardedJob(
      db,
      jobId: jobId,
      originOwnerId: _originOwnerId,
      localTransactionId: ownerOne,
    );
    try {
      await sqlite.queueForwardingConfirmation(
        forwardingJobId: jobId,
        recipientDeviceName: 'Origin device',
        protocolVersion: forwardingConfirmationProtocolVersion,
        originOwnerId: _originOwnerId,
        confirmationOwnerId: _confirmationOwnerId,
        localTransactionId: ownerOne,
      );
      expect(
        await sqlite.acknowledgeForwardingConfirmation(
          jobId,
          protocolVersion: forwardingConfirmationProtocolVersion,
          originOwnerId: _originOwnerId,
          confirmationOwnerId: _otherConfirmationOwnerId,
        ),
        isFalse,
      );
      expect(await sqlite.getForwardingConfirmation(jobId), isNotNull);
      expect(
        await sqlite.acknowledgeForwardingConfirmation(
          jobId,
          protocolVersion: forwardingConfirmationProtocolVersion,
          originOwnerId: _originOwnerId,
          confirmationOwnerId: _confirmationOwnerId,
        ),
        isTrue,
      );
      expect(
        await sqlite.acknowledgeForwardingConfirmation(
          jobId,
          protocolVersion: forwardingConfirmationProtocolVersion,
          originOwnerId: _originOwnerId,
          confirmationOwnerId: _confirmationOwnerId,
        ),
        isFalse,
      );
      final rows = await db.query(
        'transactions',
        columns: ['id', 'alternativeConfirmationDelivered'],
        where: 'id IN (?, ?)',
        whereArgs: [ownerOne, ownerTwo],
      );
      expect(
        rows.singleWhere(
            (row) => row['id'] == ownerOne)['alternativeConfirmationDelivered'],
        1,
      );
      expect(
        rows.singleWhere(
            (row) => row['id'] == ownerTwo)['alternativeConfirmationDelivered'],
        0,
      );
      expect(await sqlite.getForwardingConfirmation(jobId), isNull);
    } finally {
      await db.delete('transactions',
          where: 'id IN (?, ?)', whereArgs: [ownerOne, ownerTwo]);
      await db.delete('forwardedSmsJobs',
          where: 'forwardingJobId = ?', whereArgs: [jobId]);
    }
  });

  test('legacy outbox identity is never inferred during upgrade handling',
      () async {
    final db = await sqlite.database;
    final jobId = 'legacy-outbox-${DateTime.now().microsecondsSinceEpoch}';
    await sqlite.queueForwardingConfirmation(
      forwardingJobId: jobId,
      recipientDeviceName: 'Origin device',
      transactionId: 'legacy-mpesa-code',
    );
    final row = await sqlite.getForwardingConfirmation(jobId);
    expect(row?['protocolVersion'], isNull);
    expect(row?['originOwnerId'], isNull);
    expect(row?['confirmationOwnerId'], isNull);
    expect(
      await sqlite.acknowledgeForwardingConfirmation(
        jobId,
        protocolVersion: forwardingConfirmationProtocolVersion,
        originOwnerId: _originOwnerId,
        confirmationOwnerId: _confirmationOwnerId,
      ),
      isFalse,
    );
    expect(await sqlite.getForwardingConfirmation(jobId), isNotNull);
    await db.delete('forwardingConfirmations',
        where: 'forwardingJobId = ?', whereArgs: [jobId]);
  });

  test('worker does not POST when deletion wins before durable pre-send check',
      () async {
    final db = await sqlite.database;
    final jobId = 'presend-delete-${DateTime.now().microsecondsSinceEpoch}';
    final transactionId = await db.insert('transactions', {
      'status': TransactionStatuses.doneConfirmed,
      'forwardingJobId': jobId,
      'confirmationOwnerId': _confirmationOwnerId,
    });
    await _insertCompletedForwardedJob(
      db,
      jobId: jobId,
      originOwnerId: _originOwnerId,
      localTransactionId: transactionId,
    );
    final enteredBarrier = Completer<void>();
    final releaseBarrier = Completer<void>();
    var postCount = 0;
    final controller = TransactionController(
      sqliteService: sqlite,
      senderDeviceNameProvider: () async => 'Receiver device',
      confirmationPost: (path, body) async {
        postCount++;
        return {'success': true, 'statusCode': 200};
      },
      beforeConfirmationActiveCheck: () async {
        enteredBarrier.complete();
        await releaseBarrier.future;
      },
      startConfirmationTimer: false,
    );

    final delivery = controller.sendForwardingConfirmation(
      forwardingJobId: jobId,
      recipientDeviceName: 'Origin device',
    );
    await enteredBarrier.future;
    expect(
        await sqlite
            .deleteTransactions(where: 'id = ?', whereArgs: [transactionId]),
        1);
    releaseBarrier.complete();
    await delivery;

    expect(postCount, 0);
    expect(await sqlite.getForwardingConfirmation(jobId), isNull);
    expect(
      await db.query('cancelledForwardingConfirmations',
          where: 'forwardingJobId = ?', whereArgs: [jobId]),
      hasLength(1),
    );
  });

  test('in-flight POST may finish but deletion blocks stale retry recreation',
      () async {
    final db = await sqlite.database;
    final jobId = 'inflight-delete-${DateTime.now().microsecondsSinceEpoch}';
    final transactionId = await db.insert('transactions', {
      'status': TransactionStatuses.doneConfirmed,
      'forwardingJobId': jobId,
      'confirmationOwnerId': _confirmationOwnerId,
    });
    await _insertCompletedForwardedJob(
      db,
      jobId: jobId,
      originOwnerId: _originOwnerId,
      localTransactionId: transactionId,
    );
    final postStarted = Completer<void>();
    final finishPost = Completer<Map<String, dynamic>>();
    final controller = TransactionController(
      sqliteService: sqlite,
      senderDeviceNameProvider: () async => 'Receiver device',
      confirmationPost: (path, body) {
        postStarted.complete();
        return finishPost.future;
      },
      startConfirmationTimer: false,
    );

    final delivery = controller.sendForwardingConfirmation(
      forwardingJobId: jobId,
      recipientDeviceName: 'Origin device',
    );
    await postStarted.future;
    final claimed = await sqlite.getForwardingConfirmation(jobId);
    expect(claimed, isNotNull);
    final attempt = int.parse(claimed!['attempt'].toString());
    expect(
        await sqlite
            .deleteTransactions(where: 'id = ?', whereArgs: [transactionId]),
        1);
    // Model a remote acceptance after deletion has already committed locally.
    finishPost.complete({'success': true, 'statusCode': 202});
    await delivery;

    expect(await sqlite.getForwardingConfirmation(jobId), isNull);
    await sqlite.scheduleForwardingConfirmationRetry(
      jobId,
      attempt: attempt,
      nextAttemptAt: DateTime.now().millisecondsSinceEpoch,
    );
    expect(await sqlite.getForwardingConfirmation(jobId), isNull);
    expect(
      await db.query('cancelledForwardingConfirmations',
          where: 'forwardingJobId = ?', whereArgs: [jobId]),
      hasLength(1),
    );
  });

  test('same-owner processing replacement preserves confirmation identity',
      () async {
    final db = await sqlite.database;
    final jobId = 'replace-same-${DateTime.now().microsecondsSinceEpoch}';
    final transactionId = await db.insert('transactions', {
      'status': TransactionStatuses.doneConfirmed,
      'forwardingJobId': jobId,
      'originOwnerId': _originOwnerId,
      'confirmationOwnerId': _confirmationOwnerId,
    });
    await _insertCompletedForwardedJob(
      db,
      jobId: jobId,
      originOwnerId: _originOwnerId,
      localTransactionId: transactionId,
    );
    await sqlite.queueForwardingConfirmation(
      forwardingJobId: jobId,
      recipientDeviceName: 'Origin device',
      protocolVersion: forwardingConfirmationProtocolVersion,
      originOwnerId: _originOwnerId,
      confirmationOwnerId: _confirmationOwnerId,
      localTransactionId: transactionId,
    );

    final controller = TransactionController(
      sqliteService: sqlite,
      startConfirmationTimer: false,
    );
    final replacedId = await controller.dontProcess(
      'replacement body',
      'replacement-code',
      254700000000,
      '',
      100,
      -1,
      id: transactionId,
      forwardingJobId: jobId,
      status: TransactionStatuses.forwardedPending,
    );

    final row = await db
        .query('transactions', where: 'id = ?', whereArgs: [replacedId]);
    expect(row, hasLength(1));
    expect(row.single['originOwnerId'], _originOwnerId);
    expect(row.single['confirmationOwnerId'], _confirmationOwnerId);
    expect(await sqlite.getForwardingConfirmation(jobId), isNotNull);
    expect(
      await db.query('cancelledForwardingConfirmations',
          where: 'forwardingJobId = ?', whereArgs: [jobId]),
      isEmpty,
    );
  });

  test('processing replacement tombstones an abandoned old job', () async {
    final db = await sqlite.database;
    final oldJobId = 'replace-old-${DateTime.now().microsecondsSinceEpoch}';
    final newJobId = '$oldJobId-next';
    final transactionId = await db.insert('transactions', {
      'status': TransactionStatuses.doneConfirmed,
      'forwardingJobId': oldJobId,
      'originOwnerId': _originOwnerId,
      'confirmationOwnerId': _confirmationOwnerId,
    });
    await _insertCompletedForwardedJob(
      db,
      jobId: oldJobId,
      originOwnerId: _originOwnerId,
      localTransactionId: transactionId,
    );
    await sqlite.queueForwardingConfirmation(
      forwardingJobId: oldJobId,
      recipientDeviceName: 'Origin device',
      protocolVersion: forwardingConfirmationProtocolVersion,
      originOwnerId: _originOwnerId,
      confirmationOwnerId: _confirmationOwnerId,
      localTransactionId: transactionId,
    );

    final controller = TransactionController(
      sqliteService: sqlite,
      startConfirmationTimer: false,
    );
    await controller.dontProcess(
      'replacement body',
      'replacement-code',
      254700000000,
      '',
      100,
      -1,
      id: transactionId,
      forwardingJobId: newJobId,
      status: TransactionStatuses.forwardedPending,
    );

    expect(await sqlite.getForwardingConfirmation(oldJobId), isNull);
    expect(
      await db.query('cancelledForwardingConfirmations',
          where: 'forwardingJobId = ?', whereArgs: [oldJobId]),
      hasLength(1),
    );
    final row = await db
        .query('transactions', where: 'id = ?', whereArgs: [transactionId]);
    expect(row.single['forwardingJobId'], newJobId);
    expect(row.single['originOwnerId'], _originOwnerId);
    expect(row.single['confirmationOwnerId'], isNull);
  });

  test('received acknowledgement is never treated as final confirmation', () {
    expect(
      isFinalForwardedSmsConfirmation(ackKind: 'received', status: 'received'),
      isFalse,
    );
    expect(
      isFinalForwardedSmsConfirmation(
        ackKind: '',
        status: TransactionStatuses.doneConfirmed,
      ),
      isTrue,
    );
    expect(
      isFinalForwardedSmsConfirmation(ackKind: 'confirmed', status: 'received'),
      isFalse,
    );
  });

  test('final confirmation persists the unique intended job row', () async {
    final db = await sqlite.database;
    final jobId = 'confirmation-${DateTime.now().microsecondsSinceEpoch}';
    final id = await db.insert('transactions', {
      'status': TransactionStatuses.forwardedPending,
      'forwardingJobId': jobId,
      'originOwnerId': _originOwnerId,
      'awaitingTopUp': 0,
    });
    try {
      final result = await sqlite.applyForwardedSmsConfirmation(
        forwardingJobId: jobId,
        protocolVersion: forwardingConfirmationProtocolVersion,
        originOwnerId: _originOwnerId,
        awaitingTopUp: false,
      );
      expect(result, ForwardedSmsConfirmationApplyResult.applied);
      expect(result.canAcknowledge, isTrue);
      final row = await db.query(
        'transactions',
        columns: ['status', 'canRetry', 'awaitingTopUp'],
        where: 'id = ?',
        whereArgs: [id],
      );
      expect(row.single['status'], TransactionStatuses.forwardedConfirmed);
      expect(row.single['canRetry'], 0);
      expect(row.single['awaitingTopUp'], 0);
    } finally {
      await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
    }
  });

  test('missing or ambiguous job rows are not acknowledged or updated',
      () async {
    final db = await sqlite.database;
    final jobId = 'ambiguous-${DateTime.now().microsecondsSinceEpoch}';
    final ids = <int>[];
    try {
      final missing = await sqlite.applyForwardedSmsConfirmation(
        forwardingJobId: jobId,
        protocolVersion: forwardingConfirmationProtocolVersion,
        originOwnerId: _originOwnerId,
        awaitingTopUp: false,
      );
      expect(missing, ForwardedSmsConfirmationApplyResult.missing);
      expect(missing.canAcknowledge, isFalse);

      for (var index = 0; index < 2; index++) {
        ids.add(await db.insert('transactions', {
          'status': TransactionStatuses.forwardedPending,
          'forwardingJobId': jobId,
          'originOwnerId': _originOwnerId,
        }));
      }
      final ambiguous = await sqlite.applyForwardedSmsConfirmation(
        forwardingJobId: jobId,
        protocolVersion: forwardingConfirmationProtocolVersion,
        originOwnerId: _originOwnerId,
        awaitingTopUp: false,
      );
      expect(ambiguous, ForwardedSmsConfirmationApplyResult.ambiguous);
      expect(ambiguous.canAcknowledge, isFalse);
      final rows = await db.query(
        'transactions',
        columns: ['status'],
        where: 'forwardingJobId = ?',
        whereArgs: [jobId],
      );
      expect(
          rows,
          everyElement(
              containsPair('status', TransactionStatuses.forwardedPending)));
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

  test('zero-row SQLite update is not acknowledgement eligible', () async {
    final db = await sqlite.database;
    final suffix = DateTime.now().microsecondsSinceEpoch;
    final jobId = 'failed-update-$suffix';
    final triggerName = 'ignore_confirmation_$suffix';
    final id = await db.insert('transactions', {
      'status': TransactionStatuses.forwardedPending,
      'forwardingJobId': jobId,
      'originOwnerId': _originOwnerId,
      'awaitingTopUp': 0,
    });
    try {
      await db.execute(
        'CREATE TRIGGER $triggerName BEFORE UPDATE ON transactions '
        "WHEN OLD.forwardingJobId = '$jobId' "
        'BEGIN SELECT RAISE(IGNORE); END',
      );
      final result = await sqlite.applyForwardedSmsConfirmation(
        forwardingJobId: jobId,
        protocolVersion: forwardingConfirmationProtocolVersion,
        originOwnerId: _originOwnerId,
        awaitingTopUp: false,
      );
      expect(result, ForwardedSmsConfirmationApplyResult.updateFailed);
      expect(result.canAcknowledge, isFalse);
    } finally {
      await db.execute('DROP TRIGGER IF EXISTS $triggerName');
      await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
    }
  });

  test('duplicate final confirmation is idempotent and acknowledgeable',
      () async {
    final db = await sqlite.database;
    final jobId = 'duplicate-${DateTime.now().microsecondsSinceEpoch}';
    final id = await db.insert('transactions', {
      'status': TransactionStatuses.forwardedPending,
      'forwardingJobId': jobId,
      'originOwnerId': _originOwnerId,
      'awaitingTopUp': 0,
    });
    try {
      await sqlite.applyForwardedSmsConfirmation(
        forwardingJobId: jobId,
        protocolVersion: forwardingConfirmationProtocolVersion,
        originOwnerId: _originOwnerId,
        awaitingTopUp: false,
      );
      final duplicate = await sqlite.applyForwardedSmsConfirmation(
        forwardingJobId: jobId,
        protocolVersion: forwardingConfirmationProtocolVersion,
        originOwnerId: _originOwnerId,
        awaitingTopUp: false,
      );
      expect(duplicate, ForwardedSmsConfirmationApplyResult.alreadyHandled);
      expect(duplicate.canAcknowledge, isTrue);
    } finally {
      await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
    }
  });

  test('late definitive success resolves an ambiguous alternative row',
      () async {
    final db = await sqlite.database;
    final jobId = 'late-success-${DateTime.now().microsecondsSinceEpoch}';
    final id = await db.insert('transactions', {
      'status': TransactionStatuses.alternativeAmbiguous,
      'forwardingJobId': jobId,
      'originOwnerId': _originOwnerId,
      'awaitingTopUp': 0,
    });
    try {
      final result = await sqlite.applyForwardedSmsConfirmation(
        forwardingJobId: jobId,
        protocolVersion: forwardingConfirmationProtocolVersion,
        originOwnerId: _originOwnerId,
        awaitingTopUp: false,
      );
      expect(result, ForwardedSmsConfirmationApplyResult.applied);
      final row = await db.query(
        'transactions',
        columns: ['status'],
        where: 'id = ?',
        whereArgs: [id],
      );
      expect(row.single['status'], TransactionStatuses.forwardedConfirmed);
    } finally {
      await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
    }
  });

  test('unavailable offer with top-up stays pending and is durably handled',
      () async {
    final db = await sqlite.database;
    final jobId = 'topup-${DateTime.now().microsecondsSinceEpoch}';
    final id = await db.insert('transactions', {
      'status': TransactionStatuses.forwardedPending,
      'forwardingJobId': jobId,
      'originOwnerId': _originOwnerId,
      'awaitingTopUp': 0,
    });
    try {
      final result = await sqlite.applyForwardedSmsConfirmation(
        forwardingJobId: jobId,
        protocolVersion: forwardingConfirmationProtocolVersion,
        originOwnerId: _originOwnerId,
        awaitingTopUp: true,
        requiredTopUp: 5,
        targetAmount: 25,
        targetOfferId: 4,
      );
      expect(result.canAcknowledge, isTrue);
      final duplicate = await sqlite.applyForwardedSmsConfirmation(
        forwardingJobId: jobId,
        protocolVersion: forwardingConfirmationProtocolVersion,
        originOwnerId: _originOwnerId,
        awaitingTopUp: true,
        requiredTopUp: 5,
        targetAmount: 25,
        targetOfferId: 4,
      );
      expect(duplicate, ForwardedSmsConfirmationApplyResult.alreadyHandled);
      final row = await db.query(
        'transactions',
        columns: ['status', 'awaitingTopUp', 'requiredTopUp', 'targetAmount'],
        where: 'id = ?',
        whereArgs: [id],
      );
      expect(row.single['status'], TransactionStatuses.forwardedPending);
      expect(row.single['awaitingTopUp'], 1);
      expect(row.single['requiredTopUp'], 5);
      expect(row.single['targetAmount'], 25);
    } finally {
      await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
    }
  });

  test('incompatible state and wrong job ID cannot be confirmed', () async {
    final db = await sqlite.database;
    final jobId = 'wrong-job-${DateTime.now().microsecondsSinceEpoch}';
    final id = await db.insert('transactions', {
      'status': TransactionStatuses.alternativeFailed,
      'forwardingJobId': jobId,
      'originOwnerId': _originOwnerId,
    });
    try {
      final wrongJob = await sqlite.applyForwardedSmsConfirmation(
        forwardingJobId: '$jobId-other',
        protocolVersion: forwardingConfirmationProtocolVersion,
        originOwnerId: _originOwnerId,
        awaitingTopUp: false,
      );
      expect(wrongJob, ForwardedSmsConfirmationApplyResult.missing);
      expect(wrongJob.canAcknowledge, isFalse);
      final incompatible = await sqlite.applyForwardedSmsConfirmation(
        forwardingJobId: jobId,
        protocolVersion: forwardingConfirmationProtocolVersion,
        originOwnerId: _originOwnerId,
        awaitingTopUp: false,
      );
      expect(
          incompatible, ForwardedSmsConfirmationApplyResult.incompatibleState);
      expect(incompatible.canAcknowledge, isFalse);
    } finally {
      await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
    }
  });

  test('Phone C error cannot downgrade a confirmed forwarded transaction',
      () async {
    final db = await sqlite.database;
    final jobId =
        'confirmed-alt-error-${DateTime.now().microsecondsSinceEpoch}';
    final id = await db.insert('transactions', {
      'status': TransactionStatuses.forwardedConfirmed,
      'forwardingJobId': jobId,
      'originOwnerId': _originOwnerId,
      'alternativeQueueState': 'active',
    });
    try {
      final updated = await sqlite.markAlternativeResultFailedIfUnconfirmed(
        forwardingJobId: jobId,
        transactionId: id,
        ussdReply: 'late alternative error',
      );
      expect(updated, 0);
      final rows = await db.query(
        'transactions',
        columns: ['status'],
        where: 'id = ? AND forwardingJobId = ?',
        whereArgs: [id, jobId],
      );
      expect(rows.single['status'], TransactionStatuses.forwardedConfirmed);
    } finally {
      await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
    }
  });

  test('alternative result correlation uses origin row ID only', () async {
    final db = await sqlite.database;
    final jobId = 'alt-id-${DateTime.now().microsecondsSinceEpoch}';
    final originId = await db.insert('transactions', {
      'status': TransactionStatuses.forwardedPending,
      'forwardingJobId': jobId,
      'originOwnerId': _originOwnerId,
    });
    try {
      expect(
        originatingForwardingTransactionId(
          ' $originId ',
          hasOriginatingRowIdProvenance: true,
        ),
        '$originId',
      );
      expect(
        originatingForwardingTransactionId(
          null,
          hasOriginatingRowIdProvenance: true,
        ),
        isNull,
      );
      expect(
        originatingForwardingTransactionId(
          'not-an-id',
          hasOriginatingRowIdProvenance: true,
        ),
        isNull,
      );
      expect(
        originatingForwardingTransactionId('987654'),
        isNull,
        reason: 'numeric input without an origin-row source contract is '
            'untrusted',
      );
      final senderLocalId = originId + 100000;
      final mismatchedRows = await db.query(
        'transactions',
        where: 'forwardingJobId = ? AND id = ?',
        whereArgs: [jobId, senderLocalId],
      );
      expect(mismatchedRows, isEmpty);
      final matchedRows = await db.query(
        'transactions',
        where: 'forwardingJobId = ? AND id = ?',
        whereArgs: [
          jobId,
          originatingForwardingTransactionId(
            '$originId',
            hasOriginatingRowIdProvenance: true,
          ),
        ],
      );
      expect(matchedRows, hasLength(1));
    } finally {
      await db.delete('transactions', where: 'id = ?', whereArgs: [originId]);
    }
  });

  test('confirmation outbox remains until an explicit receipt', () async {
    final db = await sqlite.database;
    final jobId = 'outbox-${DateTime.now().microsecondsSinceEpoch}';
    final localId = await db.insert('transactions', {
      'status': TransactionStatuses.doneConfirmed,
      'forwardingJobId': jobId,
      'originOwnerId': _originOwnerId,
      'confirmationOwnerId': _confirmationOwnerId,
    });
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('forwardedSmsJobs', {
      'forwardingJobId': jobId,
      'protocolVersion': forwardingConfirmationProtocolVersion,
      'originOwnerId': _originOwnerId,
      'localTransactionId': localId,
      'state': 'completed',
      'createdAt': now,
      'updatedAt': now,
    });
    try {
      await sqlite.queueForwardingConfirmation(
        forwardingJobId: jobId,
        recipientDeviceName: 'Origin device',
        protocolVersion: forwardingConfirmationProtocolVersion,
        originOwnerId: _originOwnerId,
        confirmationOwnerId: _confirmationOwnerId,
        localTransactionId: localId,
        transactionId: '42',
      );
      expect(await sqlite.getForwardingConfirmation(jobId), isNotNull);
      expect(
        await sqlite.acknowledgeForwardingConfirmation(
          jobId,
          protocolVersion: forwardingConfirmationProtocolVersion,
          originOwnerId: _originOwnerId,
          confirmationOwnerId: _confirmationOwnerId,
        ),
        isTrue,
      );
      expect(await sqlite.getForwardingConfirmation(jobId), isNull);
    } finally {
      await db.delete(
        'forwardingConfirmations',
        where: 'forwardingJobId = ?',
        whereArgs: [jobId],
      );
      await db.delete('transactions', where: 'id = ?', whereArgs: [localId]);
      await db.delete('forwardedSmsJobs',
          where: 'forwardingJobId = ?', whereArgs: [jobId]);
    }
  });

  test('failed delivery attempt is persisted and cannot be claimed twice',
      () async {
    final jobId = 'retry-attempt-${DateTime.now().microsecondsSinceEpoch}';
    const now = 1000;
    try {
      await sqlite.queueForwardingConfirmation(
        forwardingJobId: jobId,
        recipientDeviceName: 'Origin device',
      );
      final attempt = await sqlite.claimDueForwardingConfirmation(
        forwardingJobId: jobId,
        now: now,
        leaseUntil: now + 120000,
      );
      expect(attempt, 1);
      final firstAttempt = attempt!;
      final retryDelay = forwardingConfirmationRetryDelay(
        attempt: firstAttempt,
        statusCode: 503,
        message: 'Temporary server error',
      );
      await sqlite.scheduleForwardingConfirmationRetry(
        jobId,
        attempt: firstAttempt,
        nextAttemptAt: now + retryDelay.inMilliseconds,
      );
      final row = await sqlite.getForwardingConfirmation(jobId);
      expect(row?['attempt'], firstAttempt);
      expect(row?['nextAttemptAt'], now + retryDelay.inMilliseconds);
      expect(
        await sqlite.claimDueForwardingConfirmation(
          forwardingJobId: jobId,
          now: now + retryDelay.inMilliseconds,
          leaseUntil: now + retryDelay.inMilliseconds + 120000,
        ),
        2,
      );
      expect(
        await sqlite.claimDueForwardingConfirmation(
          forwardingJobId: jobId,
          now: now + retryDelay.inMilliseconds + 1,
          leaseUntil: now + retryDelay.inMilliseconds + 120001,
        ),
        isNull,
      );
    } finally {
      await sqlite.removeForwardingConfirmation(jobId);
    }
  });

  test('pairing 403 schedules 30 minutes and keeps its queued confirmation',
      () async {
    final jobId = 'pairing-retry-${DateTime.now().microsecondsSinceEpoch}';
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      await sqlite.queueForwardingConfirmation(
        forwardingJobId: jobId,
        recipientDeviceName: 'Origin device',
      );
      final attempt = await sqlite.claimDueForwardingConfirmation(
        forwardingJobId: jobId,
        now: now,
        leaseUntil: now + const Duration(minutes: 2).inMilliseconds,
      );
      final delay = forwardingConfirmationRetryDelay(
        attempt: attempt!,
        statusCode: 403,
        message: 'Devices are not paired',
        error: {'devices': '726 and 733', 'status': 'accepted not found'},
      );
      expect(delay, const Duration(minutes: 30));
      await sqlite.scheduleForwardingConfirmationRetry(
        jobId,
        attempt: attempt!,
        nextAttemptAt: now + delay.inMilliseconds,
      );
      final row = await sqlite.getForwardingConfirmation(jobId);
      expect(row?['attempt'], 1);
      expect(
        row?['nextAttemptAt'],
        now + const Duration(minutes: 30).inMilliseconds,
      );
    } finally {
      await sqlite.removeForwardingConfirmation(jobId);
    }
  });

  test('transient failure uses bounded ordinary backoff', () {
    expect(
      forwardingConfirmationRetryDelay(
        attempt: 2,
        statusCode: 503,
        message: 'Temporary service error',
      ),
      const Duration(seconds: 15),
    );
    expect(
      forwardingConfirmationRetryDelay(
        attempt: 100,
        statusCode: 403,
        message: 'Forbidden',
      ),
      const Duration(seconds: 300),
    );
  });

  test('delivery failure leaves the forwarded transaction unchanged', () async {
    final db = await sqlite.database;
    final jobId = 'no-purchase-${DateTime.now().microsecondsSinceEpoch}';
    final id = await db.insert('transactions', {
      'status': TransactionStatuses.forwardedPending,
      'forwardingJobId': jobId,
      'originOwnerId': _originOwnerId,
    });
    try {
      await sqlite.queueForwardingConfirmation(
        forwardingJobId: jobId,
        recipientDeviceName: 'Origin device',
      );
      final attempt = await sqlite.claimDueForwardingConfirmation(
        forwardingJobId: jobId,
        now: 1000,
        leaseUntil: 121000,
      );
      final delay = forwardingConfirmationRetryDelay(
        attempt: attempt!,
        statusCode: 403,
        message: 'Devices are not paired',
      );
      await sqlite.scheduleForwardingConfirmationRetry(
        jobId,
        attempt: attempt!,
        nextAttemptAt: 1000 + delay.inMilliseconds,
      );
      final transaction = await db.query(
        'transactions',
        columns: ['status'],
        where: 'id = ?',
        whereArgs: [id],
      );
      expect(
        transaction.single['status'],
        TransactionStatuses.forwardedPending,
      );
      expect(await sqlite.getForwardingConfirmation(jobId), isNotNull);
    } finally {
      await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
      await sqlite.removeForwardingConfirmation(jobId);
    }
  });

  test('forwarded display prefers configured name and safely falls back', () {
    expect(
      forwardingDisplayReply(
        status: TransactionStatuses.forwardedPending,
        reply: 'Forwarded to Old Device',
        destinationDeviceName: 'Shop Counter',
      ),
      'Forwarded to Shop Counter',
    );
    expect(
      forwardingDisplayReply(
        status: TransactionStatuses.forwardedConfirmed,
        reply: 'Forwarded to Historical Phone',
      ),
      'Forwarded to Historical Phone',
    );
    expect(
      meaningfulForwardingDeviceName('device_id: 1234'),
      isNull,
    );
    expect(
      forwardingDisplayReply(
        status: TransactionStatuses.doneConfirmed,
        reply: 'Purchase successful',
        destinationDeviceName: 'Shop Counter',
      ),
      'Purchase successful',
    );
  });
}
