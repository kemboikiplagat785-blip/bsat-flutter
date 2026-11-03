// My Offers: search, sort and the dragged order; a signature shared by offers
// dialing the same code; and Pata More's amounts. Synthetic data only.
import 'package:bsat/models/code_signature.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:bsat/utils/offer_list_order.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/stage0_harness.dart';

Map<String, dynamic> _offer(
  int id,
  int amount, {
  String name = '',
  String code = '*1#',
  int enabled = 1,
}) =>
    {
      'id': id,
      'amount': amount,
      'offerName': name,
      'code': code,
      'enabled': enabled,
    };

void main() {
  group('sorting offers', () {
    final rows = [
      _offer(1, 50, name: 'Bravo'),
      _offer(2, 20, name: 'charlie', enabled: 0),
      _offer(3, 99, name: 'Alpha'),
    ];
    List<Object?> ids(OfferSort sort, [List<int> order = const []]) =>
        sortOfferRows(rows, sort, order).map((row) => row['id']).toList();

    test('by amount, by name and with paused offers last', () {
      expect(ids(OfferSort.amountAscending), [2, 1, 3]);
      expect(ids(OfferSort.amountDescending), [3, 1, 2]);
      expect(ids(OfferSort.name), [3, 1, 2]);
      expect(ids(OfferSort.pausedLast), [1, 3, 2]);
    });

    test('in the dragged order, with offers added since then last', () {
      expect(ids(OfferSort.custom, [3, 2]), [3, 2, 1]);
    });

    test('an unknown stored sort falls back to the amount', () {
      expect(OfferSort.fromName('nonsense'), OfferSort.amountAscending);
      expect(OfferSort.fromName('custom'), OfferSort.custom);
    });
  });

  test('search looks at the amount, name and code', () {
    final row = _offer(1, 50, name: 'Daily Data', code: '*180*5#');
    expect(offerRowMatches(row, ''), isTrue);
    expect(offerRowMatches(row, '50'), isTrue);
    expect(offerRowMatches(row, 'daily'), isTrue);
    expect(offerRowMatches(row, '*180'), isTrue);
    expect(offerRowMatches(row, 'weekly'), isFalse);
  });

  group('database', () {
    final h = Stage0Harness();
    const code = '*544*6*n*1#';
    const dialed = '*544*6*0722000111*1#';
    final procedure = [
      {'options': '1:Bundles', 'choice': '6'},
      {'options': 'Enter number', 'choice': 'n'},
      {'options': '1:Buy', 'choice': '1'},
    ];

    setUpAll(Stage0Harness.setUpAllOnce);
    tearDownAll(Stage0Harness.tearDownAllOnce);
    setUp(() => h.setUp());
    tearDown(h.tearDown);

    Future<int> offer(int amount, {String variantCode = code}) async {
      final db = await h.db;
      final id = await db.insert('ussdCodes', {
        'amount': amount,
        'fromSim': -1,
        'dialSim': 1,
        'canRetry': 1,
        'isAdvanced': 1,
        'enabled': 1,
      });
      await db.insert(
          'ussdCodeVariants', {'ussdCodeId': id, 'code': variantCode});
      return id;
    }

    Future<int> recordedSignature(int offerId) async {
      return SQLiteService().insertStuff(
        CodeSignature(
          ussdCodeId: offerId,
          usdCode: code,
          acceptedProcedure: procedure,
          isActive: true,
          autoSwitch: true,
        ).sqlSavableForm(),
        'codeSignature',
      );
    }

    test('an offer without a recording uses the one for the same code',
        () async {
      final twenty = await offer(20);
      final twentyThree = await offer(23);
      await recordedSignature(twenty);
      // What saving an offer stores before anything is recorded.
      await SQLiteService().insertStuff(
        CodeSignature(ussdCodeId: twentyThree, usdCode: code, isActive: false)
            .sqlSavableForm(),
        'codeSignature',
      );

      final signature =
          await SQLiteService().codeSignatureFor(twentyThree, dialed);

      expect(signature!.isUsableFor(dialed), isTrue);
      expect(signature.isActive, isTrue);
    });

    test('another code never gets it, nor does a deleted offer pass it on',
        () async {
      final twenty = await offer(20);
      final other = await offer(30, variantCode: '*544*7*n*1#');
      await recordedSignature(twenty);

      expect(
        await SQLiteService().codeSignatureFor(other, '*544*7*0722000111*1#'),
        isNull,
      );

      await SQLiteService().deleteStuff(twenty, 'ussdCodes');
      final twentyThree = await offer(23);
      expect(await SQLiteService().codeSignatureFor(twentyThree, dialed), isNull);
    });

    test('saving shares a recording with every offer dialing that code',
        () async {
      final twenty = await offer(20);
      final twentyThree = await offer(23);
      final twentyFour = await offer(24);
      final other = await offer(30, variantCode: '*544*7*n*1#');
      await SQLiteService().insertStuff(
        CodeSignature(ussdCodeId: twentyThree, usdCode: code, isActive: false)
            .sqlSavableForm(),
        'codeSignature',
      );

      await SQLiteService().shareCodeSignature(CodeSignature(
        id: await recordedSignature(twenty),
        ussdCodeId: twenty,
        usdCode: code,
        acceptedProcedure: procedure,
        isActive: true,
      ));

      for (final id in [twentyThree, twentyFour]) {
        final rows = await SQLiteService()
            .queryCustom('codeSignature', 'ussdCodeId = ?', [id]);
        expect(rows, hasLength(1), reason: 'no second row for offer $id');
        final signature = CodeSignature.fromMap(rows.single);
        expect(signature.isUsableFor(dialed), isTrue);
        expect(signature.isActive, isTrue);
      }
      expect(
        await SQLiteService().queryCustom(
            'codeSignature', 'ussdCodeId = ?', [other]),
        isEmpty,
      );
    });

    test('an unrecorded signature overwrites nothing', () async {
      final twenty = await offer(20);
      final twentyThree = await offer(23);
      await recordedSignature(twentyThree);

      await SQLiteService().shareCodeSignature(
          CodeSignature(ussdCodeId: twenty, usdCode: code));

      final signature =
          await SQLiteService().codeSignatureFor(twentyThree, dialed);
      expect(signature!.isRecorded, isTrue);
    });

    test('Pata More lists the amounts of the date with their counts', () async {
      final db = await h.db;
      Future<void> row(int amount, String status, String date) => db.insert(
            'transactions',
            {'amount': amount, 'status': status, 'date': date},
          );
      await row(55, TransactionStatuses.pataMore, '2026-11-03');
      await row(20, TransactionStatuses.pataMore, '2026-11-03');
      await row(20, TransactionStatuses.pataMore, '2026-11-03');
      await row(99, TransactionStatuses.pataMore, '2026-11-02');
      await row(21, TransactionStatuses.error, '2026-11-03');

      final amounts = await SQLiteService().pataMoreAmounts('2026-11-03');

      expect(amounts, [(amount: 20, count: 2), (amount: 55, count: 1)]);
    });
  });
}
