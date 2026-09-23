import 'package:decimal/decimal.dart';
import 'package:en16931/en16931.dart';
import 'package:en16931_peppol/en16931_peppol.dart';
import 'package:en16931_ublbe/en16931_ublbe.dart';
import 'package:en16931_ublbe/src/code_lists.dart';
import 'package:test/test.dart';

void main() {
  final catalogue = ublBeCatalogue.map((rule) => rule.id).toSet();

  test('is read from the release the artefact is pinned to', () {
    expect(ublBeArtefactRelease, 'V1.31');
  });

  test('holds the fifteen Belgian rules', () {
    expect(catalogue.where((id) => id.startsWith('ubl-BE-')), hasLength(15));
  });

  test('has an answer for every rule UBL.BE adds', () {
    expect(catalogue.difference(accountedUblBeRules), isEmpty);
    expect(accountedUblBeRules.difference(catalogue), isEmpty);
  });

  test('gives each rule one answer', () {
    final answers = [
      ...implementedUblBeRules,
      ...ublBeMetByConstruction.keys,
      ...ublBeForTheSyntax.keys,
    ];
    expect(answers.toSet(), hasLength(answers.length));
  });

  test('keeps the rules of the standard apart from its own', () {
    final standard = ruleCatalogue.map((rule) => rule.id).toSet();
    expect(catalogue.intersection(standard), isEmpty);
    for (final set in [
      ublBeSuspendedRules,
      ublBeAbsentRules,
      ublBeSeverities.keys.toSet(),
      ublBeCodeLists.keys.toSet(),
    ]) {
      expect(set.difference(standard), isEmpty);
    }
  });

  test('reads every list it holds differently', () {
    expect(
      ublBeCodeLists.keys.toSet(),
      ublBeListReaders.keys.toSet(),
      reason: 'A list UBL.BE rewrites has to be read term for term.',
    );
  });

  test('renames only what both sides hold', () {
    final standard = ruleCatalogue.map((rule) => rule.id).toSet();
    for (final MapEntry(key: old, value: current)
        in ublBeRenamedRules.entries) {
      expect(catalogue, contains(old));
      expect(standard, contains(current));
      expect(ublBeAbsentRules, contains(current));
    }
  });

  test('checks again every rule of the standard it answers for', () {
    final standard = ruleCatalogue.map((rule) => rule.id).toSet();
    final own = ublBeRules.keys.where(standard.contains).toSet();
    expect(own, {'BR-51'});
    expect(ublBeSeverities, contains('BR-51'));
  });

  test(
    'takes the Peppol rules it does not rewrite from the Peppol package',
    () {
      for (final id in ublBePeppolRules.keys) {
        expect(peppolRules, contains(id));
        expect(ublBeRules, isNot(contains(id)));
      }
    },
  );

  test('comments out the rule a Belgian exemption code would break', () {
    // The widening trap: UBL.BE takes BETE- codes for BT-121, which the
    // standard's list does not hold. The artefact takes the narrower rule
    // off, and so does this package.
    expect(ublBeSuspendedRules, contains('BR-CL-22'));
    expect(ublBeOverriddenRules, contains('BR-CL-22'));
    expect(
      ublBeExemptionReasonCodes.every((code) => code.startsWith('BETE-')),
      isTrue,
    );
  });

  test(
    'holds every rewritten list apart from the standard, wider or narrower',
    () {
      for (final id in ublBeCodeLists.keys) {
        if (codeListByRule[id] case final standard?) {
          final wider = ublBeCodeLists[id]!.difference(standard);
          final narrower = standard.difference(ublBeCodeLists[id]!);
          expect(
            wider.isNotEmpty || narrower.isNotEmpty,
            isTrue,
            reason: '$id is held differently or not at all',
          );
        }
      }
      expect(ublBeCodeLists['BR-CL-11'], contains('9925'));
      expect(codeListByRule['BR-CL-11'], isNot(contains('9925')));
    },
  );

  test('knows every Belgian category a BETE- code names', () {
    for (final code in ublBeExemptionReasonCodes) {
      final category = ublBeTaxCategoryOf(
        VatBreakdown(
          category: VatCategory.exempt,
          taxableAmount: Decimal.zero,
          taxAmount: Decimal.zero,
          exemptionReasonCode: code,
        ),
      );
      expect(ublBeTaxCategories, contains(category), reason: code);
    }
  });
}
