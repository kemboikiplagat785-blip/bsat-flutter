// One-call USSD offers, and downloading offers from a paired phone over a real
// authenticated LAN session on 127.0.0.1. Synthetic data on in-memory
// databases; no USSD or network request leaves the host.
import 'dart:convert';

import 'package:bsat/controllers/transaction_controller.dart';
import 'package:bsat/services/lan/lan_forwarding_service.dart';
import 'package:bsat/services/lan/lan_messages.dart';
import 'package:bsat/services/lan/lan_offers_transfer.dart';
import 'package:bsat/services/offers_transfer_service.dart';
import 'package:bsat/services/payments.dart';
import 'package:bsat/services/phone_service.dart';
import 'package:bsat/services/shared_preferences_service.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/lan_test_support.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('one-call offers', () {
    late Database db;
    late SQLiteService sqlite;
    late _RecordingPhoneService phone;
    late TransactionController controller;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'offers_might_have_changed': false,
        'retry_minutes': 6,
      });
      db = await openPhoneDatabase();
      sqlite = SQLiteService(databaseOverride: db);
      phone = _RecordingPhoneService();
      controller = TransactionController(
        phoneService: phone,
        sqliteService: sqlite,
        paymentOps: _PaidPaymentOps(),
        sharedPreferencesService: SharedPreferencesService(),
        startConfirmationTimer: false,
      );
    });

    tearDown(() async {
      if (db.isOpen) await db.close();
    });

    Future<void> offer({required int isOneCall}) async {
      final id = await db.insert('ussdCodes', {
        'amount': 20,
        'fromSim': 14,
        'dialSim': 14,
        'canRetry': 1,
        'isAdvanced': 0,
        'isOneCall': isOneCall,
        'enabled': 1,
      });
      await db.insert('ussdCodeVariants', {
        'ussdCodeId': id,
        'code': '*180*5*2*n*2*1#',
      });
    }

    Future<int> failedTransaction() => db.insert('transactions', {
          'initialMessage': 'Payment received Ksh 20 from 0712345678',
          'transactionId': 'ONE-${DateTime.now().microsecondsSinceEpoch}',
          'number': 712345678,
          'date': 'today',
          'time': '12:00',
          'ussdDialed': '*180*5*2*0712345678*2*1#',
          'ussdReply': 'Previous reply',
          'amount': 20,
          'smsDate': 'today',
          'smsTime': '12:00',
          'simSubId': 14,
          'source': 'test',
          'timeStamp': DateTime.now().millisecondsSinceEpoch,
          'canRetry': 0,
          'status': TransactionStatuses.error,
        });

    test('a one-call offer dials through the USSD dialog, in one piece',
        () async {
      await offer(isOneCall: 1);
      await failedTransaction();

      await controller.retryAll(true);

      expect(phone.oneCalls, ['*180*5*2*0712345678*2*1#@14']);
      expect(phone.silentCalls, isEmpty);
    });

    test('any other offer keeps the silent request', () async {
      await offer(isOneCall: 0);
      await failedTransaction();

      await controller.retryAll(true);

      expect(phone.silentCalls, ['*180*5*2*0712345678*2*1#@14']);
      expect(phone.oneCalls, isEmpty);
    });

    test('the switch only applies to its own amount and code', () async {
      await offer(isOneCall: 1);

      expect(await sqlite.isOneCallCode(20, '*180*5*2*n*2*1#'), isTrue);
      expect(await sqlite.isOneCallCode(25, '*180*5*2*n*2*1#'), isFalse);
      expect(await sqlite.isOneCallCode(20, '*544*1*n#'), isFalse);
    });
  });

  group('offer pieces', () {
    test('survive the trip, including names in any language', () {
      final json = jsonEncode([
        for (var i = 0; i < 400; i++)
          {'amount': i, 'offerName': 'Ofa ya bei nafuu 🎉 $i'},
      ]);

      final chunks = splitOffersForLan(json);

      expect(chunks.length, greaterThan(1));
      expect(
        chunks.every((chunk) => chunk.length <= maxLanOffersChunkChars),
        isTrue,
      );
      expect(joinLanOffersChunks(_replies(chunks)), json);
    });

    test('a missing or out-of-order piece gives nothing', () {
      final chunks = splitOffersForLan('x' * (maxLanOffersChunkChars * 2));
      expect(chunks.length, greaterThan(2));
      final replies = _replies(chunks);

      expect(joinLanOffersChunks(replies.sublist(1)), isNull);
      expect(joinLanOffersChunks(replies.sublist(0, 2)), isNull);
      expect(joinLanOffersChunks(replies.reversed.toList()), isNull);
      expect(joinLanOffersChunks(const []), isNull);
    });

    test('a piece that breaks the rules is refused', () {
      Map<String, Object?> chunk(int part, int total, String body) => {
            'type': lanOffersChunkType,
            'forwardingJobId': 'offers_1234',
            'senderDeviceName': 'Phone A',
            'recipientDeviceName': 'Phone B',
            'part': part,
            'totalParts': total,
            'chunk': body,
          };
      LanForwardingData validate(Map<String, Object?> data) =>
          validateLanForwardingData(
            data,
            allowed: {LanMessageKind.offersChunk},
            authenticatedPeerDeviceName: 'Phone A',
            ownDeviceName: 'Phone B',
          );

      expect(validate(chunk(0, 1, 'abc')).kind, LanMessageKind.offersChunk);
      final invalid = isA<LanMessageException>();
      expect(() => validate(chunk(1, 1, 'abc')), throwsA(invalid));
      expect(() => validate(chunk(0, 1, '')), throwsA(invalid));
      expect(
        () => validate(chunk(0, maxLanOffersChunks + 1, 'abc')),
        throwsA(invalid),
      );
      expect(
        () => validate(chunk(0, 1, 'a' * (maxLanOffersChunkChars + 1))),
        throwsA(invalid),
      );
    });
  });

  group('downloading over LAN', () {
    late LanTestPhone source;
    late LanTestPhone receiver;
    late _ExportingOffers exported;
    late _RecordingImports imports;
    var sourceAllows = true;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      sourceAllows = true;
      exported = _ExportingOffers();
      imports = _RecordingImports();
      source = await LanTestPhone.create(
        'Phone A',
        inboundHandler: (message, peer, reply) async {
          await SharedPreferencesService().setDownloadOffers(sourceAllows);
          await serveLanOffersRequest(
            message,
            reply,
            offersTransferService: exported,
          );
        },
      );
      receiver = await LanTestPhone.create('Phone B');
      await source.service.loadIdentity(createIfAbsent: true);
      await receiver.service.loadIdentity(createIfAbsent: true);
      await source.service.startListening();
      await receiver.service.startListening();
      await pairPhones(source, receiver);
    });

    tearDown(() async {
      await source.dispose();
      await receiver.dispose();
    });

    Future<int> download() => downloadOffersOverLan(
          client: receiver.service,
          ownDeviceName: 'Phone B',
          deviceName: 'Phone A',
          offersTransferService: imports,
        );

    test('brings all the offers, even more than fit one message', () async {
      exported.offers = jsonEncode([
        for (var i = 0; i < 300; i++)
          {
            'amount': i,
            'offerName': 'Offer $i',
            'variants': [
              {'code': '*180*5*2*n*$i*1#'},
            ],
          },
      ]);
      expect(splitOffersForLan(exported.offers).length, greaterThan(1));

      expect(await download(), 300);
      expect(imports.received, exported.offers);
    });

    test('says so when the other phone has downloads turned off', () async {
      sourceAllows = false;
      exported.offers = '[{"amount":20}]';

      await expectLater(
        download(),
        throwsA(
          isA<LanOffersDownloadException>().having(
            (error) => error.message,
            'message',
            contains('turned off'),
          ),
        ),
      );
      expect(imports.received, isNull);
    });

    test('says so when the other phone has no offers', () async {
      exported.offers = '[]';

      await expectLater(download(), throwsA(isA<LanOffersDownloadException>()));
    });

    test('a phone that is not paired gets nothing', () async {
      await expectLater(
        downloadOffersOverLan(
          client: receiver.service,
          ownDeviceName: 'Phone B',
          deviceName: 'Phone C',
          offersTransferService: imports,
        ),
        throwsA(
          isA<LanOffersDownloadException>().having(
            (error) => error.message,
            'message',
            contains('not paired'),
          ),
        ),
      );
      expect(imports.received, isNull);
    });
  });

  group('offer export', () {
    test('keeps the one-call switch, and import applies it', () async {
      SharedPreferences.setMockInitialValues({});
      final db = await openPhoneDatabase();
      addTearDown(db.close);
      final service =
          OffersTransferService(sqliteService: SQLiteService(databaseOverride: db));
      final id = await db.insert('ussdCodes', {
        'amount': 20,
        'fromSim': 14,
        'dialSim': 14,
        'canRetry': 1,
        'isAdvanced': 0,
        'isOneCall': 1,
        'enabled': 1,
      });
      await db.insert('ussdCodeVariants', {
        'ussdCodeId': id,
        'code': '*180*5*2*n*2*1#',
      });

      final json = await service.exportOffersJson();
      expect(jsonDecode(json).single['isOneCall'], 1);

      expect(await service.importOffersFromPayload(json), 1);
      expect((await db.query('ussdCodes')).single['isOneCall'], 1);
    });
  });
}

