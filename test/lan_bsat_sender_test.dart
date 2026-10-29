// Phone A and job persistence for LAN forwarding (disposable copy, host
// SQLite). Phone A is real (default database, production handlers and
// controller); Phone B is a simulated paired phone with its own database
// where a session is needed. Synthetic data; no SMS, USSD or network
// request may happen unless a test asserts the exact Internet request.
import 'dart:typed_data';

import 'package:bsat/controllers/transaction_controller.dart';
import 'package:bsat/services/forwarding_transport.dart';
import 'package:bsat/services/forwarding_transport_selection.dart';
import 'package:bsat/services/lan/lan_forwarding_bootstrap.dart';
import 'package:bsat/services/lan/lan_forwarding_service.dart';
import 'package:bsat/services/lan/lan_messages.dart';
import 'package:bsat/services/lan/lan_peer_store.dart';
import 'package:bsat/services/lan_forwarding_transport.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:bsat/utils/forwarding_delivery_retry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/lan_test_support.dart';
import 'support/stage0_harness.dart';
import 'support/stage1_fakes.dart';

const _receipt = 'SJK1LAN042';
const _jobId = 'fwd_${_receipt}_1793000000000';
const _sms = '$_receipt Confirmed. Ksh100.00 received from JOHN DOE '
    '0712345678. SYNTHETIC LAN TEST MESSAGE ONLY.';

/// A [LanForwardingClient] that records exchanges and answers with a fixed
/// outcome, for the transport's own semantics.
class _FakeLanClient implements LanForwardingClient {
  final LanExchangeOutcome outcome;
  final List<Map<String, dynamic>> sent = [];
  final List<String> recipients = [];

  _FakeLanClient(this.outcome);

  @override
  Future<LanExchangeResult> exchange({
    required String recipientDeviceName,
    required Map<String, dynamic> data,
    required bool Function(LanForwardingData reply) isFinalReply,
    LanReplyProcessor? onReply,
  }) async {
    recipients.add(recipientDeviceName);
    sent.add(data);
    return LanExchangeResult(outcome, requestWritten: true);
  }

  @override
  Future<LanReachability> probe(String deviceName) async =>
      LanReachability.reachable;
}

