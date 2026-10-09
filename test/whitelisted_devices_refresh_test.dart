import 'dart:io';

import 'package:bsat/services/sqlite_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory temporaryDirectory;
  late Database db;

  setUp(() async {
    temporaryDirectory =
        await Directory.systemTemp.createTemp('bsat-whitelist-refresh-');
    db = await databaseFactoryFfi.openDatabase(
      path.join(temporaryDirectory.path, 'refresh.db'),
    );
    await db.execute('''
      CREATE TABLE whitelistedDevices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device_name TEXT NOT NULL UNIQUE,
        device_id TEXT NOT NULL,
        owner_email TEXT NOT NULL,
        user_id INTEGER
      )
    ''');
    await db.insert('whitelistedDevices', _device('old', 'old-id'));
  });

  tearDown(() async {
    await db.close();
    await temporaryDirectory.delete(recursive: true);
  });

  Future<List<String>> names() async {
    final rows = await db.query(
      'whitelistedDevices',
      columns: ['device_name'],
      orderBy: 'id ASC',
    );
    return rows.map((row) => row['device_name']! as String).toList();
  }

  test('valid response replaces the cache atomically', () async {
    final refreshed = await SQLiteService().refreshWhitelistedDevices(
      {
        'devices': [
          _device('first', 'first-id'),
          _device('second', 'second-id', userId: 2),
        ],
      },
      databaseOverride: db,
    );

    expect(refreshed, hasLength(2));
    expect(await names(), ['first', 'second']);
    expect((await db.query('whitelistedDevices')).last['user_id'], 2);
  });

  test('malformed response leaves the old cache unchanged', () async {
    final refreshed = await SQLiteService().refreshWhitelistedDevices(
      {
        'devices': {'not': 'a list'}
      },
      databaseOverride: db,
    );

    expect(refreshed, isNull);
    expect(await names(), ['old']);
  });

  test('duplicate names leave the old cache unchanged', () async {
    final refreshed = await SQLiteService().refreshWhitelistedDevices(
      {
        'devices': [
          _device('same', 'first-id'),
          _device('same', 'second-id'),
        ],
      },
      databaseOverride: db,
    );

    expect(refreshed, isNull);
    expect(await names(), ['old']);
  });

  test('insert failure rolls back deletion and earlier inserts', () async {
    await db.execute('''
      CREATE TRIGGER fail_whitelisted_insert
      AFTER INSERT ON whitelistedDevices
      WHEN NEW.device_name = 'fail'
      BEGIN
        SELECT RAISE(ABORT, 'forced insert failure');
      END
    ''');

    final refreshed = await SQLiteService().refreshWhitelistedDevices(
      {
        'devices': [
          _device('inserted-before-failure', 'first-id'),
          _device('fail', 'failing-id'),
        ],
      },
      databaseOverride: db,
    );

    expect(refreshed, isNull);
    expect(await names(), ['old']);
  });

  test('empty valid response clears the cache', () async {
    final refreshed = await SQLiteService().refreshWhitelistedDevices(
      {'devices': <Map<String, dynamic>>[]},
      databaseOverride: db,
    );

    expect(refreshed, isEmpty);
    expect(await db.query('whitelistedDevices'), isEmpty);
  });

  test('optional user_id may be absent', () async {
    final device = _device('without-owner-id', 'device-id')
      ..remove('id')
      ..remove('user_id');

    final refreshed = await SQLiteService().refreshWhitelistedDevices(
      {
        'devices': [device]
      },
      databaseOverride: db,
    );

    expect(refreshed, hasLength(1));
    final rows = await db.query('whitelistedDevices');
    expect(rows.single['device_name'], 'without-owner-id');
    expect(rows.single['user_id'], isNull);
  });
}

Map<String, dynamic> _device(
  String name,
  String deviceId, {
  int? userId,
}) {
  return {
    'id': 999,
    'device_name': name,
    'device_id': deviceId,
    'owner_email': '$name@example.com',
    'user_id': userId,
  };
}
