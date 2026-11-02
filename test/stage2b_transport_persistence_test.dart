// STAGE 2B persistence (disposable copy): the per-destination forwarding
// transport is stored in forwardingDevices.forwarding_transport, added by the
// critical-schema repair (_addColumnIfMissing) that runs on every open.
// Storage tests use temporary database files opened the way
// SQLiteService._initDatabase opens the app database (version 22, onCreate,
// onUpgrade, then ensureCriticalSchema). Controller tests use the Stage 0
// harness: offline, USSD/SMS refused and recorded, HTTP answered locally.
import 'dart:io';

import 'package:bsat/controllers/transaction_controller.dart';
import 'package:bsat/services/forwarding_transport_selection.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/stage0_harness.dart';
import 'support/stage1_fakes.dart';

const _receipt = 'SJK1ABCD23';
const _sms = '$_receipt Confirmed. Ksh100.00 received from JOHN DOE '
    '0712345678. SYNTHETIC STAGE 2B TEST MESSAGE ONLY.';

const _phoneB = ForwardingDestination(deviceId: 'device-b', deviceName: 'Phone B');
const _phoneC = ForwardingDestination(deviceId: 'device-c', deviceName: 'Phone C');

/// The columns edit_forwarder.dart writes when creating or editing a rule.
Map<String, Object?> _screenRow(String name, String id) => {
      'device_id': id,
      'device_name': name,
      'owner_email': 'owner@example.test',
      'user_id': 7,
      'amounts_to_forward': '[100]',
    };

Future<bool> _hasTransportColumn(Database db) async =>
    (await db.rawQuery('PRAGMA table_info("forwardingDevices")'))
        .any((c) => c['name'] == 'forwarding_transport');

