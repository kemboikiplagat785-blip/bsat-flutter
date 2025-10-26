import 'package:bsat/models/transaction.dart';
import 'package:bsat/utils/date_ops.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class SQLiteService {
  static Database? _database;
  static bool _isInitializing = false;

  // List<Map<String, dynamic>> initialCodes = [
  //   {'code': '*180*5*2*n*7*1#', 'amount': 99},
  //   {'code': '*180*5*2*n*8*1#', 'amount': 55},
  //   {'code': '*180*5*2*n*6*1#', 'amount': 20},
  //   {'code': '*180*5*2*n*5*1#', 'amount': 19},
  // ];

  Future<Database> get database async {
    // Prevent concurrent initialization
    if (_database != null && _database!.isOpen) return _database!;
    // Use a lock to ensure only one isolate initializes the database at a time
    return await _initializeDatabaseSafely();
  }

  Future<Database> _initializeDatabaseSafely() async {
    // Dart's Object is not a true mutex, but this pattern prevents concurrent init in Dart's single-threaded async model
    return await Future.sync(() async {
      if (_database != null) return _database!;
      _database = await _initDatabase();
      return _database!;
    });
  }

  Future<Database> _initDatabase() async {
    var databasesPath = await getDatabasesPath();
    String path = join(databasesPath, 'bsat_app.db');
    return await openDatabase(path,
        version: 3,
        onCreate: onCreate,
        onUpgrade: onUpgrade,
        singleInstance: true);
  }

  void onCreate(Database db, int version) async {
    // Create the Sales table
    // debugPrint('Creating database');
    await db.execute(
      '''CREATE TABLE transactions (
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
          canRetry INTEGER
        )''',
    );

    await db.execute(
      '''CREATE TABLE ussdCodes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT,
        amount INTEGER,
        fromSim INTEGER,
        dialSim INTEGER,
        canRetry INTEGER,
        isAdvanced INTEGER,
        enabled INTEGER,
        usesBongaPoints INTEGER DEFAULT 0,
        fallbackCode TEXT,
        balanceCheckCode TEXT,
        bongaPointsPerTransaction INTEGER DEFAULT 0
      )''',
    );

    await db.execute(
      '''CREATE TABLE tasks (
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
        )''',
    );

    await db.execute(
      // condition amount works as on/off flag
      '''CREATE TABLE replies (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          condition INTEGER,
          conditionAmount INTEGER,
          dialSim INTEGER,
          reply TEXT,
          amounts TEXT
        )''',
    );

    await db.execute(
      '''CREATE TABLE payments (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          till INTEGER,
          sim INTEGER
        )''',
    );
    await db.execute(
      '''CREATE TABLE blacklist (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          number INTEGER
        )''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS forwarded (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          dialSim INTEGER,
          numberToReceive INTEGER,
          amounts TEXT,
          isActive INTEGER DEFAULT 1,
          simSlot INTEGER DEFAULT 1
        )''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS processText (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          number INTEGER
        )''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS clients (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        firstName TEXT NOT NULL,
        lastName TEXT NOT NULL,
        phoneNumber TEXT NOT NULL UNIQUE,
        createdAt INTEGER NOT NULL,
        lastBought INTEGER,
        noOfPurchases INTEGER NOT NULL DEFAULT 0
      )''',
    );

    await db.execute(
      '''CREATE TABLE IF NOT EXISTS whitelistedDevices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device_name TEXT NOT NULL,
        device_id TEXT NOT NULL UNIQUE,
        owner_email TEXT NOT NULL,
        user_id INTEGER
      )''',
    );

    await db.execute(
      '''CREATE TABLE IF NOT EXISTS forwardingDevices (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          device_name TEXT NOT NULL,
          device_id TEXT NOT NULL UNIQUE,
          owner_email TEXT NOT NULL,
          user_id INTEGER,
          amounts_to_forward TEXT
        )''',
    );

    // Create indexes for better performance
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_clients_phone ON clients(phoneNumber)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_clients_name ON clients(firstName, lastName)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_clients_last_bought ON clients(lastBought)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_clients_purchases ON clients(noOfPurchases)');

    // Fix: Change 'devices' to 'whitelistedDevices'
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_whitelisted_devices_email ON whitelistedDevices(owner_email)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_whitelisted_devices_device_id ON whitelistedDevices(device_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_whitelisted_devices_user_id ON whitelistedDevices(user_id)');

    // Add indexes for forwardingDevices
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_forwarding_devices_email ON forwardingDevices(owner_email)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_forwarding_devices_device_id ON forwardingDevices(device_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_forwarding_devices_user_id ON forwardingDevices(user_id)');
  }

  void onUpgrade(Database db, int oldVersion, int newVersion) async {
    //print('Upgrading database from $oldVersion to $newVersion');
    if (oldVersion < newVersion) {
      await db.execute(
        '''CREATE TABLE IF NOT EXISTS whitelistedDevices (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      device_name TEXT NOT NULL,
      device_id TEXT NOT NULL UNIQUE,
      owner_email TEXT NOT NULL,
      user_id INTEGER
    )''',
      );

      await db.execute(
        '''CREATE TABLE IF NOT EXISTS clients (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          firstName TEXT NOT NULL,
          lastName TEXT NOT NULL,
          phoneNumber TEXT NOT NULL UNIQUE,
          createdAt INTEGER NOT NULL,
          lastBought INTEGER,
          noOfPurchases INTEGER NOT NULL DEFAULT 0
        )''',
      );

      await db.execute(
        '''CREATE TABLE IF NOT EXISTS forwardingDevices (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          device_name TEXT NOT NULL,
          device_id TEXT NOT NULL UNIQUE,
          owner_email TEXT NOT NULL,
          user_id INTEGER,
          amounts_to_forward TEXT
        )''',
      );

      // Create indexes for better performance
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_clients_phone ON clients(phoneNumber)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_clients_name ON clients(firstName, lastName)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_clients_last_bought ON clients(lastBought)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_clients_purchases ON clients(noOfPurchases)');

      // Fix: Change 'devices' to 'whitelistedDevices'
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_whitelisted_devices_email ON whitelistedDevices(owner_email)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_whitelisted_devices_device_id ON whitelistedDevices(device_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_whitelisted_devices_user_id ON whitelistedDevices(user_id)');

      // Add indexes for forwardingDevices
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_forwarding_devices_email ON forwardingDevices(owner_email)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_forwarding_devices_device_id ON forwardingDevices(device_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_forwarding_devices_user_id ON forwardingDevices(user_id)');
      // Add new columns to ussdCodes table
      try {
        await db.execute(
            'ALTER TABLE ussdCodes ADD COLUMN usesBongaPoints INTEGER DEFAULT 0');
      } catch (e) {
        //print('Column usesBongaPoints already exists or error: $e');
      }

      try {
        await db.execute('ALTER TABLE ussdCodes ADD COLUMN fallbackCode TEXT');
      } catch (e) {
        //print('Column fallbackCode already exists or error: $e');
      }

      try {
        await db
            .execute('ALTER TABLE ussdCodes ADD COLUMN balanceCheckCode TEXT');
      } catch (e) {
        //print('Column balanceCheckCode already exists or error: $e');
      }

      try {
        await db.execute(
            'ALTER TABLE ussdCodes ADD COLUMN bongaPointsPerTransaction INTEGER DEFAULT 0');
      } catch (e) {
        //print('Column bongaPointsPerTransaction already exists or error: $e');
      }
    }
  }

  Future<int> insertStuff(Map<String, dynamic> row, String table) async {
    Database db = await database;
    if (!db.isOpen) {
      _database = null;
      db = await database;
    }
    return await db.insert(table, row);
  }

  Future<List<Map<String, dynamic>>> queryAll(
    String table, {
    int? limit,
    String? orderBy,
    int? offset,
  }) async {
    Database db = await database;
    if (!db.isOpen) {
      _database = null;
      db = await database;
    }
    return await db.query(
      table,
      limit: limit,
      orderBy: orderBy,
      offset: offset,
    );
  }

  Future<Map<String, dynamic>> queryOne(String table, int id) async {
    Database db = await database;
    if (!db.isOpen) {
      _database = null;
      db = await database;
    }
    var response = await db.query(
      table,
      where: 'id = ?',
      whereArgs: [id],
    );

    return response.first;
  }

  Future<int> getCount(
    String table, {
    List? args,
    String? appendQuery,
  }) async {
    Database db = await database;
    if (!db.isOpen) {
      _database = null;
      db = await database;
    }
    var result = await db.rawQuery(
      'SELECT COUNT(*) FROM $table $appendQuery',
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
    Database db = await database;
    if (!db.isOpen) {
      _database = null;
      db = await database;
    }
    return await db.query(
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
    Database db = await database;
    if (!db.isOpen) {
      _database = null;
      db = await database;
    }
    final result = await db.query(
      'transactions',
      where: 'date || " " || time BETWEEN ? AND ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
    );
    return result.map((json) => MyTransaction.fromMap(json)).toList();
    // return result
  }

  Future<List<Map<String, dynamic>>> querySearch(
    String table,
    String searchText, {
    int? limit,
    int? offset,
    String? orderBy,
  }) async {
    Database db = await database;
    if (!db.isOpen) {
      _database = null;
      db = await database;
    }
    return await db.query(
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
  }) async {
    Database db = await database;

    if (!db.isOpen) {
      _database = null;
      db = await database;
    }

    // debugPrint('Executing query: $query with arguments: $whereArgs');

    return await db.query(
        columns: columns,
        table,
        where: query,
        whereArgs: whereArgs,
        orderBy: orderBy);
  }

  Future<int> updateStuff(
    Map<String, dynamic> row,
    String where,
    List whereArgs,
    String table,
  ) async {
    Database db = await database;
    if (!db.isOpen) {
      _database = null;
      db = await database;
    }
    return await db.update(table, row, where: where, whereArgs: whereArgs);
  }

  Future<void> updateOnly(String query, List<dynamic> args) async {
    Database db = await database;
    if (!db.isOpen) {
      _database = null;
      db = await database;
    }
    await db.rawQuery(query, args);
  }

  Future<int> deleteStuff(int id, String table) async {
    Database db = await database;
    if (!db.isOpen) {
      _database = null;
      db = await database;
    }
    return await db.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteWhere(
      String table, String where, List<dynamic> whereArgs) async {
    Database db = await database;
    if (!db.isOpen) {
      _database = null;
      db = await database;
    }
    return await db.delete(table, where: where, whereArgs: whereArgs);
  }

  Future<void> addColumnIfNotExists(
    String table,
    String column,
    String type, {
    dynamic defaultValue = 'NULL',
  }) async {
    Database db = await database;
    if (!db.isOpen) {
      _database = null;
      db = await database;
    }
    try {
      await db.query(table, columns: [column]);
    } catch (e) {
      await db.execute(
          'ALTER TABLE $table ADD COLUMN $column $type DEFAULT $defaultValue');
    }
  }

  Future<List<Map<String, dynamic>>> getCountOfAmountsByDate() async {
    Database db = await database;
    if (!db.isOpen) {
      _database = null;
      db = await database;
    }
    var result = await db.rawQuery('''
    SELECT date, amount, COUNT(*) as count
    FROM transactions
    GROUP BY date, amount
    ORDER BY date DESC, amount ASC
    ''');
    return result;
  }

  Future<List<Map<String, dynamic>>> rawQueryInput(
      String query, List<dynamic> args) async {
    Database db = await database;
    if (!db.isOpen) {
      _database = null;
      db = await database;
    }
    return await db.rawQuery(query, args);
  }
}
