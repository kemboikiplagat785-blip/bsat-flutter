// The "Kindly wait" acknowledgement confirming a purchase, the auto-retry of
// transactions left in Successful(Pending), and the reply triggers for the
// newer categories. Synthetic data on an in-memory database.
import 'package:bsat/controllers/transaction_controller.dart';
import 'package:bsat/models/transaction_message.dart';
import 'package:bsat/services/payments.dart';
import 'package:bsat/services/phone_service.dart';
import 'package:bsat/services/shared_preferences_service.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:bsat/utils/date_ops.dart';
import 'package:bsat/utils/transaction_categories.dart';
import 'package:bsat/utils/transaction_execution_safety.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _acknowledgement =
    'Thank you for choosing Safaricom.Kindly wait as we process your request.';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late SQLiteService sqlite;
  late _RecordingPhoneService phone;
  late TransactionController controller;

  Future<void> start({int? stalePendingMinutes}) async {
    SharedPreferences.setMockInitialValues({
      'offers_might_have_changed': false,
      'retry_minutes': 6,
      if (stalePendingMinutes != null)
        'stale_pending_retry_minutes': stalePendingMinutes,
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
  }

  tearDown(() async {
    if (db.isOpen) await db.close();
  });

  Future<int> insert(Map<String, dynamic> values) =>
      db.insert('transactions', {
        'initialMessage': 'Payment received for offer Ksh 50 from 0712345678',
        'transactionId': 'T-${DateTime.now().microsecondsSinceEpoch}',
        'number': 712345678,
        'amount': 50,
        'ussdDialed': '*180*5#',
        'ussdReply': 'first reply',
        'simSubId': 14,
        'canRetry': 0,
        'retryState': 'blocked',
        'date': getNormalDate(DateTime.now()),
        'time': '12:00',
        'smsDate': 'today',
        'smsTime': '12:00',
        'source': 'test',
        'timeStamp': DateTime.now().millisecondsSinceEpoch,
        ...values,
      });

  Future<Map<String, dynamic>> read(int id) async =>
      (await sqlite.queryCustom('transactions', 'id = ?', [id])).single;

  int minutesAgo(int minutes) => DateTime.now()
      .subtract(Duration(minutes: minutes))
      .millisecondsSinceEpoch;

  Future<void> receive(String body, {int? sim}) => controller.updateWithMessage(
        TransactionMessage(
          body: body,
          subscriptionId: sim,
          date: DateTime.now().millisecondsSinceEpoch,
        ),
        notifyReplies: false,
      );

  group('Kindly wait acknowledgement', () {
    test('as a USSD reply confirms the transaction', () async {
      await start();
      expect(
        await controller.transactionStatus(
          [_acknowledgement, TransactionStatuses.advancedUssd],
        ),
        TransactionStatuses.doneConfirmed,
      );
    });

    test('other Safaricom wording is not an acknowledgement', () {
      expect(
        isSafaricomPurchaseAcknowledgement(
          'Sorry, we are unable to process your request at the moment.',
        ),
        isFalse,
      );
      expect(
        isSafaricomPurchaseAcknowledgement('Kindly wait as we process this.'),
        isFalse,
      );
    });

    test('naming the customer confirms that customer\'s transaction', () async {
      await start();
      final id = await insert({'status': TransactionStatuses.advancedUssd});
      final other = await insert({
        'status': TransactionStatuses.advancedUssd,
        'number': 722000111,
      });

      await receive('$_acknowledgement Bundle for 0712345678.');

      expect((await read(id))['status'], TransactionStatuses.doneConfirmed);
      expect((await read(other))['status'], TransactionStatuses.advancedUssd);
    });

    test('naming nobody confirms the only recent Advanced transaction',
        () async {
      await start();
      final id = await insert({'status': TransactionStatuses.advancedUssd});

      await receive(_acknowledgement, sim: 14);

      final row = await read(id);
      expect(row['status'], TransactionStatuses.doneConfirmed);
      expect(row['ussdReply'], contains('Kindly wait'));
    });

    test('naming nobody leaves two recent Advanced transactions alone',
        () async {
      await start();
      final first = await insert({'status': TransactionStatuses.advancedUssd});
      final second = await insert({
        'status': TransactionStatuses.advancedUssd,
        'number': 722000111,
      });

      await receive(_acknowledgement, sim: 14);

      expect((await read(first))['status'], TransactionStatuses.advancedUssd);
      expect((await read(second))['status'], TransactionStatuses.advancedUssd);
    });

    test('naming nobody skips another SIM, old dials and other statuses',
        () async {
      await start();
      final otherSim = await insert({
        'status': TransactionStatuses.advancedUssd,
        'simSubId': 15,
      });
      final old = await insert({
        'status': TransactionStatuses.advancedUssd,
        'timeStamp': minutesAgo(5),
      });
      final pending = await insert({
        'status': TransactionStatuses.successfulPending,
      });

      await receive(_acknowledgement, sim: 14);

      expect(
        (await read(otherSim))['status'],
        TransactionStatuses.advancedUssd,
      );
      expect((await read(old))['status'], TransactionStatuses.advancedUssd);
      expect(
        (await read(pending))['status'],
        TransactionStatuses.successfulPending,
      );
    });

    test('an acknowledgement before the row exists confirms it afterwards',
        () async {
      await start();
      await receive(_acknowledgement, sim: 14);
      final id = await insert({'status': TransactionStatuses.advancedUssd});

      await sqlite.getUnresolvedSafaricomMessages().then((messages) async {
        expect(messages, hasLength(1));
        await controller.updateWithMessage(
          TransactionMessage(
            body: messages.single['body'].toString(),
            date: int.parse(messages.single['smsTimestamp'].toString()),
          ),
          retryUnresolvedMessages: false,
          notifyReplies: false,
        );
      });

      expect((await read(id))['status'], TransactionStatuses.doneConfirmed);
      expect(await sqlite.getUnresolvedSafaricomMessages(), isEmpty);
    });

    test('the later purchase message keeps the transaction confirmed',
        () async {
      await start();
      final id = await insert({'status': TransactionStatuses.advancedUssd});

      await receive(_acknowledgement, sim: 14);
      await receive(
        'Thank you for choosing Safaricom. You have purchased Content bundles '
        'for 0712345678.',
      );

      final row = await read(id);
      expect(row['status'], TransactionStatuses.doneConfirmed);
      expect(row['ussdReply'], contains('You have purchased'));
    });
  });

  group('auto-retry of long pending transactions', () {
    test('is off unless enabled', () async {
      await start();
      final id = await insert({
        'status': TransactionStatuses.successfulPending,
        'timeStamp': minutesAgo(60),
      });

      await controller.retryAll(true);

      expect(phone.calls, isEmpty);
      expect((await read(id))['status'], TransactionStatuses.successfulPending);
    });

    test('retries once the chosen time has passed, not before', () async {
      await start(stalePendingMinutes: 20);
      final stale = await insert({
        'status': TransactionStatuses.successfulPending,
        'timeStamp': minutesAgo(21),
      });
      final recent = await insert({
        'status': TransactionStatuses.successfulPending,
        'timeStamp': minutesAgo(19),
        'number': 722000111,
      });

      await controller.retryAll(true);

      expect(phone.calls, ['*180*5#@14']);
      final retried = await read(stale);
      expect(retried['stalePendingRetries'], 1);
      expect(retried['retryStartedAt'], isNotNull);
      expect((await read(recent))['status'],
          TransactionStatuses.successfulPending);
    });

    test('the wait restarts from the latest retry', () async {
      await start(stalePendingMinutes: 20);
      await insert({
        'status': TransactionStatuses.successfulPending,
        'timeStamp': minutesAgo(90),
        'retryStartedAt': minutesAgo(5),
      });

      await controller.retryAll(true);

      expect(phone.calls, isEmpty);
    });

    test('stops at the retry limit', () async {
      await start(stalePendingMinutes: 20);
      final id = await insert({
        'status': TransactionStatuses.successfulPending,
        'timeStamp': minutesAgo(60),
        'stalePendingRetries': SQLiteService.maxStalePendingRetries,
      });

      await controller.retryAll(true);

      expect(phone.calls, isEmpty);
      expect((await read(id))['status'], TransactionStatuses.successfulPending);
    });

    test('leaves transactions over a day old alone', () async {
      await start(stalePendingMinutes: 20);
      await insert({
        'status': TransactionStatuses.successfulPending,
        'timeStamp': minutesAgo(60 * 25),
      });

      await controller.retryAll(true);

      expect(phone.calls, isEmpty);
    });

    test('leaves confirmed transactions and disabled offers alone', () async {
      await start(stalePendingMinutes: 20);
      await insert({
        'status': TransactionStatuses.doneConfirmed,
        'timeStamp': minutesAgo(60),
      });
      final disabled = await insert({
        'status': TransactionStatuses.successfulPending,
        'timeStamp': minutesAgo(60),
        'number': 722000111,
      });
      await db.update('ussdCodes', {'enabled': 0});

      await controller.retryAll(true);

      expect(phone.calls, isEmpty);
      expect(
        (await read(disabled))['status'],
        TransactionStatuses.successfulPending,
      );
    });

    test('a confirmation arriving first keeps it out of the retry', () async {
      await start(stalePendingMinutes: 20);
      final id = await insert({
        'status': TransactionStatuses.successfulPending,
        'timeStamp': minutesAgo(60),
      });
      final staleBefore = minutesAgo(20);
      await sqlite.reconcileSafaricomTransaction(
        transactionId: id,
        targetStatus: TransactionStatuses.doneConfirmed,
        message: 'You have successfully recommended offer to 0712345678',
      );

      expect(
        await sqlite.moveStalePendingToRetry(id, staleBefore: staleBefore),
        isFalse,
      );
      expect((await read(id))['status'], TransactionStatuses.doneConfirmed);
    });
  });

  group('reply triggers', () {
    test('every category a customer can be told about has a trigger', () {
      // Second Attempt and Error also cover statuses with no reply of their
      // own. A masked message has no number to reply to.
      final triggers = TransactionStatuses.statuses.values.toSet();
      for (final category in TransactionCategory.all) {
        if (category.key == TransactionStatuses.masked) continue;
        expect(triggers, contains(category.key), reason: category.label);
      }
    });

    test('a reply for a new category is found', () async {
      await start();
      for (final status in [
        TransactionStatuses.successfulPending,
        TransactionStatuses.forwardedConfirmed,
        TransactionStatuses.pataMore,
        TransactionStatuses.offerChanged,
      ]) {
        expect(await controller.hasConfiguredReplyFor(status, 50), isFalse);
        await db.insert('replies', {
          'reply': 'reply for $status',
          'condition': TransactionStatuses.statuses.entries
              .firstWhere((entry) => entry.value == status)
              .key,
          'conditionAmount': 1,
          'dialSim': 14,
          'amounts': '[]',
        });
        expect(await controller.hasConfiguredReplyFor(status, 50), isTrue);
      }
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
