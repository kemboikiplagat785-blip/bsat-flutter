// Phone B over LAN (disposable copy). Phone B is real: the production
// handler (handleRemoteMessage via handleLanForwardingRequest), claims and
// confirmation delivery on the default database. Phone A is a simulated
// paired phone with its own database, talking to B over a real
// authenticated session on 127.0.0.1. Synthetic data; no SMS, USSD or
// network request may happen (asserted).
import 'package:bsat/controllers/transaction_controller.dart';
import 'package:bsat/services/firebase_messaging_service.dart';
import 'package:bsat/services/lan/lan_forwarding_bootstrap.dart';
import 'package:bsat/services/lan/lan_forwarding_service.dart';
import 'package:bsat/services/lan/lan_messages.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/lan_test_support.dart';
import 'support/stage0_harness.dart';

const _receipt = 'SJK1LAN023';
const _jobId = 'fwd_${_receipt}_1793000000000';
const _sms = '$_receipt Confirmed. Ksh100.00 received from JOHN DOE '
    '0712345678. SYNTHETIC LAN TEST MESSAGE ONLY.';

Map<String, dynamic> _job({
  String sender = 'Phone A',
  String recipient = 'Phone B',
  String jobId = _jobId,
  int transactionId = 41,
}) =>
    {
      'type': 'forwarded_sms',
      'body': _sms,
      'title': 'Forwarded Message',
      'messageId': _receipt,
      'transactionId': transactionId,
      'forwardingJobId': jobId,
      'forwardingStatus': 'forwarding-pending',
      'senderDeviceName': sender,
      'recipientDeviceName': recipient,
    };

Map<String, dynamic> _alternative({String sender = 'Phone A'}) => {
      'type': 'process_alt_request',
      'transactionId': '41',
      'forwardingJobId': _jobId,
      'senderDeviceName': sender,
      'recipientDeviceName': 'Phone B',
      'ussdCode': '*180*5*2*0712345678*1*1#',
      'isAdvanced': 'false',
      'smsMessage': _sms,
      'body': 'Forwarded alternative USSD request',
      'title': 'Forwarded Code',
    };

bool _isReceipt(LanForwardingData reply) =>
    reply.kind == LanMessageKind.receiptAck;

