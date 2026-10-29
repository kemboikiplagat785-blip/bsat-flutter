@Tags(['requires-system-sqlite'])
// Manual re-forward reproduction (disposable copy). Characterizes the
// integration as delivered (patch B91C218F...): a manual forward of a
// transaction whose job the destination already accepted creates a NEW job
// ID, and Phone B treats each job ID as a separate request, over both LAN and
// the Internet path. Synthetic data; no real SMS, USSD or network request.
// System-SQLite variant: Phone B's purchase path reaches _findReplyFor.
library;
import 'package:bsat/controllers/transaction_controller.dart';
import 'package:bsat/services/firebase_messaging_service.dart';
import 'package:bsat/services/lan/lan_forwarding_bootstrap.dart';
import 'package:bsat/services/lan/lan_forwarding_service.dart';
import 'package:bsat/services/lan/lan_messages.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:bsat/utils/forwarding_job_id.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/lan_test_support.dart';
import 'support/stage0_harness.dart';
import 'support/stage1_fakes.dart';

const _receipt = 'SJK1RFW001';
const _sms = '$_receipt Confirmed. Ksh100.00 received from JOHN DOE '
    '0712345678. SYNTHETIC RE-FORWARD TEST MESSAGE ONLY.';
const _jobX = 'fwd_${_receipt}_1793000000001';
const _jobY = 'fwd_${_receipt}_1793000000002';

Map<String, dynamic> _job(String jobId) => {
      'type': 'forwarded_sms',
      'body': _sms,
      'title': 'Forwarded Message',
      'messageId': _receipt,
      // The bulk screen keeps the row ID, so both jobs carry the same one.
      'transactionId': 41,
      'forwardingJobId': jobId,
      'forwardingStatus': 'forwarding-pending',
      'senderDeviceName': 'Phone A',
      'recipientDeviceName': 'Phone B',
    };

void main() {
  final h = Stage0Harness();

  setUpAll(Stage0Harness.setUpAllOnce);
  tearDownAll(Stage0Harness.tearDownAllOnce);
  tearDown(h.tearDown);

  test('Phone A: the bulk manual forward replaces an accepted job with a new '
      'job ID and submits it again', () async {
    await h.setUp(prefs: {'user_device_name': 'Phone A'});
    final db = await h.db;
    final id = await db.insert('transactions', {
      'initialMessage': _sms,
      'transactionId': _receipt,
      'amount': 100,
      'number': 712345678,
      'status': TransactionStatuses.forwardedPending,
      'canRetry': 1,
      'forwardingJobId': _jobX,
      'forwardingSenderDeviceName': 'Phone A',
      'forwardingRecipientDeviceName': 'Phone B',
      'forwardingTransport': 'lan',
      'ussdReply': 'Forwarding to device\n•\n'
          'Receipt acknowledged by destination device',
      'timeStamp': DateTime.now().millisecondsSinceEpoch,
    });
    await db.insert('forwardingDeliveryRetries', {
      'forwardingJobId': _jobX,
      'attempt': 0,
      'nextAttemptAt': 0,
      'acknowledged': 1,
    });
    final lan = RecordingForwardingTransport();
    final controller = TransactionController(
      sqliteService: SQLiteService(),
      lanForwardingTransport: lan,
    );
    // Exactly the calls transaction_history._forwardSelectedOverLan makes.
    final newJob = ForwardingJobId.generate(mpesaCode: _receipt);
    final txId = await controller.dontProcess(
      _sms, _receipt, 712345678, '', 100, 0,
      status: TransactionStatuses.forwardedPending,
      id: id,
      reply: 'Forwarding to Phone B over LAN',
      forwardingJobId: newJob,
      forwardingSenderDeviceName: 'Phone A',
      forwardingRecipientDeviceName: 'Phone B',
      forwardingTransport: 'lan',
    );
    await controller.submitManualLanForwardingJob(
      transactionId: txId!,
      forwardingJobId: newJob,
      message: _sms,
      messageId: _receipt,
      senderDeviceName: 'Phone A',
      recipientDeviceName: 'Phone B',
    );
    final row = (await db.query('transactions', where: 'id = ?', whereArgs: [id]))
        .single;
    expect(row['forwardingJobId'], isNot(_jobX),
        reason: 'the accepted job X was replaced by a new job ID');
    expect(lan.submissions.single.request['data']['forwardingJobId'], newJob);
    expect(lan.submissions.single.request['data']['body'], _sms,
        reason: 'the same payment is requested again');
  });

  test('Phone B over LAN: two job IDs for one payment are two independent '
      'claims, and each is charged', () async {
    await h.setUp(prefs: {
      'user_device_name': 'Phone B',
      'delivery_tokens': 2,
    });
    final db = await h.db;
    await db.insert('whitelistedDevices', {
      'device_name': 'Phone A',
      'device_id': 'device-phone-a',
      'owner_email': 'owner@example.test',
    });
    final b = await LanTestPhone.create('Phone B',
        sqlite: SQLiteService(),
        inboundHandler: handleLanForwardingRequest,
        replyProcessor: handleLanForwardingReply);
    final receipts = <LanForwardingData>[];
    final a = await LanTestPhone.create('Phone A',
        replyProcessor: (reply, peer) async => receipts.add(reply));
    addTearDown(() async {
      await a.dispose();
      await b.dispose();
    });
    await pairPhones(b, a);
    for (final job in [_jobX, _jobX, _jobY]) {
      await a.service.exchange(
        recipientDeviceName: 'Phone B',
        data: _job(job),
        isFinalReply: (r) => r.kind == LanMessageKind.receiptAck,
      );
      await waitForAsync(() async => (await db.query('forwardedSmsJobs'))
          .every((claim) => claim['state'] == 'completed'));
    }
    final claims = await db.query('forwardedSmsJobs', orderBy: 'forwardingJobId');
    expect(claims.map((c) => c['forwardingJobId']), [_jobX, _jobY],
        reason: 'the repeated X is deduplicated; Y is a new claim');
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getInt('delivery_tokens'), 0,
        reason: 'one token for X and one for Y: two purchase attempts for '
            'one M-PESA payment');
    expect(receipts.map((r) => r.forwardingJobId), [_jobX, _jobX, _jobY]);
  });

  test('Phone B over the Internet (FCM): the same holds for Online jobs',
      () async {
    await h.setUp(prefs: {
      'user_device_name': 'Phone B',
      'jwt_token': 'reforward-test-jwt',
      'delivery_tokens': 2,
    });
    final db = await h.db;
    await db.insert('whitelistedDevices', {
      'device_name': 'Phone A',
      'device_id': 'device-phone-a',
      'owner_email': 'owner@example.test',
    });
    LanForwardingService.instance = null;
    for (final job in [_jobX, _jobY]) {
      await h.capture(() => handleRemoteMessage(RemoteMessage(
            messageId: 'fcm-$job',
            data: _job(job).map((k, v) => MapEntry(k, '$v')),
          )));
    }
    final claims = await db.query('forwardedSmsJobs');
    expect(claims, hasLength(2));
    expect(claims.map((c) => c['transport']).toSet(), {'online'});
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getInt('delivery_tokens'), 0);
    final receiptAcks = h.backendPosts
        .where((p) => p.data['type'] == 'MESSAGE_ACK')
        .map((p) => p.data['forwardingJobId']);
    expect(receiptAcks, [_jobX, _jobY]);
  });
}
