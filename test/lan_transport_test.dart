// LAN transport integration tests (disposable copy). Prototype components
// as adapted for BSAT: framing, secure session, pairing, trust, bounded
// exchanges. Real sockets on 127.0.0.1; synthetic data only; no BSAT
// handler, purchase, SMS or USSD code runs here.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bsat/services/lan/lan_forwarding_service.dart';
import 'package:bsat/services/lan/lan_framing.dart';
import 'package:bsat/services/lan/lan_messages.dart';
import 'package:bsat/services/lan/lan_pairing.dart';
import 'package:bsat/services/lan/lan_peer_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/lan_test_support.dart';

Map<String, dynamic> _job({
  String jobId = 'fwd_SJK1ABCD23_1793000000000',
  String sender = 'Phone A',
  String recipient = 'Phone B',
}) =>
    {
      'type': 'forwarded_sms',
      'body': 'SJK1ABCD23 Confirmed. Ksh100.00 received. SYNTHETIC TEST ONLY.',
      'title': 'Forwarded Message',
      'messageId': 'SJK1ABCD23',
      'transactionId': 7,
      'forwardingJobId': jobId,
      'forwardingStatus': 'pending',
      'senderDeviceName': sender,
      'recipientDeviceName': recipient,
    };

Map<String, dynamic> _receipt(String jobId,
        {String from = 'Phone B', String to = 'Phone A'}) =>
    {
      'title': 'BSAT Online Forwarding',
      'body': 'received',
      'senderDeviceName': from,
      'recipientDeviceName': to,
      'data': {
        'type': 'MESSAGE_ACK',
        'ackKind': 'received',
        'messageId': '',
        'requestId': '',
        'transactionId': '7',
        'forwardingJobId': jobId,
        'originalType': 'forwarded_sms',
        'status': 'received',
        'receivedAt': '1793000000000',
        'senderDeviceName': from,
        'recipientDeviceName': to,
        'body': 'received',
        'title': 'Ack receive',
      },
    };

bool _isReceipt(LanForwardingData reply) =>
    reply.kind == LanMessageKind.receiptAck;

