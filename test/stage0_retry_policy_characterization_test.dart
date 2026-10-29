// STAGE 0 characterization (disposable copy only) of HEAD 086d14e's automatic
// retry policy, as decided by the user: ambiguous USSD *error* outcomes stay
// eligible for automatic retry; claims, the pre-dispatch evidence recheck and
// late Safaricom reconciliation still apply. A transport refactor must leave
// every expectation here unchanged.
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/stage0_harness.dart';

void main() {
  final h = Stage0Harness();

  setUpAll(Stage0Harness.setUpAllOnce);
  tearDownAll(Stage0Harness.tearDownAllOnce);
  tearDown(h.tearDown);
  setUp(h.setUp);

  Future<int> insert(Map<String, Object?> values) async =>
      (await h.db).insert('transactions', {
        'transactionId': 'RCPT${DateTime.now().microsecondsSinceEpoch}',
        'amount': 50,
        'number': 712345678,
        'date': '2099-01-01',
        'timeStamp': DateTime.now().millisecondsSinceEpoch,
        ...values,
      });

  Future<Set<Object?>> candidateIds() async =>
      (await SQLiteService().getAutomaticRetryCandidates(
              isAutoRetrying: true, retryLimit: 6, today: '2099-01-01'))
          .map((row) => row['id'])
          .toSet();

  test('ambiguous error stays an automatic candidate until a late Safaricom '
      'confirmation reconciles it', () async {
    final sqlite = SQLiteService();
    final id = await insert({
      'status': TransactionStatuses.error,
      'retryState': 'ambiguous',
      'canRetry': 3,
      'ussdReply': 'Error sending code: timeout',
    });

    expect(await candidateIds(), contains(id));
    expect(await sqlite.claimTransactionRetry(id), 1);
    expect(await sqlite.claimTransactionRetry(id), 0,
        reason: 'a second worker cannot claim the same retry');
    await sqlite.releaseUndispatchedTransactionRetryClaim(id);

    expect(
      await sqlite.reconcileSafaricomTransaction(
        transactionId: id,
        targetStatus: TransactionStatuses.doneConfirmed,
        message: 'SYNTHETIC Safaricom confirmation',
      ),
      1,
    );
    final row = (await (await h.db)
            .query('transactions', where: 'id = ?', whereArgs: [id]))
        .single;
    expect(row['status'], TransactionStatuses.doneConfirmed);
    expect(row['retryState'], 'blocked');
    expect(row['canRetry'], 0);
    expect(await candidateIds(), isNot(contains(id)));
    expect(await sqlite.claimTransactionRetry(id), 0);
  });

  test('a claimed ambiguous error cannot dispatch once confirmation evidence '
      'arrives before dispatch', () async {
    final sqlite = SQLiteService();
    final id = await insert({
      'status': TransactionStatuses.error,
      'retryState': 'ambiguous',
      'ussdReply': 'Error sending code: timeout',
    });
    expect(await sqlite.claimTransactionRetry(id), 1);
    await sqlite.reconcileSafaricomTransaction(
      transactionId: id,
      targetStatus: TransactionStatuses.successfulPending,
      message: 'SYNTHETIC recommendation submitted',
    );
    expect(await sqlite.beginTransactionRetryDispatch(id), 0);
  });

  test('forwarding states are not automatic retry candidates; a forwarded '
      'row that fell back to error is', () async {
    final pending = await insert({
      'status': TransactionStatuses.forwardedPending,
      'forwardingJobId': 'fwd_A_1',
    });
    final confirmed = await insert({
      'status': TransactionStatuses.forwardedConfirmed,
      'forwardingJobId': 'fwd_B_1',
    });
    final ambiguousAlt = await insert({
      'status': TransactionStatuses.alternativeAmbiguous,
      'forwardingJobId': 'fwd_C_1',
    });
    final fellBack = await insert({
      'status': TransactionStatuses.error,
      'forwardingJobId': 'fwd_D_1',
      'ussdReply':
          'Forwarding failed: Phone offline or server not reachable. Will retry later.',
    });
    final ids = await candidateIds();
    expect(ids, isNot(contains(pending)));
    expect(ids, isNot(contains(confirmed)));
    expect(ids, isNot(contains(ambiguousAlt)));
    expect(ids, contains(fellBack));
  });
}