void main() {
  final h = Stage0Harness();
  late LanTestPhone a;
  late LanTestPhone b;
  final repliesOnA = <LanForwardingData>[];
  final requestsOnA = <LanForwardingData>[];

  setUpAll(Stage0Harness.setUpAllOnce);
  tearDownAll(Stage0Harness.tearDownAllOnce);

  Future<void> phoneB({bool whitelistA = true}) async {
    await h.setUp(prefs: {
      'user_device_name': 'Phone B',
      'jwt_token': 'lan-test-jwt',
    });
    final db = await h.db;
    if (whitelistA) {
      await db.insert('whitelistedDevices', {
        'device_name': 'Phone A',
        'device_id': 'device-phone-a',
        'owner_email': 'owner@example.test',
      });
    }
    await db.insert('whitelistedDevices', {
      'device_name': 'Phone C',
      'device_id': 'device-phone-c',
      'owner_email': 'owner@example.test',
    });
    repliesOnA.clear();
    requestsOnA.clear();
    b = await LanTestPhone.create(
      'Phone B',
      sqlite: SQLiteService(),
      inboundHandler: handleLanForwardingRequest,
      replyProcessor: handleLanForwardingReply,
    );
    a = await LanTestPhone.create(
      'Phone A',
      // Phone A answers a final confirmation with its receipt, as the real
      // handler does (covered on Phone A's side in lan_bsat_sender_test).
      inboundHandler: (message, peer, reply) async {
        requestsOnA.add(message);
        if (message.kind == LanMessageKind.alternativeResult) {
          await reply({
            'data': {
              'type': 'MESSAGE_ACK',
              'ackKind': 'alternative_result_received',
              'status': 'alternative-result-received',
              'originalType': 'forwarded_alt_result',
              'resultStatus': message.data['status'],
              'transactionId': message.data['transactionId'],
              'forwardingJobId': message.forwardingJobId,
              'senderDeviceName': 'Phone A',
              'recipientDeviceName': 'Phone B',
            },
          });
        }
        if (message.kind == LanMessageKind.forwardingConfirmation) {
          await reply({
            'data': {
              'type': 'forwarded_sms_ack',
              'ackKind': 'confirmation_received',
              'status': 'received',
              'forwardingJobId': message.forwardingJobId,
              'senderDeviceName': 'Phone A',
              'recipientDeviceName': 'Phone B',
            },
          });
        }
      },
      replyProcessor: (reply, peer) async => repliesOnA.add(reply),
    );
    await pairPhones(b, a);
  }

  tearDown(() async {
    LanForwardingService.instance = null;
    await a.dispose();
    await b.dispose();
    await h.tearDown();
  });

  Future<List<Map<String, Object?>>> claims() async =>
      (await h.db).query('forwardedSmsJobs');

  Future<void> handlerFinished() => waitForAsync(
        () async => (await claims())
            .any((claim) => claim['state'] == 'completed'),
        reason: "B's handler finished the job",
      );

  test('a paired phone\'s job is durably claimed (as LAN) before its receipt '
      'ACK, which reaches Phone A over the same session', () async {
    await phoneB();
    final result = await a.service.exchange(
      recipientDeviceName: 'Phone B',
      data: _job(),
      isFinalReply: _isReceipt,
    );
    expect(result.outcome, LanExchangeOutcome.completed);
    final receipt = repliesOnA.single;
    expect(receipt.data['type'], 'MESSAGE_ACK');
    expect(receipt.data['ackKind'], 'received');
    expect(receipt.data['originalType'], 'forwarded_sms');
    expect(receipt.forwardingJobId, _jobId);
    expect(receipt.data['transactionId'], '41');
    expect(receipt.senderDeviceName, 'Phone B');
    expect(receipt.recipientDeviceName, 'Phone A');

    final claim = (await claims()).single;
    expect(claim['forwardingJobId'], _jobId);
    expect(claim['transport'], 'lan');
    expect(claim['sourceTransactionId'], '41');

    // B has no subscription and no tokens: the existing handler parks the job
    // as paused without dialling; tokens are not touched.
    await handlerFinished();
    final rows = await (await h.db).query('transactions');
    expect(rows.single['status'], TransactionStatuses.paused);
    expect(h.requests, isEmpty, reason: 'nothing goes over the Internet');
    expect(h.blockedHttpClients, isEmpty);
    h.expectNoExternalEffects();
  });

  test('a repeated delivery after a lost receipt is answered from the durable '
      'claim and never processed again', () async {
    await phoneB();
    // First delivery: B claims and processes the job, but its receipt is
    // lost (A's session ends before it arrives).
    final dropped = b.service.inboundHandler!;
    b.service.inboundHandler = (message, peer, reply) =>
        dropped(message, peer, (_) async {});
    final first = await a.service.exchange(
        recipientDeviceName: 'Phone B', data: _job(), isFinalReply: _isReceipt);
    expect(first.outcome, LanExchangeOutcome.noReply);
    await handlerFinished();
    final rowsAfterFirst = await (await h.db).query('transactions');
    expect(rowsAfterFirst, hasLength(1));

    // A retries the same job (same ID) after the ambiguous outcome.
    b.service.inboundHandler = dropped;
    final retry = await a.service.exchange(
        recipientDeviceName: 'Phone B', data: _job(), isFinalReply: _isReceipt);
    expect(retry.outcome, LanExchangeOutcome.completed);
    expect(repliesOnA.single.forwardingJobId, _jobId);
    await Stage0Harness.settle(200);
    final rows = await (await h.db).query('transactions');
    expect(rows, hasLength(1), reason: 'no second transaction for one job');
    expect(rows.single['id'], rowsAfterFirst.single['id']);
    expect((await claims()).single['state'], 'completed');
    expect(h.requests, isEmpty);
    h.expectNoExternalEffects();
  });

  test('a job naming another (whitelisted) sender is refused before any claim',
      () async {
    await phoneB();
    final result = await a.service.exchange(
      recipientDeviceName: 'Phone B',
      data: _job(sender: 'Phone C'),
      isFinalReply: _isReceipt,
    );
    expect(result.outcome, LanExchangeOutcome.refused);
    expect(result.reason, LanRejectReasons.unexpectedSender);
    expect(await claims(), isEmpty);
    expect(await (await h.db).query('transactions'), isEmpty);
    h.expectNoExternalEffects();
  });

  test('a job addressed to another device is refused before any claim',
      () async {
    await phoneB();
    final result = await a.service.exchange(
      recipientDeviceName: 'Phone B',
      data: _job(recipient: 'Phone C'),
      isFinalReply: _isReceipt,
    );
    expect(result.outcome, LanExchangeOutcome.refused);
    expect(await claims(), isEmpty);
    h.expectNoExternalEffects();
  });

  test('a LAN-paired phone needs no Online whitelist entry on B: its trusted '
      'LAN pairing authorizes the job (claimed and receipted)', () async {
    await phoneB(whitelistA: false);
    final result = await a.service.exchange(
        recipientDeviceName: 'Phone B', data: _job(), isFinalReply: _isReceipt);
    expect(result.outcome, LanExchangeOutcome.completed);
    expect(repliesOnA.single.data['ackKind'], 'received');
    expect((await claims()).single['transport'], 'lan');
    await handlerFinished();
    expect(h.requests, isEmpty);
    h.expectNoExternalEffects();
  });

  test('a revoked phone cannot reach the handler', () async {
    await phoneB();
    await b.service.revoke(a.service.identity!.fingerprint);
    final result = await a.service.exchange(
        recipientDeviceName: 'Phone B', data: _job(), isFinalReply: _isReceipt);
    expect(result.outcome, LanExchangeOutcome.authenticationFailed);
    expect(await claims(), isEmpty);
    h.expectNoExternalEffects();
  });

  test('a paired phone\'s alternative request is receipted over LAN, and '
      'its result goes back over LAN; nothing goes online', () async {
    await phoneB();
    LanForwardingService.instance = b.service;
    final db = await h.db;
    final now = DateTime.now().millisecondsSinceEpoch;
    // Already executed on B, so nothing is dialled: a repeated request is
    // still receipted and answered with the stored result.
    await db.insert('alternativeJobs', {
      'forwardingJobId': _jobId,
      'transactionId': '41',
      'state': 'completed',
      'ussdCode': '*180*5*2*0712345678*1*1#',
      'smsMessage': _sms,
      'senderDeviceName': 'Phone A',
      'recipientDeviceName': 'Phone B',
      'resultStatus': TransactionStatuses.alternativeFailed,
      'ussdReply': 'SYNTHETIC ALTERNATIVE FAILURE',
      'transport': 'lan',
      'createdAt': now,
      'updatedAt': now,
    });
    final result = await h.capture(() => a.service.exchange(
          recipientDeviceName: 'Phone B',
          data: _alternative(),
          isFinalReply: (reply) =>
              reply.kind == LanMessageKind.alternativeRequestReceipt,
        ));
    expect(result.outcome, LanExchangeOutcome.completed);
    final receipt = repliesOnA.single;
    expect(receipt.data['ackKind'], 'alternative_received');
    expect(receipt.data['status'], 'alternative-received');
    expect(receipt.data['transactionId'], '41');
    expect(receipt.senderDeviceName, 'Phone B');

    await waitForAsync(
      () async => (await db.query('alternativeJobs')).single['resultDeliveryState'] ==
          'delivered',
      reason: "A's result receipt was processed by B's handler",
    );
    final resultOnA = requestsOnA.single;
    expect(resultOnA.kind, LanMessageKind.alternativeResult);
    expect(resultOnA.data['status'], TransactionStatuses.alternativeFailed);
    expect(resultOnA.data['transactionId'], '41');
    expect(resultOnA.data['ussdReply'], 'SYNTHETIC ALTERNATIVE FAILURE');
    expect(resultOnA.senderDeviceName, 'Phone B');
    expect(h.requests, isEmpty, reason: 'never sent over the Internet');
    h.expectNoExternalEffects();
  });

  test('an alternative request that is not from the authenticated paired '
      'phone is refused before anything is stored', () async {
    await phoneB();
    final named = await a.service.exchange(
        recipientDeviceName: 'Phone B',
        data: _alternative(sender: 'Phone C'),
        isFinalReply: (_) => false);
    expect(named.outcome, LanExchangeOutcome.refused);
    expect(named.reason, LanRejectReasons.unexpectedSender);
    // Defence in depth: the handler itself refuses a sender that is not the
    // authenticated, still-trusted LAN peer.
    await h.capture(() => handleRemoteMessage(
          RemoteMessage(data: _alternative()),
          replySink: (_) async => fail('no reply may be sent'),
          authenticatedSenderDeviceName: 'Phone C',
        ));
    expect(await (await h.db).query('alternativeJobs'), isEmpty);
    expect(h.requests, isEmpty);
    h.expectNoExternalEffects();
  });

  test('other kinds never run over LAN', () async {
    await phoneB();
    final result = await a.service.exchange(
        recipientDeviceName: 'Phone B',
        data: {
          'type': 'DATA_REQUEST',
          'forwardingJobId': _jobId,
          'senderDeviceName': 'Phone A',
          'recipientDeviceName': 'Phone B',
        },
        isFinalReply: (_) => false);
    expect(result.outcome, LanExchangeOutcome.refused);
    expect(result.reason, LanRejectReasons.unsupportedType);
    expect(h.requests, isEmpty);
    h.expectNoExternalEffects();
  });

  test('the final confirmation of a LAN job goes back over LAN; Phone A\'s '
      'receipt clears the retry record', () async {
    await phoneB();
    LanForwardingService.instance = b.service;
    final db = await h.db;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('forwardedSmsJobs', {
      'forwardingJobId': _jobId,
      'sourceTransactionId': '41',
      'localTransactionId': 5,
      'state': 'completed',
      'transport': 'lan',
      'createdAt': now,
      'updatedAt': now,
    });
    await h.capture(() => TransactionController(sqliteService: SQLiteService())
        .sendForwardingConfirmation(
          forwardingJobId: _jobId,
          recipientDeviceName: 'Phone A',
          transactionId: _receipt,
        ));
    final confirmation = requestsOnA.single;
    expect(confirmation.kind, LanMessageKind.forwardingConfirmation);
    expect(confirmation.data['status'], TransactionStatuses.doneConfirmed);
    expect(confirmation.data['transactionId'], _receipt);
    expect(confirmation.senderDeviceName, 'Phone B');
    expect(await db.query('forwardingConfirmations'), isEmpty,
        reason: "A's confirmation receipt was processed by B's handler");
    expect(h.requests, isEmpty, reason: 'never sent over the Internet');
    h.expectNoExternalEffects();
  });

  test('the final confirmation of an Online job is unchanged (Internet only)',
      () async {
    await phoneB();
    LanForwardingService.instance = b.service;
    final db = await h.db;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert('forwardedSmsJobs', {
      'forwardingJobId': _jobId,
      'sourceTransactionId': '41',
      'state': 'completed',
      'transport': 'online',
      'createdAt': now,
      'updatedAt': now,
    });
    await h.capture(() => TransactionController(sqliteService: SQLiteService())
        .sendForwardingConfirmation(
          forwardingJobId: _jobId,
          recipientDeviceName: 'Phone A',
          transactionId: _receipt,
        ));
    expect(h.backendPosts, hasLength(1));
    expect(h.backendPosts.single.url.path, '/api/fcm/send-secure');
    expect(h.backendPosts.single.data['ackKind'], 'confirmed');
    expect(requestsOnA, isEmpty);
    expect(await db.query('forwardingConfirmations'), hasLength(1),
        reason: 'kept until the Internet receipt arrives, as before');
    h.expectNoExternalEffects();
  });

  test('a LAN confirmation to an unreachable Phone A stays queued for the '
      'existing retry schedule and is never sent online', () async {
    await phoneB();
    LanForwardingService.instance = b.service;
    await a.service.stopListening();
    final db = await h.db;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final (job, transport) in [(_jobId, 'lan'), ('fwd_X_17930', 'bt')]) {
      await db.insert('forwardedSmsJobs', {
        'forwardingJobId': job,
        'sourceTransactionId': '41',
        'state': 'completed',
        'transport': transport,
        'createdAt': now,
        'updatedAt': now,
      });
    }
    final controller = TransactionController(sqliteService: SQLiteService());
    await h.capture(() async {
      await controller.sendForwardingConfirmation(
          forwardingJobId: _jobId, recipientDeviceName: 'Phone A');
      await controller.sendForwardingConfirmation(
          forwardingJobId: 'fwd_X_17930', recipientDeviceName: 'Phone A');
    });
    final queued = await db.query('forwardingConfirmations');
    expect(queued, hasLength(2));
    for (final row in queued) {
      expect(row['attempt'], 1);
      expect(row['nextAttemptAt'] as int, greaterThan(now));
    }
    expect(h.requests, isEmpty);
    expect(requestsOnA, isEmpty);
    h.expectNoExternalEffects();
  });
}
