import 'package:bsat/services/sqlite_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  final sqlite = SQLiteService();

  test('concurrent receipt claims produce one processing owner', () async {
    final db = await sqlite.database;
    final receipt = 'RCPT${DateTime.now().microsecondsSinceEpoch}';

    try {
      final claims = await Future.wait(
        List.generate(8, (_) => sqlite.claimIncomingMpesaReceipt(receipt)),
      );
      expect(claims.where((claim) => claim['claimed'] == true), hasLength(1));

      final transactionId = await db.insert(
        'transactions',
        {'transactionId': receipt, 'status': 'forwarded-pending'},
      );
      await sqlite.completeIncomingMpesaReceipt(
        receipt,
        localTransactionId: transactionId,
      );

      final duplicate = await sqlite.claimIncomingMpesaReceipt(receipt);
      expect(duplicate['claimed'], isFalse);
      expect(duplicate['localTransactionId'], transactionId);
    } finally {
      await db.delete(
        'incomingReceiptClaims',
        where: 'receiptCode = ?',
        whereArgs: [receipt],
      );
      await db.delete(
        'transactions',
        where: 'transactionId = ?',
        whereArgs: [receipt],
      );
    }
  });

  test('distinct receipts remain independently claimable', () async {
    final db = await sqlite.database;
    final suffix = DateTime.now().microsecondsSinceEpoch;
    final firstReceipt = 'ONE$suffix';
    final secondReceipt = 'TWO$suffix';

    try {
      final first = await sqlite.claimIncomingMpesaReceipt(firstReceipt);
      final second = await sqlite.claimIncomingMpesaReceipt(secondReceipt);
      expect(first['claimed'], isTrue);
      expect(second['claimed'], isTrue);
    } finally {
      await db.delete(
        'incomingReceiptClaims',
        where: 'receiptCode IN (?, ?)',
        whereArgs: [firstReceipt, secondReceipt],
      );
    }
  });

  test('legacy transaction rows resolve receipt duplicates to their ID',
      () async {
    final db = await sqlite.database;
    final receipt = 'OLD${DateTime.now().microsecondsSinceEpoch}';
    final transactionId = await db.insert(
      'transactions',
      {'transactionId': receipt, 'status': 'forwarded-pending'},
    );

    try {
      final duplicate = await sqlite.claimIncomingMpesaReceipt(receipt);
      expect(duplicate['claimed'], isFalse);
      expect(duplicate['localTransactionId'], transactionId);
    } finally {
      await db.delete(
        'incomingReceiptClaims',
        where: 'receiptCode = ?',
        whereArgs: [receipt],
      );
      await db.delete(
        'transactions',
        where: 'id = ?',
        whereArgs: [transactionId],
      );
    }
  });

  test('concurrent deliveries of one job have one execution claim', () async {
    final db = await sqlite.database;
    final jobId = 'fwd-${DateTime.now().microsecondsSinceEpoch}';

    try {
      final claims = await Future.wait(
        List.generate(
          8,
          (_) => sqlite.claimForwardedSmsJob(
            forwardingJobId: jobId,
            sourceTransactionId: 'source-transaction',
          ),
        ),
      );
      expect(claims.where((claim) => claim['claimed'] == true), hasLength(1));

      final transactionId = await db.insert(
        'transactions',
        {'forwardingJobId': jobId, 'status': 'transaction-confirmed'},
      );
      await sqlite.completeForwardedSmsJob(
        jobId,
        localTransactionId: transactionId,
      );

      final afterRestart = await SQLiteService().claimForwardedSmsJob(
        forwardingJobId: jobId,
      );
      expect(afterRestart['claimed'], isFalse);
      expect(afterRestart['state'], 'completed');
      expect(afterRestart['localTransactionId'], transactionId);
    } finally {
      await db.delete(
        'forwardedSmsJobs',
        where: 'forwardingJobId = ?',
        whereArgs: [jobId],
      );
      await db.delete(
        'transactions',
        where: 'forwardingJobId = ?',
        whereArgs: [jobId],
      );
    }
  });

  test('forwarding identity is stable across concurrent retries', () async {
    final db = await sqlite.database;
    final suffix = DateTime.now().microsecondsSinceEpoch;
    final transactionId = await db.insert(
      'transactions',
      {'transactionId': 'IDENTITY$suffix', 'status': 'error'},
    );

    try {
      final identities = await Future.wait([
        sqlite.ensureForwardingIdentity(
          transactionId: transactionId,
          candidateForwardingJobId: 'first-job-$suffix',
          candidateRecipientDeviceName: 'Phone A',
          candidateSenderDeviceName: 'Phone B',
        ),
        sqlite.ensureForwardingIdentity(
          transactionId: transactionId,
          candidateForwardingJobId: 'second-job-$suffix',
          candidateRecipientDeviceName: 'Phone C',
          candidateSenderDeviceName: 'Phone D',
        ),
      ]);

      expect(
          identities[0]['forwardingJobId'], identities[1]['forwardingJobId']);
      expect(identities[0]['forwardingRecipientDeviceName'],
          identities[1]['forwardingRecipientDeviceName']);
      expect(
        ['first-job-$suffix', 'second-job-$suffix'],
        contains(identities.first['forwardingJobId']),
      );
    } finally {
      await db.delete(
        'transactions',
        where: 'id = ?',
        whereArgs: [transactionId],
      );
    }
  });

  test('submission lock serializes retries and permits a later retry',
      () async {
    final jobId = 'send-${DateTime.now().microsecondsSinceEpoch}';
    final now = DateTime.now().millisecondsSinceEpoch;

    final claims = await Future.wait(
      List.generate(
        8,
        (_) => sqlite.claimForwardingSubmission(
          jobId,
          now: now,
          leaseExpiresAt: now + const Duration(minutes: 2).inMilliseconds,
        ),
      ),
    );
    expect(claims.where((claimed) => claimed), hasLength(1));

    await sqlite.releaseForwardingSubmission(jobId);
    expect(
      await sqlite.claimForwardingSubmission(
        jobId,
        now: now + 1,
        leaseExpiresAt: now + const Duration(minutes: 2).inMilliseconds + 1,
      ),
      isTrue,
    );
    await sqlite.releaseForwardingSubmission(jobId);
  });
}
