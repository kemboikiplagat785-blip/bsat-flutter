import 'package:bsat/services/sqlite_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late SQLiteService service;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    service = SQLiteService(databaseOverride: db);
  });

  tearDown(() => db.close());

  test('a reply is claimed once per transaction, category and number',
      () async {
    expect(await service.claimCustomerReply('SJK1ABCD23|done|712345678'),
        isTrue);
    expect(await service.claimCustomerReply('SJK1ABCD23|done|712345678'),
        isFalse);
  });

  test('a second purchase or another category gets its own reply', () async {
    expect(await service.claimCustomerReply('SJK1ABCD23|done|712345678'),
        isTrue);
    // Same customer, same amount, later the same day: a new M-Pesa code.
    expect(await service.claimCustomerReply('SJK2EFGH45|done|712345678'),
        isTrue);
    // The same transaction moving on to another category.
    expect(
        await service.claimCustomerReply(
            'SJK1ABCD23|transaction-confirmed|712345678'),
        isTrue);
  });

  test('a released claim (failed SMS) can be sent again', () async {
    const key = 'SJK1ABCD23|done|712345678';
    expect(await service.claimCustomerReply(key), isTrue);
    await service.releaseCustomerReply(key);
    expect(await service.claimCustomerReply(key), isTrue);
  });
}
