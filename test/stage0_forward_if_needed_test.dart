@Tags(['requires-system-sqlite'])
// Runs only in Stage 0 copy B (Windows system SQLite). The project's bundled
// host SQLite is built with SQLITE_DQS=0 and rejects the double-quoted string
// literal in TransactionController._findReplyFor (amounts = ""), which
// forwardIfNeeded reaches before sending.
library;

// STAGE 0 characterization (disposable copy only).
//
// Records the HTTP requests HEAD 086d14e sends on its forwarding paths, so a
// later transport refactor can be checked byte-for-byte against them. These
// tests describe current behaviour; they do not endorse it. Nothing reaches a
// network: package:http is answered by a local MockClient, any other HTTP
// client is refused, SMS sends and USSD dials are refused and recorded.
import 'dart:convert';

import 'package:bsat/controllers/transaction_controller.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:bsat/utils/forwarding_delivery_retry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/stage0_harness.dart';

const _endpoint = 'https://api.bsat2.xyz/api/fcm/send-secure';
const _jwt = 'stage0-test-jwt';
const _receipt = 'SJK1ABCD23';
const _amount = 100;
const _number = 712345678;

/// A synthetic M-PESA-style message longer than 160 characters, to show that
/// the full body (not the 160-character excerpt) is forwarded.
final _smsBody = '$_receipt Confirmed. Ksh$_amount.00 received from JOHN DOE '
    '0712345678 on 28/10/26 at 3:41 PM. New M-PESA balance is Ksh1,234.00. '
    'Transaction cost, Ksh0.00. SYNTHETIC STAGE 0 TEST MESSAGE ONLY.';

Map<String, Object> _prefs(String deviceName) => {
      'user_device_name': deviceName,
      'jwt_token': _jwt,
    };

/// JSON round trip, as the request body is encoded on the wire.
Map<String, dynamic> _wire(Map<String, dynamic> map) =>
    jsonDecode(jsonEncode(map)) as Map<String, dynamic>;

void _expectBackendPost(CapturedRequest request) {
  expect(request.method, 'POST');
  expect(request.url.toString(), _endpoint);
  expect(request.headers['content-type'], startsWith('application/json'));
  expect(request.headers['authorization'], 'Bearer $_jwt');
}

