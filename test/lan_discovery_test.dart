// LAN discovery: a paired phone whose address or port changed is found
// again from its announcement, verified by an authenticated probe.
import 'dart:io';

import 'package:bsat/services/lan/lan_discovery.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/lan_test_support.dart';

void main() {
  sqfliteFfiInit();

  final fingerprint = 'ab' * 32;
  final lan = InternetAddress('192.168.1.20');

  group('announcement wire format', () {
    test('round-trips fingerprint and port', () {
      final decoded =
          decodeLanAnnouncement(encodeLanAnnouncement(fingerprint, 47331), lan);
      expect(decoded, isNotNull);
      expect(decoded!.fingerprint, fingerprint);
      expect(decoded.port, 47331);
      expect(decoded.address, lan);
    });

    test('rejects malformed, foreign and public-address datagrams', () {
      final valid = encodeLanAnnouncement(fingerprint, 47331);
      expect(decodeLanAnnouncement(valid, InternetAddress('8.8.8.8')), isNull);
      expect(decodeLanAnnouncement('hello'.codeUnits, lan), isNull);
      expect(decodeLanAnnouncement(<int>[], lan), isNull);
      expect(
        decodeLanAnnouncement(encodeLanAnnouncement('xyz', 47331), lan),
        isNull,
      );
      expect(
        decodeLanAnnouncement(encodeLanAnnouncement(fingerprint, 70000), lan),
        isNull,
      );
      expect(decodeLanAnnouncement(List.filled(400, 32), lan), isNull);
    });

    test('broadcast targets include limited and /24 directed broadcast', () {
      final targets = lanBroadcastTargets([
        InternetAddress('192.168.43.17'),
        InternetAddress('10.0.5.9'),
      ]).map((a) => a.address);
      expect(
        targets,
        containsAll(['255.255.255.255', '192.168.43.255', '10.0.5.255']),
      );
    });
  });

  group('rediscovery', () {
    late LanTestPhone a;
    late LanTestPhone b;
    const udpA = 47911;
    const udpB = 47912;

    List<InternetAddress> loopback(List<InternetAddress> _) =>
        [InternetAddress.loopbackIPv4];

    setUp(() async {
      a = await LanTestPhone.create(
        'Phone A',
        discovery:
            LanDiscovery(port: udpA, announcePort: udpB, targets: loopback),
      );
      b = await LanTestPhone.create(
        'Phone B',
        discovery:
            LanDiscovery(port: udpB, announcePort: udpA, targets: loopback),
      );
      await pairPhones(a, b);
    });

    tearDown(() async {
      await a.dispose();
      await b.dispose();
    });

    test('stale record is replaced after the peer announces', () async {
      final aFingerprint = a.service.identity!.fingerprint;
      // B's record of A points at a dead port (as after A rebinds elsewhere).
      await b.sqlite.recordLanPeerConnection(
        aFingerprint,
        address: '127.0.0.1',
        port: 1,
        connectedAt: 0,
      );
      expect((await b.peers.byFingerprint(aFingerprint))!.lastPort, 1);

      // The periodic refresh: A is already listening, so it just announces.
      await a.service.startListening();

      await waitForAsync(
        () async =>
            (await b.peers.byFingerprint(aFingerprint))?.lastPort ==
            a.service.listenPort,
        reason: 'B saved the verified announced port',
      );
    });

    test('an announced address that fails the probe is not saved', () async {
      final aFingerprint = a.service.identity!.fingerprint;
      await b.sqlite.recordLanPeerConnection(
        aFingerprint,
        address: '127.0.0.1',
        port: 2,
        connectedAt: 0,
      );

      // A forged announcement for A's fingerprint, pointing where nothing
      // listens.
      final forger = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      forger.send(
        encodeLanAnnouncement(aFingerprint, 3),
        InternetAddress.loopbackIPv4,
        udpB,
      );
      await Future<void>.delayed(const Duration(seconds: 3));
      forger.close();

      expect((await b.peers.byFingerprint(aFingerprint))!.lastPort, 2);
    });

    test('announcements from unpaired fingerprints are ignored', () async {
      final aFingerprint = a.service.identity!.fingerprint;
      final before = await b.peers.byFingerprint(aFingerprint);

      final stranger = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      stranger.send(
        encodeLanAnnouncement('cd' * 32, a.service.listenPort!),
        InternetAddress.loopbackIPv4,
        udpB,
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
      stranger.close();

      final after = await b.peers.byFingerprint(aFingerprint);
      expect(after!.lastPort, before!.lastPort);
      expect(after.lastAddress, before.lastAddress);
    });
  });
}