List<LanForwardingData> _replies(List<String> chunks) => [
      for (var part = 0; part < chunks.length; part++)
        LanForwardingData(LanMessageKind.offersChunk, {
          'part': '$part',
          'totalParts': '${chunks.length}',
          'chunk': chunks[part],
        }),
    ];

class _ExportingOffers extends OffersTransferService {
  String offers = '[]';

  @override
  Future<String> exportOffersJson() async => offers;
}

class _RecordingImports extends OffersTransferService {
  String? received;

  @override
  Future<int> importOffersFromPayload(
    dynamic rawOffers, {
    bool replaceExisting = true,
  }) async {
    received = rawOffers as String;
    return (jsonDecode(received!) as List).length;
  }
}

class _PaidPaymentOps extends PaymentOps {
  @override
  Future<bool> hasActiveSubscription() async => true;
}

class _RecordingPhoneService extends PhoneService {
  final List<String> silentCalls = [];
  final List<String> oneCalls = [];

  @override
  Future<List> makeMyRequest(
    String code,
    int subscriptionId, {
    int? triesParam = 0,
  }) async {
    silentCalls.add('$code@$subscriptionId');
    return ['Error sending code: timeout', TransactionStatuses.error];
  }

  @override
  Future<List> makeOneCallRequest(String code, int subscriptionId) async {
    oneCalls.add('$code@$subscriptionId');
    return ['Error sending code: timeout', TransactionStatuses.error];
  }
}
