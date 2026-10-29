// LAN pairing flow tests: invitation codes, either phone initiating, both-side
// approval, cancellation, restart persistence, LAN revoke/remove leaving the
// Online pairing alone, and pairing candidates. Real sockets on 127.0.0.1,
// real handshake crypto, synthetic data only; no BSAT handler, purchase, SMS
// or USSD code runs here.
import 'dart:io';
import 'dart:typed_data';

import 'package:bsat/services/lan/lan_device_identity.dart';
import 'package:bsat/services/lan/lan_forwarding_service.dart';
import 'package:bsat/services/lan/lan_key_wrapper.dart';
import 'package:bsat/services/lan/lan_messages.dart';
import 'package:bsat/services/lan/lan_pairing.dart';
import 'package:bsat/services/lan/lan_pairing_candidates.dart';
import 'package:bsat/services/lan/lan_peer_store.dart';
import 'package:bsat/services/lan/lan_secure_session.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/lan_test_support.dart';

PairingInvitation _invitation({String host = '192.168.43.10', int port = 47820}) =>
    PairingInvitation(
      host: InternetAddress(host),
      port: port,
      token: Uint8List.fromList(List.generate(10, (i) => i + 1)),
      fingerprintPrefix: Uint8List.fromList(List.generate(8, (i) => 200 + i)),
    );

Map<String, dynamic> _job(String jobId) => {
      'type': 'forwarded_sms',
      'body': 'SJK1ABCD23 Confirmed. Ksh100.00 received. SYNTHETIC TEST ONLY.',
      'title': 'Forwarded Message',
      'messageId': 'SJK1ABCD23',
      'transactionId': 7,
      'forwardingJobId': jobId,
      'forwardingStatus': 'pending',
      'senderDeviceName': 'Phone A',
      'recipientDeviceName': 'Phone B',
    };

Map<String, dynamic> _receipt(String jobId) => {
      'title': 'BSAT Online Forwarding',
      'body': 'received',
      'senderDeviceName': 'Phone B',
      'recipientDeviceName': 'Phone A',
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
        'senderDeviceName': 'Phone B',
        'recipientDeviceName': 'Phone A',
        'body': 'received',
        'title': 'Ack receive',
      },
    };

Future<void> _receiptHandler(
  LanForwardingData message,
  LanPeer peer,
  LanReplySink reply,
) =>
    reply(_receipt(message.forwardingJobId));

Future<LanExchangeResult> _send(LanForwardingService sender, String jobId) =>
    sender.exchange(
      recipientDeviceName: 'Phone B',
      data: _job(jobId),
      isFinalReply: (reply) => reply.kind == LanMessageKind.receiptAck,
    );

/// A phone whose database, identity directory and key wrapper outlive its
/// service, so the app can be "restarted" with a new service instance.
class _DurablePhone {
  final String name;
  final String id;
  final SQLiteService sqlite;
  final Directory directory;
  final TestKeyWrapper wrapper = TestKeyWrapper();

  _DurablePhone(this.name, this.sqlite, this.directory)
      : id = 'device-${name.toLowerCase().replaceAll(' ', '-')}';

  static Future<_DurablePhone> create(String name) async => _DurablePhone(
        name,
        SQLiteService(databaseOverride: await openPhoneDatabase()),
        await Directory.systemTemp.createTemp('bsat_lan_restart_'),
      );

  LanForwardingService start({
    int preferredPort = 0,
    LanInboundHandler? inboundHandler,
  }) =>
      LanForwardingService(
        peers: LanPeerStore(sqlite),
        identityStore: IdentityStore(directory: directory, wrapper: wrapper),
        ownDeviceName: () async => name,
        ownDeviceId: () async => id,
        listenAddresses: () async => [InternetAddress.loopbackIPv4],
        preferredPort: preferredPort,
        connectTimeout: const Duration(seconds: 2),
        replyTimeout: const Duration(seconds: 5),
        probeTimeout: const Duration(seconds: 2),
        inboundHandler: inboundHandler,
      );
}

