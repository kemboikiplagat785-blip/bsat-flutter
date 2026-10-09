import 'package:bsat/models/transaction.dart';
import 'package:bsat/utils/logger.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class SQLiteService {
  static Database? _database;
  static final BsatLogger _logger = BsatLogger(tag: 'SQLiteService');

  Future<Database> get database async {
    if (_database != null && _database!.isOpen) {
      return _database!;
    }
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'bsat_app.db');
    final db = await openDatabase(
      path,
      version: 18,
      onCreate: onCreate,
      onUpgrade: onUpgrade,
      singleInstance: true,
    );
    // Unconditional safety net: some devices' schema history predates or
    // fell through gaps in the onCreate/onUpgrade version-transition logic
    // (e.g. installs that have been incrementally upgraded since long before
    // ussdCodeVariants/offerName existed). Ensure these are present on every
    // app start, independent of what version transition (if any) just ran.
    await _ensureCriticalSchema(db);
    await backfillOrphanedUssdCodeVariants(db);
    return db;
  }

  Future<void> _ensureCriticalSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS forwardingConfirmations (
        forwardingJobId TEXT PRIMARY KEY,
        recipientDeviceName TEXT NOT NULL,
        transactionId TEXT,
        attempt INTEGER NOT NULL DEFAULT 0,
        nextAttemptAt INTEGER NOT NULL DEFAULT 0,
        resultStatus TEXT NOT NULL DEFAULT 'transaction-confirmed',
        requiredTopUp INTEGER,
        targetAmount INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS alternativeJobs (
        forwardingJobId TEXT PRIMARY KEY,
        transactionId TEXT NOT NULL,
        localTransactionId INTEGER,
        state TEXT NOT NULL,
        ussdCode TEXT NOT NULL,
        isAdvanced INTEGER NOT NULL DEFAULT 0,
        smsMessage TEXT NOT NULL DEFAULT '',
        senderDeviceName TEXT NOT NULL DEFAULT '',
        recipientDeviceName TEXT NOT NULL DEFAULT '',
        resultStatus TEXT,
        ussdReply TEXT,
        resultDeliveryState TEXT NOT NULL DEFAULT 'none',
        resultAttempt INTEGER NOT NULL DEFAULT 0,
        resultNextAttemptAt INTEGER NOT NULL DEFAULT 0,
        executionStartedAt INTEGER,
        createdAt INTEGER NOT NULL,
        updatedAt INTEGER NOT NULL
      )
    ''');
    final alternativeJobColumns = await db.rawQuery(
      'PRAGMA table_info(alternativeJobs)',
    );
    final existingAlternativeJobColumns = alternativeJobColumns
        .map((column) => column['name']?.toString())
        .whereType<String>()
        .toSet();
    for (final definition in const <String, String>{
      'resultDeliveryState': "TEXT NOT NULL DEFAULT 'none'",
      'resultAttempt': 'INTEGER NOT NULL DEFAULT 0',
      'resultNextAttemptAt': 'INTEGER NOT NULL DEFAULT 0',
      'executionStartedAt': 'INTEGER',
    }.entries) {
      if (!existingAlternativeJobColumns.contains(definition.key)) {
        await db.execute(
          'ALTER TABLE alternativeJobs ADD COLUMN '
          '${definition.key} ${definition.value}',
        );
      }
    }
    final transactionColumns = await db.rawQuery(
      'PRAGMA table_info(transactions)',
    );
    final existingTransactionColumns = transactionColumns
        .map((column) => column['name']?.toString())
        .whereType<String>()
        .toSet();
    if (!existingTransactionColumns
        .contains('alternativeConfirmationDelivered')) {
      await db.execute(
        'ALTER TABLE transactions ADD COLUMN '
        'alternativeConfirmationDelivered INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!existingTransactionColumns.contains('alternativeQueueState')) {
      await db.execute(
        'ALTER TABLE transactions ADD COLUMN alternativeQueueState TEXT',
      );
    }
    if (!existingTransactionColumns
        .contains('alternativeRequestSenderDeviceName')) {
      await db.execute(
        'ALTER TABLE transactions ADD COLUMN '
        'alternativeRequestSenderDeviceName TEXT',
      );
    }
    await db.update(
      'transactions',
      {'alternativeQueueState': 'waiting'},
      where: 'alternativeQueueState IS NULL AND status = ? '
          'AND forwardingRecipientDeviceName IS NOT NULL '
          'AND alternativeRequestCode IS NOT NULL',
      whereArgs: ['transaction-alternative-delivery-pending'],
    );
    await db.update(
      'transactions',
      {'alternativeQueueState': 'active'},
      where: 'alternativeQueueState IS NULL AND status = ? '
          'AND forwardingRecipientDeviceName IS NOT NULL '
          'AND alternativeRequestCode IS NOT NULL',
      whereArgs: ['transaction-forwarded-pending'],
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_alternative_queue_recipient '
      'ON transactions(forwardingRecipientDeviceName, alternativeQueueState, status)',
    );
    await db.update(
      'alternativeJobs',
      {
        'resultDeliveryState': 'pending',
        'resultNextAttemptAt': 0,
      },
      where: 'resultDeliveryState = ? AND state IN (?, ?) '
          'AND resultStatus IS NOT NULL AND resultStatus != ? '
          'AND resultStatus NOT IN (?, ?) AND resultStatus != ?',
      whereArgs: [
        'none',
        'completed',
        'ambiguous',
        '',
        'successful-pending',
        'transaction-advanced-ussd',
        'unknown',
      ],
    );
    for (final column in const <String, String>{
      'resultStatus': "TEXT NOT NULL DEFAULT 'transaction-confirmed'",
      'requiredTopUp': 'INTEGER',
      'targetAmount': 'INTEGER',
    }.entries) {
      try {
        await db.query('forwardingConfirmations',
            columns: [column.key], limit: 1);
      } catch (_) {
        await db.execute(
          'ALTER TABLE forwardingConfirmations ADD COLUMN '
          '${column.key} ${column.value}',
        );
      }
    }
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS ussdCodeVariants (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          ussdCodeId INTEGER,
          code TEXT,
          startTime TEXT,
          endTime TEXT,
          alternativeUssdCode TEXT,
          runAltOn TEXT,
          altIsAdvanced INTEGER DEFAULT 0,
          altDelayMinutes INTEGER DEFAULT 0
        )
      ''');
    } catch (_) {}

    try {
      await db.execute('ALTER TABLE transactions ADD COLUMN runOn TEXT');
    } catch (_) {}

    try {
      await db.execute(
        'ALTER TABLE transactions ADD COLUMN firstFailedTimeStamp INTEGER',
      );
    } catch (_) {}

    try {
      await db.execute(
        'ALTER TABLE transactions ADD COLUMN forwardingJobId TEXT',
      );
    } catch (_) {}

    try {
      await db.execute(
        'ALTER TABLE transactions ADD COLUMN forwardingSenderDeviceName TEXT',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE transactions ADD COLUMN forwardingRecipientDeviceName TEXT',
      );
    } catch (_) {}
    for (final definition in const [
      'awaitingTopUp INTEGER NOT NULL DEFAULT 0',
      'requiredTopUp INTEGER',
      'targetAmount INTEGER',
      'targetOfferId INTEGER',
      'parentTransactionId INTEGER',
      'topUpTransactionId TEXT',
    ]) {
      try {
        await db.execute('ALTER TABLE transactions ADD COLUMN $definition');
      } catch (_) {}
    }
    try {
      await db.query('replies', columns: ['targetOfferId'], limit: 1);
    } catch (_) {
      await db.execute('ALTER TABLE replies ADD COLUMN targetOfferId INTEGER');
    }
    try {
      await db.execute(
        'ALTER TABLE transactions ADD COLUMN alternativeExecuteAt INTEGER',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE transactions ADD COLUMN alternativeRequestCode TEXT',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE transactions ADD COLUMN alternativeRequestIsAdvanced INTEGER',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE transactions ADD COLUMN alternativeDeliveryNextAttemptAt INTEGER',
      );
    } catch (_) {}
  }

  /// Idempotent, unconditional backfill: copies legacy per-offer USSD data
  /// that still lives on `ussdCodes` (code / alternativeUssdCode / runAltOn /
  /// altIsAdvanced) into `ussdCodeVariants` for any `ussdCodes` row that has
  /// zero variants. Safe to call on every DB open and on every offer-list
  /// refresh:
  ///  - the INSERT is guarded with NOT EXISTS so it only ever fills in a
  ///    ussdCodes row that currently has zero variants, and never duplicates.
  ///  - the UPDATEs only ever touch NULL/empty fields, so they can't clobber
  ///    data a user has since edited via the app.
  /// This exists because onUpgrade (which used to run this same logic) is
  /// only invoked by sqflite when storedVersion < targetVersion - devices
  /// whose stored user_version was already stamped to/past the target by an
  /// earlier build never got this migration to run. New orphan rows can also
  /// be created live by CSV import (file_service.dart) and inbound FCM
  /// offer-edit pushes (firebase_messaging_service.dart), neither of which
  /// creates a matching ussdCodeVariants row - calling this again from the
  /// offers list refresh heals those within the same running session.
  Future<void> backfillOrphanedUssdCodeVariants([Database? dbOverride]) async {
    final db = dbOverride ?? await database;

    // Devices that originated from very old installs (e.g. v4.0.53) never
    // had startTime/endTime columns on ussdCodes at all (those were added at
    // a later intermediate schema, before offers moved to ussdCodeVariants).
    // Check up front rather than try-and-catch on every call: sqflite's
    // native layer logs a failed statement's error to the platform console
    // even when the Dart side catches it, so attempting a statement we
    // already know will fail on this device would spam the device log on
    // every single app start and offers-list refresh.
    bool hasLegacyStartEndTime = false;
    bool hasLegacyCode = false;

    try {
      final columns = await db.rawQuery('PRAGMA table_info(ussdCodes)');
      final columnNames = columns.map((c) => c['name']).toSet();

      hasLegacyStartEndTime =
          columnNames.contains('startTime') && columnNames.contains('endTime');

      hasLegacyCode = columnNames.contains('code');
    } catch (_) {}

    try {
      if (hasLegacyCode && hasLegacyStartEndTime) {
        await db.execute('''
      INSERT INTO ussdCodeVariants(
        ussdCodeId,
        code,
        startTime,
        endTime
      )
      SELECT
        id,
        code,
        startTime,
        endTime
      FROM ussdCodes u
      WHERE code IS NOT NULL
        AND code != ''
        AND NOT EXISTS (
          SELECT 1
          FROM ussdCodeVariants v
          WHERE v.ussdCodeId = u.id
        )
    ''');
      } else if (hasLegacyCode) {
        await db.execute('''
      INSERT INTO ussdCodeVariants(
        ussdCodeId,
        code
      )
      SELECT
        id,
        code
      FROM ussdCodes u
      WHERE code IS NOT NULL
        AND code != ''
        AND NOT EXISTS (
          SELECT 1
          FROM ussdCodeVariants v
          WHERE v.ussdCodeId = u.id
        )
    ''');
      }
    } catch (_) {}

    try {
      await db.execute('''
        UPDATE ussdCodeVariants
        SET alternativeUssdCode = (
          SELECT alternativeUssdCode FROM ussdCodes
          WHERE ussdCodes.id = ussdCodeVariants.ussdCodeId
        )
        WHERE alternativeUssdCode IS NULL OR alternativeUssdCode = ''
      ''');
    } catch (_) {}

    try {
      await db.execute('''
        UPDATE ussdCodeVariants
        SET runAltOn = (
          SELECT runAltOn FROM ussdCodes
          WHERE ussdCodes.id = ussdCodeVariants.ussdCodeId
        )
        WHERE runAltOn IS NULL OR runAltOn = ''
      ''');
    } catch (_) {}

    try {
      await db.execute('''
        UPDATE ussdCodeVariants
        SET altIsAdvanced = COALESCE((
          SELECT altIsAdvanced FROM ussdCodes
          WHERE ussdCodes.id = ussdCodeVariants.ussdCodeId
        ), 0)
        WHERE altIsAdvanced IS NULL
      ''');
    } catch (_) {}
  }

  Future<void> onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        initialMessage TEXT,
        transactionId TEXT,
        number INTEGER,
        date TEXT,
        time TEXT,
        ussdDialed TEXT,
        ussdReply TEXT,
        amount INTEGER,
        smsDate TEXT,
        smsTime TEXT,
        status TEXT,
        simSubId INTEGER,
        source TEXT,
        timeStamp INTEGER,
        canRetry INTEGER,
        firstFailedTimeStamp INTEGER,
        forwardingJobId TEXT,
        forwardingSenderDeviceName TEXT,
        forwardingRecipientDeviceName TEXT,
        alternativeExecuteAt INTEGER,
        alternativeRequestCode TEXT,
        alternativeRequestIsAdvanced INTEGER,
        alternativeDeliveryNextAttemptAt INTEGER,
        alternativeConfirmationDelivered INTEGER NOT NULL DEFAULT 0,
        awaitingTopUp INTEGER NOT NULL DEFAULT 0,
        requiredTopUp INTEGER,
        targetAmount INTEGER,
        targetOfferId INTEGER,
        parentTransactionId INTEGER,
        topUpTransactionId TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE ussdCodes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        amount INTEGER,
        fromSim INTEGER,
        dialSim INTEGER,
        canRetry INTEGER,
        isAdvanced INTEGER,
        enabled INTEGER,
        usesBongaPoints INTEGER DEFAULT 0,
        fallbackCode TEXT,
        balanceCheckCode TEXT,
        bongaPointsPerTransaction INTEGER DEFAULT 0,
        offerName TEXT,
        startTime TEXT,
        endTime TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ussdCodeVariants (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ussdCodeId INTEGER,
        code TEXT,
        startTime TEXT,
        endTime TEXT,
        alternativeUssdCode TEXT,
        runAltOn TEXT,
        altIsAdvanced INTEGER DEFAULT 0,
        altDelayMinutes INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE tasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT,
        taskName TEXT,
        taskAmount INTEGER,
        dialSim INTEGER,
        duration INTEGER,
        startDate INTEGER,
        timeOfDay TEXT,
        nextTaskDate INTEGER,
        offer TEXT,
        amount INTEGER,
        number INTEGER,
        deleteAfterRunning INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE replies (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        condition INTEGER,
        conditionAmount INTEGER,
        dialSim INTEGER,
        reply TEXT,
        amounts TEXT,
        targetOfferId INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        till INTEGER,
        sim INTEGER,
        plan_id INTEGER DEFAULT -1,
        amount INTEGER DEFAULT 0,
        payment_date INTEGER DEFAULT 0,
        type TEXT DEFAULT 'subscription',
        token_count INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE blacklist (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        number INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS forwarded (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        dialSim INTEGER,
        numberToReceive INTEGER,
        amounts TEXT,
        isActive INTEGER DEFAULT 1,
        simSlot INTEGER DEFAULT 1,
        paused INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS processText (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        number INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS clients (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        firstName TEXT NOT NULL,
        lastName TEXT NOT NULL,
        phoneNumber TEXT NOT NULL UNIQUE,
        alternativePhoneNumber TEXT,
        createdAt INTEGER NOT NULL,
        lastBought INTEGER,
        noOfPurchases INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS whitelistedDevices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device_name TEXT NOT NULL,
        device_id TEXT NOT NULL,
        owner_email TEXT NOT NULL,
        user_id INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS forwardingDevices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device_name TEXT NOT NULL UNIQUE,
        device_id TEXT NOT NULL,
        owner_email TEXT NOT NULL,
        user_id INTEGER,
        amounts_to_forward TEXT,
        paused INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS codeSignature (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ussdCodeId INTEGER,
        usdCode TEXT,
        acceptedProcedure TEXT,
        lastProcedure TEXT,
        importantSteps TEXT,
        mightBeCompromised INTEGER DEFAULT 0,
        autoSwitch INTEGER DEFAULT 0,
        isActive INTEGER DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS "custom codes" (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        pattern TEXT NOT NULL,
        transactionStatus TEXT NOT NULL,
        isCaseSensitive INTEGER DEFAULT 0
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_clients_phone ON clients(phoneNumber)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_clients_name ON clients(firstName, lastName)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_clients_last_bought ON clients(lastBought)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_clients_purchases ON clients(noOfPurchases)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_whitelisted_devices_email ON whitelistedDevices(owner_email)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_whitelisted_devices_device_id ON whitelistedDevices(device_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_whitelisted_devices_user_id ON whitelistedDevices(user_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_forwarding_devices_email ON forwardingDevices(owner_email)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_forwarding_devices_device_id ON forwardingDevices(device_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_forwarding_devices_user_id ON forwardingDevices(user_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_custom_codes_pattern ON "custom codes"(pattern)',
    );
  }

  Future<void> onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion >= newVersion) {
      return;
    }

    // sqflite wraps onUpgrade in a version-change transaction; rethrowing
    // below rolls back this rebuild and the database-version update.
    if (oldVersion < 9) {
      try {
        await _rebuildWhitelistedDevices(db);
      } catch (error, stackTrace) {
        // Report which device_name values collide before sqflite rolls the
        // transaction back, so an operator can fix the records at the source.
        // Read-only and best-effort: it must never replace the original error.
        final duplicateDeviceNames = await _safeDuplicateDeviceNames(db);
        _logger.error(
          'Failed to rebuild whitelistedDevices during database upgrade',
          {
            'error': error,
            'stackTrace': stackTrace,
            if (duplicateDeviceNames.isNotEmpty)
              'duplicateDeviceNames': duplicateDeviceNames,
          },
        );
        rethrow;
      }
    }

    // Every statement below is individually try/catch-wrapped: some devices'
    // schema history predates these tables/columns in ways this linear
    // version-gated migration doesn't fully anticipate, and one unexpected
    // failure here must never prevent the rest of onUpgrade (in particular
    // ussdCodeVariants creation further down) from still running.
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS whitelistedDevices (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          device_name TEXT NOT NULL,
          device_id TEXT NOT NULL,
          owner_email TEXT NOT NULL,
          user_id INTEGER
        )
      ''');
    } catch (_) {}

    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS clients (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          firstName TEXT NOT NULL,
          lastName TEXT NOT NULL,
          phoneNumber TEXT NOT NULL UNIQUE,
          alternativePhoneNumber TEXT,
          createdAt INTEGER NOT NULL,
          lastBought INTEGER,
          noOfPurchases INTEGER NOT NULL DEFAULT 0
        )
      ''');
    } catch (_) {}

    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS forwardingDevices (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          device_name TEXT NOT NULL UNIQUE,
          device_id TEXT NOT NULL,
          owner_email TEXT NOT NULL,
          user_id INTEGER,
          amounts_to_forward TEXT,
          paused INTEGER DEFAULT 0
        )
      ''');
    } catch (_) {}

    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS "custom codes" (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          pattern TEXT NOT NULL,
          transactionStatus TEXT NOT NULL,
          isCaseSensitive INTEGER DEFAULT 0
        )
      ''');
    } catch (_) {}

    try {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_custom_codes_pattern ON "custom codes"(pattern)',
      );
    } catch (_) {}

    try {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_clients_phone ON clients(phoneNumber)',
      );
    } catch (_) {}
    try {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_clients_name ON clients(firstName, lastName)',
      );
    } catch (_) {}
    try {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_clients_last_bought ON clients(lastBought)',
      );
    } catch (_) {}
    try {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_clients_purchases ON clients(noOfPurchases)',
      );
    } catch (_) {}
    try {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_whitelisted_devices_email ON whitelistedDevices(owner_email)',
      );
    } catch (_) {}
    try {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_whitelisted_devices_device_id ON whitelistedDevices(device_id)',
      );
    } catch (_) {}
    try {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_whitelisted_devices_user_id ON whitelistedDevices(user_id)',
      );
    } catch (_) {}
    try {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_forwarding_devices_email ON forwardingDevices(owner_email)',
      );
    } catch (_) {}
    try {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_forwarding_devices_device_id ON forwardingDevices(device_id)',
      );
    } catch (_) {}
    try {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_forwarding_devices_user_id ON forwardingDevices(user_id)',
      );
    } catch (_) {}

    try {
      await db.execute('''
      CREATE TABLE IF NOT EXISTS codeSignature (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ussdCodeId INTEGER,
        usdCode TEXT,
        acceptedProcedure TEXT,
        lastProcedure TEXT,
        importantSteps TEXT,
        mightBeCompromised INTEGER DEFAULT 0,
        autoSwitch INTEGER DEFAULT 0,
        isActive INTEGER DEFAULT 1
      )
    ''');
    } catch (_) {}

    try {
      await db.execute('''
      CREATE TABLE IF NOT EXISTS ussdCodeVariants (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ussdCodeId INTEGER,
        code TEXT,
        startTime TEXT,
        endTime TEXT,
        alternativeUssdCode TEXT,
        runAltOn TEXT,
        altIsAdvanced INTEGER DEFAULT 0
      )
    ''');
    } catch (_) {}

    try {
      await db.execute(
        'ALTER TABLE ussdCodeVariants ADD COLUMN alternativeUssdCode TEXT',
      );
    } catch (_) {}

    try {
      await db.execute('ALTER TABLE ussdCodeVariants ADD COLUMN runAltOn TEXT');
    } catch (_) {}

    try {
      await db.execute(
        'ALTER TABLE ussdCodeVariants ADD COLUMN altIsAdvanced INTEGER DEFAULT 0',
      );
    } catch (_) {}

    try {
      await db.execute(
        'ALTER TABLE ussdCodeVariants ADD COLUMN altDelayMinutes INTEGER DEFAULT 0',
      );
    } catch (_) {}

    try {
      await db.execute('ALTER TABLE ussdCodes ADD COLUMN offerName TEXT');
    } catch (_) {}

    try {
      await db.execute('ALTER TABLE transactions ADD COLUMN runOn TEXT');
    } catch (_) {}

    try {
      await db.execute(
        'ALTER TABLE transactions ADD COLUMN firstFailedTimeStamp INTEGER',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE transactions ADD COLUMN alternativeExecuteAt INTEGER',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE transactions ADD COLUMN targetOfferId INTEGER',
      );
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE replies ADD COLUMN targetOfferId INTEGER');
    } catch (_) {}

    // Legacy ussdCodes -> ussdCodeVariants data copy now lives in
    // backfillOrphanedUssdCodeVariants(), called unconditionally from
    // _initDatabase() and from the offers list refresh - it's a strict
    // superset of what used to run here (idempotent, not tied to whether
    // onUpgrade fires at all), so it's not duplicated in this callback.

    if (oldVersion < 9) {
      try {
        await db.execute(
          'ALTER TABLE ussdCodes ADD COLUMN usesBongaPoints INTEGER DEFAULT 0',
        );
      } catch (_) {}

      try {
        await db.execute('ALTER TABLE ussdCodes ADD COLUMN fallbackCode TEXT');
      } catch (_) {}

      try {
        await db.execute(
          'ALTER TABLE ussdCodes ADD COLUMN balanceCheckCode TEXT',
        );
      } catch (_) {}

      try {
        await db.execute(
          'ALTER TABLE ussdCodes ADD COLUMN bongaPointsPerTransaction INTEGER DEFAULT 0',
        );
      } catch (_) {}

      try {
        await db.execute(
          'ALTER TABLE codeSignature ADD COLUMN mightBeCompromised INTEGER DEFAULT 0',
        );
      } catch (_) {}

      try {
        await db.execute(
          'ALTER TABLE codeSignature ADD COLUMN autoSwitch INTEGER DEFAULT 0',
        );
      } catch (_) {}

      try {
        await db.execute(
          'ALTER TABLE codeSignature ADD COLUMN isActive INTEGER DEFAULT 1',
        );
      } catch (_) {}

      try {
        await db.execute(
          'ALTER TABLE payments ADD COLUMN plan_id INTEGER DEFAULT -1',
        );
      } catch (_) {}

      try {
        await db.execute(
          'ALTER TABLE payments ADD COLUMN amount INTEGER DEFAULT 0',
        );
      } catch (_) {}

      try {
        await db.execute(
          'ALTER TABLE payments ADD COLUMN payment_date INTEGER DEFAULT 0',
        );
      } catch (_) {}

      try {
        await db.execute(
          'ALTER TABLE payments ADD COLUMN type TEXT DEFAULT "Offline"',
        );
      } catch (_) {}

      try {
        await db.execute(
          'ALTER TABLE payments ADD COLUMN token_count INTEGER DEFAULT 0',
        );
      } catch (_) {}

      try {
        await db.execute(
            'ALTER TABLE forwarded ADD COLUMN paused INTEGER DEFAULT 0');
      } catch (_) {}

      try {
        await db.execute(
          'ALTER TABLE forwardingDevices ADD COLUMN paused INTEGER DEFAULT 0',
        );
      } catch (_) {}

      try {
        await db.execute(
          'ALTER TABLE clients ADD COLUMN alternativePhoneNumber TEXT',
        );
      } catch (_) {}

      try {
        await db.execute(
          'CREATE UNIQUE INDEX idx_forwarding_devices_name ON forwardingDevices(device_name)',
        );
      } catch (_) {}
    }

    if (oldVersion < 10) {
      try {
        await db.execute(
          'ALTER TABLE clients ADD COLUMN alternativePhoneNumber TEXT',
        );
      } catch (_) {}
    }
  }

  Future<void> _rebuildWhitelistedDevices(Database db) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name IN ('whitelistedDevices', 'whitelistedDevices_new')",
    );
    final tableNames =
        tables.map((row) => row['name']).whereType<String>().toSet();
    var hasOriginalTable = tableNames.contains('whitelistedDevices');
    final hasTemporaryTable = tableNames.contains('whitelistedDevices_new');

    if (hasTemporaryTable) {
      final rowCounts = await db.rawQuery(
        'SELECT COUNT(*) AS rowCount FROM whitelistedDevices_new',
      );
      final temporaryRowCount = rowCounts.single['rowCount'] as int;

      if (!hasOriginalTable) {
        await db.execute(
          'ALTER TABLE whitelistedDevices_new RENAME TO whitelistedDevices',
        );
        hasOriginalTable = true;
      } else if (temporaryRowCount == 0) {
        await db.execute('DROP TABLE whitelistedDevices_new');
      } else {
        throw StateError(
          'Cannot safely recover non-empty whitelistedDevices_new while '
          'whitelistedDevices also exists; both tables were preserved.',
        );
      }
    }

    if (!hasOriginalTable) {
      await db.execute('''
        CREATE TABLE whitelistedDevices (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          device_name TEXT NOT NULL,
          device_id TEXT NOT NULL,
          owner_email TEXT NOT NULL,
          user_id INTEGER
        )
      ''');
    }

    await db.execute('''
      CREATE TABLE whitelistedDevices_new (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device_name TEXT NOT NULL UNIQUE,
        device_id TEXT NOT NULL,
        owner_email TEXT NOT NULL,
        user_id INTEGER
      )
    ''');
    await db.execute('''
      INSERT INTO whitelistedDevices_new
        (id, device_name, device_id, owner_email, user_id)
      SELECT id, device_name, device_id, owner_email, user_id
      FROM whitelistedDevices
    ''');
    await db.execute('DROP TABLE whitelistedDevices');
    await db.execute(
      'ALTER TABLE whitelistedDevices_new RENAME TO whitelistedDevices',
    );
    await db.execute(
      'CREATE INDEX idx_whitelisted_devices_email '
      'ON whitelistedDevices(owner_email)',
    );
    await db.execute(
      'CREATE INDEX idx_whitelisted_devices_device_id '
      'ON whitelistedDevices(device_id)',
    );
    await db.execute(
      'CREATE INDEX idx_whitelisted_devices_user_id '
      'ON whitelistedDevices(user_id)',
    );
  }

  /// Returns the `whitelistedDevices.device_name` values that occur more than
  /// once, formatted as `<name> (x<count>)`, ordered by name.
  ///
  /// Read-only: rows are never deleted, merged, or rewritten here. The rebuild
  /// still fails through the normal UNIQUE constraint error so sqflite rolls
  /// the whole upgrade back; this only reports the conflicting values so the
  /// failure is actionable instead of a bare `UNIQUE constraint failed` string.
  Future<List<String>> findDuplicateDeviceNames(
    DatabaseExecutor db,
  ) async {
    final rows = await db.rawQuery(
      "SELECT device_name, COUNT(*) AS occurrences "
      'FROM whitelistedDevices '
      'GROUP BY device_name '
      'HAVING COUNT(*) > 1 '
      'ORDER BY device_name',
    );
    return rows.map((row) {
      final deviceName = row['device_name']?.toString() ?? '<null>';
      final occurrences = row['occurrences'];
      return '$deviceName (x$occurrences)';
    }).toList();
  }

  /// Best-effort wrapper for [findDuplicateDeviceNames] used from the migration
  /// failure path: the transaction may already have dropped the table, and a
  /// diagnostic failure must never mask the original migration error.
  Future<List<String>> _safeDuplicateDeviceNames(
    DatabaseExecutor db,
  ) async {
    try {
      return await findDuplicateDeviceNames(db);
    } catch (_) {
      return const <String>[];
    }
  }

  Future<int> insertStuff(Map<String, dynamic> row, String table) async {
    final db = await database;
    return db.insert(table, row);
  }

  /// Validates and atomically replaces the local whitelist cache.
  ///
  /// The backend response contract is only known to require the fields that
  /// are non-null in the current SQLite schema. Backend-only fields, including
  /// a possible `id`, are intentionally not copied into the local row.
  Future<List<Map<String, dynamic>>?> refreshWhitelistedDevices(
    dynamic responseData, {
    Database? databaseOverride,
  }) async {
    final devices = _validateWhitelistedDevicesResponse(responseData);
    if (devices == null) return null;

    final db = databaseOverride ?? await database;
    try {
      await db.transaction((txn) async {
        await replaceWhitelistedDevicesInTransaction(txn, devices);
      });
      _logger.info('Whitelisted device cache refreshed', {
        'deviceCount': devices.length,
      });
      return devices;
    } catch (error, stackTrace) {
      _logger.error('Whitelisted device cache replacement failed', {
        'deviceCount': devices.length,
        'error': error,
        'stackTrace': stackTrace,
      });
      return null;
    }
  }

  /// Replaces the whitelist rows using the caller's transaction.
  ///
  /// This method deliberately does not catch database errors. The enclosing
  /// transaction must see the error so that deletion and prior inserts roll
  /// back together.
  Future<void> replaceWhitelistedDevicesInTransaction(
    DatabaseExecutor txn,
    List<Map<String, dynamic>> devices,
  ) async {
    await txn.delete('whitelistedDevices');
    for (final device in devices) {
      await txn.insert('whitelistedDevices', device);
    }
  }

  List<Map<String, dynamic>>? _validateWhitelistedDevicesResponse(
    dynamic responseData,
  ) {
    if (responseData is! Map) {
      _logger.warn('Malformed whitelisted device response', {
        'reason': 'response data is not an object',
      });
      return null;
    }

    final rawDevices = responseData['devices'];
    if (rawDevices is! List) {
      _logger.warn('Malformed whitelisted device response', {
        'reason': 'devices is not a collection',
      });
      return null;
    }

    final devices = <Map<String, dynamic>>[];
    final names = <String>{};
    for (var index = 0; index < rawDevices.length; index++) {
      final rawDevice = rawDevices[index];
      if (rawDevice is! Map) {
        _logger.warn('Malformed whitelisted device response', {
          'reason': 'collection item is not an object',
          'index': index,
        });
        return null;
      }

      final deviceName = rawDevice['device_name'];
      final deviceId = rawDevice['device_id'];
      final ownerEmail = rawDevice['owner_email'];
      final userId = rawDevice['user_id'];
      if (deviceName is! String ||
          deviceName.isEmpty ||
          deviceId is! String ||
          deviceId.isEmpty ||
          ownerEmail is! String ||
          ownerEmail.isEmpty ||
          (userId != null && userId is! int)) {
        _logger.warn('Malformed whitelisted device response', {
          'reason': 'required field has an invalid value',
          'index': index,
        });
        return null;
      }

      if (!names.add(deviceName)) {
        _logger.warn('Duplicate whitelisted device name detected', {
          'duplicateCount': 1,
        });
        return null;
      }

      devices.add({
        'device_name': deviceName,
        'device_id': deviceId,
        'owner_email': ownerEmail,
        'user_id': userId,
      });
    }

    return devices;
  }

  Future<bool> reserveAlternativeJob(Map<String, dynamic> row) async {
    final db = await database;
    final insertedId = await db.insert(
      'alternativeJobs',
      row,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return insertedId != -1;
  }

  Future<int> deleteAlternativeJob(
    String forwardingJobId, {
    required String expectedState,
  }) async {
    final db = await database;
    return db.delete(
      'alternativeJobs',
      where: 'forwardingJobId = ? AND state = ?',
      whereArgs: [forwardingJobId, expectedState],
    );
  }

  Future<int> claimAlternativeResultDelivery({
    required String forwardingJobId,
    required int now,
    required int nextAttemptAt,
    required int attempt,
  }) async {
    final db = await database;
    return db.update(
      'alternativeJobs',
      {
        'resultAttempt': attempt,
        'resultNextAttemptAt': nextAttemptAt,
      },
      where: 'forwardingJobId = ? AND resultDeliveryState = ? '
          'AND resultNextAttemptAt <= ?',
      whereArgs: [forwardingJobId, 'pending', now],
    );
  }

  Future<Map<String, dynamic>?> claimNextAlternativeDelivery({
    required String recipientDeviceName,
    required int now,
    required int nextAttemptAt,
  }) async {
    final db = await database;
    return db.transaction<Map<String, dynamic>?>((txn) async {
      final activeRows = await txn.query(
        'transactions',
        where: 'forwardingRecipientDeviceName = ? AND '
            'alternativeRequestCode IS NOT NULL AND '
            'alternativeQueueState = ? AND status IN (?, ?, ?)',
        whereArgs: [
          recipientDeviceName,
          'active',
          'transaction-alternative-delivery-pending',
          'transaction-forwarded-pending',
          'transaction-alternative-ambiguous',
        ],
        orderBy: 'COALESCE(firstFailedTimeStamp, timeStamp) ASC, id ASC',
        limit: 1,
      );

      if (activeRows.isNotEmpty) {
        final active = Map<String, dynamic>.from(activeRows.first);
        if (active['status'] != 'transaction-alternative-delivery-pending') {
          return null;
        }

        final scheduledAt = int.tryParse(
            active['alternativeDeliveryNextAttemptAt']?.toString() ?? '');
        if (scheduledAt != null && scheduledAt > now) return null;

        final claimed = await txn.update(
          'transactions',
          {'alternativeDeliveryNextAttemptAt': nextAttemptAt},
          where: 'id = ? AND status = ? AND alternativeQueueState = ? AND '
              '(alternativeDeliveryNextAttemptAt IS NULL OR '
              'alternativeDeliveryNextAttemptAt <= ?)',
          whereArgs: [
            active['id'],
            'transaction-alternative-delivery-pending',
            'active',
            now,
          ],
        );
        if (claimed != 1) return null;
        active['alternativeDeliveryNextAttemptAt'] = nextAttemptAt;
        return active;
      }

      final waitingRows = await txn.query(
        'transactions',
        where: 'forwardingRecipientDeviceName = ? AND '
            'alternativeQueueState = ? AND status = ?',
        whereArgs: [
          recipientDeviceName,
          'waiting',
          'transaction-alternative-delivery-pending',
        ],
        orderBy: 'COALESCE(firstFailedTimeStamp, timeStamp) ASC, id ASC',
        limit: 1,
      );
      if (waitingRows.isEmpty) return null;

      final waiting = Map<String, dynamic>.from(waitingRows.first);
      final claimed = await txn.update(
        'transactions',
        {
          'alternativeQueueState': 'active',
          'alternativeDeliveryNextAttemptAt': nextAttemptAt,
        },
        where: 'id = ? AND status = ? AND alternativeQueueState = ?',
        whereArgs: [
          waiting['id'],
          'transaction-alternative-delivery-pending',
          'waiting',
        ],
      );
      if (claimed != 1) return null;
      waiting['alternativeQueueState'] = 'active';
      waiting['alternativeDeliveryNextAttemptAt'] = nextAttemptAt;
      return waiting;
    });
  }

  Future<Map<String, dynamic>?> getAlternativeJob(
    String forwardingJobId,
  ) async {
    final rows = await queryCustom(
      'alternativeJobs',
      'forwardingJobId = ?',
      [forwardingJobId],
      limit: 1,
    );
    return rows.firstOrNull;
  }

  Future<List<Map<String, dynamic>>> getAlternativeJobsByState(
    String state,
  ) async {
    return queryCustom(
      'alternativeJobs',
      'state = ?',
      [state],
    );
  }

  Future<int> updateAlternativeJob(
    String forwardingJobId,
    Map<String, dynamic> values, {
    String? expectedState,
  }) async {
    final db = await database;
    return db.update(
      'alternativeJobs',
      values,
      where: expectedState == null
          ? 'forwardingJobId = ?'
          : 'forwardingJobId = ? AND state = ?',
      whereArgs: expectedState == null
          ? [forwardingJobId]
          : [forwardingJobId, expectedState],
    );
  }

  Future<void> queueForwardingConfirmation({
    required String forwardingJobId,
    required String recipientDeviceName,
    String? transactionId,
    String resultStatus = 'transaction-confirmed',
    int? requiredTopUp,
    int? targetAmount,
  }) async {
    final db = await database;
    await db.insert(
      'forwardingConfirmations',
      {
        'forwardingJobId': forwardingJobId,
        'recipientDeviceName': recipientDeviceName,
        'transactionId': transactionId ?? '',
        'attempt': 0,
        'nextAttemptAt': 0,
        'resultStatus': resultStatus,
        'requiredTopUp': requiredTopUp,
        'targetAmount': targetAmount,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool> queueForwardingConfirmationIfAbsent({
    required String forwardingJobId,
    required String recipientDeviceName,
    String? transactionId,
    String resultStatus = 'transaction-confirmed',
    int? requiredTopUp,
    int? targetAmount,
  }) async {
    final db = await database;
    final insertedId = await db.insert(
      'forwardingConfirmations',
      {
        'forwardingJobId': forwardingJobId,
        'recipientDeviceName': recipientDeviceName,
        'transactionId': transactionId ?? '',
        'attempt': 0,
        'nextAttemptAt': 0,
        'resultStatus': resultStatus,
        'requiredTopUp': requiredTopUp,
        'targetAmount': targetAmount,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return insertedId != -1;
  }

  Future<List<Map<String, dynamic>>> dueForwardingConfirmations(
    int now,
  ) async {
    final db = await database;
    return db.query(
      'forwardingConfirmations',
      where: 'nextAttemptAt <= ?',
      whereArgs: [now],
    );
  }

  Future<void> scheduleForwardingConfirmationRetry(
    String forwardingJobId, {
    required int attempt,
    required int nextAttemptAt,
  }) async {
    final db = await database;
    await db.update(
      'forwardingConfirmations',
      {'attempt': attempt, 'nextAttemptAt': nextAttemptAt},
      where: 'forwardingJobId = ?',
      whereArgs: [forwardingJobId],
    );
  }

  Future<Map<String, dynamic>?> getForwardingConfirmation(
    String forwardingJobId,
  ) async {
    final db = await database;
    final rows = await db.query(
      'forwardingConfirmations',
      where: 'forwardingJobId = ?',
      whereArgs: [forwardingJobId],
      limit: 1,
    );
    return rows.firstOrNull;
  }

  Future<void> acknowledgeForwardingConfirmation(
    String forwardingJobId,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update(
        'transactions',
        {'alternativeConfirmationDelivered': 1},
        where: 'forwardingJobId = ? AND alternativeRequestCode IS NOT NULL',
        whereArgs: [forwardingJobId],
      );
      await txn.delete(
        'forwardingConfirmations',
        where: 'forwardingJobId = ?',
        whereArgs: [forwardingJobId],
      );
    });
  }

  Future<void> removeForwardingConfirmation(String forwardingJobId) async {
    final db = await database;
    await db.delete(
      'forwardingConfirmations',
      where: 'forwardingJobId = ?',
      whereArgs: [forwardingJobId],
    );
  }

  Future<List<Map<String, dynamic>>> queryAll(
    String table, {
    int? limit,
    String? orderBy,
    int? offset,
    String? where,
    List<Object?>? whereArgs,
    List<String>? columns,
  }) async {
    final db = await database;
    return db.query(
      table,
      limit: limit,
      orderBy: orderBy,
      offset: offset,
      where: where,
      whereArgs: whereArgs,
      columns: columns,
    );
  }

  Future<Map<String, dynamic>> queryOne(String table, int id) async {
    final db = await database;
    final response = await db.query(
      table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return response.first;
  }

  Future<int> getCount(
    String table, {
    List? args,
    String? appendQuery,
  }) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) FROM $table ${appendQuery ?? ''}',
      args,
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<Map<String, dynamic>>> queryDay(
    String table,
    String date, {
    int? limit,
    int? offset,
    String? orderBy,
  }) async {
    final db = await database;
    return db.query(
      table,
      orderBy: orderBy ?? 'id DESC',
      where: 'date = ?',
      whereArgs: [date],
      limit: limit,
      offset: offset,
    );
  }

  Future<List<MyTransaction>> getTransactions(
    DateTime start,
    DateTime end,
  ) async {
    final db = await database;
    final result = await db.query(
      'transactions',
      where: 'date || " " || time BETWEEN ? AND ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
    );
    return result.map((json) => MyTransaction.fromMap(json)).toList();
  }

  Future<List<Map<String, dynamic>>> querySearch(
    String table,
    String searchText, {
    int? limit,
    int? offset,
    String? orderBy,
  }) async {
    final db = await database;
    return db.query(
      table,
      where:
          'initialMessage LIKE ? OR number LIKE ? OR ussdReply LIKE ? OR amount LIKE ? OR transactionId LIKE ? OR status LIKE ? OR ussdDialed LIKE ?',
      whereArgs: [
        '%$searchText%',
        '%$searchText%',
        '%$searchText%',
        '%$searchText%',
        '%$searchText%',
        '%$searchText%',
        '%$searchText%',
      ],
      limit: limit,
      offset: offset,
      orderBy: orderBy,
    );
  }

  Future<List<Map<String, dynamic>>> queryCustom(
    String table,
    String query,
    List<Object> whereArgs, {
    List<String>? columns,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    final db = await database;
    return db.query(
      table,
      columns: columns,
      where: query,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }

  Future<int> updateStuff(
    Map<String, dynamic> row,
    String where,
    List whereArgs,
    String table,
  ) async {
    final db = await database;
    return db.update(table, row, where: where, whereArgs: whereArgs);
  }

  Future<void> updateOnly(String query, List<dynamic> args) async {
    final db = await database;
    await db.rawUpdate(query, args);
  }

  Future<int> deleteStuff(int id, String table) async {
    final db = await database;
    return db.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteWhere(
    String table,
    String where,
    List<dynamic> whereArgs,
  ) async {
    final db = await database;
    return db.delete(table, where: where, whereArgs: whereArgs);
  }

  Future<void> addColumnIfNotExists(
    String table,
    String column,
    String type, {
    dynamic defaultValue = 'NULL',
  }) async {
    final db = await database;
    try {
      await db.query(table, columns: [column], limit: 1);
    } catch (_) {
      await db.execute(
        'ALTER TABLE $table ADD COLUMN $column $type DEFAULT $defaultValue',
      );
    }
  }

  Future<void> clearTable(String table) async {
    final db = await database;
    await db.delete(table);
  }

  Future<List<Map<String, dynamic>>> getCountOfAmountsByDate() async {
    final db = await database;
    return db.rawQuery('''
      SELECT date, amount, COUNT(*) as count
      FROM transactions
      GROUP BY date, amount
      ORDER BY date DESC, amount ASC
    ''');
  }

  Future<List<Map<String, dynamic>>> rawQueryInput(
    String query,
    List<dynamic> args,
  ) async {
    final db = await database;
    return db.rawQuery(query, args);
  }

  Future<List<Map<String, dynamic>>> getCustomCodes() async {
    final db = await database;
    return db.rawQuery(
      'SELECT id, pattern, transactionStatus, isCaseSensitive FROM "custom codes" ORDER BY id DESC',
    );
  }

  Future<int> insertCustomCode({
    required String pattern,
    required String transactionStatus,
    bool isCaseSensitive = false,
  }) async {
    final db = await database;
    return db.rawInsert(
      'INSERT INTO "custom codes"(pattern, transactionStatus, isCaseSensitive) VALUES(?, ?, ?)',
      [pattern, transactionStatus, isCaseSensitive ? 1 : 0],
    );
  }

  Future<int> updateCustomCode(
    int id, {
    required String pattern,
    required String transactionStatus,
    bool isCaseSensitive = false,
  }) async {
    final db = await database;
    return db.rawUpdate(
      'UPDATE "custom codes" SET pattern = ?, transactionStatus = ?, isCaseSensitive = ? WHERE id = ?',
      [pattern, transactionStatus, isCaseSensitive ? 1 : 0, id],
    );
  }

  Future<int> deleteCustomCode(int id) async {
    final db = await database;
    return db.rawDelete('DELETE FROM "custom codes" WHERE id = ?', [id]);
  }
}