void main() {
  final h = Stage0Harness();

  setUpAll(Stage0Harness.setUpAllOnce);
  tearDownAll(Stage0Harness.tearDownAllOnce);
  tearDown(() async {
    LanForwardingService.instance = null;
    await h.tearDown();
  });

  Future<void> phoneA() => h.setUp(prefs: {
        'user_device_name': 'Phone A',
        'jwt_token': 'lan-test-jwt',
      });

  Future<int> jobRow({
    String recipient = 'Phone B',
    Object? transport = 'lan',
    String status = TransactionStatuses.forwardedPending,
    String jobId = _jobId,
  }) async =>
      (await h.db).insert('transactions', {
        'initialMessage': _sms,
        'transactionId': _receipt,
        'amount': 100,
        'number': 712345678,
        'status': status,
        'canRetry': 1,
        'forwardingJobId': jobId,
        'forwardingSenderDeviceName': 'Phone A',
        'forwardingRecipientDeviceName': recipient,
        'forwardingTransport': transport,
        'awaitingTopUp': 0,
        'source': 'JOHN DOE',
        'ussdDialed': '',
        'ussdReply': '',
        'simSubId': -1,
        'smsDate': '2026-10-29',
        'smsTime': '10:00',
        'date': '2026-10-29',
        'time': '10:00',
        'timeStamp': DateTime.now().millisecondsSinceEpoch,
      });

  Future<Map<String, Object?>> row(int id) async =>
      (await (await h.db).query('transactions', where: 'id = ?', whereArgs: [id]))
          .single;

  group('Phone A receives over LAN (production handler)', () {
    late LanTestPhone a;
    late LanTestPhone b;
    final repliesOnB = <LanForwardingData>[];

    Future<void> pair() async {
      repliesOnB.clear();
      a = await LanTestPhone.create(
        'Phone A',
        sqlite: SQLiteService(),
        inboundHandler: handleLanForwardingRequest,
        replyProcessor: handleLanForwardingReply,
      );
      b = await LanTestPhone.create(
        'Phone B',
        replyProcessor: (reply, peer) async => repliesOnB.add(reply),
      );
      await pairPhones(a, b);
    }

    tearDown(() async {
      await a.dispose();
      await b.dispose();
    });

    Map<String, dynamic> confirmation({String sender = 'Phone B'}) => {
          'type': 'forwarded_sms_ack',
          'ackKind': 'confirmed',
          'status': TransactionStatuses.doneConfirmed,
          'resultStatus': TransactionStatuses.doneConfirmed,
          'forwardingJobId': _jobId,
          'transactionId': _receipt,
          'senderDeviceName': sender,
          'recipientDeviceName': 'Phone A',
        };

    test('a confirmation from the authenticated destination confirms the job '
        'and is receipted over LAN, never online', () async {
      await phoneA();
      await pair();
      final id = await jobRow();
      final result = await b.service.exchange(
        recipientDeviceName: 'Phone A',
        data: confirmation(),
        isFinalReply: (r) => r.kind == LanMessageKind.confirmationReceipt,
      );
      expect(result.outcome, LanExchangeOutcome.completed);
      expect((await row(id))['status'], TransactionStatuses.forwardedConfirmed);
      expect(repliesOnB.single.data['ackKind'], 'confirmation_received');
      expect(repliesOnB.single.forwardingJobId, _jobId);
      expect(h.requests, isEmpty);
      h.expectNoExternalEffects();
    });

    test('a confirmation for a job sent to another device is not applied, '
        'even from an authenticated peer', () async {
      await phoneA();
      await pair();
      final id = await jobRow(recipient: 'Phone C');
      await b.service.exchange(
        recipientDeviceName: 'Phone A',
        data: confirmation(),
        isFinalReply: (r) => r.kind == LanMessageKind.confirmationReceipt,
      );
      expect((await row(id))['status'], TransactionStatuses.forwardedPending);
      h.expectNoExternalEffects();
    });

    test('a peer naming another device as the confirming sender is refused',
        () async {
      await phoneA();
      await pair();
      final id = await jobRow(recipient: 'Phone C');
      final result = await b.service.exchange(
        recipientDeviceName: 'Phone A',
        data: confirmation(sender: 'Phone C'),
        isFinalReply: (r) => r.kind == LanMessageKind.confirmationReceipt,
      );
      expect(result.outcome, LanExchangeOutcome.refused);
      expect((await row(id))['status'], TransactionStatuses.forwardedPending);
      h.expectNoExternalEffects();
    });
  });

  group('receipt ACK semantics (Phone A processes B\'s LAN receipt)', () {
    test('a receipt acknowledges delivery only; the job stays pending',
        () async {
      await phoneA();
      final id = await jobRow();
      await handleLanForwardingReply(
        validateLanForwardingData(
          {
            'type': 'MESSAGE_ACK',
            'ackKind': 'received',
            'messageId': '',
            'requestId': '',
            'transactionId': '$id',
            'forwardingJobId': _jobId,
            'originalType': 'forwarded_sms',
            'status': 'received',
            'receivedAt': '1793000000000',
            'senderDeviceName': 'Phone B',
            'recipientDeviceName': 'Phone A',
            'body': 'received',
            'title': 'Ack receive',
          },
          allowed: {LanMessageKind.receiptAck},
          authenticatedPeerDeviceName: 'Phone B',
          ownDeviceName: 'Phone A',
        ),
        LanPeer(
          fingerprint: 'f' * 64,
          publicKey: Uint8List(32),
          deviceName: 'Phone B',
          deviceId: 'device-b',
          status: LanPeerStatus.trusted,
          pairedAt: DateTime.now(),
        ),
      );
      final r = await row(id);
      expect(r['status'], TransactionStatuses.forwardedPending,
          reason: 'a transport receipt never confirms a purchase');
      expect(r['ussdReply'].toString(),
          contains('Receipt acknowledged by destination device'));
      expect(await SQLiteService().isForwardingDeliveryAcknowledged(_jobId),
          isTrue);
      h.expectNoExternalEffects();
    });
  });

  group('delivery retries use the persisted job transport', () {
    test('lan -> LAN only, online -> Internet only, NULL/unknown -> neither',
        () async {
      await phoneA();
      final db = await h.db;
      final jobs = {
        'fwd_LAN_1793000000001': 'lan',
        'fwd_ONLINE_1793000000002': 'online',
        'fwd_NULL_1793000000003': null,
        'fwd_BT_1793000000004': 'bluetooth',
      };
      for (final entry in jobs.entries) {
        await jobRow(jobId: entry.key, transport: entry.value);
        await db.insert('forwardingDeliveryRetries', {
          'forwardingJobId': entry.key,
          'attempt': 0,
          'nextAttemptAt': DateTime.now().millisecondsSinceEpoch - 1000,
          'acknowledged': 0,
        });
      }
      final online = RecordingForwardingTransport();
      final lan = RecordingForwardingTransport();
      await h.capture(() async {
        TransactionController(
          sqliteService: SQLiteService(),
          forwardingTransport: online,
          lanForwardingTransport: lan,
          // A LAN destination switched to Online since: retries ignore it.
          forwardingTransportPreferences:
              _AllOnlinePreferences(),
        );
      });
      expect(lan.submissions.map((s) => s.request['data']['forwardingJobId']),
          ['fwd_LAN_1793000000001']);
      expect(
          online.submissions.map((s) => s.request['data']['forwardingJobId']),
          ['fwd_ONLINE_1793000000002']);
      for (final job in ['fwd_NULL_1793000000003', 'fwd_BT_1793000000004']) {
        final retry = (await db.query('forwardingDeliveryRetries',
                where: 'forwardingJobId = ?', whereArgs: [job]))
            .single;
        expect(retry['attempt'], 1);
        expect(retry['lastFailure'],
            'Forwarding transport unavailable for this job');
      }
      expect(h.backendPosts, isEmpty);
      h.expectNoExternalEffects();
    });
  });

  group('LanForwardingTransport semantics', () {
    final request = buildForwardedSmsRequestPayload(
      message: _sms,
      messageId: _receipt,
      transactionRowId: 7,
      forwardingJobId: _jobId,
      senderDeviceName: 'Phone A',
      recipientDeviceName: 'Phone B',
    );

    test('a forwarded SMS is accepted only after a durably acknowledged '
        'receipt', () async {
      for (final (outcome, acknowledged, expected) in [
        (LanExchangeOutcome.completed, true, true),
        (LanExchangeOutcome.completed, false, false),
        (LanExchangeOutcome.noReply, true, false),
        (LanExchangeOutcome.deliveryUnknown, true, false),
        (LanExchangeOutcome.unreachable, true, false),
        (LanExchangeOutcome.authenticationFailed, true, false),
      ]) {
        final client = _FakeLanClient(outcome);
        final result = await LanForwardingTransport(
          client: client,
          isDeliveryAcknowledged: (_) async => acknowledged,
        ).submit(ForwardingSubmission(request));
        expect(result.accepted, expected, reason: '$outcome/$acknowledged');
        expect(result.details['transport'], 'lan');
        expect(client.sent.single, request['data'],
            reason: 'exactly the Internet data map');
        expect(client.recipients.single, 'Phone B');
      }
    });

    test('kinds that are not LAN kinds are never sent', () async {
      final client = _FakeLanClient(LanExchangeOutcome.completed);
      final result = await LanForwardingTransport(client: client).submit(
        const ForwardingSubmission({
          'recipientDeviceName': 'Phone B',
          'data': {'type': 'process_alt_request', 'forwardingJobId': _jobId},
        }),
      );
      expect(result.accepted, isFalse);
      expect(client.sent, isEmpty);
    });

    test('without the main-isolate service LAN is unavailable, not Internet',
        () async {
      final result =
          await LanForwardingTransport().submit(ForwardingSubmission(request));
      expect(result.accepted, isFalse);
      expect(result.details['lanOutcome'], 'lan_service_unavailable');
      expect(await LanServiceRegistry.probe('Phone B'),
          LanReachability.notConfigured);
    });
  });

  group('migration (transactions.forwardingTransport)', () {
    test('only the run that adds the column marks legacy forwarding jobs '
        'online; ordinary rows stay NULL and are never converted later',
        () async {
      final db = await databaseFactoryFfiNoIsolate.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 22,
          singleInstance: false,
          onCreate: (db, v) => SQLiteService(databaseOverride: db).onCreate(db, v),
        ),
      );
      addTearDown(db.close);
      final service = SQLiteService(databaseOverride: db);
      // A legacy database: the repair adds the earlier forwarding columns but
      // not the job transport yet.
      final columns = await db.rawQuery('PRAGMA table_info(transactions)');
      expect(columns.any((c) => c['name'] == 'forwardingTransport'), isFalse);
      for (final c in [
        'forwardingJobId',
        'forwardingSenderDeviceName',
        'forwardingRecipientDeviceName',
      ]) {
        if (!columns.any((col) => col['name'] == c)) {
          await db.execute('ALTER TABLE transactions ADD COLUMN $c TEXT');
        }
      }
      await db.execute('''
        CREATE TABLE forwardedSmsJobs (
          forwardingJobId TEXT PRIMARY KEY, sourceTransactionId TEXT,
          localTransactionId INTEGER, state TEXT NOT NULL,
          createdAt INTEGER NOT NULL, updatedAt INTEGER NOT NULL)
      ''');
      await db.insert('forwardedSmsJobs', {
        'forwardingJobId': 'fwd_IN_1',
        'state': 'completed',
        'createdAt': 1,
        'updatedAt': 1,
      });
      Future<int> legacy(Map<String, Object?> values) =>
          db.insert('transactions', {
            'initialMessage': _sms,
            'transactionId': _receipt,
            'status': TransactionStatuses.forwardedPending,
            ...values,
          });
      final both = await legacy({
        'forwardingJobId': 'fwd_A_1',
        'forwardingRecipientDeviceName': 'Phone B',
      });
      final jobOnly = await legacy({'forwardingJobId': 'fwd_A_2'});
      final recipientOnly =
          await legacy({'forwardingRecipientDeviceName': 'Phone B'});
      final ordinary = await legacy({
        'status': TransactionStatuses.doneConfirmed,
        'forwardingJobId': '',
      });

      await service.ensureCriticalSchema(db);
      Future<Object?> transport(int id) async =>
          (await db.query('transactions', where: 'id = ?', whereArgs: [id]))
              .single['forwardingTransport'];
      expect(await transport(both), 'online');
      expect(await transport(jobOnly), 'online');
      expect(await transport(recipientOnly), 'online');
      expect(await transport(ordinary), isNull);
      expect(
          (await db.query('forwardedSmsJobs')).single['transport'], 'online');

      // A later job that lost its transport is not converted on later opens.
      await db.update('transactions', {'forwardingTransport': null},
          where: 'id = ?', whereArgs: [both]);
      await service.ensureCriticalSchema(db);
      await service.ensureCriticalSchema(db);
      expect(await transport(both), isNull);
      expect(await transport(ordinary), isNull);
    });
  });

  group('job identity copies keep the transport', () {
    test('dontProcess(id:) keeps the transport only with the same job ID',
        () async {
      await phoneA();
      final controller = TransactionController(sqliteService: SQLiteService());
      final id = await jobRow(transport: 'lan');
      final same = await controller.dontProcess(
          _sms, _receipt, 712345678, '', 100, -1,
          id: id,
          status: TransactionStatuses.forwardedPending,
          forwardingJobId: _jobId);
      expect((await row(same!))['forwardingTransport'], 'lan');
      final renewed = await controller.dontProcess(
          _sms, _receipt, 712345678, '', 100, -1,
          id: id,
          status: TransactionStatuses.forwardedPending,
          forwardingJobId: 'fwd_NEW_1793000000009');
      expect((await row(renewed!))['forwardingTransport'], isNull,
          reason: 'a new job ID never inherits an old route');
      final explicit = await controller.dontProcess(
          _sms, _receipt, 712345678, '', 100, -1,
          id: id,
          forwardingJobId: 'fwd_NEW_1793000000010',
          forwardingTransport: 'online');
      expect((await row(explicit!))['forwardingTransport'], 'online');
      final plain = await controller.dontProcess(
          _sms, 'PLAIN00001', 712345678, '', 100, -1);
      expect((await row(plain!))['forwardingTransport'], isNull,
          reason: 'ordinary transactions are not forwarding jobs');
    });

    test('purgeAndMerge keeps the transport of the preserved job identity',
        () async {
      await phoneA();
      final controller = TransactionController(sqliteService: SQLiteService());
      final original = await jobRow(transport: 'lan');
      final replacement = await (await h.db).insert('transactions', {
        'initialMessage': _sms,
        'transactionId': _receipt,
        'amount': 100,
        'number': 712345678,
        'status': TransactionStatuses.forwardedPending,
        'forwardingTransport': 'online',
        'canRetry': 1,
        'source': 'JOHN DOE',
        'ussdDialed': '',
        'ussdReply': '',
        'simSubId': -1,
        'smsDate': '2026-10-29',
        'smsTime': '10:00',
        'date': '2026-10-29',
        'time': '10:00',
        'timeStamp': DateTime.now().millisecondsSinceEpoch,
      });
      await controller.purgeAndMerge(replacement, original);
      final merged = await row(original);
      expect(merged['forwardingJobId'], _jobId);
      expect(merged['forwardingTransport'], 'lan');
    });

    test('a new route assigns its transport with the recipient; an existing '
        'route keeps its persisted transport', () async {
      await phoneA();
      final service = SQLiteService();
      final fresh = await (await h.db).insert('transactions', {
        'initialMessage': _sms,
        'transactionId': _receipt,
        'status': TransactionStatuses.error,
        'forwardingJobId': _jobId,
        'forwardingTransport': 'online', // legacy backfill, no recipient yet
      });
      final assigned = await service.ensureForwardingIdentity(
        transactionId: fresh,
        candidateForwardingJobId: 'fwd_OTHER_1',
        candidateRecipientDeviceName: 'Phone B',
        candidateSenderDeviceName: 'Phone A',
        candidateForwardingTransport: 'lan',
      );
      expect(assigned['forwardingJobId'], _jobId);
      expect(assigned['forwardingRecipientDeviceName'], 'Phone B');
      expect(assigned['forwardingTransport'], 'lan');

      final existing = await jobRow(transport: 'online', jobId: 'fwd_E_1');
      final kept = await service.ensureForwardingIdentity(
        transactionId: existing,
        candidateForwardingJobId: 'fwd_OTHER_2',
        candidateRecipientDeviceName: 'Phone C',
        candidateSenderDeviceName: 'Phone A',
        candidateForwardingTransport: 'lan',
      );
      expect(kept['forwardingRecipientDeviceName'], 'Phone B');
      expect(kept['forwardingTransport'], 'online',
          reason: 'an existing job is never rerouted');
    });
  });

  group('existing jobs that are not Online never fall back', () {
    test('a LAN job whose forwarding rule was removed is not "unconfigured": '
        'no SMS, no Internet, no local USSD', () async {
      await phoneA();
      final id = await jobRow(status: TransactionStatuses.error);
      final online = RecordingForwardingTransport();
      final lan = RecordingForwardingTransport()
        ..result = const ForwardingSubmissionResult(
            accepted: false, statusCode: null, details: {'transport': 'lan'});
      final controller = TransactionController(
        sqliteService: SQLiteService(),
        forwardingTransport: online,
        lanForwardingTransport: lan,
      );
      final result = await h.capture(() => controller.forwardIfNeeded(
          100, _sms, _sms, _receipt, 712345678, 'JOHN DOE', true,
          txId: id));
      expect(result.state, isNot(ForwardingAttemptState.noConfiguration));
      expect(online.submissions, isEmpty);
      expect(h.backendPosts, isEmpty);
      await h.capture(() => controller.redoTransaction(id, '', -1, 1, ''));
      expect(online.submissions, isEmpty);
      expect((await row(id))['status'], TransactionStatuses.error);
      expect(h.backendPosts, isEmpty);
      h.expectNoExternalEffects();
    });

    test('a job without a usable transport is never sent anywhere', () async {
      await phoneA();
      final db = await h.db;
      await db.insert('forwardingDevices', {
        'device_name': 'Phone B',
        'device_id': 'device-b',
        'owner_email': 'owner@example.test',
        'amounts_to_forward': '[100]',
        'paused': 0,
      });
      final id = await jobRow(transport: null, status: TransactionStatuses.error);
      final online = RecordingForwardingTransport();
      final lan = RecordingForwardingTransport();
      final result = await h.capture(() => TransactionController(
            sqliteService: SQLiteService(),
            forwardingTransport: online,
            lanForwardingTransport: lan,
          ).forwardIfNeeded(
              100, _sms, _sms, _receipt, 712345678, 'JOHN DOE', true,
              txId: id));
      expect(result.state, ForwardingAttemptState.configuredButUnavailable);
      expect(online.submissions, isEmpty);
      expect(lan.submissions, isEmpty);
      expect(h.requests, isEmpty, reason: 'not even an Internet ping');
      expect((await row(id))['ussdReply'],
          contains('no usable forwarding transport'));
      h.expectNoExternalEffects();
    });
  });

  group('manual forwarding', () {
    test('the picked device resolves to its forwarding record\'s transport',
        () async {
      await phoneA();
      final db = await h.db;
      await db.insert('forwardingDevices', {
        'device_name': 'Phone B',
        'device_id': 'device-b',
        'owner_email': 'o@example.test',
        'amounts_to_forward': '[100]',
        'forwarding_transport': 'lan',
      });
      await db.insert('forwardingDevices', {
        'device_name': 'Phone C',
        'device_id': 'device-c',
        'owner_email': 'o@example.test',
        'amounts_to_forward': '[100]',
      });
      final s = SQLiteService();
      Future<ForwardingTransportKind?> pick(String id, String name) =>
          resolveManualForwardingTransport(
              sqliteService: s, deviceId: id, deviceName: name);
      expect(await pick('device-b', 'Phone B'), ForwardingTransportKind.lan);
      expect(await pick('device-c', 'Phone C'), ForwardingTransportKind.online);
      expect(await pick('device-d', 'Phone D'), ForwardingTransportKind.online,
          reason: 'whitelist-only: the legacy manual Online path');
      expect(await pick('device-b', 'Phone B renamed'), isNull,
          reason: 'an ID bound to another name is ambiguous');
      expect(await pick('device-b', ''), isNull);
      expect(
          await resolveManualForwardingTransport(
              sqliteService: SQLiteService(databaseOverride: _ClosedDb()),
              deviceId: 'device-b',
              deviceName: 'Phone B'),
          isNull);
    });

    test('a manual LAN job is sent only over LAN, only for a LAN row',
        () async {
      await phoneA();
      final lan = RecordingForwardingTransport()
        ..result = const ForwardingSubmissionResult(
            accepted: false, statusCode: null, details: {'transport': 'lan'});
      final online = RecordingForwardingTransport();
      final controller = TransactionController(
        sqliteService: SQLiteService(),
        forwardingTransport: online,
        lanForwardingTransport: lan,
      );
      final onlineRow = await jobRow(transport: 'online', jobId: 'fwd_M_1');
      expect(
          await controller.submitManualLanForwardingJob(
              transactionId: onlineRow,
              forwardingJobId: 'fwd_M_1',
              message: _sms,
              messageId: _receipt,
              senderDeviceName: 'Phone A',
              recipientDeviceName: 'Phone B'),
          isFalse);
      expect(lan.submissions, isEmpty);

      final lanRow = await jobRow(transport: 'lan', jobId: 'fwd_M_2');
      final delivered = await controller.submitManualLanForwardingJob(
          transactionId: lanRow,
          forwardingJobId: 'fwd_M_2',
          message: _sms,
          messageId: _receipt,
          senderDeviceName: 'Phone A',
          recipientDeviceName: 'Phone B');
      expect(delivered, isFalse);
      expect(lan.submissions.single.request,
          buildForwardedSmsRequestPayload(
            message: _sms,
            messageId: _receipt,
            transactionRowId: lanRow,
            forwardingJobId: 'fwd_M_2',
            senderDeviceName: 'Phone A',
            recipientDeviceName: 'Phone B',
          ));
      final r = await row(lanRow);
      expect(r['status'], TransactionStatuses.error);
      expect(r['ussdReply'], contains('LAN forwarding failed'));
      expect(online.submissions, isEmpty);
      expect(h.requests, isEmpty);
      h.expectNoExternalEffects();
    });
  });

  group('alternatives stay Online-only', () {
    test('a queued alternative row that is not Online is never dispatched',
        () async {
      await phoneA();
      final db = await h.db;
      await db.insert('transactions', {
        'transactionId': 'RCPT-ALT',
        'initialMessage': _sms,
        'amount': 100,
        'number': 712345678,
        'status': TransactionStatuses.alternativeDeliveryPending,
        'forwardingJobId': 'fwd_ALT_1',
        'forwardingSenderDeviceName': 'Phone A',
        'forwardingRecipientDeviceName': 'Phone C',
        'forwardingTransport': 'lan',
        'alternativeRequestCode': '*180*1#',
        'alternativeRequestIsAdvanced': 0,
        'alternativeRequestSenderDeviceName': 'Phone A',
        'alternativeQueueState': 'waiting',
        'timeStamp': DateTime.now().millisecondsSinceEpoch,
      });
      await h.capture(() => TransactionController(sqliteService: SQLiteService())
          .dispatchNextAlternativeDelivery('Phone C'));
      expect(h.backendPosts, isEmpty);
      h.expectNoExternalEffects();
    });
  });
}

class _AllOnlinePreferences implements ForwardingTransportPreferences {
  @override
  Future<Object?> storedPreferenceFor(ForwardingDestination destination) async =>
      'online';
}

/// A database whose every call fails.
class _ClosedDb implements Database {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<Never>.error(StateError('database unavailable'));
}