void main() {
  final h = Stage0Harness();

  setUpAll(Stage0Harness.setUpAllOnce);
  tearDownAll(Stage0Harness.tearDownAllOnce);
  tearDown(h.tearDown);
  group('Phone A: forwardIfNeeded (online path)', () {
    Future<TransactionController> setUpPhoneA() async {
      await h.setUp(prefs: _prefs('Phone A'));
      final db = await h.db;
      await db.insert('forwardingDevices', {
        'device_name': 'Phone B',
        'device_id': 'device-b',
        'owner_email': 'owner@example.test',
        'amounts_to_forward': '[$_amount]',
        'paused': 0,
      });
      return TransactionController(sqliteService: SQLiteService());
    }

    // HOST LIMITATION (not HEAD behaviour): after the send, forwardIfNeeded
    // calls processReply -> another_telephony getSentSms, which asserts
    // Platform.isAndroid. On a test host that assertion throws and the
    // method's catch-all returns configuredButUnavailable, so the return
    // value of the success path is not asserted here. Everything below
    // happens before that call and is asserted.
    test('sends one forwarded_sms POST with the persisted identity', () async {
      final controller = await setUpPhoneA();
      final before = DateTime.now().millisecondsSinceEpoch;
      await h.capture(() => controller.forwardIfNeeded(
            _amount,
            _smsBody.trim(),
            _smsBody,
            _receipt,
            _number,
            'JOHN DOE',
            false,
          ));
      final after = DateTime.now().millisecondsSinceEpoch;

      final row = (await (await h.db).query('transactions',
              where: 'transactionId = ?', whereArgs: [_receipt]))
          .single;
      final rowId = row['id'] as int;
      final jobId = row['forwardingJobId'] as String;
      expect(jobId, matches(RegExp('^fwd_${_receipt}_\\d{13}\$')));

      // Reachability check that precedes the send (documents the known
      // defect: the peer's name is not part of the request).
      final gets = h.requests.where((r) => r.method == 'GET').toList();
      expect(gets.map((r) => r.url.toString()), ['https://google.com']);

      expect(h.backendPosts, hasLength(1));
      final post = h.backendPosts.single;
      _expectBackendPost(post);
      expect(
        post.json,
        _wire(buildForwardedSmsRequestPayload(
          message: _smsBody,
          messageId: _receipt,
          transactionRowId: rowId,
          forwardingJobId: jobId,
          senderDeviceName: 'Phone A',
          recipientDeviceName: 'Phone B',
        )),
      );
      // Exact wire shape and value types.
      expect(post.json.keys.toSet(),
          {'title', 'body', 'senderDeviceName', 'recipientDeviceName', 'data'});
      expect(post.data, {
        'type': 'forwarded_sms',
        'body': _smsBody,
        'title': 'Forwarded Message',
        'messageId': _receipt,
        'transactionId': rowId,
        'forwardingJobId': jobId,
        'forwardingStatus': 'forwarding-pending',
        'senderDeviceName': 'Phone A',
        'recipientDeviceName': 'Phone B',
      });
      expect(post.data['transactionId'], isA<int>(),
          reason: 'origin row ID is sent as a JSON number');
      expect(post.data['messageId'], isA<String>(),
          reason: 'M-PESA receipt code is sent as messageId');
      expect(_smsBody.length, greaterThan(160));
      expect(post.json['body'], _smsBody, reason: 'full SMS, not truncated');

      // Durable state written around the send.
      expect(row['status'], TransactionStatuses.forwardedPending);
      expect(row['transactionId'], _receipt);
      expect(row['initialMessage'], _smsBody);
      expect(row['forwardingSenderDeviceName'], 'Phone A');
      expect(row['forwardingRecipientDeviceName'], 'Phone B');
      final retry = (await (await h.db).query('forwardingDeliveryRetries',
              where: 'forwardingJobId = ?', whereArgs: [jobId]))
          .single;
      expect(retry['attempt'], 0);
      expect(retry['acknowledged'], 0);
      const firstDelayMs = initialForwardingDeliveryRetryDelaySeconds * 1000;
      expect(retry['nextAttemptAt'] as int,
          inInclusiveRange(before + firstDelayMs, after + firstDelayMs));
      expect(
          await (await h.db).query('forwardingSubmissionClaims',
              where: 'forwardingJobId = ?', whereArgs: [jobId]),
          isEmpty,
          reason: 'submission claim released after the send');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('online_forwarding_index_$_amount'), 0);

      h.expectNoExternalEffects();
    });

    test('backend failure marks the row error and schedules no retry',
        () async {
      final controller = await setUpPhoneA();
      h.backendStatus = 503;
      h.backendResponse = {'message': 'Service unavailable'};
      final result = await h.capture(() => controller.forwardIfNeeded(
          _amount, _smsBody.trim(), _smsBody, _receipt, _number, 'JOHN DOE',
          false));

      expect(result.state, ForwardingAttemptState.configuredButUnavailable);
      expect(h.backendPosts, hasLength(1));
      final row = (await (await h.db).query('transactions',
              where: 'id = ?', whereArgs: [result.transactionId]))
          .single;
      expect(row['status'], TransactionStatuses.error);
      expect(row['ussdReply'],
          'Forwarding failed: Phone offline or server not reachable. Will retry later.');
      expect(
          await (await h.db).query('forwardingDeliveryRetries',
              where: 'forwardingJobId = ?',
              whereArgs: [row['forwardingJobId']]),
          isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('online_forwarding_index_$_amount'), isNull,
          reason: 'round-robin index is not advanced on failure');
      h.expectNoExternalEffects();
    });
  });

}
