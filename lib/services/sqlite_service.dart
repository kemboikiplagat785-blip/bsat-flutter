import 'package:bsat/models/transaction.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class SQLiteService {
  static Database? _database;

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
    return openDatabase(
      path,
      version: 15,
      onCreate: onCreate,
      onUpgrade: onUpgrade,
      singleInstance: true,
    );
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
        firstFailedTimeStamp INTEGER
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
        amounts TEXT
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
      CREATE TABLE IF NOT EXISTS "custom codes" (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        pattern TEXT NOT NULL,
        transactionStatus TEXT NOT NULL,
        isCaseSensitive INTEGER DEFAULT 0
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_custom_codes_pattern ON "custom codes"(pattern)',
    );

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
      await db.execute('''
        INSERT INTO ussdCodeVariants(ussdCodeId, code, startTime, endTime)
        SELECT id, code, startTime, endTime
        FROM ussdCodes
        WHERE code IS NOT NULL AND code != ''
      ''');
    } catch (_) {}

    try {
      await db.execute('''
        UPDATE ussdCodeVariants
        SET alternativeUssdCode = (
          SELECT alternativeUssdCode
          FROM ussdCodes
          WHERE ussdCodes.id = ussdCodeVariants.ussdCodeId
        )
        WHERE alternativeUssdCode IS NULL OR alternativeUssdCode = ''
      ''');
    } catch (_) {}

    try {
      await db.execute('''
        UPDATE ussdCodeVariants
        SET runAltOn = (
          SELECT runAltOn
          FROM ussdCodes
          WHERE ussdCodes.id = ussdCodeVariants.ussdCodeId
        )
        WHERE runAltOn IS NULL OR runAltOn = ''
      ''');
    } catch (_) {}

    try {
      await db.execute('''
        UPDATE ussdCodeVariants
        SET altIsAdvanced = COALESCE((
          SELECT altIsAdvanced
          FROM ussdCodes
          WHERE ussdCodes.id = ussdCodeVariants.ussdCodeId
        ), 0)
      ''');
    } catch (_) {}

    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS whitelistedDevices_new (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          device_name TEXT NOT NULL,
          device_id TEXT NOT NULL,
          owner_email TEXT NOT NULL,
          user_id INTEGER
        )
      ''');

      await db.execute('''
        INSERT INTO whitelistedDevices_new (id, device_name, device_id, owner_email, user_id)
        SELECT id, device_name, device_id, owner_email, user_id FROM whitelistedDevices
      ''');

      await db.execute('DROP TABLE IF EXISTS whitelistedDevices');
      await db.execute(
        'ALTER TABLE whitelistedDevices_new RENAME TO whitelistedDevices',
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
    }

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
        await db.execute('ALTER TABLE forwarded ADD COLUMN paused INTEGER DEFAULT 0');
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

      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS whitelistedDevices_new (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            device_name TEXT NOT NULL UNIQUE,
            device_id TEXT NOT NULL,
            owner_email TEXT NOT NULL,
            user_id INTEGER
          )
        ''');

        await db.execute('''
          INSERT INTO whitelistedDevices_new (id, device_name, device_id, owner_email, user_id)
          SELECT id, device_name, device_id, owner_email, user_id FROM whitelistedDevices
        ''');

        await db.execute('DROP TABLE IF EXISTS whitelistedDevices');
        await db.execute(
          'ALTER TABLE whitelistedDevices_new RENAME TO whitelistedDevices',
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

  Future<int> insertStuff(Map<String, dynamic> row, String table) async {
    final db = await database;
    return db.insert(table, row);
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