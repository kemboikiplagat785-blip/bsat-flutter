import 'dart:math';

import 'package:bsat/models/transaction.dart';
import 'package:bsat/utils/constants.dart';
import 'package:bsat/utils/logger.dart';
import 'package:bsat/utils/forwarding_identifiers.dart';
import 'package:bsat/utils/forwarding_delivery_retry.dart';
import 'package:bsat/utils/transaction_reply.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class SQLiteService {
  static Database? _database;
  static Future<Database>? _databaseFuture;
  static final String _retryClaimOwner =
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
  static final BsatLogger _logger = BsatLogger(tag: 'SQLiteService');
  final Database? _databaseOverride;

  SQLiteService({Database? databaseOverride})
      : _databaseOverride = databaseOverride;

  Future<Database> get database async {
    if (_databaseOverride != null) return _databaseOverride;
    if (_database != null && _database!.isOpen) {
      return _database!;
    }
    final pending = _databaseFuture ??= _initDatabase();
    try {
      _database = await pending;
      return _database!;
    } catch (_) {
      if (identical(_databaseFuture, pending)) _databaseFuture = null;
      rethrow;
    }
  }

  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'bsat_app.db');
    final db = await openDatabase(
      path,
      version: 22,
      onCreate: onCreate,
      onUpgrade: onUpgrade,
      singleInstance: true,
    );
    // Unconditional safety net: some devices' schema history predates or
    // fell through gaps in the onCreate/onUpgrade version-transition logic
    // (e.g. installs that have been incrementally upgraded since long before
    // ussdCodeVariants/offerName existed). Ensure these are present on every
    // app start, independent of what version transition (if any) just ran.
    await ensureCriticalSchema(db);
    // A `claimed` retry has not crossed the durable dispatch boundary. It is
    // therefore safe to release after a process restart. `dispatching` means
    // the request may have reached the phone/Safaricom and must stay blocked.
    await recoverAbandonedTransactionRetryClaims(db);
    await backfillOrphanedUssdCodeVariants(db);
    return db;
  }

  Future<void> _addColumnIfMissing(
    DatabaseExecutor db,
    String table,
    String column,
    String definition,
  ) async {
    _validateSchemaIdentifier(table);
    _validateSchemaIdentifier(column);
    final tableRows = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
      [table],
    );
    if (tableRows.isEmpty) return;
    final columns = await db.rawQuery('PRAGMA table_info("$table")');
    if (!columns.any((row) => row['name'] == column)) {
      try {
        await db.execute(
          'ALTER TABLE "$table" ADD COLUMN "$column" $definition',
        );
      } catch (error, stackTrace) {
        _logger.error('Failed to add schema column $table.$column', {
          'error': error,
          'stackTrace': stackTrace,
        });
        rethrow;
      }
    }
  }

  static final RegExp _schemaIdentifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

  void _validateSchemaIdentifier(String value) {
    if (!_schemaIdentifier.hasMatch(value)) {
      throw ArgumentError.value(
          value, 'identifier', 'Invalid SQLite identifier');
    }
  }

  /// Adds `transactions.forwardingTransport`, the transport selected for an
  /// individual forwarding job (`online` or `lan`).
  ///
  /// Only the run that adds the column backfills it: every forwarding job
  /// that existed before (a row with a job ID or a recipient) was sent over
  /// the Internet, so it is marked `online`. Ordinary transactions stay NULL.
  /// Later opens never convert a missing value: after this migration NULL or
  /// any other value means "no usable transport" and is never sent.
  Future<void> _addForwardingJobTransportColumn(DatabaseExecutor db) async {
    final tableRows = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
      ['transactions'],
    );
    if (tableRows.isEmpty) return;
    final columns = await db.rawQuery('PRAGMA table_info("transactions")');
    if (columns.any((row) => row['name'] == 'forwardingTransport')) return;
    await db.execute(
      'ALTER TABLE "transactions" ADD COLUMN "forwardingTransport" TEXT',
    );
    await db.execute('''
      UPDATE transactions
      SET forwardingTransport = 'online'
      WHERE (forwardingJobId IS NOT NULL AND forwardingJobId != '')
         OR (forwardingRecipientDeviceName IS NOT NULL
             AND forwardingRecipientDeviceName != '')
    ''');
  }

  /// Adds `forwardedSmsJobs.transport`, the transport a received job arrived
  /// over (the receiver's replies use the same one). Existing claims all
  /// arrived over the Internet; only the run that adds the column marks them.
  Future<void> _addInboundJobTransportColumn(DatabaseExecutor db) async {
    final columns = await db.rawQuery('PRAGMA table_info("forwardedSmsJobs")');
    if (columns.isEmpty ||
        columns.any((row) => row['name'] == 'transport')) {
      return;
    }
    await db.execute(
      'ALTER TABLE "forwardedSmsJobs" ADD COLUMN "transport" TEXT',
    );
    await db.execute("UPDATE forwardedSmsJobs SET transport = 'online'");
  }

  Future<void> ensureCriticalSchema(Database db) async {
    // SQLite's write transaction serializes this repair across connections and
    // isolates. Each column check therefore observes any preceding repair.
    await db.transaction(_ensureCriticalSchema);
  }

  Future<void> _ensureCriticalSchema(DatabaseExecutor db) async {
    // Safaricom inactive-line failures held until a transaction is found for
    // them (see lib/utils/inactive_line_failure.dart).
    await db.execute('''
      CREATE TABLE IF NOT EXISTS inactiveLineFailures (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        body TEXT NOT NULL,
        smsTimestamp INTEGER NOT NULL,
        simSubId INTEGER,
        transactionRowId INTEGER,
        resolvedAt INTEGER,
        UNIQUE(smsTimestamp, body)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS forwardingDeliveryRetries (
        forwardingJobId TEXT PRIMARY KEY,
        attempt INTEGER NOT NULL DEFAULT 0,
        nextAttemptAt INTEGER NOT NULL,
        acknowledged INTEGER NOT NULL DEFAULT 0,
        lastFailure TEXT
      )
    ''');
    await _addColumnIfMissing(
        db, 'transactions', 'retryState', "TEXT NOT NULL DEFAULT 'ready'");
    await _addColumnIfMissing(db, 'transactions', 'retryStartedAt', 'INTEGER');
    await _addColumnIfMissing(db, 'transactions', 'retryClaimOwner', 'TEXT');
    // Repair legacy schema gaps on each open using SQLite metadata. The
    // transaction above serializes repair across database connections.
    for (final definition in const <String, Map<String, String>>{
      'transactions': {
        'initialMessage': 'TEXT',
        'runOn': 'TEXT',
        'firstFailedTimeStamp': 'INTEGER',
        'forwardingJobId': 'TEXT',
        'forwardingSenderDeviceName': 'TEXT',
        'forwardingRecipientDeviceName': 'TEXT',
        'awaitingTopUp': 'INTEGER NOT NULL DEFAULT 0',
        'requiredTopUp': 'INTEGER',
        'targetAmount': 'INTEGER',
        'targetOfferId': 'INTEGER',
        'parentTransactionId': 'INTEGER',
        'topUpTransactionId': 'TEXT',
        'alternativeExecuteAt': 'INTEGER',
        'alternativeRequestCode': 'TEXT',
        'alternativeRequestIsAdvanced': 'INTEGER',
        'alternativeDeliveryNextAttemptAt': 'INTEGER',
      },
      'ussdCodeVariants': {
        'alternativeUssdCode': 'TEXT',
        'runAltOn': 'TEXT',
        'altIsAdvanced': 'INTEGER DEFAULT 0',
        'altDelayMinutes': 'INTEGER DEFAULT 0',
        'altDelaySeconds': 'INTEGER',
      },
      'ussdCodes': {
        'offerName': 'TEXT',
        'usesBongaPoints': 'INTEGER DEFAULT 0',
        'fallbackCode': 'TEXT',
        'balanceCheckCode': 'TEXT',
        'bongaPointsPerTransaction': 'INTEGER DEFAULT 0',
      },
      'replies': {'targetOfferId': 'INTEGER'},
      'codeSignature': {
        'mightBeCompromised': 'INTEGER DEFAULT 0',
        'autoSwitch': 'INTEGER DEFAULT 0',
        'isActive': 'INTEGER DEFAULT 1',
      },
      'payments': {
        'plan_id': 'INTEGER DEFAULT -1',
        'amount': 'INTEGER DEFAULT 0',
        'payment_date': 'INTEGER DEFAULT 0',
        'type': "TEXT DEFAULT 'Offline'",
        'token_count': 'INTEGER DEFAULT 0',
      },
      'forwarded': {'paused': 'INTEGER DEFAULT 0'},
      'forwardingDevices': {
        'paused': 'INTEGER DEFAULT 0',
        // Per-destination forwarding transport; NULL (legacy) means online.
        'forwarding_transport': 'TEXT',
      },
      'clients': {'alternativePhoneNumber': 'TEXT'},
    }.entries) {
      for (final column in definition.value.entries) {
        await _addColumnIfMissing(db, definition.key, column.key, column.value);
      }
    }
    await _addForwardingJobTransportColumn(db);
    await db.execute('''
      INSERT OR IGNORE INTO forwardingDeliveryRetries
        (forwardingJobId, attempt, nextAttemptAt, acknowledged)
      SELECT forwardingJobId, 0, COALESCE(timeStamp, 0) + 30000, 0
      FROM transactions
      WHERE status = '${TransactionStatuses.forwardedPending}'
        AND forwardingJobId IS NOT NULL AND forwardingJobId != ''
        AND forwardingRecipientDeviceName IS NOT NULL
        AND forwardingRecipientDeviceName != ''
        AND forwardingSenderDeviceName IS NOT NULL
        AND forwardingSenderDeviceName != ''
        AND initialMessage IS NOT NULL AND initialMessage != ''
        AND COALESCE(awaitingTopUp, 0) = 0
        AND alternativeRequestCode IS NULL
        AND instr(COALESCE(ussdReply, ''), 'Receipt acknowledged by destination device') = 0
    ''');
    await db.execute('''
      UPDATE forwardingDeliveryRetries
      SET acknowledged = 1
      WHERE acknowledged = 0
        AND forwardingJobId IN (
          SELECT forwardingJobId
          FROM transactions
          WHERE status = '${TransactionStatuses.forwardedPending}'
            AND instr(
              COALESCE(ussdReply, ''),
              'Receipt acknowledged by destination device'
            ) > 0
        )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS safaricomTransactionMessages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        messageKey TEXT NOT NULL UNIQUE,
        body TEXT NOT NULL,
        smsTimestamp INTEGER NOT NULL,
        receivedAt INTEGER NOT NULL,
        resolvedAt INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tasks (
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
        offerId INTEGER,
        offerVariantId INTEGER,
        amount INTEGER,
        number INTEGER,
        deleteAfterRunning INTEGER
      )
    ''');
    final taskColumns = await db.rawQuery('PRAGMA table_info(tasks)');
    final taskColumnNames = taskColumns
        .map((column) => column['name']?.toString())
        .whereType<String>()
        .toSet();
    for (final column in const ['offerId', 'offerVariantId']) {
      if (!taskColumnNames.contains(column)) {
        await db.execute('ALTER TABLE tasks ADD COLUMN $column INTEGER');
      }
    }
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
        altDelayMinutes INTEGER DEFAULT 0,
        altDelaySeconds INTEGER
      )
    ''');
    final variantColumns = await db.rawQuery(
      'PRAGMA table_info(ussdCodeVariants)',
    );
    final variantColumnNames = variantColumns
        .map((column) => column['name']?.toString())
        .whereType<String>()
        .toSet();
    if (!variantColumnNames.contains('altDelayMinutes')) {
      await db.execute(
        'ALTER TABLE ussdCodeVariants ADD COLUMN altDelayMinutes INTEGER DEFAULT 0',
      );
    }
    if (!variantColumnNames.contains('altDelaySeconds')) {
      await db.execute(
        'ALTER TABLE ussdCodeVariants ADD COLUMN altDelaySeconds INTEGER',
      );
    }
    // NULL marks a legacy row. Once populated, it is never converted again.
    await db.execute('''
      UPDATE ussdCodeVariants
      SET altDelaySeconds = COALESCE(altDelayMinutes, 0) * 60
      WHERE altDelaySeconds IS NULL
    ''');
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
      CREATE TABLE IF NOT EXISTS incomingReceiptClaims (
        receiptCode TEXT PRIMARY KEY,
        localTransactionId INTEGER,
        state TEXT NOT NULL,
        updatedAt INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS forwardedSmsJobs (
        forwardingJobId TEXT PRIMARY KEY,
        sourceTransactionId TEXT,
        localTransactionId INTEGER,
        state TEXT NOT NULL,
        createdAt INTEGER NOT NULL,
        updatedAt INTEGER NOT NULL
      )
    ''');
    await _addInboundJobTransportColumn(db);
    // Devices paired for LAN forwarding. Identity is the pinned Ed25519
    // public key (fingerprint); device_name/device_id bind it to one BSAT
    // device. No secret is stored here: this device's private key is kept
    // wrapped by the Android Keystore in a no-backup file.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS lanPeers (
        fingerprint TEXT PRIMARY KEY,
        public_key TEXT NOT NULL,
        device_name TEXT NOT NULL,
        device_id TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL,
        paired_at INTEGER NOT NULL,
        revoked_at INTEGER,
        last_address TEXT,
        last_port INTEGER,
        last_connected_at INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS forwardingSubmissionClaims (
        forwardingJobId TEXT PRIMARY KEY,
        leaseExpiresAt INTEGER NOT NULL,
        claimToken TEXT
      )
    ''');
    await _addColumnIfMissing(
      db,
      'forwardingSubmissionClaims',
      'claimToken',
      'TEXT',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_transactions_transaction_id '
      'ON transactions(transactionId)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_forwarding_devices_name '
      'ON forwardingDevices(device_name)',
    );
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
        transport TEXT,
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
      // Transport the request arrived on; its result goes back the same
      // way. NULL (every job before LAN alternatives) is Online.
      'transport': 'TEXT',
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
          altDelayMinutes INTEGER DEFAULT 0,
          altDelaySeconds INTEGER
        )
      ''');
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
        retryState TEXT NOT NULL DEFAULT 'ready',
        retryStartedAt INTEGER,
        retryClaimOwner TEXT,
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
      CREATE TABLE IF NOT EXISTS safaricomTransactionMessages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        messageKey TEXT NOT NULL UNIQUE,
        body TEXT NOT NULL,
        smsTimestamp INTEGER NOT NULL,
        receivedAt INTEGER NOT NULL,
        resolvedAt INTEGER
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
        altDelayMinutes INTEGER DEFAULT 0,
        altDelaySeconds INTEGER
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
        offerId INTEGER,
        offerVariantId INTEGER,
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

    await _addColumnIfMissing(
        db, 'ussdCodeVariants', 'alternativeUssdCode', 'TEXT');

    await _addColumnIfMissing(db, 'ussdCodeVariants', 'runAltOn', 'TEXT');

    await _addColumnIfMissing(
        db, 'ussdCodeVariants', 'altIsAdvanced', 'INTEGER DEFAULT 0');

    await _addColumnIfMissing(
        db, 'ussdCodeVariants', 'altDelayMinutes', 'INTEGER DEFAULT 0');

    await _addColumnIfMissing(
        db, 'ussdCodeVariants', 'altDelaySeconds', 'INTEGER');

    await _addColumnIfMissing(db, 'ussdCodes', 'offerName', 'TEXT');

    await _addColumnIfMissing(db, 'transactions', 'runOn', 'TEXT');

    await _addColumnIfMissing(
        db, 'transactions', 'firstFailedTimeStamp', 'INTEGER');
    await _addColumnIfMissing(
        db, 'transactions', 'alternativeExecuteAt', 'INTEGER');
    await _addColumnIfMissing(db, 'transactions', 'targetOfferId', 'INTEGER');
    await _addColumnIfMissing(db, 'replies', 'targetOfferId', 'INTEGER');

    // Legacy ussdCodes -> ussdCodeVariants data copy now lives in
    // backfillOrphanedUssdCodeVariants(), called unconditionally from
    // _initDatabase() and from the offers list refresh - it's a strict
    // superset of what used to run here (idempotent, not tied to whether
    // onUpgrade fires at all), so it's not duplicated in this callback.

    if (oldVersion < 9) {
      await _addColumnIfMissing(
          db, 'ussdCodes', 'usesBongaPoints', 'INTEGER DEFAULT 0');

      await _addColumnIfMissing(db, 'ussdCodes', 'fallbackCode', 'TEXT');

      await _addColumnIfMissing(db, 'ussdCodes', 'balanceCheckCode', 'TEXT');

      await _addColumnIfMissing(
          db, 'ussdCodes', 'bongaPointsPerTransaction', 'INTEGER DEFAULT 0');

      await _addColumnIfMissing(
          db, 'codeSignature', 'mightBeCompromised', 'INTEGER DEFAULT 0');

      await _addColumnIfMissing(
          db, 'codeSignature', 'autoSwitch', 'INTEGER DEFAULT 0');

      await _addColumnIfMissing(
          db, 'codeSignature', 'isActive', 'INTEGER DEFAULT 1');

      await _addColumnIfMissing(
          db, 'payments', 'plan_id', 'INTEGER DEFAULT -1');

      await _addColumnIfMissing(db, 'payments', 'amount', 'INTEGER DEFAULT 0');

      await _addColumnIfMissing(
          db, 'payments', 'payment_date', 'INTEGER DEFAULT 0');

      await _addColumnIfMissing(
          db, 'payments', 'type', 'TEXT DEFAULT "Offline"');

      await _addColumnIfMissing(
          db, 'payments', 'token_count', 'INTEGER DEFAULT 0');

      await _addColumnIfMissing(db, 'forwarded', 'paused', 'INTEGER DEFAULT 0');

      await _addColumnIfMissing(
          db, 'forwardingDevices', 'paused', 'INTEGER DEFAULT 0');

      await _addColumnIfMissing(
          db, 'clients', 'alternativePhoneNumber', 'TEXT');

      try {
        await db.execute(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_forwarding_devices_name ON forwardingDevices(device_name)',
        );
      } catch (_) {}
    }

    if (oldVersion < 10) {
      await _addColumnIfMissing(
          db, 'clients', 'alternativePhoneNumber', 'TEXT');
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
    return db.insert(table, _withTransactionReply(row, table, inserting: true));
  }

  /// Every transaction keeps a reply: a missing or blank `ussdReply` written
  /// to `transactions` is replaced by a readable fallback for its status.
  static Map<String, dynamic> _withTransactionReply(
    Map<String, dynamic> row,
    String table, {
    required bool inserting,
  }) {
    if (table != 'transactions') return row;
    if (!inserting && !row.containsKey('ussdReply')) return row;
    final reply = row['ussdReply'];
    if (reply != null && reply.toString().trim().isNotEmpty) return row;
    return {
      ...row,
      'ussdReply': transactionReplyOrFallback(reply, row['status']),
    };
  }

  /// Raw `forwarding_transport` stored on the forwarding device row matching
  /// both [deviceId] and [deviceName] (unique), or null when none is stored.
  /// Throws when the row does not exist or cannot be read, so a failed read
  /// is never mistaken for a missing (legacy) preference.
  Future<Object?> getForwardingTransportPreference({
    required String deviceId,
    required String deviceName,
  }) async {
    final db = await database;
    final rows = await db.query(
      'forwardingDevices',
      where: 'device_id = ? AND device_name = ?',
      whereArgs: [deviceId, deviceName],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('Forwarding device not found');
    }
    return rows.single['forwarding_transport'];
  }

  /// Confirms that [deviceName] is a whitelisted device with no forwarding
  /// device record: exactly one `whitelistedDevices` row has this name, its
  /// ID is [deviceId], and no `forwardingDevices` row has this ID or name.
  /// Throws otherwise, so a renamed, duplicated or unidentifiable destination
  /// is never treated as whitelist-only.
  Future<void> verifyWhitelistOnlyDestination({
    required String deviceId,
    required String deviceName,
  }) async {
    if (deviceId.trim().isEmpty || deviceName.trim().isEmpty) {
      throw StateError('Whitelisted device identity is incomplete');
    }
    final db = await database;
    await db.transaction((txn) async {
      final forwarding = await txn.query(
        'forwardingDevices',
        columns: ['id'],
        where: 'device_id = ? OR device_name = ?',
        whereArgs: [deviceId, deviceName],
        limit: 1,
      );
      if (forwarding.isNotEmpty) {
        throw StateError('Device has a forwarding device record');
      }
      final whitelisted = await txn.query(
        'whitelistedDevices',
        columns: ['device_id'],
        where: 'device_name = ?',
        whereArgs: [deviceName],
      );
      if (whitelisted.length != 1 ||
          whitelisted.single['device_id']?.toString() != deviceId) {
        throw StateError('Whitelisted device is not uniquely identified');
      }
    });
  }

  /// Stores [transport] on the single forwarding device row matching both
  /// [deviceId] and [deviceName]. Returns the number of rows updated.
  Future<int> setForwardingTransportPreference({
    required String deviceId,
    required String deviceName,
    required String transport,
  }) async {
    final db = await database;
    return db.update(
      'forwardingDevices',
      {'forwarding_transport': transport},
      where: 'device_id = ? AND device_name = ?',
      whereArgs: [deviceId, deviceName],
    );
  }

  /// All LAN pairing records (trusted and revoked).
  Future<List<Map<String, dynamic>>> getLanPeers() async {
    final db = await database;
    return db.query('lanPeers', orderBy: 'device_name ASC');
  }

  Future<Map<String, dynamic>?> getLanPeer(String fingerprint) async {
    final db = await database;
    final rows = await db.query(
      'lanPeers',
      where: 'fingerprint = ?',
      whereArgs: [fingerprint],
      limit: 1,
    );
    return rows.firstOrNull;
  }

  /// Pairing records bound to [deviceName], any status.
  Future<List<Map<String, dynamic>>> getLanPeersForDevice(
    String deviceName,
  ) async {
    final db = await database;
    return db.query(
      'lanPeers',
      where: 'device_name = ?',
      whereArgs: [deviceName],
    );
  }

  /// Stores a completed pairing. A BSAT device is bound to at most one key:
  /// older records for the same device name (an earlier installation) are
  /// removed in the same transaction.
  Future<void> saveLanPeer(Map<String, dynamic> row) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'lanPeers',
        where: 'device_name = ? AND fingerprint != ?',
        whereArgs: [row['device_name'], row['fingerprint']],
      );
      await txn.insert(
        'lanPeers',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  /// Marks a pairing revoked. Every later session with that key is refused.
  Future<int> revokeLanPeer(String fingerprint, {required int revokedAt}) async {
    final db = await database;
    return db.update(
      'lanPeers',
      {'status': 'revoked', 'revoked_at': revokedAt},
      where: 'fingerprint = ?',
      whereArgs: [fingerprint],
    );
  }

  Future<int> removeLanPeer(String fingerprint) async {
    final db = await database;
    return db.delete(
      'lanPeers',
      where: 'fingerprint = ?',
      whereArgs: [fingerprint],
    );
  }

  Future<int> clearLanPeers() async {
    final db = await database;
    return db.delete('lanPeers');
  }

  /// Records an authenticated connection. The address is a routing hint only.
  Future<void> recordLanPeerConnection(
    String fingerprint, {
    required String address,
    int? port,
    required int connectedAt,
  }) async {
    final db = await database;
    await db.update(
      'lanPeers',
      {
        'last_address': address,
        if (port != null) 'last_port': port,
        'last_connected_at': connectedAt,
      },
      where: "fingerprint = ? AND status = 'trusted'",
      whereArgs: [fingerprint],
    );
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

  Future<Map<String, dynamic>> claimIncomingMpesaReceipt(
    String receiptCode,
  ) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.transaction((txn) async {
      final transactions = await txn.query(
        'transactions',
        columns: ['id'],
        where: 'transactionId = ?',
        whereArgs: [receiptCode],
        orderBy: 'id ASC',
        limit: 1,
      );
      if (transactions.isNotEmpty) {
        final transactionId =
            int.tryParse(transactions.first['id']?.toString() ?? '');
        await txn.insert(
          'incomingReceiptClaims',
          {
            'receiptCode': receiptCode,
            'localTransactionId': transactionId,
            'state': 'completed',
            'updatedAt': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        return {
          'claimed': false,
          'localTransactionId': transactionId,
          'state': 'completed',
        };
      }

      final claims = await txn.query(
        'incomingReceiptClaims',
        where: 'receiptCode = ?',
        whereArgs: [receiptCode],
        limit: 1,
      );
      if (claims.isNotEmpty) {
        return {
          'claimed': false,
          'localTransactionId': int.tryParse(
            claims.first['localTransactionId']?.toString() ?? '',
          ),
          'state': claims.first['state'],
        };
      }

      final insertedId = await txn.insert(
        'incomingReceiptClaims',
        {
          'receiptCode': receiptCode,
          'state': 'processing',
          'updatedAt': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      return {
        'claimed': insertedId != -1,
        'localTransactionId': null,
        'state': 'processing',
      };
    });
  }

  Future<void> completeIncomingMpesaReceipt(
    String receiptCode, {
    int? localTransactionId,
  }) async {
    final db = await database;
    final updated = await db.update(
      'incomingReceiptClaims',
      {
        'localTransactionId': localTransactionId,
        'state': 'completed',
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'receiptCode = ?',
      whereArgs: [receiptCode],
    );
    if (updated != 1) {
      throw StateError('No receipt claim exists for $receiptCode');
    }
  }

  Future<Map<String, dynamic>> ensureForwardingIdentity({
    required int transactionId,
    required String candidateForwardingJobId,
    required String candidateRecipientDeviceName,
    required String candidateSenderDeviceName,
    String? candidateForwardingTransport,
  }) async {
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'transactions',
        columns: [
          'id',
          'forwardingJobId',
          'forwardingRecipientDeviceName',
          'forwardingSenderDeviceName',
          'forwardingTransport',
        ],
        where: 'id = ?',
        whereArgs: [transactionId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('Transaction $transactionId does not exist');
      }
      final current = rows.first;
      final existingJobId = current['forwardingJobId']?.toString() ?? '';
      final existingRecipient =
          current['forwardingRecipientDeviceName']?.toString() ?? '';
      final existingSender =
          current['forwardingSenderDeviceName']?.toString() ?? '';
      final values = <String, dynamic>{
        if (existingJobId.isEmpty) 'forwardingJobId': candidateForwardingJobId,
        if (existingRecipient.isEmpty)
          'forwardingRecipientDeviceName': candidateRecipientDeviceName,
        if (existingSender.isEmpty)
          'forwardingSenderDeviceName': candidateSenderDeviceName,
        // The job's route is established together with its recipient. A row
        // that already has a recipient keeps its persisted transport, so an
        // existing job is never rerouted by a later preference change.
        if (existingRecipient.isEmpty && candidateForwardingTransport != null)
          'forwardingTransport': candidateForwardingTransport,
      };
      if (values.isNotEmpty) {
        await txn.update(
          'transactions',
          values,
          where: 'id = ?',
          whereArgs: [transactionId],
        );
      }
      final updatedRows = await txn.query(
        'transactions',
        columns: [
          'forwardingJobId',
          'forwardingRecipientDeviceName',
          'forwardingSenderDeviceName',
          'forwardingTransport',
        ],
        where: 'id = ?',
        whereArgs: [transactionId],
        limit: 1,
      );
      return updatedRows.single;
    });
  }

  /// [transport] is the transport the job arrived over (`online` for FCM,
  /// `lan` for an authenticated LAN session). It is recorded with the first
  /// claim only; a later delivery of the same job never changes it.
  Future<Map<String, dynamic>> claimForwardedSmsJob({
    required String forwardingJobId,
    String? sourceTransactionId,
    String transport = 'online',
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.transaction((txn) async {
      final existingClaims = await txn.query(
        'forwardedSmsJobs',
        where: 'forwardingJobId = ?',
        whereArgs: [forwardingJobId],
        limit: 1,
      );
      if (existingClaims.isNotEmpty) {
        final existingSourceTransactionId =
            existingClaims.first['sourceTransactionId']?.toString() ?? '';
        if (sourceTransactionId != null &&
            sourceTransactionId.isNotEmpty &&
            existingSourceTransactionId.isNotEmpty &&
            sourceTransactionId != existingSourceTransactionId) {
          return {
            'claimed': false,
            'localTransactionId': int.tryParse(
              existingClaims.first['localTransactionId']?.toString() ?? '',
            ),
            'sourceTransactionId': existingSourceTransactionId,
            'state': 'identifier_mismatch',
          };
        }
        return {
          'claimed': false,
          'localTransactionId': int.tryParse(
            existingClaims.first['localTransactionId']?.toString() ?? '',
          ),
          'sourceTransactionId': existingSourceTransactionId,
          'state': existingClaims.first['state'],
        };
      }

      final existingTransactions = await txn.query(
        'transactions',
        columns: ['id'],
        where: 'forwardingJobId = ?',
        whereArgs: [forwardingJobId],
        orderBy: 'id ASC',
        limit: 1,
      );
      final existingTransactionId = existingTransactions.isEmpty
          ? null
          : int.tryParse(existingTransactions.first['id']?.toString() ?? '');
      if (existingTransactionId != null) {
        await txn.insert(
          'forwardedSmsJobs',
          {
            'forwardingJobId': forwardingJobId,
            'sourceTransactionId': sourceTransactionId,
            'localTransactionId': existingTransactionId,
            'state': 'completed',
            'transport': transport,
            'createdAt': now,
            'updatedAt': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        return {
          'claimed': false,
          'localTransactionId': existingTransactionId,
          'state': 'completed',
        };
      }

      final insertedId = await txn.insert(
        'forwardedSmsJobs',
        {
          'forwardingJobId': forwardingJobId,
          'sourceTransactionId': sourceTransactionId,
          'state': 'executing',
          'transport': transport,
          'createdAt': now,
          'updatedAt': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      return {
        'claimed': insertedId != -1,
        'localTransactionId': null,
        'state': 'executing',
      };
    });
  }

  /// The transport a received job arrived over: the `transport` of its
  /// `forwardedSmsJobs` claim. Null when no claim exists (a job received
  /// before claims, or by a path without one; those arrived over the
  /// Internet). Any other stored value is returned as is.
  Future<String?> getInboundForwardingTransport(String forwardingJobId) async {
    final db = await database;
    final rows = await db.query(
      'forwardedSmsJobs',
      columns: ['transport'],
      where: 'forwardingJobId = ?',
      whereArgs: [forwardingJobId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.single['transport']?.toString() ?? '';
  }

  Future<void> completeForwardedSmsJob(
    String forwardingJobId, {
    int? localTransactionId,
  }) async {
    final db = await database;
    final updated = await db.update(
      'forwardedSmsJobs',
      {
        'localTransactionId': localTransactionId,
        'state': 'completed',
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'forwardingJobId = ?',
      whereArgs: [forwardingJobId],
    );
    if (updated != 1) {
      throw StateError('No forwarding job claim exists for $forwardingJobId');
    }
  }

  Future<int> recordForwardingReceiptAcknowledgement({
    required int transactionId,
    required String forwardingJobId,
    required String note,
  }) async {
    final db = await database;
    return db.rawUpdate(
      '''
      UPDATE transactions
      SET ussdReply = CASE
        WHEN instr(COALESCE(ussdReply, ''), ?) > 0 THEN ussdReply
        WHEN COALESCE(ussdReply, '') = '' THEN ?
        ELSE ussdReply || char(10) || '•' || char(10) || ?
      END
      WHERE id = ? AND forwardingJobId = ? AND status = ?
      ''',
      [
        note,
        note,
        note,
        transactionId,
        forwardingJobId,
        TransactionStatuses.forwardedPending,
      ],
    );
  }

  Future<bool> acknowledgeForwardingDeliveryIfMatches({
    required String forwardingJobId,
    required String transactionRowId,
    required String receivedSenderDeviceName,
    required String receivedRecipientDeviceName,
    required String localDeviceName,
  }) async {
    final transactionId = int.tryParse(transactionRowId.trim());
    if (forwardingJobId.trim().isEmpty ||
        transactionId == null ||
        transactionId <= 0) {
      return false;
    }

    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'transactions',
        where: 'id = ? AND forwardingJobId = ?',
        whereArgs: [transactionId, forwardingJobId.trim()],
        limit: 1,
      );
      if (rows.length != 1) return false;

      final transaction = rows.single;
      final persistedSender =
          transaction['forwardingSenderDeviceName']?.toString().trim() ?? '';
      if (!isMatchingForwardingReceipt(
        expectedJobId: transaction['forwardingJobId']?.toString() ?? '',
        receivedJobId: forwardingJobId,
        expectedTransactionId: transaction['id']?.toString() ?? '',
        receivedTransactionId: transactionRowId,
        expectedRecipientDeviceName:
            transaction['forwardingRecipientDeviceName']?.toString() ?? '',
        receivedSenderDeviceName: receivedSenderDeviceName,
        expectedSenderDeviceName:
            persistedSender.isEmpty ? localDeviceName : persistedSender,
        receivedRecipientDeviceName: receivedRecipientDeviceName,
      )) {
        return false;
      }

      const receiptNote = 'Receipt acknowledged by destination device';
      if (transaction['status'] == TransactionStatuses.forwardedPending ||
          transaction['status'] == TransactionStatuses.error) {
        await txn.rawUpdate(
          '''
          UPDATE transactions
          SET status = ?, ussdReply = CASE
            WHEN instr(COALESCE(ussdReply, ''), ?) > 0 THEN ussdReply
            WHEN COALESCE(ussdReply, '') = '' THEN ?
            ELSE ussdReply || char(10) || '•' || char(10) || ?
          END
          WHERE id = ? AND forwardingJobId = ? AND status IN (?, ?)
          ''',
          [
            TransactionStatuses.forwardedPending,
            receiptNote,
            receiptNote,
            receiptNote,
            transactionId,
            forwardingJobId.trim(),
            TransactionStatuses.forwardedPending,
            TransactionStatuses.error,
          ],
        );
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      await txn.insert(
        'forwardingDeliveryRetries',
        {
          'forwardingJobId': forwardingJobId.trim(),
          'attempt': 0,
          'nextAttemptAt': now,
          'acknowledged': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await txn.update(
        'forwardingDeliveryRetries',
        {'acknowledged': 1},
        where: 'forwardingJobId = ?',
        whereArgs: [forwardingJobId.trim()],
      );
      return true;
    });
  }

  Future<int> markForwardingSubmissionFailedIfUnacknowledged({
    required int transactionId,
    required String forwardingJobId,
    required String reply,
  }) async {
    final db = await database;
    return db.rawUpdate(
      '''
      UPDATE transactions
      SET status = ?, ussdReply = ?
      WHERE id = ? AND forwardingJobId = ? AND status = ?
        AND instr(
          COALESCE(ussdReply, ''),
          'Receipt acknowledged by destination device'
        ) = 0
        AND NOT EXISTS (
          SELECT 1 FROM forwardingDeliveryRetries
          WHERE forwardingJobId = ? AND acknowledged = 1
        )
      ''',
      [
        TransactionStatuses.error,
        reply,
        transactionId,
        forwardingJobId,
        TransactionStatuses.forwardedPending,
        forwardingJobId,
      ],
    );
  }

  Future<bool> claimForwardingSubmission(
    String forwardingJobId, {
    required int now,
    required int leaseExpiresAt,
    String? claimToken,
  }) async {
    final db = await database;
    final token = claimToken ??
        '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
    return db.transaction((txn) async {
      final existing = await txn.query(
        'forwardingSubmissionClaims',
        columns: ['leaseExpiresAt'],
        where: 'forwardingJobId = ?',
        whereArgs: [forwardingJobId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final expiresAt = int.tryParse(
              existing.first['leaseExpiresAt']?.toString() ?? '',
            ) ??
            0;
        if (expiresAt > now) return false;
        return await txn.update(
              'forwardingSubmissionClaims',
              {'leaseExpiresAt': leaseExpiresAt, 'claimToken': token},
              where: 'forwardingJobId = ? AND leaseExpiresAt <= ?',
              whereArgs: [forwardingJobId, now],
            ) ==
            1;
      }

      final insertedId = await txn.insert(
        'forwardingSubmissionClaims',
        {
          'forwardingJobId': forwardingJobId,
          'leaseExpiresAt': leaseExpiresAt,
          'claimToken': token,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      return insertedId != -1;
    });
  }

  Future<void> releaseForwardingSubmission(
    String forwardingJobId, {
    String? claimToken,
  }) async {
    final db = await database;
    await db.delete(
      'forwardingSubmissionClaims',
      where: claimToken == null
          ? 'forwardingJobId = ?'
          : 'forwardingJobId = ? AND claimToken = ?',
      whereArgs: claimToken == null
          ? [forwardingJobId]
          : [forwardingJobId, claimToken],
    );
  }

  Future<bool> renewForwardingSubmission(
    String forwardingJobId, {
    required String claimToken,
    required int leaseExpiresAt,
  }) async {
    final db = await database;
    return await db.update(
          'forwardingSubmissionClaims',
          {'leaseExpiresAt': leaseExpiresAt},
          where: 'forwardingJobId = ? AND claimToken = ?',
          whereArgs: [forwardingJobId, claimToken],
        ) ==
        1;
  }

  Future<void> scheduleForwardingDeliveryRetry(
    String forwardingJobId, {
    required int attempt,
    required int nextAttemptAt,
    String? lastFailure,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert(
        'forwardingDeliveryRetries',
        {
          'forwardingJobId': forwardingJobId,
          'attempt': attempt,
          'nextAttemptAt': nextAttemptAt,
          'acknowledged': 0,
          'lastFailure': lastFailure,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await txn.update(
        'forwardingDeliveryRetries',
        {
          'attempt': attempt,
          'nextAttemptAt': nextAttemptAt,
          'lastFailure': lastFailure,
        },
        where: 'forwardingJobId = ? AND acknowledged = 0',
        whereArgs: [forwardingJobId],
      );
    });
  }

  Future<List<Map<String, dynamic>>> dueForwardingDeliveryRetries(
      int now) async {
    final db = await database;
    return db.rawQuery('''
      SELECT r.*, t.id AS transactionRowId, t.initialMessage, t.transactionId,
             t.forwardingRecipientDeviceName, t.forwardingSenderDeviceName,
             t.forwardingTransport
      FROM forwardingDeliveryRetries r
      JOIN transactions t ON t.forwardingJobId = r.forwardingJobId
      WHERE r.acknowledged = 0 AND r.attempt < ?
        AND r.nextAttemptAt <= ?
        AND t.status = ? AND COALESCE(t.awaitingTopUp, 0) = 0
        AND t.alternativeRequestCode IS NULL
        AND t.initialMessage IS NOT NULL AND t.initialMessage != ''
        AND t.forwardingRecipientDeviceName IS NOT NULL
        AND t.forwardingRecipientDeviceName != ''
        AND t.forwardingSenderDeviceName IS NOT NULL
        AND t.forwardingSenderDeviceName != ''
    ''', [
      maxForwardingDeliveryRetries,
      now,
      TransactionStatuses.forwardedPending,
    ]);
  }

  /// True when the destination's receipt for [forwardingJobId] was accepted
  /// (see [acknowledgeForwardingDeliveryIfMatches]).
  Future<bool> isForwardingDeliveryAcknowledged(String forwardingJobId) async {
    final db = await database;
    final rows = await db.query(
      'forwardingDeliveryRetries',
      columns: ['acknowledged'],
      where: 'forwardingJobId = ? AND acknowledged = 1',
      whereArgs: [forwardingJobId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> acknowledgeForwardingDelivery(String forwardingJobId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert(
        'forwardingDeliveryRetries',
        {
          'forwardingJobId': forwardingJobId,
          'attempt': 0,
          'nextAttemptAt': DateTime.now().millisecondsSinceEpoch,
          'acknowledged': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await txn.update(
        'forwardingDeliveryRetries',
        {'acknowledged': 1},
        where: 'forwardingJobId = ?',
        whereArgs: [forwardingJobId],
      );
    });
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

  Future<List<Map<String, dynamic>>> getAutomaticRetryCandidates({
    required bool isAutoRetrying,
    required int retryLimit,
    required String today,
  }) async {
    return queryCustom(
      'transactions',
      '''
        (status = ?
          AND COALESCE(retryState, 'ready') NOT IN ('claimed', 'dispatching'))
        OR
        (status = ? AND date = ? AND canRetry < ?
          AND COALESCE(retryState, 'ready') = 'ready')
      ''',
      [
        TransactionStatuses.error,
        TransactionStatuses.timedOut,
        today,
        retryLimit,
      ],
      columns: [
        'id',
        'ussdDialed',
        'simSubId',
        'canRetry',
        'ussdReply',
        'amount',
        'initialMessage',
        'status',
        'retryState',
      ],
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
    return db.update(
      table,
      _withTransactionReply(row, table, inserting: false),
      where: where,
      whereArgs: whereArgs,
    );
  }

  Future<int> updateRetryTransactionIfEligible(
    int transactionId,
    Map<String, dynamic> values,
  ) async {
    final db = await database;
    return db.update(
      'transactions',
      values,
      where: '''
        id = ?
        AND status IN (?, ?, ?, ?, ?, ?, ?, ?)
        AND COALESCE(retryState, 'ready') = 'ready'
      ''',
      whereArgs: [
        transactionId,
        TransactionStatuses.error,
        TransactionStatuses.timedOut,
        TransactionStatuses.secondAttempt,
        TransactionStatuses.done,
        TransactionStatuses.advancedUssd,
        TransactionStatuses.advancedQueue,
        TransactionStatuses.paused,
        TransactionStatuses.hasOkoa,
      ],
    );
  }

  Future<int> updateTransactionUnlessSafaricomSuccess(
    int transactionId,
    Map<String, dynamic> values,
  ) async {
    final db = await database;
    return db.update(
      'transactions',
      values,
      where: '''
        id = ?
        AND status NOT IN (?, ?, ?, ?)
        AND COALESCE(retryState, 'ready') != 'dispatching'
      ''',
      whereArgs: [
        transactionId,
        TransactionStatuses.successfulPending,
        TransactionStatuses.doneConfirmed,
        TransactionStatuses.forwardedPending,
        TransactionStatuses.forwardedConfirmed,
      ],
    );
  }

  Future<bool> mergeTransactionUnlessSafaricomSuccess(
    int replacedTransactionId,
    int replacementTransactionId,
    Map<String, dynamic> replacement,
  ) async {
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'transactions',
        columns: ['status', 'retryState'],
        where: 'id = ?',
        whereArgs: [replacedTransactionId],
        limit: 1,
      );
      if (rows.isEmpty) return false;
      final status = rows.first['status']?.toString();
      final retryState = rows.first['retryState']?.toString();
      if (status == TransactionStatuses.successfulPending ||
          status == TransactionStatuses.doneConfirmed ||
          retryState == 'claimed' ||
          retryState == 'dispatching') {
        return false;
      }
      await txn.delete(
        'transactions',
        where: 'id IN (?, ?)',
        whereArgs: [replacedTransactionId, replacementTransactionId],
      );
      await txn.insert('transactions', replacement);
      return true;
    });
  }

  Future<void> recoverAbandonedTransactionRetryClaims(Database db) async {
    await db.update(
      'transactions',
      {'retryState': 'ready', 'retryClaimOwner': null},
      where: "retryState = 'claimed'",
    );
  }

  Future<int> releaseUndispatchedTransactionRetryClaim(
      int transactionId) async {
    final db = await database;
    return db.update(
      'transactions',
      {'retryState': 'ready', 'retryClaimOwner': null},
      where: 'id = ? AND retryState = ? AND retryClaimOwner = ?',
      whereArgs: [transactionId, 'claimed', _retryClaimOwner],
    );
  }

  Future<int> resetKnownUndispatchedTransactionRetry(int transactionId) async {
    final db = await database;
    return db.update(
      'transactions',
      {'retryState': 'claimed'},
      where: '''
        id = ? AND retryState = ? AND retryClaimOwner = ?
        AND status NOT IN (?, ?)
      ''',
      whereArgs: [
        transactionId,
        'dispatching',
        _retryClaimOwner,
        TransactionStatuses.successfulPending,
        TransactionStatuses.doneConfirmed,
      ],
    );
  }

  /// Makes [transactionId] retryable because the user asked to retry it
  /// manually, whatever its status or earlier outcome (the user accepts the
  /// risk of a second purchase). The row is put in the error state with a
  /// ready retry claim; its reply is kept. A forwarding job sent from this
  /// phone gets a new job on retry: its job ID is cleared, so its old
  /// delivery retries stop and the destination does not ignore the retry as
  /// a duplicate.
  ///
  /// A transaction being dialed right now (claimed, or dispatched less than
  /// [manualRetryDispatchLease] ago) is not unlocked, so one dial never
  /// overlaps another; a dispatch older than that is treated as stuck.
  /// Returns false when the row is missing or being dialed.
  Future<bool> unlockTransactionForManualRetry(int transactionId) async {
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'transactions',
        columns: ['status', 'retryState', 'retryStartedAt'],
        where: 'id = ?',
        whereArgs: [transactionId],
        limit: 1,
      );
      if (rows.isEmpty) return false;
      final retryState = rows.first['retryState']?.toString() ?? 'ready';
      final retryStartedAt =
          int.tryParse(rows.first['retryStartedAt']?.toString() ?? '') ?? 0;
      final dialingNow = retryState == 'claimed' ||
          (retryState == 'dispatching' &&
              DateTime.now().millisecondsSinceEpoch - retryStartedAt <
                  manualRetryDispatchLease.inMilliseconds);
      if (dialingNow) return false;
      final status = rows.first['status']?.toString() ?? '';
      const outgoingForwardStatuses = {
        TransactionStatuses.forwarded,
        TransactionStatuses.forwardedPending,
        TransactionStatuses.forwardedConfirmed,
        TransactionStatuses.forwardedOnline,
      };
      return await txn.update(
            'transactions',
            {
              'status': TransactionStatuses.error,
              'retryState': 'ready',
              'retryClaimOwner': null,
              if (outgoingForwardStatuses.contains(status))
                'forwardingJobId': null,
            },
            where: 'id = ?',
            whereArgs: [transactionId],
          ) ==
          1;
    });
  }

  /// How long a dispatched retry counts as still dialing; see
  /// [unlockTransactionForManualRetry].
  static const Duration manualRetryDispatchLease = Duration(minutes: 3);

  /// Atomically reserves a retry dispatch for one transaction. A stale queue
  /// item cannot claim a transaction after success evidence has changed it to
  /// pending or confirmed, and concurrent workers can claim only once.
  Future<int> claimTransactionRetry(int transactionId) async {
    final result = await claimTransactionRetryWithReason(transactionId);
    return result['claimed'] as int;
  }

  Future<Map<String, Object?>> claimTransactionRetryWithReason(
    int transactionId,
  ) async {
    final db = await database;
    final result = await db.transaction<Map<String, Object?>>((txn) async {
      final claimed = await txn.update(
        'transactions',
        {'retryState': 'claimed', 'retryClaimOwner': _retryClaimOwner},
        where: '''
          id = ?
          AND (
            (status = ?
              AND COALESCE(retryState, 'ready') NOT IN ('claimed', 'dispatching'))
            OR
            (status IN (?, ?, ?, ?, ?, ?, ?)
              AND COALESCE(retryState, 'ready') = 'ready')
          )
        ''',
        whereArgs: [
          transactionId,
          TransactionStatuses.error,
          TransactionStatuses.timedOut,
          TransactionStatuses.secondAttempt,
          TransactionStatuses.done,
          TransactionStatuses.advancedUssd,
          TransactionStatuses.advancedQueue,
          TransactionStatuses.paused,
          TransactionStatuses.hasOkoa,
        ],
      );
      if (claimed != 1) {
        final rows = await txn.query(
          'transactions',
          columns: ['status', 'retryState', 'retryClaimOwner'],
          where: 'id = ?',
          whereArgs: [transactionId],
          limit: 1,
        );
        if (rows.isEmpty) {
          return {'claimed': 0, 'reason': 'transaction missing'};
        }
        final row = rows.first;
        final status = row['status']?.toString() ?? '';
        final state = row['retryState']?.toString() ?? 'ready';
        final reason = switch (status) {
          TransactionStatuses.successfulPending => 'pending confirmation',
          TransactionStatuses.doneConfirmed => 'confirmed',
          _ when state == 'claimed' => 'another worker owns the claim',
          _ when state == 'dispatching' => 'another worker is dispatching',
          _ when state == 'ambiguous' =>
            'previous dispatch has an ambiguous outcome',
          _ when state == 'blocked' => 'retry is blocked',
          _ when state != 'ready' => 'invalid retry state',
          _ => 'invalid transaction status',
        };
        return {
          'claimed': 0,
          'reason': reason,
          'status': status,
          'retryState': state,
        };
      }

      return {'claimed': 1};
    });
    if (result['claimed'] != 1) {
      _logger.warn('Retry claim rejected', {
        'transactionId': transactionId,
        ...result,
      });
    }
    return result;
  }

  /// Marks the point after which a phone request may have been dispatched.
  /// The durable state remains non-retryable if the process dies from here on.
  Future<int> beginTransactionRetryDispatch(int transactionId) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'transactions',
        columns: ['status', 'retryStartedAt', 'retryClaimOwner'],
        where: 'id = ? AND retryState = ? AND retryClaimOwner = ?',
        whereArgs: [transactionId, 'claimed', _retryClaimOwner],
        limit: 1,
      );
      if (rows.isEmpty) return 0;
      final row = rows.first;
      final status = row['status']?.toString() ?? '';
      final previousRetryStartedAt =
          int.tryParse(row['retryStartedAt']?.toString() ?? '');
      const eligibleStatuses = {
        TransactionStatuses.error,
        TransactionStatuses.timedOut,
        TransactionStatuses.secondAttempt,
        TransactionStatuses.done,
        TransactionStatuses.advancedUssd,
        TransactionStatuses.advancedQueue,
        TransactionStatuses.paused,
        TransactionStatuses.hasOkoa,
      };
      if (!eligibleStatuses.contains(status)) return 0;

      return txn.update(
        'transactions',
        {
          'retryState': 'dispatching',
          'retryStartedAt':
              previousRetryStartedAt != null && now <= previousRetryStartedAt
                  ? previousRetryStartedAt + 1
                  : now,
        },
        where:
            'id = ? AND status = ? AND retryState = ? AND retryClaimOwner = ?',
        whereArgs: [transactionId, status, 'claimed', _retryClaimOwner],
      );
    });
  }

  Future<int> finishTransactionRetryClaim(
    int transactionId, {
    bool ambiguousOutcome = false,
    bool retryableOutcome = false,
  }) async {
    final db = await database;
    return db.update(
      'transactions',
      {
        'retryState': ambiguousOutcome
            ? 'ambiguous'
            : retryableOutcome
                ? 'ready'
                : 'blocked',
        'retryClaimOwner': null,
      },
      where: 'id = ? AND retryState = ? AND retryClaimOwner = ?',
      whereArgs: [transactionId, 'dispatching', _retryClaimOwner],
    );
  }

  String _safaricomMessageKey(String body, int smsTimestamp) =>
      '$smsTimestamp:${body.trim().toLowerCase()}';

  Future<void> recordUnresolvedSafaricomMessage({
    required String body,
    required int smsTimestamp,
  }) async {
    final db = await database;
    await db.insert(
      'safaricomTransactionMessages',
      {
        'messageKey': _safaricomMessageKey(body, smsTimestamp),
        'body': body,
        'smsTimestamp': smsTimestamp,
        'receivedAt': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<Map<String, dynamic>>> getUnresolvedSafaricomMessages() async {
    final db = await database;
    return db.query(
      'safaricomTransactionMessages',
      where: 'resolvedAt IS NULL',
      orderBy: 'receivedAt ASC, id ASC',
    );
  }

  Future<void> resolveSafaricomMessage({
    required String body,
    required int smsTimestamp,
  }) async {
    final db = await database;
    await db.update(
      'safaricomTransactionMessages',
      {'resolvedAt': DateTime.now().millisecondsSinceEpoch},
      where: 'messageKey = ?',
      whereArgs: [_safaricomMessageKey(body, smsTimestamp)],
    );
  }

  /// Reconciles Safaricom evidence without allowing a weaker submission event
  /// to downgrade confirmed success. Retry invalidation is committed in the
  /// same SQLite transaction as the status change.
  /// Holds an inactive-line failure SMS; the same SMS seen twice is kept
  /// once.
  Future<void> recordInactiveLineFailure({
    required String body,
    required int smsTimestamp,
    int? simSubId,
  }) async {
    final db = await database;
    await db.insert(
      'inactiveLineFailures',
      {
        'body': body,
        'smsTimestamp': smsTimestamp,
        'simSubId': simSubId,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Failures not yet given to a transaction, received after [since],
  /// oldest first.
  Future<List<Map<String, dynamic>>> unassignedInactiveLineFailures({
    required int since,
  }) async {
    final db = await database;
    return db.query(
      'inactiveLineFailures',
      where: 'transactionRowId IS NULL AND smsTimestamp >= ?',
      whereArgs: [since],
      orderBy: 'smsTimestamp ASC',
    );
  }

  /// Gives failure [failureId] to transaction [transactionId] and moves that
  /// transaction from Successful(Pending) to Okoa, with the SMS added to its
  /// reply. Both happen or neither (false: the failure was taken, or the
  /// transaction is no longer pending).
  Future<bool> assignInactiveLineFailure({
    required int failureId,
    required int transactionId,
  }) async {
    final db = await database;
    return db.transaction((txn) async {
      final failures = await txn.query(
        'inactiveLineFailures',
        columns: ['body'],
        where: 'id = ? AND transactionRowId IS NULL',
        whereArgs: [failureId],
        limit: 1,
      );
      final rows = await txn.query(
        'transactions',
        columns: ['ussdReply'],
        where: 'id = ? AND status = ?',
        whereArgs: [transactionId, TransactionStatuses.successfulPending],
        limit: 1,
      );
      if (failures.isEmpty || rows.isEmpty) return false;
      final body = failures.single['body']?.toString().trim() ?? '';
      final previousReply = rows.single['ussdReply']?.toString() ?? '';
      await txn.update(
        'transactions',
        {
          'status': TransactionStatuses.hasOkoa,
          'ussdReply':
              previousReply.isEmpty ? body : '$body\n•\n$previousReply',
          'canRetry': 0,
        },
        where: 'id = ? AND status = ?',
        whereArgs: [transactionId, TransactionStatuses.successfulPending],
      );
      await txn.update(
        'inactiveLineFailures',
        {
          'transactionRowId': transactionId,
          'resolvedAt': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [failureId],
      );
      return true;
    });
  }

  /// Frees the failure given to [transactionId] (its purchase was confirmed
  /// after all), so it can be matched to another transaction. Returns the
  /// number of failures freed.
  Future<int> releaseInactiveLineFailureOf(int transactionId) async {
    final db = await database;
    return db.update(
      'inactiveLineFailures',
      {'transactionRowId': null, 'resolvedAt': null},
      where: 'transactionRowId = ?',
      whereArgs: [transactionId],
    );
  }

  Future<int> reconcileSafaricomTransaction({
    required int transactionId,
    required String targetStatus,
    required String message,
  }) async {
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'transactions',
        columns: [
          'status',
          'ussdReply',
          'firstFailedTimeStamp',
          'retryClaimOwner',
        ],
        where: 'id = ?',
        whereArgs: [transactionId],
        limit: 1,
      );
      if (rows.isEmpty) return 0;

      final currentStatus = rows.first['status']?.toString() ?? '';
      if (currentStatus == TransactionStatuses.doneConfirmed &&
          targetStatus != TransactionStatuses.doneConfirmed) {
        return 0;
      }

      final eligibleStatuses = <String>{
        TransactionStatuses.error,
        TransactionStatuses.secondAttempt,
        TransactionStatuses.timedOut,
        TransactionStatuses.done,
        TransactionStatuses.advancedUssd,
        TransactionStatuses.advancedQueue,
        TransactionStatuses.successfulPending,
        TransactionStatuses.alternativeExecuting,
        TransactionStatuses.doneConfirmed,
        // A confirmation proves the purchase went through, even after an
        // Okoa result (such as a misattributed inactive-line failure).
        if (targetStatus == TransactionStatuses.doneConfirmed)
          TransactionStatuses.hasOkoa,
      };
      if (!eligibleStatuses.contains(currentStatus)) return 0;

      final previousReply = rows.first['ussdReply']?.toString() ?? '';
      final alreadyRecorded =
          message.isNotEmpty && previousReply.contains(message);
      final updatedReply = message.isEmpty || alreadyRecorded
          ? previousReply
          : previousReply.isEmpty
              ? message
              : '$message\n•\n$previousReply';
      final invalidatesRetry =
          targetStatus == TransactionStatuses.successfulPending ||
              targetStatus == TransactionStatuses.doneConfirmed;

      return txn.update(
        'transactions',
        {
          'status': targetStatus,
          if (invalidatesRetry) 'canRetry': 0,
          if (invalidatesRetry) 'retryState': 'blocked',
          if (invalidatesRetry) 'retryClaimOwner': null,
          if (targetStatus == TransactionStatuses.secondAttempt)
            'firstFailedTimeStamp': rows.first['firstFailedTimeStamp'] ??
                DateTime.now().millisecondsSinceEpoch,
          'ussdReply': transactionReplyOrFallback(updatedReply, targetStatus),
        },
        where: 'id = ? AND status = ?',
        whereArgs: [transactionId, currentStatus],
      );
    });
  }

  /// Persists the result of a retry while preserving stronger Safaricom
  /// evidence that may have arrived during the external USSD call.
  Future<Map<String, dynamic>?> completeTransactionRetry({
    required int transactionId,
    required String resultStatus,
    required String reply,
    required Map<String, dynamic> fields,
    bool ambiguousOutcome = false,
  }) async {
    final db = await database;
    final completion = await db.transaction<Map<String, dynamic>?>((txn) async {
      final rows = await txn.query(
        'transactions',
        columns: ['status', 'ussdReply', 'retryState', 'retryClaimOwner'],
        where: 'id = ?',
        whereArgs: [transactionId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final row = rows.first;
      final currentStatus = row['status']?.toString() ?? '';
      if (row['retryState'] != 'dispatching' ||
          row['retryClaimOwner'] != _retryClaimOwner) {
        return {'status': currentStatus, 'updated': false};
      }

      final isConfirmed = currentStatus == TransactionStatuses.doneConfirmed;
      final isPending = currentStatus == TransactionStatuses.successfulPending;
      final preserveStrongerEvidence = isConfirmed ||
          (isPending && resultStatus != TransactionStatuses.doneConfirmed);
      final effectiveStatus = isConfirmed
          ? TransactionStatuses.doneConfirmed
          : isPending && preserveStrongerEvidence
              ? TransactionStatuses.successfulPending
              : resultStatus;
      final currentReply = row['ussdReply']?.toString() ?? '';
      final replyAlreadyRecorded =
          reply.isNotEmpty && currentReply.contains(reply);
      final effectiveReply = isConfirmed || isPending
          ? (reply.isEmpty || replyAlreadyRecorded
              ? currentReply
              : currentReply.isEmpty
                  ? reply
                  : '$currentReply\n•\n$reply')
          : reply;
      final isTerminal = preserveStrongerEvidence ||
          effectiveStatus == TransactionStatuses.doneConfirmed ||
          effectiveStatus == TransactionStatuses.successfulPending ||
          effectiveStatus == TransactionStatuses.done;
      final nextRetryState = isTerminal
          ? 'blocked'
          : effectiveStatus == TransactionStatuses.error || !ambiguousOutcome
              ? 'ready'
              : 'ambiguous';

      final updated = await txn.update(
        'transactions',
        {
          ...fields,
          'status': effectiveStatus,
          'ussdReply':
              transactionReplyOrFallback(effectiveReply, effectiveStatus),
          if (effectiveStatus == TransactionStatuses.doneConfirmed ||
              effectiveStatus == TransactionStatuses.successfulPending)
            'canRetry': 0,
          'retryState': nextRetryState,
          'retryClaimOwner': null,
        },
        where:
            'id = ? AND retryState = ? AND status = ? AND retryClaimOwner = ?',
        whereArgs: [
          transactionId,
          'dispatching',
          currentStatus,
          _retryClaimOwner,
        ],
      );
      return {
        'status': effectiveStatus,
        'updated': updated == 1,
        'retryState': nextRetryState,
      };
    });
    if (completion?['updated'] == true &&
        completion?['retryState'] == 'ambiguous') {
      _logger.warn('Retry remains blocked pending independent confirmation', {
        'transactionId': transactionId,
        'status': completion?['status'],
        'retryState': 'ambiguous',
        'reason': 'The phone request may have been dispatched.',
      });
    }
    return completion;
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
