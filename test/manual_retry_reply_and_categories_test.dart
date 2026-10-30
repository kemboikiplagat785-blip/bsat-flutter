// Manual retry of any transaction, a reply on every transaction, and
// History categories that list what they count. Synthetic data on an
// in-memory database; the phone service only records the codes it is asked
// to dial.
import 'package:bsat/controllers/transaction_controller.dart';
import 'package:bsat/services/payments.dart';
import 'package:bsat/services/phone_service.dart';
import 'package:bsat/services/shared_preferences_service.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:bsat/utils/transaction_categories.dart';
import 'package:bsat/utils/transaction_reply.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late SQLiteService sqlite;
  late _RecordingPhoneService phone;
  late TransactionController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'offers_might_have_changed': false,
      'retry_minutes': 6,
    });
    final schema = SQLiteService();
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 22,
        onCreate: schema.onCreate,
        singleInstance: true,
      ),
    );
    await schema.ensureCriticalSchema(db);
    sqlite = SQLiteService(databaseOverride: db);
    phone = _RecordingPhoneService();
    controller = TransactionController(
      phoneService: phone,
      sqliteService: sqlite,
      paymentOps: _PaidPaymentOps(),
      sharedPreferencesService: SharedPreferencesService(),
      startConfirmationTimer: false,
    );
    final offerId = await db.insert('ussdCodes', {
      'amount': 50,
      'fromSim': 14,
      'dialSim': 14,
      'canRetry': 1,
      'isAdvanced': 0,
      'enabled': 1,
      'fallbackCode': '*180*5#',
    });
    await db.insert('ussdCodeVariants', {
      'ussdCodeId': offerId,
      'code': '*180*5#',
    });
  });

  tearDown(() async {
    if (db.isOpen) await db.close();
  });

  Future<int> insert(Map<String, dynamic> values) =>
      db.insert('transactions', {
        'initialMessage': 'Payment received for offer Ksh 50 from 0712345678',
        'transactionId': 'RETRY-${DateTime.now().microsecondsSinceEpoch}',
        'number': 712345678,
        'date': 'today',
        'time': '12:00',
        'ussdDialed': '*180*5#',
        'ussdReply': 'Previous reply',
        'amount': 50,
        'smsDate': 'today',
        'smsTime': '12:00',
        'simSubId': 14,
        'source': 'test',
        'timeStamp': DateTime.now().millisecondsSinceEpoch,
        'canRetry': 0,
        ...values,
      });

  Future<Map<String, dynamic>> read(int id) async =>
      (await db.query('transactions', where: 'id = ?', whereArgs: [id])).single;

  group('manual retry', () {
    for (final status in [
      TransactionStatuses.doneConfirmed,
      TransactionStatuses.successfulPending,
      TransactionStatuses.done,
      TransactionStatuses.unavailableOffer,
    ]) {
      test('runs for a transaction in $status whose earlier retry finished',
          () async {
        final id = await insert({'status': status, 'retryState': 'blocked'});

        final result = await controller.manuallyRetryTransaction(id);

        expect(result, ManualRetryResult.executionDispatched);
        expect(phone.calls, ['*180*5#@14']);
      });
    }

    test('runs for a transaction whose earlier outcome is unknown', () async {
      final id = await insert({
        'status': TransactionStatuses.advancedUssd,
        'retryState': 'ambiguous',
      });

      expect(await controller.manuallyRetryTransaction(id),
          ManualRetryResult.executionDispatched);
      expect(phone.calls, hasLength(1));
    });

    test('is refused while the transaction is being dialed', () async {
      final id = await insert({
        'status': TransactionStatuses.error,
        'retryState': 'dispatching',
        'retryStartedAt': DateTime.now().millisecondsSinceEpoch,
      });

      expect(await controller.manuallyRetryTransaction(id),
          ManualRetryResult.rejected);
      expect(phone.calls, isEmpty);
      expect((await read(id))['retryState'], 'dispatching');
    });

    test('runs for a dispatch left stuck (older than the dial lease)',
        () async {
      final id = await insert({
        'status': TransactionStatuses.error,
        'retryState': 'dispatching',
        'retryStartedAt': DateTime.now()
            .subtract(SQLiteService.manualRetryDispatchLease * 2)
            .millisecondsSinceEpoch,
      });

      expect(await controller.manuallyRetryTransaction(id),
          ManualRetryResult.executionDispatched);
      expect(phone.calls, hasLength(1));
    });

    test('a forwarded job sent from this phone gets a new job ID; a job this '
        'phone received keeps its own', () async {
      final sent = await insert({
        'status': TransactionStatuses.forwardedConfirmed,
        'retryState': 'blocked',
        'forwardingJobId': 'fwd_SENT_1',
        'forwardingRecipientDeviceName': 'Phone B',
        'forwardingTransport': 'lan',
      });
      final received = await insert({
        'status': TransactionStatuses.doneConfirmed,
        'retryState': 'blocked',
        'forwardingJobId': 'fwd_RECEIVED_1',
        'forwardingSenderDeviceName': 'Phone A',
      });

      expect(await sqlite.unlockTransactionForManualRetry(sent), isTrue);
      expect(await sqlite.unlockTransactionForManualRetry(received), isTrue);

      final sentRow = await read(sent);
      expect(sentRow['status'], TransactionStatuses.error);
      expect(sentRow['retryState'], 'ready');
      expect(sentRow['forwardingJobId'], isNull);
      expect(sentRow['forwardingRecipientDeviceName'], 'Phone B');
      expect(sentRow['forwardingTransport'], 'lan');
      expect(sentRow['ussdReply'], 'Previous reply');
      expect((await read(received))['forwardingJobId'], 'fwd_RECEIVED_1');
    });

    test('selected transactions are all retried, whatever their status',
        () async {
      final ids = [
        await insert({'status': TransactionStatuses.error}),
        await insert({
          'status': TransactionStatuses.doneConfirmed,
          'retryState': 'blocked',
        }),
      ];

      final result = await controller.retryTransactionsGivenIds(ids);

      expect(result.dispatched, 2);
      expect(phone.calls, hasLength(2));
    });

    test('Retry options retry the chosen categories, Successful(Pending) '
        'included', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await insert({
        'status': TransactionStatuses.successfulPending,
        'retryState': 'blocked',
        'timeStamp': now,
      });
      await insert({
        'status': TransactionStatuses.doneConfirmed,
        'retryState': 'blocked',
        'timeStamp': now,
      });

      await controller.retrySpecific(
          false, false, true, false, false, false, false, now - 1000, now + 1);

      expect(phone.calls, hasLength(1),
          reason: 'only the Successful(Pending) row was chosen');
    });
  });

  group('every transaction has a reply', () {
    test('a failed USSD call with an empty reply stores a readable reply',
        () async {
      phone.responses.add(('', TransactionStatuses.error));
      final id = await insert({'status': TransactionStatuses.error});

      await controller.manuallyRetryTransaction(id);

      final row = await read(id);
      expect(row['status'], TransactionStatuses.error);
      expect(row['ussdReply'], failedUssdNoReply);
    });

    test('inserts and updates never store a blank reply', () async {
      final failed = await sqlite.insertStuff({
        'status': TransactionStatuses.error,
        'ussdReply': '  ',
        'date': 'today',
      }, 'transactions');
      final pending = await sqlite.insertStuff({
        'status': TransactionStatuses.successfulPending,
        'date': 'today',
      }, 'transactions');
      expect((await read(failed))['ussdReply'], failedUssdNoReply);
      expect((await read(pending))['ussdReply'], noReplyReceived);

      await sqlite.updateStuff(
          {'status': TransactionStatuses.error, 'ussdReply': ''},
          'id = ?',
          [pending],
          'transactions');
      expect((await read(pending))['ussdReply'], failedUssdNoReply);

      await sqlite.updateStuff({'status': TransactionStatuses.timedOut},
          'id = ?', [pending], 'transactions');
      expect((await read(pending))['ussdReply'], failedUssdNoReply,
          reason: 'an update without a reply keeps the stored one');
    });

    test('a real reply is kept as it is', () {
      expect(
        transactionReplyOrFallback('Sorry, try again', TransactionStatuses.error),
        'Sorry, try again',
      );
    });
  });

  group('History categories', () {
    test('Successful(Pending) lists and counts successful-pending rows',
        () async {
      final id = await insert({'status': TransactionStatuses.successfulPending});
      final where = TransactionCategory.successfulPending.onDate('today');

      final listed = await db.query('transactions', where: where);
      final counted = await sqlite.getCount('transactions',
          appendQuery: 'WHERE $where');

      expect(listed.map((row) => row['id']), [id]);
      expect(counted, 1);
      expect(
          TransactionCategory.forQuery(TransactionStatuses.successfulPending),
          TransactionCategory.successfulPending);
      expect(TransactionCategory.forQuery(TransactionStatuses.done),
          TransactionCategory.successfulPending);
      expect(TransactionCategory.forQuery('advanced'),
          TransactionCategory.advanced);
    });

    test('every stored status belongs to a category', () async {
      final statuses = {...TransactionStatuses.statuses.values, 'No reply'};
      final ids = <int, String>{};
      for (final status in statuses) {
        ids[await insert({'status': status})] = status;
      }
      // A plain `forwarded` row that is a forwarding job (legacy Online).
      ids[await insert({
        'status': TransactionStatuses.forwarded,
        'forwardingJobId': 'fwd_LEGACY_1',
        'forwardingRecipientDeviceName': 'Phone B',
      })] = 'legacy forwarded job';

      final covered = <Object?>{};
      for (final category in TransactionCategory.all) {
        final rows = await db.query('transactions',
            columns: ['id'], where: category.onDate('today'));
        covered.addAll(rows.map((row) => row['id']));
      }
      final missing = [
        for (final entry in ids.entries)
          if (!covered.contains(entry.key)) entry.value,
      ];
      expect(missing, isEmpty);
    });

    test('offline Forwarded excludes forwarding jobs; they are pending',
        () async {
      final offline = await insert({'status': TransactionStatuses.forwarded});
      final job = await insert({
        'status': TransactionStatuses.forwarded,
        'forwardingJobId': 'fwd_LEGACY_2',
        'forwardingRecipientDeviceName': 'Phone B',
      });

      Future<List<Object?>> idsIn(TransactionCategory category) async => [
            for (final row in await db.query('transactions',
                columns: ['id'], where: category.onDate('today')))
              row['id'],
          ];

      expect(await idsIn(TransactionCategory.forwarded), [offline]);
      expect(await idsIn(TransactionCategory.forwardedPending), [job]);
    });
  });
}

class _PaidPaymentOps extends PaymentOps {
  @override
  Future<bool> hasActiveSubscription() async => true;
}

class _RecordingPhoneService extends PhoneService {
  final List<(String, String)> responses = [];
  final List<String> calls = [];

  @override
  Future<List> makeMyRequest(
    String code,
    int subscriptionId, {
    int? triesParam = 0,
  }) async {
    calls.add('$code@$subscriptionId');
    final response = responses.isEmpty
        ? ('Error sending code: timeout', TransactionStatuses.error)
        : responses.removeAt(0);
    return [response.$1, response.$2];
  }
}
