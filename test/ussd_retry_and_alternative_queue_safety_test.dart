import 'dart:async';

import 'package:bsat/controllers/transaction_controller.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/models/code_signature.dart';
import 'package:bsat/services/phone_service.dart';
import 'package:bsat/services/sms_sevice.dart';
import 'package:bsat/utils/constants.dart';
import 'package:bsat/utils/transaction_execution_safety.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late SQLiteService sqlite;
  late Database db;

  setUp(() async {
    final schema = SQLiteService();
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 23, onCreate: schema.onCreate),
    );
    await schema.ensureCriticalSchema(db);
    sqlite = SQLiteService(databaseOverride: db);
  });

  tearDown(() async {
    if (db.isOpen) await db.close();
  });

  test('only explicit initial rejection remains retry-ready', () {
    expect(
      initialTransactionRetryState(
        status: TransactionStatuses.error,
        reply: 'Recommendation failed for 0712345678',
      ),
      'ready',
    );
    expect(
      initialTransactionRetryState(
        status: TransactionStatuses.error,
        reply:
            'Error sending code: PlatformException(ussd_plugin, Recommendation failed for 0712345678)',
      ),
      'ready',
    );
    expect(
      initialTransactionRetryState(
        status: TransactionStatuses.timedOut,
        reply: 'Recommendation failed after the response timeout',
      ),
      'ambiguous',
    );

    for (final reply in [
      '',
      'Error sending code: permission state unknown',
      'Error sending code: MissingPluginException: no handler',
      'Carrier request timed out',
      'Network error',
    ]) {
      expect(
        initialTransactionRetryState(
          status: TransactionStatuses.error,
          reply: reply,
        ),
        'ambiguous',
        reason: reply,
      );
    }

    expect(
      initialTransactionRetryState(
        status: TransactionStatuses.timedOut,
        reply: 'USSD response timed out; carrier outcome is unknown.',
      ),
      'ambiguous',
    );
    expect(
      initialTransactionRetryState(
        status: TransactionStatuses.error,
        reply:
            'Error sending code: PlatformException(ussd_plugin_ussd_execution_failure, USSD_RETURN_FAILURE)',
      ),
      'ready',
    );
    expect(
      initialTransactionRetryState(
        status: TransactionStatuses.doneConfirmed,
        reply: 'Purchase confirmed',
      ),
      'blocked',
    );
    expect(
      initialTransactionRetryState(
        status: TransactionStatuses.successfulPending,
        reply: 'Recommendation submitted successfully',
      ),
      'blocked',
    );
    expect(
      initialTransactionRetryState(
        status: TransactionStatuses.advancedQueue,
        reply: 'USSD session already in progress',
      ),
      'ambiguous',
    );
  });

  test('background SMS callback awaits routing setup and message processing',
      () async {
    final processing = Completer<void>();
    final order = <String>[];
    var callbackCompleted = false;
    final callback = awaitSmsBackgroundCallbackWork(
      {'address': 'MPESA'},
      initializeRouting: () async {
        order.add('routing');
      },
      processMessage: (message) async {
        expect(message, {'address': 'MPESA'});
        order.add('processing-started');
        await processing.future;
        order.add('processing-completed');
      },
    ).whenComplete(() => callbackCompleted = true);

    await Future<void>.delayed(Duration.zero);
    expect(order, ['routing', 'processing-started']);
    expect(callbackCompleted, isFalse);
    processing.complete();
    await callback;
    expect(callbackCompleted, isTrue);
    expect(order, ['routing', 'processing-started', 'processing-completed']);
  });

  test('Advanced native timeout status survives transaction classification',
      () async {
    final controller = TransactionController(
      sqliteService: sqlite,
      startConfirmationTimer: false,
    );
    expect(
      await controller.transactionStatus([
        'USSD response timed out; carrier outcome is unknown.',
        TransactionStatuses.timedOut,
      ]),
      TransactionStatuses.timedOut,
    );
    for (final status in [
      TransactionStatuses.ussdOutcomeUnknown,
      TransactionStatuses.ussdLaunchRejected,
      TransactionStatuses.ussdRoutingUnavailable,
    ]) {
      expect(
        await controller.transactionStatus(['bridge result', status]),
        status,
      );
    }
  });

  test('durable retry candidates exclude ambiguous outcomes', () async {
    final expressFailureId = await db.insert('transactions', {
      'status': TransactionStatuses.error,
      'ussdReply': 'Error sending code: USSD_RETURN_FAILURE',
      'canRetry': 1,
      'retryState': initialTransactionRetryState(
        status: TransactionStatuses.error,
        reply: 'Error sending code: USSD_RETURN_FAILURE',
      ),
      'date': 'today',
    });
    final ambiguousId = await db.insert('transactions', {
      'status': TransactionStatuses.error,
      'canRetry': 1,
      'retryState': 'ambiguous',
      'date': 'today',
    });
    final rejectedId = await db.insert('transactions', {
      'status': TransactionStatuses.error,
      'ussdReply': 'Error sending code: Recommendation failed',
      'canRetry': 1,
      'retryState': initialTransactionRetryState(
        status: TransactionStatuses.error,
        reply: 'Error sending code: Recommendation failed',
      ),
      'date': 'today',
    });
    final launchRejectedId = await db.insert('transactions', {
      'status': TransactionStatuses.ussdLaunchRejected,
      'canRetry': 1,
      'retryState': initialTransactionRetryState(
        status: TransactionStatuses.ussdLaunchRejected,
        reply: 'USSD launch rejected (PERMISSION_DENIED)',
      ),
      'date': 'today',
    });
    final advancedId = await db.insert('transactions', {
      'status': TransactionStatuses.error,
      'ussdDialed': '*188*8*1#',
      'simSubId': 14,
      'amount': 5,
      'canRetry': 1,
      'retryState': initialTransactionRetryState(
        status: TransactionStatuses.error,
        reply: 'Request cannot be completed at the moment',
      ),
      'ussdReply': 'Request cannot be completed at the moment',
      'date': 'today',
    });
    final overLimitId = await db.insert('transactions', {
      'status': TransactionStatuses.error,
      'canRetry': 12,
      'retryState': 'ready',
      'date': 'today',
    });
    final confirmedId = await db.insert('transactions', {
      'status': TransactionStatuses.doneConfirmed,
      'canRetry': 1,
      'retryState': 'blocked',
      'date': 'today',
    });

    final candidates = await sqlite.getAutomaticRetryCandidates(
      isAutoRetrying: true,
      retryLimit: 12,
      today: 'today',
    );
    expect(candidates.map((row) => row['id']), contains(rejectedId));
    expect(candidates.map((row) => row['id']), contains(launchRejectedId));
    expect(candidates.map((row) => row['id']), contains(advancedId));
    expect(
        candidates.map((row) => row['id']), isNot(contains(expressFailureId)));
    expect(candidates.map((row) => row['id']), isNot(contains(ambiguousId)));
    expect(candidates.map((row) => row['id']), isNot(contains(overLimitId)));
    expect(candidates.map((row) => row['id']), isNot(contains(confirmedId)));
    expect(await sqlite.claimTransactionRetry(ambiguousId), 0);
    expect(await sqlite.claimTransactionRetry(confirmedId), 0);

    expect(await sqlite.claimTransactionRetry(rejectedId), 1);
    expect(await sqlite.beginTransactionRetryDispatch(rejectedId), 1);
    final completed = await sqlite.completeTransactionRetry(
      transactionId: rejectedId,
      resultStatus: TransactionStatuses.error,
      reply: 'Error sending code: Recommendation failed',
      ambiguousOutcome: false,
      fields: {'canRetry': 3},
    );
    expect(completed?['updated'], isTrue);
    expect(completed?['retryState'], 'ready');
    final nextAttemptCandidates = await sqlite.getAutomaticRetryCandidates(
      isAutoRetrying: true,
      retryLimit: 12,
      today: 'today',
    );
    expect(nextAttemptCandidates.map((row) => row['id']), contains(rejectedId));
  });

  test(
      'retryAll selects, dispatches, and repeats eligible Express and Advanced errors within limit',
      () async {
    SharedPreferences.setMockInitialValues({
      'offers_might_have_changed': false,
      'retry_minutes': 6,
    });
    final expressId = await db.insert('transactions', {
      'status': TransactionStatuses.error,
      'ussdReply':
          'Error sending code: PlatformException(ussd_plugin_ussd_execution_failure, USSD_RETURN_FAILURE, null, null)',
      'ussdDialed': '*180*5*2*0701135362*2*1#',
      'simSubId': 14,
      'amount': 5,
      'number': 701135362,
      'transactionId': 'EXPRESS-RETRY',
      'initialMessage': 'Payment received for offer 5',
      'canRetry': 1,
      'retryState': initialTransactionRetryState(
        status: TransactionStatuses.error,
        reply:
            'Error sending code: PlatformException(ussd_plugin_ussd_execution_failure, USSD_RETURN_FAILURE, null, null)',
      ),
      'date': 'today',
      'timeStamp': DateTime.now().millisecondsSinceEpoch,
    });
    final confirmedId = await db.insert('transactions', {
      'status': TransactionStatuses.doneConfirmed,
      'ussdReply': 'Purchase confirmed',
      'ussdDialed': '*180*5*2*0701135362*2*1#',
      'simSubId': 14,
      'amount': 5,
      'number': 701135362,
      'transactionId': 'CONFIRMED-NO-RETRY',
      'initialMessage': 'Payment received for offer 5',
      'canRetry': 1,
      'retryState': 'blocked',
      'date': 'today',
      'timeStamp': DateTime.now().millisecondsSinceEpoch,
    });
    final advancedId = await db.insert('transactions', {
      'status': TransactionStatuses.error,
      'ussdReply': 'Request cannot be completed at the moment',
      'ussdDialed': '*188*8*1*1*0701135362*1*2#',
      'simSubId': 14,
      'amount': 8,
      'number': 701135362,
      'transactionId': 'ADVANCED-RETRY',
      'initialMessage': 'Payment received for offer 8',
      'canRetry': 1,
      'retryState': 'ready',
      'date': 'today',
      'timeStamp': DateTime.now().millisecondsSinceEpoch,
    });
    await db.insert('ussdCodes', {
      'amount': 5,
      'dialSim': 14,
      'canRetry': 1,
      'isAdvanced': 0,
      'enabled': 1,
    });
    await db.insert('ussdCodes', {
      'amount': 8,
      'dialSim': 14,
      'canRetry': 1,
      'isAdvanced': 1,
      'enabled': 1,
    });
    final advancedBridgeCalls = <(String, int)>[];
    PhoneService.configureBackgroundAdvancedRequestExecutor(
      (code, subscriptionId,
          {codeSignature, required isGettingSignature}) async {
        advancedBridgeCalls.add((code, subscriptionId));
        return [
          'Request cannot be completed at the moment',
          TransactionStatuses.error
        ];
      },
    );
    final controller = _RetryAllHarness(sqlite);

    // Retry preference 6 has a scheduler limit of 12; the historical counter
    // increases by two after every dispatch.
    try {
      // This is the scheduler pass invoked by the incoming SMS path after the
      // first execution has been persisted. It must dispatch immediately.
      await controller.retryAll(true);
      expect(controller.dispatchedIds, contains(expressId));
      expect(controller.dispatchedIds, contains(advancedId));
      for (var attempt = 0; attempt < 6; attempt++) {
        await controller.retryAll(true);
      }
      await controller.retryAll(true);
    } finally {
      PhoneService.resetBackgroundAdvancedRequestExecutorForTesting();
    }

    expect(
        controller.dispatchedIds.where((id) => id == expressId), hasLength(6));
    expect(
        controller.dispatchedIds.where((id) => id == advancedId), hasLength(6));
    expect(controller.dispatchedIds, isNot(contains(confirmedId)));
    expect(advancedBridgeCalls, hasLength(6));
    expect(
      advancedBridgeCalls,
      everyElement(('*188*8*1*1*0701135362*1*2#', 14)),
    );
    for (final id in [expressId, advancedId]) {
      final row = (await db.query(
        'transactions',
        where: 'id = ?',
        whereArgs: [id],
      ))
          .single;
      expect(row['canRetry'], 13);
      expect(row['retryState'], 'ready');
    }
  });

  test('ambiguous result releases only its correlated active queue slot',
      () async {
    const recipient = 'Phone C';
    const firstJob = 'ambiguous-job';
    const nextJob = 'next-job';
    final firstId = await db.insert('transactions', {
      'status': TransactionStatuses.forwardedPending,
      'forwardingJobId': firstJob,
      'forwardingRecipientDeviceName': recipient,
      'alternativeRequestCode': '*123#',
      'alternativeQueueState': 'active',
      'canRetry': 1,
    });
    final nextId = await db.insert('transactions', {
      'status': TransactionStatuses.alternativeDeliveryPending,
      'forwardingJobId': nextJob,
      'forwardingRecipientDeviceName': recipient,
      'alternativeRequestCode': '*456#',
      'alternativeQueueState': 'waiting',
      'firstFailedTimeStamp': 2,
      'timeStamp': 2,
    });
    final pendingId = await db.insert('transactions', {
      'status': TransactionStatuses.successfulPending,
      'forwardingJobId': 'pending-job',
      'forwardingRecipientDeviceName': 'Phone C pending',
      'alternativeRequestCode': '*789#',
      'alternativeQueueState': 'active',
      'canRetry': 0,
    });

    expect(
      await sqlite.markAlternativeResultAmbiguous(
        forwardingJobId: firstJob,
        transactionId: firstId,
        ussdReply: 'Carrier outcome unknown',
      ),
      1,
    );
    expect(
      await sqlite.markAlternativeResultAmbiguous(
        forwardingJobId: firstJob,
        transactionId: firstId,
        ussdReply: 'Duplicate result',
      ),
      0,
    );
    expect(
      await sqlite.markAlternativeResultAmbiguous(
        forwardingJobId: firstJob,
        transactionId: nextId,
        ussdReply: 'Mismatched result',
      ),
      0,
    );

    final ambiguous = (await db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [firstId],
    ))
        .single;
    expect(ambiguous['status'], TransactionStatuses.alternativeAmbiguous);
    expect(ambiguous['alternativeQueueState'], 'released');
    expect(ambiguous['canRetry'], 0);
    expect(ambiguous['retryState'], 'ambiguous');

    expect(
      await sqlite.getAlternativeDeliveryRecipientsWithWaitingJobs(),
      [recipient],
    );
    final next = await sqlite.claimNextAlternativeDelivery(
      recipientDeviceName: recipient,
      now: 100,
      nextAttemptAt: 20100,
    );
    expect(next?['id'], nextId);

    expect(
      await sqlite.markAlternativeResultAmbiguous(
        forwardingJobId: 'pending-job',
        transactionId: pendingId,
        ussdReply: 'Delayed ambiguous result',
      ),
      1,
    );
    final pendingAfterAmbiguous = (await db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [pendingId],
    ))
        .single;
    expect(
        pendingAfterAmbiguous['status'], TransactionStatuses.successfulPending);
    expect(pendingAfterAmbiguous['alternativeQueueState'], 'released');

    expect(
      (await sqlite.claimNextAlternativeDelivery(
        recipientDeviceName: recipient,
        now: 20200,
        nextAttemptAt: 40200,
      ))?['id'],
      nextId,
    );
  });

  test('restart repair releases a legacy ambiguous slot without re-execution',
      () async {
    const recipient = 'Phone C restart';
    final ambiguousId = await db.insert('transactions', {
      'status': TransactionStatuses.alternativeAmbiguous,
      'forwardingJobId': 'legacy-ambiguous-job',
      'forwardingRecipientDeviceName': recipient,
      'alternativeRequestCode': '*123#',
      'alternativeQueueState': 'active',
      'canRetry': 0,
      'retryState': 'ambiguous',
    });
    final waitingId = await db.insert('transactions', {
      'status': TransactionStatuses.alternativeDeliveryPending,
      'forwardingJobId': 'restart-next-job',
      'forwardingRecipientDeviceName': recipient,
      'alternativeRequestCode': '*456#',
      'alternativeQueueState': 'waiting',
    });

    expect(await sqlite.releaseAmbiguousAlternativeQueueSlots(), [recipient]);
    final repaired = (await db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [ambiguousId],
    ))
        .single;
    expect(repaired['status'], TransactionStatuses.alternativeAmbiguous);
    expect(repaired['alternativeQueueState'], 'released');
    expect(repaired['retryState'], 'ambiguous');
    expect(repaired['canRetry'], 0);

    final claimed = await sqlite.claimNextAlternativeDelivery(
      recipientDeviceName: recipient,
      now: 100,
      nextAttemptAt: 20100,
    );
    expect(claimed?['id'], waitingId);
  });
}