void main() {
  group('storage', () {
    late Directory dir;
    late String dbPath;
    final service = SQLiteService();
    final opened = <Database>[];

    setUpAll(sqfliteFfiInit);
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('bsat-stage2b-persist-');
      dbPath = path.join(dir.path, 'bsat_app.db');
    });
    tearDown(() async {
      for (final db in opened) {
        if (db.isOpen) await db.close();
      }
      opened.clear();
      await dir.delete(recursive: true);
    });

    /// Opens [dbPath] like SQLiteService._initDatabase (open + repair).
    Future<Database> openLikeApp() async {
      final db = await databaseFactoryFfiNoIsolate.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 22,
          onCreate: service.onCreate,
          onUpgrade: service.onUpgrade,
        ),
      );
      opened.add(db);
      await service.ensureCriticalSchema(db);
      return db;
    }

    /// The current production schema before this change: onCreate only, no
    /// repair, so forwardingDevices has no forwarding_transport column.
    Future<Database> openLegacy() async {
      final db = await databaseFactoryFfiNoIsolate.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(version: 22, onCreate: service.onCreate),
      );
      opened.add(db);
      return db;
    }

    SQLiteForwardingTransportPreferences storeFor(Database db) =>
        SQLiteForwardingTransportPreferences(
            SQLiteService(databaseOverride: db));

    Future<ForwardingRouteDecision> resolve(
            Database db, ForwardingDestination d) =>
        ForwardingTransportResolver(storeFor(db)).resolve(d);

    Future<Object?> stored(Database db, String deviceId) async =>
        (await db.query('forwardingDevices',
                where: 'device_id = ?', whereArgs: [deviceId]))
            .single['forwarding_transport'];

    test('1. a new device without a preference resolves to online', () async {
      final db = await openLikeApp();
      expect(await _hasTransportColumn(db), isTrue,
          reason: 'fresh databases get the column from the repair');
      await SQLiteService(databaseOverride: db)
          .insertStuff(_screenRow('Phone B', 'device-b'), 'forwardingDevices');

      expect(await stored(db, 'device-b'), isNull);
      final decision = await resolve(db, _phoneB);
      expect(decision.selected, ForwardingTransportKind.online);
      expect(decision.deliverable, isTrue);
    });

    test('2. an existing database with legacy device rows migrates; rows are '
        'intact and resolve to online', () async {
      final legacy = await openLegacy();
      expect(await _hasTransportColumn(legacy), isFalse);
      await legacy.insert('forwardingDevices',
          {..._screenRow('Phone B', 'device-b'), 'paused': 0});
      await legacy.insert('forwardingDevices',
          {..._screenRow('Phone C', 'device-c'), 'paused': 1});
      final before = await legacy.query('forwardingDevices', orderBy: 'id');
      await legacy.close();

      final db = await openLikeApp();
      expect(await _hasTransportColumn(db), isTrue);
      final after = await db.query('forwardingDevices', orderBy: 'id');
      expect(
          after.map((r) => Map.of(r)..remove('forwarding_transport')).toList(),
          before,
          reason: 'existing columns, values and ids unchanged');
      expect(after.map((r) => r['forwarding_transport']).toList(),
          [null, null]);
      for (final d in [_phoneB, _phoneC]) {
        expect((await resolve(db, d)).selected, ForwardingTransportKind.online);
      }
    });

    test('2b. an older install without forwardingDevices.paused gets both '
        'columns; defaults of existing columns are unchanged', () async {
      final legacy = await openLegacy();
      await legacy.execute('ALTER TABLE forwardingDevices DROP COLUMN paused');
      await legacy.insert('forwardingDevices', _screenRow('Phone B', 'device-b'));
      await legacy.close();

      final db = await openLikeApp();
      final row = (await db.query('forwardingDevices')).single;
      expect(row['paused'], 0, reason: 'paused keeps its DEFAULT 0');
      expect(row['forwarding_transport'], isNull);
      expect((await resolve(db, _phoneB)).deliverable, isTrue);
    });

    test('3. the migration can run repeatedly without damaging data',
        () async {
      var db = await openLikeApp();
      await db.insert('forwardingDevices', _screenRow('Phone B', 'device-b'));
      await db.insert('forwardingDevices', _screenRow('Phone C', 'device-c'));
      await storeFor(db).save(_phoneC, ForwardingTransportKind.lan);
      final before = await db.query('forwardingDevices', orderBy: 'id');

      await service.ensureCriticalSchema(db);
      await service.ensureCriticalSchema(db);
      await db.close();
      db = await openLikeApp();
      await db.close();
      db = await openLikeApp();

      expect(await db.query('forwardingDevices', orderBy: 'id'), before);
      final columns = (await db.rawQuery('PRAGMA table_info("forwardingDevices")'))
          .where((c) => c['name'] == 'forwarding_transport')
          .toList();
      expect(columns, hasLength(1));
      expect(columns.single['type'], 'TEXT');
      expect(columns.single['notnull'], 0);
      expect(columns.single['dflt_value'], isNull);
    });

    for (final kind in ForwardingTransportKind.values) {
      test('${kind == ForwardingTransportKind.online ? 4 : 5}. a ${kind.name} '
          'preference survives closing and reopening the database', () async {
        var db = await openLikeApp();
        await db.insert('forwardingDevices', _screenRow('Phone C', 'device-c'));
        await storeFor(db).save(_phoneC, kind);
        await db.close();

        db = await openLikeApp();
        expect(await stored(db, 'device-c'), kind.name);
        final decision = await resolve(db, _phoneC);
        expect(decision.selected, kind);
        expect(decision.deliverable, kind == ForwardingTransportKind.online);
      });
    }

    test('6/7. unknown, malformed and empty stored values resolve to online',
        () async {
      final db = await openLikeApp();
      await db.insert('forwardingDevices', _screenRow('Phone C', 'device-c'));
      for (final raw in <Object?>['', 'LAN', ' lan ', 'wifi', 'online ', 7]) {
        await db.update('forwardingDevices', {'forwarding_transport': raw},
            where: 'device_id = ?', whereArgs: ['device-c']);
        final decision = await resolve(db, _phoneC);
        expect(decision.selected, ForwardingTransportKind.online,
            reason: 'stored ${raw.runtimeType} "$raw"');
        expect(decision.deliverable, isTrue);
      }
    });

    test('8. a database read failure is not mistaken for a missing '
        'preference: a LAN destination stays undeliverable', () async {
      final db = await openLikeApp();
      await db.insert('forwardingDevices', _screenRow('Phone B', 'device-b'));
      await db.insert('forwardingDevices', _screenRow('Phone C', 'device-c'));
      await storeFor(db).save(_phoneC, ForwardingTransportKind.lan);
      final store = storeFor(db);
      expect(await store.storedPreferenceFor(_phoneB), isNull,
          reason: 'a legacy row is a missing preference');

      await db.close();
      await expectLater(store.storedPreferenceFor(_phoneC), throwsA(anything),
          reason: 'a failed read throws instead of returning null');
      for (final d in [_phoneB, _phoneC]) {
        final decision = await ForwardingTransportResolver(store).resolve(d);
        expect(decision.selected, isNull);
        expect(decision.deliverable, isFalse);
        expect(decision.label, 'unresolved');
      }
    });

    test('8b. a destination whose row is gone is unresolved, not online',
        () async {
      final db = await openLikeApp();
      await expectLater(storeFor(db).storedPreferenceFor(_phoneC),
          throwsA(isA<StateError>()));
      expect((await resolve(db, _phoneC)).deliverable, isFalse);
      await expectLater(
          storeFor(db).save(_phoneC, ForwardingTransportKind.lan),
          throwsA(isA<StateError>()),
          reason: 'saving never creates a device row');
      expect(await db.query('forwardingDevices'), isEmpty);
    });

    test('9. saving Phone B\'s preference does not change Phone C\'s',
        () async {
      final db = await openLikeApp();
      await db.insert('forwardingDevices', _screenRow('Phone B', 'device-b'));
      await db.insert('forwardingDevices', _screenRow('Phone C', 'device-c'));
      final service = SQLiteService(databaseOverride: db);
      expect(
          await service.setForwardingTransportPreference(
              deviceId: 'device-c', deviceName: 'Phone C', transport: 'lan'),
          1);
      for (final kind in [
        ForwardingTransportKind.lan,
        ForwardingTransportKind.online,
      ]) {
        expect(
            await service.setForwardingTransportPreference(
                deviceId: 'device-b',
                deviceName: 'Phone B',
                transport: kind.name),
            1,
            reason: 'exactly one row updated');
        expect(await stored(db, 'device-c'), 'lan');
        expect((await resolve(db, _phoneC)).selected,
            ForwardingTransportKind.lan);
      }
      expect(await stored(db, 'device-b'), 'online');
    });

    test('9b. the lookup needs both device_id and device_name, so a row that '
        'shares one of them never supplies the preference', () async {
      final db = await openLikeApp();
      await db.insert('forwardingDevices', _screenRow('Phone C', 'device-c'));
      await db.insert(
          'forwardingDevices', _screenRow('Phone C (old)', 'device-c'));
      await storeFor(db).save(
          const ForwardingDestination(
              deviceId: 'device-c', deviceName: 'Phone C (old)'),
          ForwardingTransportKind.lan);
      expect((await resolve(db, _phoneC)).selected,
          ForwardingTransportKind.online);
    });

    test('10/12. editing and pausing through the screens\' SQL does not '
        'overwrite the preference', () async {
      final db = await openLikeApp();
      final service = SQLiteService(databaseOverride: db);
      final id = await service.insertStuff(
          _screenRow('Phone C', 'device-c'), 'forwardingDevices');
      await storeFor(db).save(_phoneC, ForwardingTransportKind.lan);

      // edit_forwarder.dart, editing the same destination's amounts.
      await service.updateStuff(
        {..._screenRow('Phone C', 'device-c'), 'amounts_to_forward': '[100,250]'},
        'id = ?',
        [id],
        'forwardingDevices',
      );
      // paired_devices.dart _togglePause, both directions.
      for (final paused in [1, 0]) {
        await service.updateStuff(
            {'paused': paused}, 'id = ?', [id], 'forwardingDevices');
      }

      final row = (await db.query('forwardingDevices')).single;
      expect(row['amounts_to_forward'], '[100,250]');
      expect(row['paused'], 0);
      expect(row['forwarding_transport'], 'lan');
      expect((await resolve(db, _phoneC)).deliverable, isFalse);
    });

    test('11/12. deleting a device removes its preference; adding it again '
        'starts from online', () async {
      final db = await openLikeApp();
      final service = SQLiteService(databaseOverride: db);
      final idB = await service.insertStuff(
          _screenRow('Phone B', 'device-b'), 'forwardingDevices');
      final idC = await service.insertStuff(
          _screenRow('Phone C', 'device-c'), 'forwardingDevices');
      await storeFor(db).save(_phoneB, ForwardingTransportKind.lan);
      await storeFor(db).save(_phoneC, ForwardingTransportKind.lan);

      // edit_forwarder.dart / paired_devices.dart delete by local id.
      expect(await service.deleteWhere('forwardingDevices', 'id = ?', [idC]), 1);
      expect((await db.query('forwardingDevices')).single['id'], idB);
      expect(await stored(db, 'device-b'), 'lan', reason: 'B unaffected');
      expect((await resolve(db, _phoneC)).deliverable, isFalse,
          reason: 'a deleted destination receives nothing');

      await service.insertStuff(
          _screenRow('Phone C', 'device-c'), 'forwardingDevices');
      expect(await stored(db, 'device-c'), isNull);
      expect((await resolve(db, _phoneC)).selected,
          ForwardingTransportKind.online);
    });

    test('characterization (known limitation): re-pointing an existing rule '
        'to another device in edit_forwarder keeps the row\'s preference',
        () async {
      final db = await openLikeApp();
      final service = SQLiteService(databaseOverride: db);
      final id = await service.insertStuff(
          _screenRow('Phone C', 'device-c'), 'forwardingDevices');
      await storeFor(db).save(_phoneC, ForwardingTransportKind.lan);

      await service.updateStuff(_screenRow('Phone D', 'device-d'), 'id = ?',
          [id], 'forwardingDevices');

      const phoneD =
          ForwardingDestination(deviceId: 'device-d', deviceName: 'Phone D');
      final decision = await resolve(db, phoneD);
      expect(decision.selected, ForwardingTransportKind.lan);
      expect(decision.deliverable, isFalse,
          reason: 'the inherited value can only block delivery, never send '
              'a LAN destination over the Internet');
    });
  });

  group('routing with persisted preferences (controller, production default '
      'store)', () {
    final h = Stage0Harness();

    setUpAll(Stage0Harness.setUpAllOnce);
    tearDownAll(Stage0Harness.tearDownAllOnce);
    tearDown(h.tearDown);

    Future<void> phoneA(Map<String, ForwardingTransportKind?> devices) async {
      await h.setUp(prefs: {
        'user_device_name': 'Phone A',
        'jwt_token': 'stage2b-test-jwt',
      });
      final db = await h.db;
      for (final MapEntry(key: name, value: kind) in devices.entries) {
        final id = 'device-${name.substring(6).toLowerCase()}';
        await db.insert('forwardingDevices', {
          ..._screenRow(name, id),
          'paused': 0,
        });
        if (kind != null) {
          await SQLiteForwardingTransportPreferences().save(
              ForwardingDestination(deviceId: id, deviceName: name), kind);
        }
      }
    }

    test('the app database (opened by SQLiteService) has the column',
        () async {
      await phoneA({});
      expect(await _hasTransportColumn(await h.db), isTrue);
    });

    test('a stored LAN preference blocks a new job without any request',
        () async {
      await phoneA({'Phone C': ForwardingTransportKind.lan});
      final transport = RecordingForwardingTransport();
      final result = await h.capture(() => TransactionController(
            sqliteService: SQLiteService(),
            forwardingTransport: transport,
          ).forwardIfNeeded(
              100, _sms, _sms, _receipt, 712345678, 'JOHN DOE', false));

      expect(result.state, ForwardingAttemptState.configuredButUnavailable);
      expect(transport.submissions, isEmpty);
      expect(h.requests, isEmpty);
      expect(await (await h.db).query('transactions'), isEmpty);
      h.expectNoExternalEffects();
    });

    test('forwardToAllAvenues: stored online B receives, stored LAN C and '
        'legacy D (no preference) behave as configured', () async {
      await phoneA({
        'Phone B': ForwardingTransportKind.online,
        'Phone C': ForwardingTransportKind.lan,
        'Phone D': null,
      });
      await h.capture(() => TransactionController(sqliteService: SQLiteService())
          .forwardToAllAvenues(_sms));

      expect(h.backendPosts.map((r) => r.json['recipientDeviceName']),
          ['Phone B', 'Phone D']);
      expect(h.requests.where((r) => r.method == 'GET'), hasLength(2),
          reason: 'the LAN destination is not pinged');
      h.expectNoExternalEffects();
    });
  });
}