Future<void> _confirmBoth(
  LanForwardingService inviter,
  LanForwardingService joiner,
) async {
  await waitFor(
    () =>
        inviter.pairing?.peerAccepted == true &&
        joiner.pairing?.peerAccepted == true,
    reason: 'both identities exchanged',
  );
  expect(inviter.pairing!.sas, joiner.pairing!.sas);
  await inviter.pairing!.confirm();
  await joiner.pairing!.confirm();
  await waitFor(
    () =>
        inviter.pairing?.phase == PairingPhase.completed &&
        joiner.pairing?.phase == PairingPhase.completed,
    reason: 'pairing completed on both phones',
  );
}

void main() {
  setUpAll(sqfliteFfiInit);

  group('invitation QR and manual code', () {
    test('the QR text and the grouped manual code carry the same invitation',
        () {
      final invitation = _invitation();
      expect(invitation.qrText, startsWith(invitationQrPrefix));
      expect(invitation.code, matches(RegExp(r'^([A-Z2-7]{4}-){9}[A-Z2-7]{4}$')));
      for (final parsed in [
        PairingInvitation.parse(invitation.qrText),
        PairingInvitation.parseScanned(invitation.qrText),
        PairingInvitation.parse(invitation.code),
        // Typed by hand: lower case, spaces instead of hyphens, look-alike
        // digits for O/I/B.
        PairingInvitation.parse(
          ' ${invitation.code.toLowerCase().replaceAll('-', ' ')} ',
        ),
        PairingInvitation.parse(invitation.code
            .replaceAll('O', '0')
            .replaceAll('I', '1')
            .replaceAll('B', '8')),
      ]) {
        expect(parsed.toBytes(), invitation.toBytes());
        expect(parsed.host.address, '192.168.43.10');
        expect(parsed.port, 47820);
      }
    });

    test('a camera scan accepts only the exact QR text', () {
      final invitation = _invitation();
      for (final text in [
        invitation.code,
        invitation.qrText.toLowerCase(),
        '${invitation.qrText} ',
        'https://example.com/${invitation.qrText}',
      ]) {
        expect(() => PairingInvitation.parseScanned(text),
            throwsA(isA<InvitationFormatException>()),
            reason: text);
      }
    });

    test('typos, truncation, other versions and public addresses are refused',
        () {
      final code = _invitation().code;
      final symbols = code.replaceAll('-', '');
      final typo = symbols.substring(0, 10) +
          (symbols[10] == 'A' ? 'C' : 'A') +
          symbols.substring(11);
      final cases = <String, InvitationProblem>{
        typo: InvitationProblem.checksum,
        symbols.substring(0, 39): InvitationProblem.wrongLength,
        '${symbols}A': InvitationProblem.wrongLength,
        'ABCD-EFGH-!!!!': InvitationProblem.invalidCharacters,
        'BSATLAN:PAIR:2:$symbols': InvitationProblem.unsupportedVersion,
        'BSATLAN:OTHER:$symbols': InvitationProblem.notAnInvitation,
        'A' * (maxInvitationTextLength + 1): InvitationProblem.tooLong,
        _invitation(host: '8.8.8.8').code: InvitationProblem.notPrivateAddress,
      };
      cases.forEach((text, problem) {
        expect(
          () => PairingInvitation.parse(text),
          throwsA(isA<InvitationFormatException>()
              .having((e) => e.problem, 'problem', problem)),
          reason: text,
        );
      });
    });

    test('the 6-digit code is derived from the handshake transcript', () {
      final th2 = Uint8List.fromList(List.generate(32, (i) => i));
      final changed = Uint8List.fromList(th2)..[31] ^= 1;
      expect(deriveSas(th2), matches(RegExp(r'^\d{6}$')));
      expect(deriveSas(th2), deriveSas(Uint8List.fromList(th2)));
      expect(deriveSas(changed), isNot(deriveSas(th2)));
    });
  });

  group('pairing over loopback', () {
    late LanTestPhone a;
    late LanTestPhone b;

    setUp(() async {
      a = await LanTestPhone.create('Phone A');
      b = await LanTestPhone.create('Phone B');
    });
    tearDown(() async {
      await a.dispose();
      await b.dispose();
    });

    for (final aShowsQr in [true, false]) {
      test(
          'either phone can show the QR: '
          '${aShowsQr ? 'A shows, B scans' : 'B shows, A scans'}', () async {
        aShowsQr ? await pairPhones(a, b) : await pairPhones(b, a);
        final onA = await a.peers.lookupDevice('Phone B');
        final onB = await b.peers.lookupDevice('Phone A');
        expect(onA.state, LanPeerLookupState.trusted);
        expect(onB.state, LanPeerLookupState.trusted);
        expect(onA.peer!.fingerprint, b.service.identity!.fingerprint);
        expect(onB.peer!.fingerprint, a.service.identity!.fingerprint);
        expect(onA.peer!.deviceId, b.id);
        expect(onB.peer!.deviceId, a.id);
      });
    }

    test('the typed manual code pairs like a scan; both phones show one code',
        () async {
      final invitation = await b.service.createInvitation(
          expectedDeviceName: 'Phone A', expectedDeviceId: a.id);
      await a.service.joinWithInvitation(invitation.code,
          expectedDeviceName: 'Phone B', expectedDeviceId: b.id);
      expect(a.service.pairingError, isNull);
      await _confirmBoth(b.service, a.service);
      expect(a.service.pairing!.sas, matches(RegExp(r'^\d{6}$')));
      expect((await a.peers.lookupDevice('Phone B')).state,
          LanPeerLookupState.trusted);
    });

    test('the typed code given to the camera path is refused before connecting',
        () async {
      final invitation = await b.service.createInvitation(
          expectedDeviceName: 'Phone A', expectedDeviceId: a.id);
      await a.service.joinWithInvitation(invitation.code,
          expectedDeviceName: 'Phone B', expectedDeviceId: b.id, scanned: true);
      expect(a.service.pairing, isNull);
      expect(a.service.pairingError, isNotNull);
      // The invitation was never redeemed: it still works.
      expect(b.service.invitations.invitation, isNotNull);
    });

    test('a confirmation on one phone alone trusts nothing, even when the '
        'other phone waits until the confirmation window ends', () async {
      final invitation = await b.service.createInvitation(
          expectedDeviceName: 'Phone A', expectedDeviceId: a.id);
      await a.service.joinWithInvitation(invitation.qrText,
          expectedDeviceName: 'Phone B', expectedDeviceId: b.id, scanned: true);
      await waitFor(() =>
          a.service.pairing?.peerAccepted == true &&
          b.service.pairing?.peerAccepted == true);
      await a.service.pairing!.confirm();
      expect(a.service.pairing!.phase, PairingPhase.waitingForPeer);
      // B never approves; B's user leaves the pairing screen.
      b.service.abandonPairing();
      await waitFor(() => a.service.pairing!.isFinished);
      expect(a.service.pairing!.phase, PairingPhase.failed);
      expect(await a.peers.all(), isEmpty);
      expect(await b.peers.all(), isEmpty);
      expect(b.service.pairing, isNull);
      // The redeemed invitation cannot be used again afterwards.
      final c = await LanTestPhone.create('Phone A');
      addTearDown(c.dispose);
      await c.service.joinWithInvitation(invitation.qrText,
          expectedDeviceName: 'Phone B', expectedDeviceId: b.id, scanned: true);
      expect(c.service.pairing, isNull);
      expect(c.service.pairingError, contains('already used'));
    });

    test('the joiner leaving the screen cancels the pairing on both phones',
        () async {
      final invitation = await b.service.createInvitation(
          expectedDeviceName: 'Phone A', expectedDeviceId: a.id);
      await a.service.joinWithInvitation(invitation.qrText,
          expectedDeviceName: 'Phone B', expectedDeviceId: b.id, scanned: true);
      await waitFor(() => b.service.pairing?.peerAccepted == true);
      await b.service.pairing!.confirm();
      a.service.abandonPairing();
      expect(a.service.pairing, isNull);
      await waitFor(() => b.service.pairing!.isFinished);
      expect(b.service.pairing!.phase, PairingPhase.failed);
      expect(await a.peers.all(), isEmpty);
      expect(await b.peers.all(), isEmpty);
    });

    test('a second attempt with the same invitation during confirmation is '
        'refused and does not disturb the first', () async {
      final invitation = await b.service.createInvitation(
          expectedDeviceName: 'Phone A', expectedDeviceId: a.id);
      await a.service.joinWithInvitation(invitation.qrText,
          expectedDeviceName: 'Phone B', expectedDeviceId: b.id, scanned: true);
      await waitFor(() =>
          a.service.pairing?.peerAccepted == true &&
          b.service.pairing?.peerAccepted == true);
      final first = b.service.pairing;

      final intruder = await LanTestPhone.create('Phone A');
      addTearDown(intruder.dispose);
      await intruder.service.joinWithInvitation(invitation.qrText,
          expectedDeviceName: 'Phone B', expectedDeviceId: b.id, scanned: true);
      expect(intruder.service.pairing, isNull);
      expect(intruder.service.pairingError, contains('already used'));
      expect(identical(b.service.pairing, first), isTrue);

      await _confirmBoth(b.service, a.service);
      final trusted = await b.peers.all();
      expect(trusted.single.fingerprint, a.service.identity!.fingerprint);
    });

    test('an invitation whose phone stopped listening fails safely', () async {
      final invitation = await b.service.createInvitation(
          expectedDeviceName: 'Phone A', expectedDeviceId: a.id);
      await b.service.stopListening();
      await a.service.joinWithInvitation(invitation.qrText,
          expectedDeviceName: 'Phone B', expectedDeviceId: b.id, scanned: true);
      expect(a.service.pairing, isNull);
      expect(a.service.pairingError, isNotNull);
      expect(await a.peers.all(), isEmpty);
      expect(await b.peers.all(), isEmpty);
    });

    test('pairing again after a revoke restores one trusted record', () async {
      await pairPhones(b, a);
      final fingerprint = b.service.identity!.fingerprint;
      await a.service.revoke(fingerprint);
      expect((await a.peers.lookupDevice('Phone B')).state,
          LanPeerLookupState.revoked);
      await pairPhones(b, a);
      final records = await a.peers.all();
      expect(records, hasLength(1));
      expect(records.single.fingerprint, fingerprint);
      expect(records.single.isTrusted, isTrue);
    });
  });

  group('LAN revoke and remove leave the Online pairing alone', () {
    late LanTestPhone a;
    late LanTestPhone b;

    Future<Map<String, List<Map<String, dynamic>>>> onlineState() async => {
          for (final table in ['whitelistedDevices', 'forwardingDevices'])
            table: await a.sqlite.queryAll(table),
        };

    setUp(() async {
      a = await LanTestPhone.create('Phone A');
      b = await LanTestPhone.create('Phone B', inboundHandler: _receiptHandler);
      await a.sqlite.insertStuff({
        'device_name': 'Phone B',
        'device_id': b.id,
        'owner_email': 'owner@example.invalid',
        'user_id': 1,
      }, 'whitelistedDevices');
      await a.sqlite.insertStuff({
        'device_name': 'Phone B',
        'device_id': b.id,
        'owner_email': 'owner@example.invalid',
        'user_id': 1,
        'amounts_to_forward': '[100]',
        'forwarding_transport': 'lan',
      }, 'forwardingDevices');
      await pairPhones(b, a);
    });
    tearDown(() async {
      await a.dispose();
      await b.dispose();
    });

    test('revoke stops LAN delivery; whitelist, rule and transport stay',
        () async {
      final before = await onlineState();
      expect((await _send(a.service, 'fwd_SJK1ABCD23_1')).outcome,
          LanExchangeOutcome.completed);

      await a.service.revoke(b.service.identity!.fingerprint);

      expect(await onlineState(), before);
      expect((await a.peers.lookupDevice('Phone B')).state,
          LanPeerLookupState.revoked);
      expect((await _send(a.service, 'fwd_SJK1ABCD23_2')).outcome,
          LanExchangeOutcome.revoked);
      // B's own LAN pairing is B's to manage.
      expect((await b.peers.lookupDevice('Phone A')).state,
          LanPeerLookupState.trusted);
    });

    test('remove deletes only the LAN record', () async {
      final before = await onlineState();
      await a.service.remove(b.service.identity!.fingerprint);
      expect(await onlineState(), before);
      expect(await a.peers.all(), isEmpty);
      expect((await _send(a.service, 'fwd_SJK1ABCD23_3')).outcome,
          LanExchangeOutcome.unpaired);
    });

    test('the receiver revoking the sender refuses it before any handler',
        () async {
      await b.service.revoke(a.service.identity!.fingerprint);
      final result = await _send(a.service, 'fwd_SJK1ABCD23_4');
      expect(result.outcome, LanExchangeOutcome.authenticationFailed);
      expect(result.requestWritten, isFalse);
    });
  });

  test('pairings and identities survive an app restart', () async {
    final a = await _DurablePhone.create('Phone A');
    final b = await _DurablePhone.create('Phone B');
    addTearDown(() async {
      for (final dir in [a.directory, b.directory]) {
        try {
          await dir.delete(recursive: true);
        } catch (_) {}
      }
    });

    var serviceA = a.start();
    var serviceB = b.start(inboundHandler: _receiptHandler);
    final invitation = await serviceB.createInvitation(
        expectedDeviceName: 'Phone A', expectedDeviceId: a.id);
    await serviceA.joinWithInvitation(invitation.qrText,
        expectedDeviceName: 'Phone B', expectedDeviceId: b.id, scanned: true);
    await _confirmBoth(serviceB, serviceA);
    final fingerprintA = serviceA.identity!.fingerprint;
    final fingerprintB = serviceB.identity!.fingerprint;
    final portB = serviceB.listenPort!;

    // Both apps stop; new services start from the same storage.
    await serviceA.stopListening();
    await serviceB.stopListening();
    serviceA = a.start();
    serviceB = b.start(preferredPort: portB, inboundHandler: _receiptHandler);
    addTearDown(() async {
      await serviceA.stopListening();
      await serviceB.stopListening();
    });
    expect(serviceA.identity, isNull);

    expect(await serviceA.loadIdentity(), IdentityStatus.ready);
    expect(await serviceB.loadIdentity(), IdentityStatus.ready);
    expect(serviceA.identity!.fingerprint, fingerprintA);
    expect(serviceB.identity!.fingerprint, fingerprintB);
    await serviceB.startListening();
    expect(serviceB.listenPort, portB);

    expect((await serviceA.peers.lookupDevice('Phone B')).state,
        LanPeerLookupState.trusted);
    expect((await serviceB.peers.lookupDevice('Phone A')).state,
        LanPeerLookupState.trusted);
    expect(await serviceA.probe('Phone B'), LanReachability.reachable);
    expect((await _send(serviceA, 'fwd_SJK1ABCD23_5')).outcome,
        LanExchangeOutcome.completed);
  });

  group('pairing candidates', () {
    late SQLiteService sqlite;

    setUp(() async {
      sqlite = SQLiteService(databaseOverride: await openPhoneDatabase());
    });

    test('no known device: empty list and guidance', () async {
      expect(await loadLanPairingCandidates(sqlite), isEmpty);
      expect(lanNoPairingCandidatesHelp, contains('Pair New Device'));
      expect(lanNoPairingCandidatesHelp, contains('same Wi-Fi or hotspot'));
    });

    test('only Online paired devices and forwarding rule targets are eligible',
        () async {
      Map<String, Object?> row(String name, String id) => {
            'device_name': name,
            'device_id': id,
            'owner_email': 'owner@example.invalid',
            'user_id': 1,
          };
      await sqlite.insertStuff(row('Phone C', 'id-c'), 'whitelistedDevices');
      await sqlite.insertStuff(row('Phone B', 'id-b'), 'whitelistedDevices');
      await sqlite.insertStuff(row('  ', 'id-blank'), 'whitelistedDevices');
      await sqlite.insertStuff(
          {...row('Phone B', 'id-b-rule'), 'amounts_to_forward': '[100]'},
          'forwardingDevices');
      await sqlite.insertStuff(
          {...row('Phone D', 'id-d'), 'amounts_to_forward': '[50]'},
          'forwardingDevices');
      // A LAN pairing record alone does not make a device eligible.
      await LanPeerStore(sqlite).trust(
        publicKey: List.filled(32, 7),
        deviceName: 'Phone LAN only',
        deviceId: 'id-lan',
      );

      final candidates = await loadLanPairingCandidates(sqlite);
      expect([for (final c in candidates) c.deviceName],
          ['Phone B', 'Phone C', 'Phone D']);
      expect(candidates.first.deviceId, 'id-b');
    });
  });
}
