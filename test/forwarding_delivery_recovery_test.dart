import 'package:bsat/services/firebase_messaging_service.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:bsat/utils/forwarding_delivery_retry.dart';
import 'package:bsat/utils/forwarding_identifiers.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  final sqlite = SQLiteService();

  Future<(Database, String, int)> createPendingForwardingTransaction({
    String? alternativeRequestCode,
    int? timestamp,
  }) async {
    final db = await sqlite.database;
    final suffix = DateTime.now().microsecondsSinceEpoch.toString();
    final jobId = 'delivery-retry-$suffix';
    final transactionId = await db.insert('transactions', {
      'initialMessage': 'RCPT$suffix Confirmed. Ksh100.00 sent to 0712345678.',
      'transactionId': 'RCPT$suffix',
      'timeStamp': timestamp ?? DateTime.now().millisecondsSinceEpoch,
      'status': TransactionStatuses.forwardedPending,
      'forwardingJobId': jobId,
      'forwardingSenderDeviceName': 'Phone A',
      'forwardingRecipientDeviceName': 'Phone B',
      'alternativeRequestCode': alternativeRequestCode,
      'awaitingTopUp': 0,
      'ussdReply': 'Forwarded to Phone B',
    });
    return (db, jobId, transactionId);
  }

  Future<void> cleanUp(Database db, String jobId, int transactionId) async {
    await db.delete(
      'forwardingDeliveryRetries',
      where: 'forwardingJobId = ?',
      whereArgs: [jobId],
    );
    await db.delete(
      'forwardingSubmissionClaims',
      where: 'forwardingJobId = ?',
      whereArgs: [jobId],
    );
    await db.delete(
      'forwardedSmsJobs',
      where: 'forwardingJobId = ?',
      whereArgs: [jobId],
    );
    await db
        .delete('transactions', where: 'id = ?', whereArgs: [transactionId]);
  }

  test('accepted send without a receipt is first due at 30 seconds', () async {
    final (db, jobId, transactionId) =
        await createPendingForwardingTransaction();
    final acceptedAt = DateTime.now().millisecondsSinceEpoch;

    try {
      await sqlite.scheduleForwardingDeliveryRetry(
        jobId,
        attempt: 0,
        nextAttemptAt: acceptedAt +
            const Duration(
              seconds: initialForwardingDeliveryRetryDelaySeconds,
            ).inMilliseconds,
      );

      expect(
        await sqlite.dueForwardingDeliveryRetries(
          acceptedAt +
              const Duration(
                seconds: initialForwardingDeliveryRetryDelaySeconds,
              ).inMilliseconds -
              1,
        ),
        isEmpty,
      );
      expect(
        await sqlite.dueForwardingDeliveryRetries(
          acceptedAt +
              const Duration(
                seconds: initialForwardingDeliveryRetryDelaySeconds,
              ).inMilliseconds,
        ),
        hasLength(1),
      );
      await sqlite.scheduleForwardingDeliveryRetry(
        jobId,
        attempt: maxForwardingDeliveryRetries,
        nextAttemptAt: acceptedAt,
      );
      expect(
        await sqlite.dueForwardingDeliveryRetries(
          acceptedAt + const Duration(days: 1).inMilliseconds,
        ),
        isEmpty,
      );
      expect(
        forwardingDeliveryRetryBackoffSeconds,
        [30, 60, 120, 300, 600, 1800],
      );
      expect(forwardingDeliveryRetryDelayAfterAttempt(7), isNull);
    } finally {
      await cleanUp(db, jobId, transactionId);
    }
  });

  test('retry payload preserves original forwarding identity and types',
      () async {
    final (db, jobId, transactionId) =
        await createPendingForwardingTransaction();
    const originalMessage = 'Original SMS including punctuation: Ksh100.00!';

    try {
      final payload = buildForwardedSmsRequestPayload(
        message: originalMessage,
        messageId: 'RCPT-original',
        transactionRowId: transactionId,
        forwardingJobId: jobId,
        senderDeviceName: 'Phone A',
        recipientDeviceName: 'Phone B',
      );

      expect(payload, {
        'title': 'BSAT Online Forwarding',
        'body': originalMessage,
        'senderDeviceName': 'Phone A',
        'recipientDeviceName': 'Phone B',
        'data': {
          'type': 'forwarded_sms',
          'body': originalMessage,
          'title': 'Forwarded Message',
          'messageId': 'RCPT-original',
          'transactionId': transactionId,
          'forwardingJobId': jobId,
          'forwardingStatus': ForwardingJobStatuses.pending,
          'senderDeviceName': 'Phone A',
          'recipientDeviceName': 'Phone B',
        },
      });
      expect(
        (payload['data'] as Map<String, dynamic>)['transactionId'],
        isA<int>(),
      );
      expect(
          (payload['data'] as Map<String, dynamic>)['body'], originalMessage);
    } finally {
      await cleanUp(db, jobId, transactionId);
    }
  });

  test('startup schema backfill recovers eligible pending jobs once', () async {
    final acceptedAt = DateTime.now()
        .subtract(const Duration(minutes: 2))
        .millisecondsSinceEpoch;
    final (db, jobId, transactionId) =
        await createPendingForwardingTransaction(timestamp: acceptedAt);

    try {
      await sqlite.ensureCriticalSchema(db);
      var retry = await db.query(
        'forwardingDeliveryRetries',
        where: 'forwardingJobId = ?',
        whereArgs: [jobId],
      );
      expect(retry, hasLength(1));
      expect(retry.single['attempt'], 0);
      expect(
        retry.single['nextAttemptAt'],
        acceptedAt + const Duration(seconds: 30).inMilliseconds,
      );

      await sqlite.scheduleForwardingDeliveryRetry(
        jobId,
        attempt: 3,
        nextAttemptAt: acceptedAt + 999000,
      );
      await sqlite.ensureCriticalSchema(db);
      retry = await db.query(
        'forwardingDeliveryRetries',
        where: 'forwardingJobId = ?',
        whereArgs: [jobId],
      );
      expect(retry.single['attempt'], 3);
      expect(retry.single['nextAttemptAt'], acceptedAt + 999000);
    } finally {
      await cleanUp(db, jobId, transactionId);
    }
  });

  test('receipt acknowledgement survives restart without backfill recreation',
      () async {
    final (db, jobId, transactionId) =
        await createPendingForwardingTransaction();

    try {
      await sqlite.scheduleForwardingDeliveryRetry(
        jobId,
        attempt: 0,
        nextAttemptAt: 0,
      );
      expect(
        await sqlite.acknowledgeForwardingDeliveryIfMatches(
          forwardingJobId: jobId,
          transactionRowId: transactionId.toString(),
          receivedSenderDeviceName: 'Phone B',
          receivedRecipientDeviceName: 'Phone A',
          localDeviceName: 'Phone A',
        ),
        isTrue,
      );
      final transaction = (await db.query(
        'transactions',
        columns: ['status', 'ussdReply'],
        where: 'id = ?',
        whereArgs: [transactionId],
      ))
          .single;
      expect(transaction['status'], TransactionStatuses.forwardedPending);
      expect(
        transaction['ussdReply'],
        contains('Receipt acknowledged by destination device'),
      );
      expect(
        (await sqlite.dueForwardingDeliveryRetries(
          DateTime.now().millisecondsSinceEpoch + 1,
        )),
        isEmpty,
      );
      await sqlite.scheduleForwardingDeliveryRetry(
        jobId,
        attempt: 1,
        nextAttemptAt: DateTime.now().millisecondsSinceEpoch,
      );
      final acknowledgedRetry = (await db.query(
        'forwardingDeliveryRetries',
        where: 'forwardingJobId = ?',
        whereArgs: [jobId],
      ))
          .single;
      expect(acknowledgedRetry['acknowledged'], 1);
      expect(
        await sqlite.dueForwardingDeliveryRetries(
          DateTime.now().millisecondsSinceEpoch + 1,
        ),
        isEmpty,
      );

      await db.delete(
        'forwardingDeliveryRetries',
        where: 'forwardingJobId = ?',
        whereArgs: [jobId],
      );
      await sqlite.ensureCriticalSchema(db);
      expect(
        await db.query(
          'forwardingDeliveryRetries',
          where: 'forwardingJobId = ?',
          whereArgs: [jobId],
        ),
        isEmpty,
      );
    } finally {
      await cleanUp(db, jobId, transactionId);
    }
  });

  test('malformed or mismatched receipt acknowledgements leave retry active',
      () async {
    final (db, jobId, transactionId) =
        await createPendingForwardingTransaction();

    try {
      await sqlite.scheduleForwardingDeliveryRetry(
        jobId,
        attempt: 0,
        nextAttemptAt: 0,
      );
      for (final acknowledgement in [
        (
          forwardingJobId: 'wrong-job',
          transactionRowId: transactionId.toString(),
          receivedSenderDeviceName: 'Phone B',
          receivedRecipientDeviceName: 'Phone A',
        ),
        (
          forwardingJobId: jobId,
          transactionRowId: 'not-a-row-id',
          receivedSenderDeviceName: 'Phone B',
          receivedRecipientDeviceName: 'Phone A',
        ),
        (
          forwardingJobId: jobId,
          transactionRowId: transactionId.toString(),
          receivedSenderDeviceName: 'Phone C',
          receivedRecipientDeviceName: 'Phone A',
        ),
        (
          forwardingJobId: jobId,
          transactionRowId: transactionId.toString(),
          receivedSenderDeviceName: 'Phone B',
          receivedRecipientDeviceName: 'Phone C',
        ),
      ]) {
        expect(
          await sqlite.acknowledgeForwardingDeliveryIfMatches(
            forwardingJobId: acknowledgement.forwardingJobId,
            transactionRowId: acknowledgement.transactionRowId,
            receivedSenderDeviceName: acknowledgement.receivedSenderDeviceName,
            receivedRecipientDeviceName:
                acknowledgement.receivedRecipientDeviceName,
            localDeviceName: 'Phone A',
          ),
          isFalse,
        );
      }
      expect(
        await sqlite.dueForwardingDeliveryRetries(
          DateTime.now().millisecondsSinceEpoch + 1,
        ),
        hasLength(1),
      );
    } finally {
      await cleanUp(db, jobId, transactionId);
    }
  });

  test(
      'late receipt ACK restores pending after POST failure and blocks overwrite',
      () async {
    final (db, jobId, transactionId) =
        await createPendingForwardingTransaction();

    try {
      await sqlite.scheduleForwardingDeliveryRetry(
        jobId,
        attempt: 0,
        nextAttemptAt: 0,
      );
      expect(
        await sqlite.markForwardingSubmissionFailedIfUnacknowledged(
          transactionId: transactionId,
          forwardingJobId: jobId,
          reply: 'Forwarding failed: server response unavailable.',
        ),
        1,
      );
      expect(
        (await db.query(
          'transactions',
          columns: ['status'],
          where: 'id = ?',
          whereArgs: [transactionId],
        ))
            .single['status'],
        TransactionStatuses.error,
      );

      expect(
        await sqlite.acknowledgeForwardingDeliveryIfMatches(
          forwardingJobId: jobId,
          transactionRowId: transactionId.toString(),
          receivedSenderDeviceName: 'Phone B',
          receivedRecipientDeviceName: 'Phone A',
          localDeviceName: 'Phone A',
        ),
        isTrue,
      );
      expect(
        await sqlite.markForwardingSubmissionFailedIfUnacknowledged(
          transactionId: transactionId,
          forwardingJobId: jobId,
          reply: 'Late API failure',
        ),
        0,
      );
      expect(
        (await db.query(
          'transactions',
          columns: ['status'],
          where: 'id = ?',
          whereArgs: [transactionId],
        ))
            .single['status'],
        TransactionStatuses.forwardedPending,
      );
      expect(
        await sqlite.dueForwardingDeliveryRetries(
          DateTime.now().millisecondsSinceEpoch + 1,
        ),
        isEmpty,
      );
    } finally {
      await cleanUp(db, jobId, transactionId);
    }
  });

  test('contradictory ACK kind and status cannot act as receipt or success',
      () {
    expect(
      isForwardingReceiptAcknowledgement(
        ackKind: 'received',
        status: 'received',
      ),
      isTrue,
    );
    expect(
      isForwardingReceiptAcknowledgement(
        ackKind: 'received',
        status: TransactionStatuses.doneConfirmed,
      ),
      isFalse,
    );
    expect(
      isFinalForwardedSmsConfirmation(
        ackKind: 'received',
        status: TransactionStatuses.doneConfirmed,
      ),
      isFalse,
    );
    expect(
      isFinalForwardedSmsConfirmation(
        ackKind: 'confirmed',
        status: 'received',
      ),
      isFalse,
    );
  });

  test('concurrent retry workers are serialized by an owned claim', () async {
    final (db, jobId, transactionId) =
        await createPendingForwardingTransaction();
    final now = DateTime.now().millisecondsSinceEpoch;

    try {
      final claims = await Future.wait(
        List.generate(
          8,
          (index) => sqlite.claimForwardingSubmission(
            jobId,
            now: now,
            leaseExpiresAt: now + const Duration(minutes: 2).inMilliseconds,
            claimToken: 'worker-$index',
          ),
        ),
      );
      expect(claims.where((claimed) => claimed), hasLength(1));
      final owner = (await db.query(
        'forwardingSubmissionClaims',
        columns: ['claimToken'],
        where: 'forwardingJobId = ?',
        whereArgs: [jobId],
      ))
          .single['claimToken'];

      expect(
        await sqlite.renewForwardingSubmission(
          jobId,
          claimToken: 'wrong-worker',
          leaseExpiresAt: now + 300000,
        ),
        isFalse,
      );
      expect(
        await sqlite.renewForwardingSubmission(
          jobId,
          claimToken: owner.toString(),
          leaseExpiresAt: now + 300000,
        ),
        isTrue,
      );
      await sqlite.releaseForwardingSubmission(
        jobId,
        claimToken: 'wrong-worker',
      );
      expect(
        await sqlite.claimForwardingSubmission(
          jobId,
          now: now + 1,
          leaseExpiresAt: now + 300001,
          claimToken: 'late-worker',
        ),
        isFalse,
      );
      await sqlite.releaseForwardingSubmission(
        jobId,
        claimToken: owner.toString(),
      );
      expect(
        await sqlite.claimForwardingSubmission(
          jobId,
          now: now + 1,
          leaseExpiresAt: now + 300001,
          claimToken: 'late-worker',
        ),
        isTrue,
      );
    } finally {
      await cleanUp(db, jobId, transactionId);
    }
  });

  test('duplicate forwarded delivery does not acquire a second execution',
      () async {
    final (db, jobId, transactionId) =
        await createPendingForwardingTransaction();
    final before = int.parse(
      (await db.rawQuery('SELECT COUNT(*) AS count FROM transactions'))
          .single['count']
          .toString(),
    );

    try {
      await db.update(
        'transactions',
        {'forwardingJobId': 'origin-$jobId'},
        where: 'id = ?',
        whereArgs: [transactionId],
      );
      final first = await sqlite.claimForwardedSmsJob(
        forwardingJobId: jobId,
        sourceTransactionId: transactionId.toString(),
      );
      final duplicate = await sqlite.claimForwardedSmsJob(
        forwardingJobId: jobId,
        sourceTransactionId: transactionId.toString(),
      );
      expect(first['claimed'], isTrue);
      expect(duplicate['claimed'], isFalse);
      expect(duplicate['state'], 'executing');
      expect(
        int.parse(
          (await db.rawQuery('SELECT COUNT(*) AS count FROM transactions'))
              .single['count']
              .toString(),
        ),
        before,
      );
    } finally {
      await cleanUp(db, jobId, transactionId);
    }
  });

  test('interrupted executing job is not blindly re-executed', () async {
    final (db, jobId, transactionId) =
        await createPendingForwardingTransaction();

    try {
      await db.update(
        'transactions',
        {'forwardingJobId': 'origin-$jobId'},
        where: 'id = ?',
        whereArgs: [transactionId],
      );
      final firstProcessClaim = await sqlite.claimForwardedSmsJob(
        forwardingJobId: jobId,
        sourceTransactionId: 'source-$jobId',
      );
      final restartedProcessClaim = await SQLiteService().claimForwardedSmsJob(
        forwardingJobId: jobId,
        sourceTransactionId: 'source-$jobId',
      );
      expect(firstProcessClaim['claimed'], isTrue);
      expect(restartedProcessClaim['claimed'], isFalse);
      expect(restartedProcessClaim['state'], 'executing');
    } finally {
      await cleanUp(db, jobId, transactionId);
    }
  });

  test('alternative flow jobs are independent from ordinary SMS retries',
      () async {
    final (db, jobId, transactionId) = await createPendingForwardingTransaction(
      alternativeRequestCode: '*123#',
    );

    try {
      await sqlite.ensureCriticalSchema(db);
      expect(
        await db.query(
          'forwardingDeliveryRetries',
          where: 'forwardingJobId = ?',
          whereArgs: [jobId],
        ),
        isEmpty,
      );
      await sqlite.scheduleForwardingDeliveryRetry(
        jobId,
        attempt: 0,
        nextAttemptAt: 0,
      );
      expect(
        await sqlite.dueForwardingDeliveryRetries(
          DateTime.now().millisecondsSinceEpoch + 1,
        ),
        isEmpty,
      );
      final transaction = (await db.query(
        'transactions',
        columns: ['alternativeRequestCode'],
        where: 'id = ?',
        whereArgs: [transactionId],
      ))
          .single;
      expect(transaction['alternativeRequestCode'], '*123#');
    } finally {
      await cleanUp(db, jobId, transactionId);
    }
  });

  test('notification taps recognize forwarded messages only', () {
    expect(
      isForwardedSmsNotification(
        RemoteMessage(data: {'type': 'forwarded_sms'}),
      ),
      isTrue,
    );
    expect(
      isForwardedSmsNotification(
        RemoteMessage(data: {
          'type': 'FORWARDED_SMS',
          'title': 'Forwarded Message',
        }),
      ),
      isTrue,
    );
    expect(
      isForwardedSmsNotification(
        RemoteMessage(data: {'type': 'unrelated_notification'}),
      ),
      isFalse,
    );
    expect(
      isForwardedSmsNotification(
        RemoteMessage(data: {'type': 'request_contacts_from_device'}),
      ),
      isFalse,
    );
    expect(
      isForwardedSmsNotification(
        RemoteMessage(
          notification: const RemoteNotification(
            title: 'BSAT Online Forwarding',
          ),
        ),
      ),
      isTrue,
    );
  });
}
