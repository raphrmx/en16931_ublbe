import 'dart:io';

import 'package:en16931/en16931.dart';
import 'package:en16931_ubl/en16931_ubl.dart';
import 'package:en16931_ublbe/en16931_ublbe.dart';
import 'package:test/test.dart';

/// The test cases UBL.BE publishes.
///
/// They are not part of this repository. Run `dart run tool/fetch_examples.dart`
/// to pull them in, and these tests wake up. Checking our own invoices proves
/// the rules do what this package thinks they do; checking these proves they
/// do what UBL.BE thinks they do.
const String _directory = 'examples_from_ublbe';

/// The documents that carry a term EN 16931 has no room for.
///
/// UBL.BE lets a line be taxed on another amount than its net amount, as a
/// discount for early payment requires, and says so in a VAT subtotal on the
/// line. The model has no such subtotal, so that amount is lost on the way in
/// and the breakdown no longer follows from the lines. `writeUblBe` writes no
/// such subtotal either, so an invoice built here is checked as the standard
/// checks it, which is how UBL.BE checks it too when the subtotal is absent.
const Map<String, String> _beyondTheModel = {
  'UBLBE_BE0000000196_V01-15000032.xml':
      'Taxes its line on 392 of 400 after a discount for early payment, in a '
          'line VAT subtotal the model cannot carry, so BR-AE-08 cannot '
          'reconcile.',
};

void main() {
  final directory = Directory(_directory);
  if (!directory.existsSync()) {
    test('the published examples', () {}, skip: 'Run tool/fetch_examples.dart');
    return;
  }

  final files = directory.listSync().whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('there are documents to check', () {
    expect(files, hasLength(greaterThan(30)));
  });

  for (final file in files) {
    final name = file.uri.pathSegments.last;

    group(name, () {
      late Invoice invoice;

      setUp(() => invoice = readUbl(file.readAsStringSync()));

      test('claims UBL.BE', () {
        expect(isUblBe(invoice), isTrue);
      });

      test('breaks no rule that would refuse it', () {
        if (_beyondTheModel.containsKey(name)) {
          markTestSkipped(_beyondTheModel[name]!);
          return;
        }
        // These are the documents UBL.BE publishes to show what a valid
        // invoice looks like, so a fatal violation means this package reads
        // or checks something wrong, not that the document is wrong. Warnings
        // are another matter: a document is accepted while breaking one.
        expect(
          validateUblBe(invoice)
              .where((v) => v.rule.severity == RuleSeverity.fatal)
              .map((violation) => violation.toString()),
          isEmpty,
        );
      });
    });
  }
}
