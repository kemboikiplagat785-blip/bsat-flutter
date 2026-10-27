import 'dart:async';

import 'package:bsat/controllers/transaction_controller.dart';
import 'package:bsat/services/payments.dart';
import 'package:bsat/services/phone_service.dart';
import 'package:bsat/services/shared_preferences_service.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
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

  test('manual retry dispatches an ambiguous Error transaction', () async {
    final id = await _insertError(
      sqlite,
      retryState: 'ambiguous',
      canRetry: 100,
    );

    final result = await controller.manuallyRetryTransaction(id);

    expect(result, ManualRetryResult.executionDispatched);
    expect(phone.calls, ['*180*5#@14']);
    final row = await _readTransaction(sqlite, id);
    expect(row['status'], TransactionStatuses.error);
    expect(row['retryState'], 'ready');
  });

  test('automatic retries repeat Error outcomes regardless of retry count',
      () async {
    final id = await _insertError(
      sqlite,
      retryState: 'blocked',
      canRetry: 100,
      date: '1999-01-01',
    );
    phone.responses.addAll([
      ('Carrier request timed out', TransactionStatuses.error),
      ('Plugin exception: outcome unknown', TransactionStatuses.error),
    ]);

    await controller.retryAll(true);
    expect(phone.calls, ['*180*5#@14']);
    var row = await _readTransaction(sqlite, id);
    expect(row['status'], TransactionStatuses.error);
    expect(row['retryState'], 'ready');

    await controller.retryAll(true);
    expect(phone.calls, hasLength(2));
    row = await _readTransaction(sqlite, id);
    expect(row['status'], TransactionStatuses.error);
    expect(row['retryState'], 'ready');

    await sqlite.reconcileSafaricomTransaction(
      transactionId: id,
      targetStatus: TransactionStatuses.successfulPending,
      message: 'Recommendation for 0712345678 submitted successfully',
    );
    expect(
      (await _readTransaction(sqlite, id))['status'],
      TransactionStatuses.successfulPending,
    );

    await controller.retryAll(true);
    expect(phone.calls, hasLength(2));
  });

  test('automatic and manual retries cannot dispatch concurrently', () async {
    final id = await _insertError(sqlite, retryState: 'ambiguous');
    final started = Completer<void>();
    final releaseDispatch = Completer<void>();
    phone.started = started;
    phone.releaseDispatch = releaseDispatch;

    final automaticRetry = controller.retryAll(true);
    await started.future;

    expect(phone.calls, hasLength(1));
    expect((await _readTransaction(sqlite, id))['retryState'], 'dispatching');
    expect(
      await controller.manuallyRetryTransaction(id),
      ManualRetryResult.rejected,
    );
    expect(phone.calls, hasLength(1));
    releaseDispatch.complete();
    await automaticRetry;
    expect(phone.calls, hasLength(1));
  });
}

Future<int> _insertError(
  SQLiteService sqlite, {
  required String retryState,
  int canRetry = 0,
  String date = 'today',
}) async {
  final db = await sqlite.database;
  return db.insert('transactions', {
    'initialMessage': 'Payment received for offer Ksh 50 from 0712345678',
    'transactionId': 'RETRY-${DateTime.now().microsecondsSinceEpoch}',
    'number': 712345678,
    'date': date,
    'time': '12:00',
    'ussdDialed': '*180*5#',
    'ussdReply': 'Previous USSD outcome unknown',
    'amount': 50,
    'smsDate': 'today',
    'smsTime': '12:00',
    'status': TransactionStatuses.error,
    'simSubId': 14,
    'source': 'test',
    'timeStamp': DateTime.now().millisecondsSinceEpoch,
    'canRetry': canRetry,
    'retryState': retryState,
  });
}

Future<Map<String, dynamic>> _readTransaction(
    SQLiteService sqlite, int id) async {
  final rows = await sqlite.queryCustom('transactions', 'id = ?', [id]);
  return rows.single;
}

class _PaidPaymentOps extends PaymentOps {
  @override
  Future<bool> hasActiveSubscription() async => true;
}

class _RecordingPhoneService extends PhoneService {
  final List<(String, String)> responses = [];
  final List<String> calls = [];
  Completer<void>? started;
  Completer<void>? releaseDispatch;

  @override
  Future<List> makeMyRequest(
    String code,
    int subscriptionId, {
    int? triesParam = 0,
  }) async {
    calls.add('$code@$subscriptionId');
    final startedSignal = started;
    if (startedSignal != null && !startedSignal.isCompleted) {
      startedSignal.complete();
    }
    await releaseDispatch?.future;
    final response = responses.isEmpty
        ? ('Error sending code: timeout', TransactionStatuses.error)
        : responses.removeAt(0);
    return [response.$1, response.$2];
  }
}
