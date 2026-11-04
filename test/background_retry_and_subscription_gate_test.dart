import 'package:bsat/controllers/transaction_controller.dart';
import 'package:bsat/models/code_signature.dart';
import 'package:bsat/services/payments.dart';
import 'package:bsat/services/phone_service.dart';
import 'package:bsat/services/shared_preferences_service.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:bsat/utils/date_ops.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _code = '*180*5*n#';
const _dialed = '*180*5*0712345678#';
const _body = 'SJK1ABCD23 Confirmed. Ksh50.00 received from JOHN DOE '
    '254712345678 on 1/1/26 at 8:00 AM.';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late SQLiteService sqlite;
  late _RecordingPhoneService phone;
  late int offerId;

  TransactionController controllerWith(PaymentOps payments) =>
      _NoRepliesController(
        phoneService: phone,
        sqliteService: sqlite,
        paymentOps: payments,
        sharedPreferencesService: SharedPreferencesService(),
        startConfirmationTimer: false,
      );

  String today() => getNormalDate(DateTime.now());

  Future<int> insertTransaction(String status,
          {int canRetry = 0, String? date}) =>
      db.insert('transactions', {
        'initialMessage': _body,
        'transactionId': 'SJK1ABCD23',
        'number': 712345678,
        'amount': 50,
        'date': date ?? today(),
        'time': '08:00:00',
        'smsDate': date ?? today(),
        'smsTime': '08:00:00',
        'ussdDialed': _dialed,
        'ussdReply': 'Offer might have changed at step 2.',
        'simSubId': 14,
        'status': status,
        'canRetry': canRetry,
        'source': 'JOHN DOE',
        'timeStamp': DateTime.now().millisecondsSinceEpoch,
      });

  Future<void> insertSignature({bool autoSwitch = true}) async {
    await db.insert(
      'codeSignature',
      CodeSignature(
        ussdCodeId: offerId,
        usdCode: _code,
        acceptedProcedure: [
          {'options': '1:Data\n2:Calls', 'choice': '5'},
          {'options': 'Enter the number', 'choice': 'n'},
        ],
        isActive: true,
        autoSwitch: autoSwitch,
      ).sqlSavableForm(),
    );
  }

  Future<Map<String, Object?>> readTransaction(int id) async =>
      (await db.query('transactions', where: 'id = ?', whereArgs: [id])).single;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'offers_might_have_changed': false,
      'retry_minutes': 6,
      // The dashboard sets this to false whenever it leaves the screen.
      'app_usage_state': false,
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
    offerId = await db.insert('ussdCodes', {
      'amount': 50,
      'fromSim': 14,
      'dialSim': 14,
      'canRetry': 1,
      'isAdvanced': 1,
      'enabled': 1,
      'fallbackCode': _code,
    });
    await db.insert('ussdCodeVariants', {
      'ussdCodeId': offerId,
      'code': _code,
    });
  });

  tearDown(() async {
    if (db.isOpen) await db.close();
  });

  group('retrying with the app off screen', () {
    test('Advanced USSD retries', () async {
      final id = await insertTransaction(TransactionStatuses.error);

      await controllerWith(_Paid()).retryAll(true);

      expect(phone.advancedCalls, [_dialed]);
      expect(phone.plainCalls, isEmpty);
      expect((await readTransaction(id))['ussdReply'], 'Dialed');
    });

    test('Express USSD retries', () async {
      await db.update('ussdCodes', {'isAdvanced': 0});
      await insertTransaction(TransactionStatuses.error);

      await controllerWith(_Paid()).retryAll(true);

      expect(phone.plainCalls, [_dialed]);
      expect(phone.advancedCalls, isEmpty);
    });
  });

  group('without a subscription', () {
    test('a retry dials nothing', () async {
      await insertTransaction(TransactionStatuses.error);

      await controllerWith(_Unpaid()).retryAll(true);

      expect(phone.allCalls, isEmpty);
    });

    test('a due alternative code waits and dials nothing', () async {
      await db.update('ussdCodeVariants', {
        'alternativeUssdCode': '*180*6*n#',
        'altDelaySeconds': 0,
      });
      final id = await insertTransaction(TransactionStatuses.secondAttempt);
      await db.update(
        'transactions',
        {'firstFailedTimeStamp': 1},
        where: 'id = ?',
        whereArgs: [id],
      );

      await controllerWith(_Unpaid()).retryAll(true);

      expect(phone.allCalls, isEmpty);
      expect(
        (await readTransaction(id))['status'],
        TransactionStatuses.secondAttempt,
      );
    });

    test('a due alternative code is claimed once there is a subscription',
        () async {
      await db.update('ussdCodeVariants', {
        'alternativeUssdCode': '*180*6*n#',
        'altDelaySeconds': 0,
      });
      final id = await insertTransaction(TransactionStatuses.secondAttempt);
      await db.update(
        'transactions',
        {'firstFailedTimeStamp': 1},
        where: 'id = ?',
        whereArgs: [id],
      );

      // Throws where it would dial; reaching that point is what this checks.
      await expectLater(
        controllerWith(_Paid()).retryAll(true),
        throwsA(anything),
      );

      expect(
        (await readTransaction(id))['status'],
        TransactionStatuses.alternativeExecuting,
      );
    });

    test('a forwarded payment shows the customer on the receiving phone',
        () async {
      final id =
          await controllerWith(_Unpaid()).recordForwardedSmsWithoutSubscription(
        _body,
        forwardingJobId: 'job-1',
        forwardingSenderDeviceName: 'Phone A',
      );

      final row = await readTransaction(id!);
      expect(row['source'], 'JOHN DOE');
      expect(row['number'], 712345678);
      expect(row['amount'], 50);
      expect(row['transactionId'], 'SJK1ABCD23');
      expect(row['status'], TransactionStatuses.paused);
      expect(row['forwardingJobId'], 'job-1');
      expect(row['forwardingSenderDeviceName'], 'Phone A');
      expect(phone.allCalls, isEmpty);
    });
  });

  group('Offer Changed with auto switch', () {
    test('retries with the signature of the dialed code', () async {
      await insertSignature();
      final id = await insertTransaction(TransactionStatuses.offerChanged);

      await controllerWith(_Paid()).retryAll(true);

      expect(phone.advancedCalls, [_dialed]);
      expect(phone.signatures.single?.usdCode, _code);
      expect((await readTransaction(id))['ussdReply'], 'Dialed');
    });

    test('stays stopped when the retry stops at the menu again, then gives up',
        () async {
      await insertSignature();
      phone.advancedStatus = TransactionStatuses.offerChanged;
      final id = await insertTransaction(TransactionStatuses.offerChanged);
      final controller = controllerWith(_Paid());

      for (var tick = 0; tick < 10; tick++) {
        await controller.retryAll(true);
      }

      // retry_minutes 6 allows a count of 12, and each retry adds 2.
      expect(phone.advancedCalls, hasLength(6));
      expect(
        (await readTransaction(id))['status'],
        TransactionStatuses.offerChanged,
      );
    });

    test('does not retry when the offer has auto switch off', () async {
      await insertSignature(autoSwitch: false);
      await insertTransaction(TransactionStatuses.offerChanged);

      await controllerWith(_Paid()).retryAll(true);

      expect(phone.allCalls, isEmpty);
    });

    test('does not retry when auto switch is off in settings', () async {
      SharedPreferences.setMockInitialValues({
        'offers_might_have_changed': false,
        'retry_minutes': 6,
        'can_auto_switch': false,
      });
      await insertSignature();
      await insertTransaction(TransactionStatuses.offerChanged);

      await controllerWith(_Paid()).retryAll(true);

      expect(phone.allCalls, isEmpty);
    });

    test('does not retry a transaction from another day', () async {
      await insertSignature();
      await insertTransaction(
        TransactionStatuses.offerChanged,
        date: '2000-01-01',
      );

      await controllerWith(_Paid()).retryAll(true);

      expect(phone.allCalls, isEmpty);
    });

    test('dials nothing without a subscription', () async {
      await insertSignature();
      await insertTransaction(TransactionStatuses.offerChanged);

      await controllerWith(_Unpaid()).retryAll(true);

      expect(phone.allCalls, isEmpty);
    });
  });
}

