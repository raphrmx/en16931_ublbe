import 'package:en16931/en16931.dart';
import 'package:en16931_ublbe/src/catalogue.g.dart';
import 'package:en16931_ublbe/src/code_lists.dart';
import 'package:en16931_ublbe/src/rules.dart';

/// The UBL.BE catalogue, indexed by identifier.
final Map<String, RuleDescriptor> _byIdentifier = {
  for (final rule in ublBeCatalogue) rule.id: rule,
};

/// Where each rule sits in the catalogue, so the profile's violations come
/// out in its order.
final Map<String, int> _order = {
  for (final (index, rule) in ublBeCatalogue.indexed) rule.id: index,
};

/// The standard's rules renamed back, by the name the standard uses now.
final Map<String, String> _renamedFrom = {
  for (final entry in ublBeRenamedRules.entries) entry.value: entry.key,
};

/// The rule UBL.BE states as [id], at the severity UBL.BE gives it.
///
/// A rule of the standard UBL.BE holds unchanged is the standard's rule; one
/// it holds at another severity is the standard's rule at that severity.
RuleDescriptor ublBeRuleFor(String id) {
  if (_byIdentifier[id] case final rule?) return rule;
  final standard = ruleFor(id);
  final severity = ublBeSeverities[id];
  if (severity == null) return standard;
  return RuleDescriptor(
    id: standard.id,
    family: standard.family,
    severity: severity,
    terms: standard.terms,
  );
}

/// The rules of the standard UBL.BE does not hold, or holds its own way.
///
/// Their verdict under EN 16931 is not UBL.BE's, so [validateUblBe] sets it
/// aside: the rules the artefact comments out or leaves out, the ones it
/// holds with another code list, and the ones this package checks again.
Set<String> get ublBeOverriddenRules => {
  ...ublBeSuspendedRules,
  ...ublBeAbsentRules,
  ...ublBeCodeLists.keys,
  ...ublBeRules.keys,
};

/// The UBL.BE rules this package evaluates.
///
/// The rules of the standard UBL.BE holds its own way are checked too, but
/// they are the standard's, and [ublBeOverriddenRules] says which.
Set<String> get implementedUblBeRules => {
  ...ublBeRules.keys.where(_byIdentifier.containsKey),
  ...ublBePeppolRules.keys,
  ...ublBeRenamedRules.keys,
};

/// Every rule UBL.BE adds that this package has an answer for, whichever the
/// answer is.
Set<String> get accountedUblBeRules => {
  ...implementedUblBeRules,
  ...ublBeMetByConstruction.keys,
  ...ublBeForTheSyntax.keys,
};

/// What [invoice] breaks, under UBL.BE.
///
/// UBL.BE is an extension of EN 16931 rather than a narrowing of it, and it
/// states the standard's rules in its own copy. So the standard is checked
/// first, as UBL.BE holds it: without the rules Belgian VAT practice departs
/// from, with the code lists and severities UBL.BE gives, and under the old
/// name of the two families EN 16931 has since renamed. Then come the Peppol
/// rules UBL.BE carries, and the Belgian ones.
///
/// An empty result means the invoice says what UBL.BE asks as far as the
/// model goes. What UBL.BE adds beyond the model, the Belgian VAT category and
/// the VAT of every line, is written by `writeUblBe`, and a document written
/// by `writeUbl` alone lacks it.
List<RuleViolation> validateUblBe(Invoice invoice) {
  final overridden = ublBeOverriddenRules;
  final violations = <RuleViolation>[];
  for (final violation in validate(invoice)) {
    final id = violation.rule.id;
    if (_renamedFrom[id] case final old?) {
      violations.add(_as(violation, ublBeRuleFor(old)));
    } else if (!overridden.contains(id)) {
      violations.add(_as(violation, ublBeRuleFor(id)));
    }
  }
  for (final id in ublBeCodeLists.keys) {
    violations.addAll(checkUblBeList(invoice, ublBeRuleFor(id)));
  }

  final found = <RuleViolation>[];
  for (final entry in ublBePeppolRules.entries) {
    found.addAll(entry.value(invoice, ublBeRuleFor(entry.key)));
  }
  for (final entry in ublBeRules.entries) {
    // A rule of the standard UBL.BE holds its own way sorts with the
    // standard's, and a rule of its own with the catalogue.
    final into = _order.containsKey(entry.key) ? found : violations;
    into.addAll(entry.value(invoice, ublBeRuleFor(entry.key)));
  }
  violations.sort((a, b) => a.rule.id.compareTo(b.rule.id));
  found.sort((a, b) => _order[a.rule.id]!.compareTo(_order[b.rule.id]!));
  return [...violations, ...found];
}

/// Whether [invoice] breaks no UBL.BE rule a receiver would refuse it for.
bool isAcceptableUblBe(Invoice invoice) => validateUblBe(
  invoice,
).every((violation) => violation.rule.severity != RuleSeverity.fatal);

RuleViolation _as(RuleViolation violation, RuleDescriptor rule) =>
    identical(violation.rule, rule)
    ? violation
    : RuleViolation(
        rule: rule,
        message: violation.message,
        path: violation.path,
      );
