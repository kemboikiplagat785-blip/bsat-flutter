// LAN forwarding test support (disposable copy only). Real sockets on
// 127.0.0.1, real handshake and record crypto, test-only key wrapper (the
// Android Keystore is not available on the host). Every simulated phone has
// its own in-memory database, so two phones never share state.
import 'dart:io';

import 'package:bsat/services/lan/lan_device_identity.dart';
import 'package:bsat/services/lan/lan_forwarding_service.dart';
import 'package:bsat/services/lan/lan_key_wrapper.dart';
import 'package:bsat/services/lan/lan_pairing.dart';
import 'package:bsat/services/lan/lan_peer_store.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A fresh, private BSAT database with the production schema.
Future<Database> openPhoneDatabase() async {
  final db = await databaseFactoryFfiNoIsolate.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 22,
      singleInstance: false,
      onCreate: (db, version) =>
          SQLiteService(databaseOverride: db).onCreate(db, version),
    ),
  );
  await SQLiteService(databaseOverride: db).ensureCriticalSchema(db);
  return db;
}

Future<void> waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
  String reason = 'condition',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for $reason');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// Polls [check] until it holds.
Future<void> waitForAsync(
  Future<bool> Function() check, {
  Duration timeout = const Duration(seconds: 10),
  String reason = 'condition',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!await check()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for $reason');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// One simulated phone: identity, pairing store and LAN service.
class LanTestPhone {
  final String name;
  final String id;
  final SQLiteService sqlite;
  final LanPeerStore peers;
  final LanForwardingService service;
  final Directory directory;

  LanTestPhone._(
    this.name,
    this.id,
    this.sqlite,
    this.peers,
    this.service,
    this.directory,
  );

  static Future<LanTestPhone> create(
    String name, {
    SQLiteService? sqlite,
    LanInboundHandler? inboundHandler,
    LanReplyProcessor? replyProcessor,
    Duration replyTimeout = const Duration(seconds: 5),
    int preferredPort = 0,
  }) async {
    final store = sqlite ?? SQLiteService(databaseOverride: await openPhoneDatabase());
    final peers = LanPeerStore(store);
    final directory = await Directory.systemTemp.createTemp('bsat_lan_');
    final id = 'device-${name.toLowerCase().replaceAll(' ', '-')}';
    final service = LanForwardingService(
      peers: peers,
      identityStore: IdentityStore(directory: directory, wrapper: TestKeyWrapper()),
      ownDeviceName: () async => name,
      ownDeviceId: () async => id,
      listenAddresses: () async => [InternetAddress.loopbackIPv4],
      preferredPort: preferredPort,
      connectTimeout: const Duration(seconds: 2),
      replyTimeout: replyTimeout,
      probeTimeout: const Duration(seconds: 2),
      inboundHandler: inboundHandler,
      replyProcessor: replyProcessor,
    );
    return LanTestPhone._(name, id, store, peers, service, directory);
  }

  Future<void> dispose() async {
    service.pairing?.cancel();
    await service.stopListening();
    try {
      await directory.delete(recursive: true);
    } catch (_) {}
  }
}

/// Pairs [inviter] (shows the QR) and [joiner] (scans it), both users
/// confirming the same code.
Future<void> pairPhones(LanTestPhone inviter, LanTestPhone joiner) async {
  final invitation = await inviter.service.createInvitation(
    expectedDeviceName: joiner.name,
    expectedDeviceId: joiner.id,
  );
  await joiner.service.joinWithInvitation(
    invitation.qrText,
    expectedDeviceName: inviter.name,
    expectedDeviceId: inviter.id,
    scanned: true,
  );
  expect(joiner.service.pairingError, isNull);
  await waitFor(
    () =>
        inviter.service.pairing?.peerAccepted == true &&
        joiner.service.pairing?.peerAccepted == true,
    reason: 'both identities exchanged',
  );
  expect(inviter.service.pairing!.sas, joiner.service.pairing!.sas);
  await inviter.service.pairing!.confirm();
  await joiner.service.pairing!.confirm();
  await waitFor(
    () =>
        inviter.service.pairing?.phase == PairingPhase.completed &&
        joiner.service.pairing?.phase == PairingPhase.completed,
    reason: 'pairing completed on both phones',
  );
}
