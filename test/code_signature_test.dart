import 'package:bsat/models/code_signature.dart';
import 'package:bsat/utils/constants.dart';
import 'package:bsat/utils/transaction_categories.dart';
import 'package:bsat/utils/transaction_execution_safety.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const code = '*544*6*8*n*00*1*0*1*1#';
  const dialed = '*544*6*8*0722000111*00*1*0*1*1#';

  List<Map<String, String>> procedure(int steps) => List.generate(
        steps,
        (i) => {'options': '1:Step $i\n2:Other', 'choice': '1'},
      );

  group('one signature per code', () {
    final signature = CodeSignature(
      usdCode: code,
      acceptedProcedure: procedure(8),
    );

    test('applies to its own code with any customer number', () {
      expect(signature.isUsableFor(dialed), isTrue);
      expect(signature.isUsableFor(code), isTrue);
    });

    test('does not apply to another code', () {
      expect(signature.matchesCode('*544*6*9*0722000111*00*1*0*1*1#'), isFalse);
      expect(signature.matchesCode('*544*6*8*0722000111*00*1#'), isFalse);
      expect(signature.matchesCode('*544*6*8*123*00*1*0*1*1#'), isFalse);
    });

    test('a partial recording protects nothing', () {
      final partial = signature.copyWith(acceptedProcedure: procedure(5));
      expect(partial.matchesCode(dialed), isTrue);
      expect(partial.isUsableFor(dialed), isFalse);
    });
  });

  group('storage', () {
    test('survives a database round trip', () {
      final restored = CodeSignature.fromMap(
        CodeSignature(usdCode: code, acceptedProcedure: procedure(8))
            .sqlSavableForm(),
      );
      expect(restored.acceptedProcedure, procedure(8));
    });

    test('survives the background bridge map', () {
      final restored = CodeSignature.fromMap(
        CodeSignature(usdCode: code, acceptedProcedure: procedure(8)).toMap(),
      );
      expect(restored.acceptedProcedure, procedure(8));
    });

    test('keeps mightBeCompromised', () {
      final signature = CodeSignature(usdCode: code, mightBeCompromised: true);
      expect(signature.mightBeCompromised, isTrue);
      expect(signature.sqlSavableForm()['mightBeCompromised'], 1);
    });
  });

  group('recording', () {
    test('replaces the probe number with n', () {
      final steps = CodeSignature.procedureFromRecording([
        {'options': 'Enter the number', 'choice': '0701 135362'},
        {'options': '1:Data', 'choice': '1'},
      ], '0701135362');
      expect(steps.map((step) => step['choice']), ['n', '1']);
    });

    test('labels support every menu format and free input', () {
      expect(
        CodeSignature.chosenLabel(
            {'options': 'Pick\n1:Data\n2:Calls', 'choice': 2}),
        'Calls',
      );
      expect(
        CodeSignature.chosenLabel(
            {'options': '1. Data 00. Home', 'choice': '00'}),
        'Home',
      );
      expect(
        CodeSignature.chosenLabel(
            {'options': '1:Data Only Plans\n0:BACK 00:HOME', 'choice': '00'}),
        'HOME',
      );
      expect(
        CodeSignature.chosenLabel(
            {'options': '1:Data Only Plans\n0:BACK 00:HOME', 'choice': '0'}),
        'BACK',
      );
      expect(
        CodeSignature.chosenLabel(
            {'options': 'Enter the number', 'choice': 'n'}),
        isNull,
      );
    });
  });

  group('Offer Changed', () {
    test('is its own category and never ambiguous', () {
      final category = TransactionCategory.forQuery(
        TransactionStatuses.offerChanged,
      );
      expect(category?.label, 'Offer Changed');
      expect(
        isAmbiguousTransactionOutcome(
          status: TransactionStatuses.offerChanged,
          reply: 'Found: request timed out',
        ),
        isFalse,
      );
    });
  });
}