class _RetryAllHarness extends TransactionController {
  _RetryAllHarness(this.sqlite)
      : super(sqliteService: sqlite, startConfirmationTimer: false);

  final SQLiteService sqlite;
  final List<int> dispatchedIds = [];

  @override
  Future<void> redoTransaction(
    int id,
    String ussdCode,
    int simSubId,
    int canRetry,
    String reply, {
    String? mpesaMessage,
    CodeSignature? codeSignature,
    bool offerResumeClaimed = false,
    bool skipForwardingCheck = false,
  }) async {
    final claims = await sqlite.claimTransactionRetry(id);
    if (claims != 1 || await sqlite.beginTransactionRetryDispatch(id) != 1) {
      return;
    }
    final rows = await sqlite.queryCustom(
      'transactions',
      'id = ?',
      [id],
      columns: ['amount'],
      limit: 1,
    );
    final offers = await sqlite.queryCustom(
      'ussdCodes',
      'amount = ?',
      [rows.single['amount']],
      columns: ['isAdvanced'],
      limit: 1,
    );
    final isAdvanced = offers.isNotEmpty && offers.single['isAdvanced'] == 1;
    dispatchedIds.add(id);
    if (isAdvanced) {
      await PhoneService().makeAdvancedRequest(ussdCode, simSubId);
    }
    await sqlite.completeTransactionRetry(
      transactionId: id,
      resultStatus: TransactionStatuses.error,
      reply: isAdvanced
          ? 'Request cannot be completed at the moment'
          : 'Error sending code: PlatformException(ussd_plugin_ussd_execution_failure, USSD_RETURN_FAILURE, null, null)',
      ambiguousOutcome: isAmbiguousTransactionOutcome(
        status: TransactionStatuses.error,
        reply: isAdvanced
            ? 'Request cannot be completed at the moment'
            : 'Error sending code: PlatformException(ussd_plugin_ussd_execution_failure, USSD_RETURN_FAILURE, null, null)',
      ),
      fields: {'canRetry': canRetry + 2, 'ussdDialed': ussdCode},
    );
  }
}
