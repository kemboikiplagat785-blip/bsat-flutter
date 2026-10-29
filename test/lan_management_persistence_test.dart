// LAN management storage without an Online account: trusted LAN devices,
// LAN forwarding rules and this phone's local LAN name are local only and
// survive an app restart (the database file is closed and reopened).
// Synthetic data; no network, SMS or USSD.
import 'dart:io';
import 'dart:typed_data';

import 'package:bsat/services/forwarding_transport_selection.dart';
import 'package:bsat/services/lan/lan_forwarding_rules.dart';
import 'package:bsat/services/lan/lan_local_identity.dart';
import 'package:bsat/services/lan/lan_peer_store.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Uint8List _key(int seed) =>
    Uint8List.fromList(List<int>.generate(32, (i) => (seed * 31 + i) & 0xff));

void main() {
  late Directory directory;
  late String path;
  late Database db;
  late SQLiteService sqlite;

  Future<void> open() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 22,
        singleInstance: false,
        onCreate: (db, version) =>
            SQLiteService(databaseOverride: db).onCreate(db, version),
      ),
    );
    sqlite = SQLiteService(databaseOverride: db);
    await sqlite.ensureCriticalSchema(db);
  }

  /// Simulates an app restart: the database is closed and reopened.
  Future<void> restart() async {
    await db.close();
    await open();
  }

  LanPeerStore peers() => LanPeerStore(sqlite);
  LanForwardingRuleStore rules() =>
      LanForwardingRuleStore(sqliteService: sqlite, peers: peers());

  Future<LanPeer> trust(String name, int seed) => peers().trust(
        publicKey: _key(seed),
        deviceName: name,
        deviceId: '',
        address: '192.168.1.${10 + seed}',
        port: 47000,
      );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('bsat_lan_mgmt_');
    path = '${directory.path}/bsat.db';
    await open();
  });

  tearDown(() async {
    await db.close();
    try {
      await directory.delete(recursive: true);
    } catch (_) {}
  });

  test('a trusted LAN pairing (no Online device record) persists across a '
      'restart', () async {
    final peer = await trust('Shop Phone', 1);
    expect(await sqlite.queryAll('whitelistedDevices'), isEmpty);

    await restart();

    final restored = await peers().all();
    expect(restored, hasLength(1));
    expect(restored.single.deviceName, 'Shop Phone');
    expect(restored.single.fingerprint, peer.fingerprint);
    expect(restored.single.isTrusted, isTrue);
    final lookup = await peers().lookupDevice('Shop Phone');
    expect(lookup.state, LanPeerLookupState.trusted);
  });

  test('LAN rules: create, edit, disable, enable and remove, each persisted '
      'across a restart', () async {
    final shop = await trust('Shop Phone', 1);
    await trust('Back Office', 2);

    final created =
        await rules().create(deviceName: 'Shop Phone', amounts: [200, 100, 100]);
    expect(created.amounts, [100, 200]);
    expect(created.enabled, isTrue);
    expect(created.lanOnly, isTrue);

    await restart();
    var all = await rules().all();
    expect(all.single.deviceName, 'Shop Phone');
    expect(all.single.amounts, [100, 200]);
    // Stored exactly as the forwarding engine reads rules.
    final row = (await sqlite.queryAll('forwardingDevices')).single;
    expect(row['forwarding_transport'], 'lan');
    expect(row['device_id'], 'lan:${shop.fingerprint}');
    expect(row['amounts_to_forward'], '[100,200]');
    expect(row['paused'], 0);
    expect(
      parseForwardingTransportPreference(row['forwarding_transport']),
      ForwardingTransportKind.lan,
    );

    await rules().update(created.id,
        deviceName: 'Back Office', amounts: [50, 100]);
    await restart();
    all = await rules().all();
    expect(all.single.deviceName, 'Back Office');
    expect(all.single.amounts, [50, 100]);

    await rules().setEnabled(created.id, false);
    await restart();
    expect((await rules().all()).single.enabled, isFalse);
    expect((await sqlite.queryAll('forwardingDevices')).single['paused'], 1);

    await rules().setEnabled(created.id, true);
    await restart();
    expect((await rules().all()).single.enabled, isTrue);

    await rules().remove(created.id);
    await restart();
    expect(await rules().all(), isEmpty);
    expect(await sqlite.queryAll('forwardingDevices'), isEmpty);
  });

  test('a rule needs a trusted LAN device: unpaired and revoked devices are '
      'refused', () async {
    await expectLater(
      rules().create(deviceName: 'Stranger', amounts: [100]),
      throwsA(isA<LanRuleException>()),
    );
    final revoked = await trust('Old Phone', 3);
    await peers().revoke(revoked.fingerprint);
    await expectLater(
      rules().create(deviceName: 'Old Phone', amounts: [100]),
      throwsA(isA<LanRuleException>()),
    );
    expect(await sqlite.queryAll('forwardingDevices'), isEmpty);
  });

  test('invalid amounts and duplicate rules are refused', () async {
    await trust('Shop Phone', 1);
    await expectLater(
      rules().create(deviceName: 'Shop Phone', amounts: []),
      throwsA(isA<LanRuleException>()),
    );
    await expectLater(
      rules().create(deviceName: 'Shop Phone', amounts: [0]),
      throwsA(isA<LanRuleException>()),
    );
    await rules().create(deviceName: 'Shop Phone', amounts: [100]);
    await expectLater(
      rules().create(deviceName: 'Shop Phone', amounts: [200]),
      throwsA(isA<LanRuleException>()),
    );
    expect(await rules().all(), hasLength(1));
  });

  test('an Online rule is never silently turned into a LAN rule, and LAN '
      'management never edits or removes Online rules', () async {
    await trust('Shop Phone', 1);
    await sqlite.insertStuff({
      'device_name': 'Shop Phone',
      'device_id': 'backend-device-7',
      'owner_email': 'owner@example.test',
      'amounts_to_forward': '[100]',
      'paused': 0,
    }, 'forwardingDevices');
    final onlineId = (await sqlite.queryAll('forwardingDevices')).single['id']
        as int;

    await expectLater(
      rules().create(deviceName: 'Shop Phone', amounts: [100]),
      throwsA(isA<LanRuleException>()),
    );
    expect(await rules().all(), isEmpty,
        reason: 'an Online-transport rule is not a LAN rule');
    await expectLater(rules().setEnabled(onlineId, false),
        throwsA(isA<LanRuleException>()));
    await rules().remove(onlineId);
    final row = (await sqlite.queryAll('forwardingDevices')).single;
    expect(row['paused'], 0);
    expect(row['device_id'], 'backend-device-7');
    expect(row['forwarding_transport'], isNull);
  });

  test('an Online rule switched to LAN is listed; its amounts may change but '
      'its Online device may not', () async {
    await trust('Shop Phone', 1);
    await trust('Back Office', 2);
    final id = await sqlite.insertStuff({
      'device_name': 'Shop Phone',
      'device_id': 'backend-device-7',
      'owner_email': 'owner@example.test',
      'amounts_to_forward': '[100]',
      'paused': 0,
      'forwarding_transport': 'lan',
    }, 'forwardingDevices');

    final rule = (await rules().all()).single;
    expect(rule.lanOnly, isFalse);
    await rules().update(id, deviceName: 'Shop Phone', amounts: [100, 300]);
    await expectLater(
      rules().update(id, deviceName: 'Back Office', amounts: [100]),
      throwsA(isA<LanRuleException>()),
    );
    final row = (await sqlite.queryAll('forwardingDevices')).single;
    expect(row['device_id'], 'backend-device-7');
    expect(row['device_name'], 'Shop Phone');
    expect(row['amounts_to_forward'], '[100,300]');
  });

  test('isLanOnlyForwardingRow marks only rules created in LAN management',
      () {
    expect(isLanOnlyForwardingRow({'device_id': 'lan:abc'}), isTrue);
    expect(isLanOnlyForwardingRow({'device_id': 'backend-device-7'}), isFalse);
    expect(isLanOnlyForwardingRow({'device_id': null}), isFalse);
  });

  group('this phone\'s forwarding name', () {
    test('without an Online account the local LAN name is used and persists',
        () async {
      SharedPreferences.setMockInitialValues({});
      expect(await forwardingDeviceName(), isNull);
      expect(await hasOnlineDeviceName(), isFalse);
      await setLanLocalDeviceName('  Shop Phone  ');
      expect(await getLanLocalDeviceName(), 'Shop Phone');
      expect(await forwardingDeviceName(), 'Shop Phone');
    });

    test('an Online device name always wins, unchanged', () async {
      SharedPreferences.setMockInitialValues({
        'user_device_name': 'Online Name',
        lanLocalDeviceNameKey: 'Shop Phone',
      });
      expect(await forwardingDeviceName(), 'Online Name');
      expect(await hasOnlineDeviceName(), isTrue);
    });

    test('with neither name the Online value is returned unchanged', () async {
      SharedPreferences.setMockInitialValues({'user_device_name': ''});
      expect(await forwardingDeviceName(), '');
    });

    test('invalid names are refused', () async {
      SharedPreferences.setMockInitialValues({});
      expect(lanDeviceNameProblem('   '), isNotNull);
      expect(lanDeviceNameProblem('a' * 101), isNotNull);
      expect(lanDeviceNameProblem('bad\nname'), isNotNull);
      expect(lanDeviceNameProblem('Shop Phone'), isNull);
      await expectLater(setLanLocalDeviceName(''), throwsArgumentError);
      expect(await getLanLocalDeviceName(), isNull);
    });
  });

}
