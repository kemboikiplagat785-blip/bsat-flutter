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
  late String databasePath;

  setUp(() async {
    temporaryDirectory =
        await Directory.systemTemp.createTemp('bsat-sqlite-migration-');
    databasePath = path.join(temporaryDirectory.path, 'migration.db');
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  test('upgrade preserves rows, enforces uniqueness, and creates indexes',
      () async {
    final expectedRows = _rows();
    await _seedLegacyDatabase(databasePath, expectedRows);

    final db = await _upgrade(databasePath);
    try {
      expect(await _readDevices(db), expectedRows);
      await _expectFinalIndexes(db);
      await _expectNoTemporaryTable(db);
      await expectLater(
        db.insert('whitelistedDevices', {
          'device_name': expectedRows.first['device_name'],
          'device_id': 'duplicate-device-id',
          'owner_email': 'duplicate@example.com',
          'user_id': 999,
        }),
        throwsA(isA<DatabaseException>()),
      );
    } finally {
      await db.close();
    }
  });

  test('repeated versioned upgrade preserves all original rows', () async {
    final expectedRows = _rows();
    await _seedLegacyDatabase(databasePath, expectedRows);

    final firstUpgrade = await _upgrade(databasePath);
    await firstUpgrade.close();

    final versionReset = await databaseFactoryFfi.openDatabase(databasePath);
    await versionReset.setVersion(8);
    await versionReset.close();

    final secondUpgrade = await _upgrade(databasePath);
    try {
      expect(await _readDevices(secondUpgrade), expectedRows);
      await _expectFinalIndexes(secondUpgrade);
      await _expectNoTemporaryTable(secondUpgrade);

      // A correct row count alone would not prove the rebuild ran again: assert
      // the replacement schema still carries `device_name TEXT NOT NULL UNIQUE`
      // after the repeated upgrade.
      await expectLater(
        secondUpgrade.insert('whitelistedDevices', {
          'device_name': expectedRows.first['device_name'],
          'device_id': 'duplicate-after-reupgrade',
          'owner_email': 'duplicate@example.com',
          'user_id': 999,
        }),
        throwsA(isA<DatabaseException>()),
        reason: 'device_name UNIQUE must still be enforced after a repeated '
            'versioned upgrade',
      );
      expect(await secondUpgrade.getVersion(), 18);
    } finally {
      await secondUpgrade.close();
    }
  });

  test('duplicate device names fail and roll back the versioned upgrade',
      () async {
    final duplicateRows = [
      _row(1, 'duplicate', 'device-1', 'one@example.com', 10),
      _row(2, 'duplicate', 'device-2', 'two@example.com', 20),
    ];
    await _seedLegacyDatabase(databasePath, duplicateRows);

    await expectLater(
        _upgrade(databasePath), throwsA(isA<DatabaseException>()));

    final db = await databaseFactoryFfi.openDatabase(databasePath);
    try {
      expect(await db.getVersion(), 8);
      expect(await _readDevices(db), duplicateRows);
      await _expectNoTemporaryTable(db);
    } finally {
      await db.close();
    }
  });

  test('index creation failure after rename rolls back the entire upgrade',
      () async {
    final expectedRows = _rows();
    await _seedLegacyDatabase(
      databasePath,
      expectedRows,
      beforeClose: (db) async {
        await db
            .execute('CREATE TABLE migration_index_blocker (owner_email TEXT)');
        await db.execute(
          'CREATE INDEX idx_whitelisted_devices_email '
          'ON migration_index_blocker(owner_email)',
        );

        // Precondition for the distinguishing check below: prove the legacy
        // schema really does accept duplicate device_name values. Remove the
        // probe row immediately so the seeded dataset stays exactly
        // [expectedRows].
        final probeId = await db.insert('whitelistedDevices', {
          'device_name': expectedRows.first['device_name'],
          'device_id': 'legacy-schema-probe',
          'owner_email': 'probe@example.com',
          'user_id': 999,
        });
        expect(probeId, isNotNull);
        await db.delete(
          'whitelistedDevices',
          where: 'id = ?',
          whereArgs: [probeId],
        );
      },
    );

    await expectLater(
        _upgrade(databasePath), throwsA(isA<DatabaseException>()));

    final db = await databaseFactoryFfi.openDatabase(databasePath);
    try {
      expect(await db.getVersion(), 8);
      expect(await _readDevices(db), expectedRows);
      await _expectNoTemporaryTable(db);
      final blocker = await db.rawQuery(
        "SELECT tbl_name FROM sqlite_master "
        "WHERE type = 'index' AND name = 'idx_whitelisted_devices_email'",
      );
      expect(blocker.single['tbl_name'], 'migration_index_blocker');

      // Distinguishing assertions. The replacement schema declares
      // `device_name TEXT NOT NULL UNIQUE`, which SQLite exposes as an
      // automatic index; the legacy schema has no index at all. Finding the
      // legacy shape here proves the DROP + RENAME was rolled back rather than
      // committed with identical row values.
      await _expectLegacySchema(db);

      // Behavioural proof of the same property: the replacement table would
      // reject this insert, the restored legacy table accepts it.
      final duplicateId = await db.insert('whitelistedDevices', {
        'device_name': expectedRows.first['device_name'],
        'device_id': 'post-rollback-probe',
        'owner_email': 'post-rollback@example.com',
        'user_id': 999,
      });
      expect(duplicateId, isNotNull);
      expect(
        (await _readDevices(db)).length,
        expectedRows.length + 1,
        reason: 'duplicate device_name was accepted, so the table is still the '
            'pre-upgrade legacy table and the rename was rolled back',
      );
    } finally {
      await db.close();
    }
  });

  test('temporary table is restored when it is the only remaining copy',
      () async {
    final expectedRows = _rows();
    final db = await databaseFactoryFfi.openDatabase(databasePath);
    try {
      await _createLegacyTable(db, 'whitelistedDevices_new');
      for (final row in expectedRows) {
        await db.insert('whitelistedDevices_new', row);
      }
      await db.setVersion(8);
    } finally {
      await db.close();
    }

    final upgraded = await _upgrade(databasePath);
    try {
      expect(await _readDevices(upgraded), expectedRows);
      await _expectFinalIndexes(upgraded);
      await _expectNoTemporaryTable(upgraded);
    } finally {
      await upgraded.close();
    }
  });

  test('empty temporary table is removed while original data is preserved',
      () async {
    final expectedRows = _rows();
    await _seedLegacyDatabase(
      databasePath,
      expectedRows,
      beforeClose: (db) => _createLegacyTable(db, 'whitelistedDevices_new'),
    );

    final upgraded = await _upgrade(databasePath);
    try {
      expect(await _readDevices(upgraded), expectedRows);
      expect(await upgraded.getVersion(), 18);
      await _expectFinalIndexes(upgraded);
      await _expectNoTemporaryTable(upgraded);
      await expectLater(
        upgraded.insert('whitelistedDevices', {
          'device_name': expectedRows.first['device_name'],
          'device_id': 'duplicate-after-empty-temp',
          'owner_email': 'duplicate@example.com',
          'user_id': 999,
        }),
        throwsA(isA<DatabaseException>()),
      );
    } finally {
      await upgraded.close();
    }
  });

  test('non-empty temporary table alongside original is preserved on failure',
      () async {
    final originalRows = _rows();
    final temporaryRows = [
      _row(101, 'recoverable', 'temporary-device', 'temp@example.com', 101),
    ];
    final db = await databaseFactoryFfi.openDatabase(databasePath);
    try {
      await _createLegacyTable(db, 'whitelistedDevices');
      await _createLegacyTable(db, 'whitelistedDevices_new');
      for (final row in originalRows) {
        await db.insert('whitelistedDevices', row);
      }
      for (final row in temporaryRows) {
        await db.insert('whitelistedDevices_new', row);
      }
      await db.setVersion(8);
    } finally {
      await db.close();
    }

    await expectLater(_upgrade(databasePath), throwsA(isA<StateError>()));

    final reopened = await databaseFactoryFfi.openDatabase(databasePath);
    try {
      expect(await reopened.getVersion(), 8);
      expect(await _readDevices(reopened), originalRows);
      expect(
        await _readDevices(reopened, table: 'whitelistedDevices_new'),
        temporaryRows,
      );
    } finally {
      await reopened.close();
    }
  });
}

Future<void> _seedLegacyDatabase(
  String databasePath,
  List<Map<String, Object?>> rows, {
  Future<void> Function(Database db)? beforeClose,
}) async {
  final db = await databaseFactoryFfi.openDatabase(databasePath);
  try {
    await _createLegacyTable(db, 'whitelistedDevices');
    for (final row in rows) {
      await db.insert('whitelistedDevices', row);
    }
    await beforeClose?.call(db);
    await db.setVersion(8);
  } finally {
    await db.close();
  }
}

Future<void> _createLegacyTable(DatabaseExecutor db, String tableName) {
  return db.execute('''
    CREATE TABLE $tableName (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      device_name TEXT NOT NULL,
      device_id TEXT NOT NULL,
      owner_email TEXT NOT NULL,
      user_id INTEGER
    )
  ''');
}

Future<Database> _upgrade(String databasePath) {
  return databaseFactoryFfi.openDatabase(
    databasePath,
    options: OpenDatabaseOptions(
      version: 18,
      onUpgrade: SQLiteService().onUpgrade,
    ),
  );
}

Future<List<Map<String, Object?>>> _readDevices(
  DatabaseExecutor db, {
  String table = 'whitelistedDevices',
}) {
  return db.query(table, orderBy: 'id');
}

Future<void> _expectFinalIndexes(DatabaseExecutor db) async {
  final indexes = await db.rawQuery("PRAGMA index_list('whitelistedDevices')");
  final indexNames = indexes.map((row) => row['name']).toSet();
  expect(
    indexNames,
    containsAll({
      'idx_whitelisted_devices_email',
      'idx_whitelisted_devices_device_id',
      'idx_whitelisted_devices_user_id',
    }),
  );
}

Future<void> _expectNoTemporaryTable(DatabaseExecutor db) async {
  final tables = await db.rawQuery(
    "SELECT name FROM sqlite_master "
    "WHERE type = 'table' AND name = 'whitelistedDevices_new'",
  );
  expect(tables, isEmpty);
}

Future<void> _expectLegacySchema(DatabaseExecutor db) async {
  final schema = await db.rawQuery(
    "SELECT sql FROM sqlite_master "
    "WHERE type = 'table' AND name = 'whitelistedDevices'",
  );
  expect(schema, hasLength(1));
  final sql = schema.single['sql'].toString().toUpperCase();
  expect(sql, contains('DEVICE_NAME TEXT NOT NULL'));
  expect(sql, isNot(contains('DEVICE_NAME TEXT NOT NULL UNIQUE')));

  final indexes = await db.rawQuery(
    "PRAGMA index_list('whitelistedDevices')",
  );
  expect(indexes, isEmpty);
}

List<Map<String, Object?>> _rows() => [
      _row(1, 'Phone A', 'device-a', 'a@example.com', 11),
      _row(2, 'Phone B', 'device-b', 'b@example.com', 22),
      _row(3, 'Phone C', 'device-c', 'c@example.com', 33),
    ];

Map<String, Object?> _row(
  int id,
  String deviceName,
  String deviceId,
  String ownerEmail,
  int userId,
) =>
    {
      'id': id,
      'device_name': deviceName,
      'device_id': deviceId,
      'owner_email': ownerEmail,
      'user_id': userId,
    };