/// Replies are sent through the SMS plugin, which needs Android.
class _NoRepliesController extends TransactionController {
  _NoRepliesController({
    super.phoneService,
    super.sqliteService,
    super.paymentOps,
    super.sharedPreferencesService,
    super.startConfirmationTimer,
  });

  @override
  Future<void> processReply(
    int number,
    String transactionStatus,
    String firstName,
    String lastName,
    int amount,
  ) async {}
}

class _Paid extends PaymentOps {
  @override
  Future<bool> hasActiveSubscription() async => true;
}

class _Unpaid extends PaymentOps {
  @override
  Future<bool> hasActiveSubscription() async => false;
}

class _RecordingPhoneService extends PhoneService {
  final plainCalls = <String>[];
  final advancedCalls = <String>[];
  final signatures = <CodeSignature?>[];
  String advancedStatus = TransactionStatuses.advancedUssd;

  List<String> get allCalls => [...plainCalls, ...advancedCalls];

  @override
  Future<List> makeMyRequest(
    String code,
    int subscriptionId, {
    int? triesParam = 0,
  }) async {
    plainCalls.add(code);
    return ['Dialed', TransactionStatuses.done];
  }

  @override
  Future<List> makeAdvancedRequest(
    String code,
    int subscriptionId, {
    CodeSignature? codeSignature,
    bool isGettingSignature = false,
  }) async {
    advancedCalls.add(code);
    signatures.add(codeSignature);
    return ['Dialed', advancedStatus];
  }
}