void main() {
  setUpAll(sqfliteFfiInit);

  group('framing (prototype FrameDecoder)', () {
    test('reassembles frames split at every byte boundary and batched frames',
        () {
      final a = encodeFrame({'n': 1, 'pad': 'x' * 300});
      final b = encodeFrame({'n': 2});
      final decoder = FrameDecoder();
      final frames = <Uint8List>[];
      for (final byte in [...a, ...b]) {
        frames.addAll(decoder.add([byte]));
      }
      expect(frames.map((f) => decodeJsonObject(f)['n']), [1, 2]);
      expect(FrameDecoder().add([...a, ...b]), hasLength(2));
    });

    test('an oversized or empty declared length closes the decoder', () {
      final oversized = Uint8List(4)
        ..buffer.asByteData().setUint32(0, maxFramePayloadBytes + 1);
      final decoder = FrameDecoder();
      expect(() => decoder.add(oversized), throwsA(isA<FrameException>()));
      expect(() => decoder.add([0]), throwsA(isA<FrameException>()));
      expect(() => FrameDecoder().add(Uint8List(4)),
          throwsA(isA<FrameException>()));
    });

    test('a partial frame stays buffered until complete', () {
      final frame = encodeFrame({'n': 3});
      final decoder = FrameDecoder();
      expect(decoder.add(frame.sublist(0, frame.length - 1)), isEmpty);
      expect(decoder.add(frame.sublist(frame.length - 1)), hasLength(1));
    });

    test('payloads that are not JSON objects are rejected', () {
      expect(() => decodeJsonObject(Uint8List.fromList(utf8.encode('[1]'))),
          throwsA(isA<ProtocolException>()));
      expect(() => decodeJsonObject(Uint8List.fromList([0xff, 0xfe])),
          throwsA(isA<ProtocolException>()));
    });
  });

  group('message validation', () {
    LanForwardingData validate(Object? data,
            {String peer = 'Phone A', String own = 'Phone B'}) =>
        validateLanForwardingData(data,
            allowed: lanRequestKinds,
            authenticatedPeerDeviceName: peer,
            ownDeviceName: own);

    test('a well-formed job is accepted with every value as a string', () {
      final message = validate(_job());
      expect(message.kind, LanMessageKind.forwardedSms);
      expect(message.data['transactionId'], '7');
      expect(message.forwardingJobId, 'fwd_SJK1ABCD23_1793000000000');
    });

    test('malformed jobs are refused', () {
      for (final bad in <Object?>[
        'not a map',
        {..._job(), 'callbackUrl': 'https://example.test'},
        Map.of(_job())..remove('forwardingJobId'),
        {..._job(), 'forwardingJobId': 'bad id with spaces'},
        {..._job(), 'transactionId': 0},
        {..._job(), 'transactionId': 'abc'},
        {..._job(), 'body': ''},
        {..._job(), 'body': 'x' * (maxLanBodyChars + 1)},
        {..._job(), 'title': {'nested': true}},
        {..._job(), 'senderDeviceName': 'Phone\u0007A'},
      ]) {
        expect(() => validate(bad), throwsA(isA<LanMessageException>()),
            reason: '$bad');
      }
    });

    test('the sender must be the authenticated peer; the recipient this phone',
        () {
      expect(
        () => validate(_job(sender: 'Phone C')),
        throwsA(isA<LanMessageException>().having(
            (e) => e.reason, 'reason', LanRejectReasons.unexpectedSender)),
      );
      expect(
        () => validate(_job(recipient: 'Phone C')),
        throwsA(isA<LanMessageException>().having(
            (e) => e.reason, 'reason', LanRejectReasons.unexpectedRecipient)),
      );
      expect(() => validate(_job(), peer: ''),
          throwsA(isA<LanMessageException>()));
    });

    test('alternative requests and results are accepted, including a long '
        'multi-line SMS or USSD reply', () {
      const sms = 'SJK1ABCD23 Confirmed.\nKsh100.00 received from JOHN DOE '
          '0712345678 on 30/10/26 at 10:00 AM. New M-PESA balance is '
          'Ksh1,000.00. Transaction cost, Ksh0.00. Amount you can transact '
          'within the day is 499,900.00. SYNTHETIC TEST ONLY.';
      final request = validate({
        'type': 'process_alt_request',
        'transactionId': '7',
        'forwardingJobId': 'fwd_X_1',
        'senderDeviceName': 'Phone A',
        'recipientDeviceName': 'Phone B',
        'ussdCode': '*180*5*2*0712345678*1*1#',
        'isAdvanced': 'false',
        'smsMessage': sms,
        'body': 'Forwarded alternative USSD request',
        'title': 'Forwarded Code',
      });
      expect(request.kind, LanMessageKind.alternativeRequest);
      expect(request.data['smsMessage'], sms);
      expect(lanReplyKindsFor(request.kind),
          {LanMessageKind.alternativeRequestReceipt});

      final result = validate({
        'type': 'forwarded_alt_result',
        'transactionId': '7',
        'forwardingJobId': 'fwd_X_1',
        'status': 'transaction-alternative-failed',
        'ussdReply': 'Line one\n${'x' * 400}',
        'senderDeviceName': 'Phone A',
        'recipientDeviceName': 'Phone B',
      });
      expect(result.kind, LanMessageKind.alternativeResult);
      expect(lanReplyKindsFor(result.kind),
          {LanMessageKind.alternativeResultReceipt});
    });

    test('malformed alternative requests are refused', () {
      final good = {
        'type': 'process_alt_request',
        'transactionId': '7',
        'forwardingJobId': 'fwd_X_1',
        'senderDeviceName': 'Phone A',
        'recipientDeviceName': 'Phone B',
        'ussdCode': '*180*1#',
      };
      expect(validate(good).kind, LanMessageKind.alternativeRequest);
      for (final bad in <Object?>[
        Map.of(good)..remove('ussdCode'),
        {...good, 'ussdCode': ' '},
        {...good, 'transactionId': '0'},
        {...good, 'callbackUrl': 'https://example.test'},
        {...good, 'ussdCode': '*180*1#\u0007'},
        {...good, 'smsMessage': 'x' * (maxLanBodyChars + 1)},
      ]) {
        expect(() => validate(bad), throwsA(isA<LanMessageException>()),
            reason: '$bad');
      }
    });

    test('alternative receipts are replies, never requests', () {
      for (final receipt in [
        {
          'type': 'MESSAGE_ACK',
          'ackKind': 'alternative_received',
          'originalType': 'process_alt_request',
          'status': 'alternative-received',
        },
        {
          'type': 'MESSAGE_ACK',
          'ackKind': 'alternative_result_received',
          'originalType': 'forwarded_alt_result',
          'status': 'alternative-result-received',
        },
      ]) {
        final data = {
          ...receipt,
          'forwardingJobId': 'fwd_X_1',
          'senderDeviceName': 'Phone A',
          'recipientDeviceName': 'Phone B',
        };
        expect(
          () => validate(data),
          throwsA(isA<LanMessageException>().having(
              (e) => e.reason, 'reason', LanRejectReasons.unsupportedType)),
        );
        expect(
          validateLanForwardingData(data,
                  allowed: LanMessageKind.values.toSet(),
                  authenticatedPeerDeviceName: 'Phone A',
                  ownDeviceName: 'Phone B')
              .kind,
          isIn([
            LanMessageKind.alternativeRequestReceipt,
            LanMessageKind.alternativeResultReceipt,
          ]),
        );
      }
    });

    test('only forwarding kinds travel over LAN; a receipt is never a request',
        () {
      for (final type in [
        {'type': 'DATA_REQUEST'},
        {'type': 'forwarded_sms_ack', 'ackKind': 'received'},
        _receipt('fwd_X_1')['data'],
      ]) {
        expect(
          () => validate({...type as Map, 'forwardingJobId': 'fwd_X_1'}),
          throwsA(isA<LanMessageException>().having(
              (e) => e.reason, 'reason', LanRejectReasons.unsupportedType)),
          reason: '$type',
        );
      }
    });
  });

  group('pairing, authentication and exchanges over loopback', () {
    late LanTestPhone a;
    late LanTestPhone b;
    final handled = <LanForwardingData>[];
    LanInboundHandler replying(
            [Future<void> Function(LanForwardingData, LanReplySink)? body]) =>
        (message, peer, reply) async {
          handled.add(message);
          if (body != null) {
            await body(message, reply);
          } else {
            await reply(_receipt(message.forwardingJobId));
          }
        };

    setUp(() async {
      handled.clear();
      a = await LanTestPhone.create('Phone A');
      b = await LanTestPhone.create('Phone B', inboundHandler: replying());
    });
    tearDown(() async {
      await a.dispose();
      await b.dispose();
    });

    test('pairing trusts both phones only after both confirm the same code',
        () async {
      await pairPhones(b, a);
      final onA = await a.peers.lookupDevice('Phone B');
      final onB = await b.peers.lookupDevice('Phone A');
      expect(onA.state, LanPeerLookupState.trusted);
      expect(onB.state, LanPeerLookupState.trusted);
      expect(onA.peer!.fingerprint, b.service.identity!.fingerprint);
      expect(onB.peer!.fingerprint, a.service.identity!.fingerprint);
      expect(onA.peer!.lastPort, b.service.listenPort);
      expect(onB.peer!.lastPort, a.service.listenPort);
    });

    test('nothing is trusted when only one phone confirms, or one rejects',
        () async {
      final invitation = await b.service.createInvitation(
          expectedDeviceName: 'Phone A', expectedDeviceId: a.id);
      await a.service.joinWithInvitation(invitation.qrText,
          expectedDeviceName: 'Phone B', expectedDeviceId: b.id, scanned: true);
      await waitFor(() =>
          a.service.pairing?.peerAccepted == true &&
          b.service.pairing?.peerAccepted == true);
      await a.service.pairing!.confirm();
      await b.service.pairing!.reject();
      await waitFor(() =>
          a.service.pairing!.isFinished && b.service.pairing!.isFinished);
      expect(a.service.pairing!.phase, PairingPhase.rejectedByPeer);
      expect(await a.peers.all(), isEmpty);
      expect(await b.peers.all(), isEmpty);
    });

    test('a phone that is not the chosen BSAT device is refused', () async {
      final c = await LanTestPhone.create('Phone C');
      addTearDown(c.dispose);
      // B invites "Phone A", but Phone C scans the code.
      final invitation = await b.service.createInvitation(
          expectedDeviceName: 'Phone A', expectedDeviceId: a.id);
      await c.service.joinWithInvitation(invitation.qrText,
          expectedDeviceName: 'Phone B', expectedDeviceId: b.id, scanned: true);
      await waitFor(() =>
          (b.service.pairing?.isFinished ?? false) &&
          (c.service.pairing?.isFinished ?? false));
      expect(b.service.pairing!.phase, PairingPhase.failed);
      expect(b.service.pairing!.failure, contains('"Phone C", not "Phone A"'));
      expect(await b.peers.all(), isEmpty);
      expect(await c.peers.all(), isEmpty);
    });

    test('a used, replayed or copied invitation cannot pair another device',
        () async {
      final invitation = await b.service.createInvitation(
          expectedDeviceName: 'Phone A', expectedDeviceId: a.id);
      final copied = invitation.qrText;
      await a.service.joinWithInvitation(copied,
          expectedDeviceName: 'Phone B', expectedDeviceId: b.id, scanned: true);
      await waitFor(() =>
          a.service.pairing?.peerAccepted == true &&
          b.service.pairing?.peerAccepted == true);
      await a.service.pairing!.confirm();
      await b.service.pairing!.confirm();
      await waitFor(() => b.service.pairing?.phase == PairingPhase.completed);

      final c = await LanTestPhone.create('Phone A'); // same name, other key
      addTearDown(c.dispose);
      await c.service.joinWithInvitation(copied,
          expectedDeviceName: 'Phone B', expectedDeviceId: b.id, scanned: true);
      expect(c.service.pairing, isNull);
      expect(c.service.pairingError, contains('already used'));
      final trusted = await b.peers.all();
      expect(trusted.single.fingerprint, a.service.identity!.fingerprint);
    });

    test('an authenticated exchange delivers the validated job and its receipt',
        () async {
      await pairPhones(b, a);
      final processed = <LanForwardingData>[];
      final result = await a.service.exchange(
        recipientDeviceName: 'Phone B',
        data: _job(),
        isFinalReply: _isReceipt,
        onReply: (reply, peer) async => processed.add(reply),
      );
      expect(result.outcome, LanExchangeOutcome.completed);
      expect(handled.single.data['transactionId'], '7');
      expect(handled.single.senderDeviceName, 'Phone A');
      expect(processed.single.kind, LanMessageKind.receiptAck);
      expect(processed.single.forwardingJobId, 'fwd_SJK1ABCD23_1793000000000');
    });

    test('a paired device that is not trusted by the receiver is refused '
        'before any handler runs', () async {
      await pairPhones(b, a);
      await b.service.revoke(a.service.identity!.fingerprint);
      final result = await a.service.exchange(
          recipientDeviceName: 'Phone B',
          data: _job(),
          isFinalReply: _isReceipt);
      expect(result.outcome, LanExchangeOutcome.authenticationFailed);
      expect(result.requestWritten, isFalse);
      expect(handled, isEmpty);
      // B still lists A, as revoked; re-trusting needs a new pairing.
      expect((await b.peers.lookupDevice('Phone A')).state,
          LanPeerLookupState.revoked);
    });

    test('revoking or removing on the sender stops it before connecting',
        () async {
      await pairPhones(b, a);
      await a.service.revoke(b.service.identity!.fingerprint);
      expect(
          (await a.service.exchange(
                  recipientDeviceName: 'Phone B',
                  data: _job(),
                  isFinalReply: _isReceipt))
              .outcome,
          LanExchangeOutcome.revoked);
      expect(await a.service.probe('Phone B'), LanReachability.revoked);
      await a.service.remove(b.service.identity!.fingerprint);
      expect(await a.service.probe('Phone B'), LanReachability.unpaired);
      expect(handled, isEmpty);
    });

    test('an unpaired destination and an unknown key are refused', () async {
      expect(
          (await a.service.exchange(
                  recipientDeviceName: 'Phone B',
                  data: _job(),
                  isFinalReply: _isReceipt))
              .outcome,
          anyOf(LanExchangeOutcome.unpaired, LanExchangeOutcome.notConfigured));
      // A third phone that never paired with B cannot reach B's handler even
      // with B's address and a record claiming to be "Phone B".
      await pairPhones(b, a);
      final c = await LanTestPhone.create('Phone A');
      addTearDown(c.dispose);
      await c.service.loadIdentity(createIfAbsent: true);
      final bPeer = (await a.peers.lookupDevice('Phone B')).peer!;
      await c.peers.trust(
        publicKey: bPeer.publicKey,
        deviceName: 'Phone B',
        deviceId: b.id,
        address: bPeer.lastAddress,
        port: bPeer.lastPort,
      );
      final result = await c.service.exchange(
          recipientDeviceName: 'Phone B',
          data: _job(),
          isFinalReply: _isReceipt);
      expect(result.outcome, LanExchangeOutcome.authenticationFailed);
      expect(handled, isEmpty);
    });

    test('a different device answering at the paired address is refused',
        () async {
      await pairPhones(b, a);
      final c = await LanTestPhone.create('Phone C',
          inboundHandler: replying());
      addTearDown(c.dispose);
      await pairPhones(c, a);
      // Point A's record for B at C's listener (for example after DHCP).
      final bPeer = (await a.peers.lookupDevice('Phone B')).peer!;
      await a.peers.recordConnection(bPeer.fingerprint, '127.0.0.1',
          port: c.service.listenPort);
      final result = await a.service.exchange(
          recipientDeviceName: 'Phone B',
          data: _job(),
          isFinalReply: _isReceipt);
      expect(result.outcome, LanExchangeOutcome.authenticationFailed);
      expect(result.reason, contains('identity_mismatch'));
      expect(handled, isEmpty);
    });

    test('a request naming another sender or recipient is refused unhandled',
        () async {
      await pairPhones(b, a);
      for (final data in [
        _job(sender: 'Phone C'),
        _job(recipient: 'Phone C'),
        {..._job(), 'unexpected': 'field'},
      ]) {
        final result = await a.service.exchange(
            recipientDeviceName: 'Phone B',
            data: data,
            isFinalReply: _isReceipt);
        expect(result.outcome, LanExchangeOutcome.refused, reason: '$data');
      }
      expect(handled, isEmpty);
    });

    test('a receiver that finishes without a receipt is not a delivery',
        () async {
      await b.dispose();
      b = await LanTestPhone.create('Phone B',
          inboundHandler: replying((message, reply) async {}));
      await pairPhones(b, a);
      final result = await a.service.exchange(
          recipientDeviceName: 'Phone B',
          data: _job(),
          isFinalReply: _isReceipt);
      expect(result.outcome, LanExchangeOutcome.noReply);
      expect(handled, hasLength(1));
    });

    test('a receipt that never arrives is "delivery unknown", bounded in time',
        () async {
      await b.dispose();
      final never = Completer<void>();
      b = await LanTestPhone.create('Phone B',
          inboundHandler: replying((message, reply) => never.future));
      await a.dispose();
      a = await LanTestPhone.create('Phone A',
          replyTimeout: const Duration(milliseconds: 600));
      await pairPhones(b, a);
      final started = DateTime.now();
      final result = await a.service.exchange(
          recipientDeviceName: 'Phone B',
          data: _job(),
          isFinalReply: _isReceipt);
      expect(result.outcome, LanExchangeOutcome.deliveryUnknown);
      expect(result.requestWritten, isTrue);
      expect(DateTime.now().difference(started),
          lessThan(const Duration(seconds: 5)));
      never.complete();
    });

    test('peer unavailable: listener stopped, then restarted with trust kept',
        () async {
      await pairPhones(b, a);
      await b.service.stopListening();
      expect(
          (await a.service.exchange(
                  recipientDeviceName: 'Phone B',
                  data: _job(),
                  isFinalReply: _isReceipt))
              .outcome,
          LanExchangeOutcome.unreachable);
      expect(await a.service.probe('Phone B'), LanReachability.unreachable);
      await b.service.startListening();
      // The same port is preferred after a restart, so A's hint still works.
      expect(await a.service.probe('Phone B'), LanReachability.reachable);
      final result = await a.service.exchange(
          recipientDeviceName: 'Phone B',
          data: _job(),
          isFinalReply: _isReceipt);
      expect(result.outcome, LanExchangeOutcome.completed);
      expect(handled, hasLength(1));
    });

    test('a receiver reply that is not a valid receipt is a protocol error',
        () async {
      await b.dispose();
      b = await LanTestPhone.create('Phone B',
          inboundHandler: replying((message, reply) async {
        await reply(_receipt(message.forwardingJobId, from: 'Phone C'));
      }));
      await pairPhones(b, a);
      final processed = <LanForwardingData>[];
      final result = await a.service.exchange(
        recipientDeviceName: 'Phone B',
        data: _job(),
        isFinalReply: _isReceipt,
        onReply: (reply, peer) async => processed.add(reply),
      );
      expect(result.outcome, LanExchangeOutcome.protocolError);
      expect(processed, isEmpty, reason: 'an invalid reply is never processed');
    });

    test('plaintext, forged and oversized frames never reach the handler',
        () async {
      await pairPhones(b, a);
      final port = b.service.listenPort!;
      Future<List<int>> send(List<int> bytes) async {
        final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
        socket.add(bytes);
        final received = <int>[];
        await socket
            .timeout(const Duration(seconds: 3), onTimeout: (s) => s.close())
            .forEach(received.addAll)
            .catchError((_) {});
        socket.destroy();
        return received;
      }

      // A plaintext request instead of a handshake.
      final reply = await send(encodeFrame({
        'version': secureProtocolVersion,
        'type': LanEnvelopeTypes.request,
        'requestId': newLanRequestId(),
        'data': _job(),
      }));
      final frames = FrameDecoder().add(reply);
      expect(decodeJsonObject(frames.single)['code'], 'protocol_error');
      // A declared length beyond the limit.
      final oversized = Uint8List(4)
        ..buffer.asByteData().setUint32(0, maxFramePayloadBytes + 10);
      expect(await send(oversized), isEmpty);
      expect(handled, isEmpty);
    });

    test('a port in use is skipped and the chosen port is announced',
        () async {
      final blocker =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(blocker.close);
      final d = await LanTestPhone.create('Phone D',
          preferredPort: blocker.port);
      addTearDown(d.dispose);
      await d.service.loadIdentity(createIfAbsent: true);
      await d.service.startListening();
      expect(d.service.isListening, isTrue);
      expect(d.service.listenPort, isNot(blocker.port));
    });
  });
}
