import 'package:en16931/en16931.dart';
import 'package:en16931_peppol/en16931_peppol.dart';
import 'package:en16931_ubl/en16931_ubl.dart';
import 'package:en16931_ublbe/src/catalogue.g.dart';
import 'package:en16931_ublbe/src/profile.dart';

/// Checks one UBL.BE rule against an invoice.
typedef UblBeCheck = Iterable<RuleViolation> Function(
    Invoice invoice, RuleDescriptor rule);

/// The Belgian rules this package evaluates against the model.
final Map<String, UblBeCheck> ublBeRules = {
  'ubl-BE-01': _be01,
  'ubl-BE-02': _be02,
  'ubl-BE-03': _be03,
  'ubl-BE-04': _be04,
  'ubl-BE-11': _be11,
  'ubl-BE-12': _be12,
  'BR-51': _br51,
  'BR-CO-25': _co25,
  'PEPPOL-EN16931-R002': _r002,
  'PEPPOL-EN16931-R004': _r004,
  'PEPPOL-EN16931-R007': _r007,
  'PEPPOL-EN16931-P0100': _p0100,
};

/// The Peppol rules UBL.BE carries and states as Peppol does.
///
/// UBL.BE copied the Peppol rules into its artefact and edited four of them,
/// which [ublBeRules] answers for here. The rest are the Peppol package's,
/// run at the severity UBL.BE gives them: the business process and one code
/// list are only a warning under UBL.BE.
Map<String, PeppolCheck> get ublBePeppolRules => {
      for (final rule in ublBeCatalogue)
        if (peppolRules[rule.id] case final check?)
          if (!ublBeRules.containsKey(rule.id)) rule.id: check,
    };

/// The rules of the standard UBL.BE still holds under the name the standard
/// has since dropped, mapped to the name the standard uses now.
///
/// EN 16931 renamed the rules of its Canary Islands and Ceuta and Melilla
/// categories after UBL.BE copied them. The rules did not change, so the
/// standard's own check answers under the old name.
const Map<String, String> ublBeRenamedRules = {
  'BR-IG-01': 'BR-AF-01',
  'BR-IG-02': 'BR-AF-02',
  'BR-IG-03': 'BR-AF-03',
  'BR-IG-04': 'BR-AF-04',
  'BR-IP-01': 'BR-AG-01',
  'BR-IP-02': 'BR-AG-02',
  'BR-IP-03': 'BR-AG-03',
  'BR-IP-04': 'BR-AG-04',
};

/// The rules an invoice built with this model cannot break.
///
/// Most bear on terms UBL.BE adds and the semantic model does not have:
/// the legal mentions carried as delivery terms, and the discount for early
/// payment. An invoice built here carries neither, so neither can be wrong.
/// A UBL.BE document read from elsewhere loses them on the way in.
Map<String, String> get ublBeMetByConstruction => {
      for (final rule in ublBeCatalogue)
        if (peppolMetByConstruction[rule.id] case final met?) rule.id: met,
      'BR-66': 'PaymentInstructions holds one card.',
      'BR-67': 'PaymentInstructions holds one direct debit.',
      'ubl-BE-05': 'The model has no delivery terms to carry a legal mention.',
      'ubl-BE-06': 'The model has no delivery terms to carry a legal mention.',
      'ubl-BE-07': 'The model has no discount for early payment.',
      'ubl-BE-08': 'The model has no discount for early payment.',
      'ubl-BE-09': 'The model has no discount for early payment.',
    };

/// The rules that are about the document rather than the invoice.
///
/// These say what the XML carries beyond the model. `writeUblBe` writes it:
/// the Belgian VAT category on every breakdown entry and every item, and the
/// VAT of every line. A document written by `writeUbl` alone breaks all four.
Map<String, String> get ublBeForTheSyntax => {
      for (final rule in ublBeCatalogue)
        if (peppolForTheSyntax[rule.id] case final syntax?) rule.id: syntax,
      'ubl-BE-10': 'writeUblBe names the Belgian category of every breakdown.',
      'ubl-BE-13':
          'writeUblBe writes the VAT of every line, and the artefact accepts any '
              'amount there.',
      'ubl-BE-14': 'writeUblBe writes the VAT of every line.',
      'ubl-BE-15': 'writeUblBe names the Belgian category of every item.',
    };

// --- The references UBL.BE asks for ----------------------------------------

Iterable<RuleViolation> _be01(Invoice invoice, RuleDescriptor rule) sync* {
  final count = invoice.supportingDocuments.length;
  if (count >= 2) return;
  yield _at(
    rule,
    'The invoice carries $count supporting document${count == 1 ? '' : 's'} '
    '(BG-24), where UBL.BE wants two at least: its rendering and the '
    'software that wrote it.',
  );
}

Iterable<RuleViolation> _be02(Invoice invoice, RuleDescriptor rule) sync* {
  final renderings = invoice.supportingDocuments.where(
    (document) => const {
      ublBeInvoiceRendering,
      ublBeCreditNoteRendering,
    }.contains(document.description),
  );
  if (renderings.length == 1) return;
  yield _at(
    rule,
    renderings.isEmpty
        ? 'No supporting document (BG-24) is described as the rendering of '
            'the invoice. UBL.BE wants one described '
            '"${ublBeRenderingFor(invoice.typeCode)}".'
        : '${renderings.length} supporting documents (BG-24) are described '
            'as the rendering of the invoice, where UBL.BE wants one.',
  );
}

Iterable<RuleViolation> _be03(Invoice invoice, RuleDescriptor rule) sync* {
  final software = invoice.supportingDocuments.where(
    (document) => document.reference == ublBeSoftwareReference,
  );
  if (software.length == 1) return;
  yield _at(
    rule,
    software.isEmpty
        ? 'No supporting document (BG-24) names the software that wrote the '
            'invoice. UBL.BE wants one referenced "$ublBeSoftwareReference" '
            '(BT-122); ublBeSoftware writes it.'
        : '${software.length} supporting documents (BG-24) are referenced '
            '"$ublBeSoftwareReference", where UBL.BE wants one.',
  );
}

Iterable<RuleViolation> _be04(Invoice invoice, RuleDescriptor rule) sync* {
  for (final (index, document) in invoice.supportingDocuments.indexed) {
    if (!_blank(document.description)) continue;
    yield _at(
      rule,
      'The supporting document "${document.reference}" has no description '
          '(BT-123). UBL.BE wants every one described.',
      'supporting document $index',
    );
  }
}

// --- The Belgian exemption reasons -----------------------------------------

Iterable<RuleViolation> _be11(Invoice invoice, RuleDescriptor rule) sync* {
  for (final (index, entry) in invoice.vatBreakdown.indexed) {
    final code = entry.exemptionReasonCode;
    if (code == null || ublBeExemptionReasonCodes.contains(code.trim())) {
      continue;
    }
    yield _at(
      rule,
      'The VAT exemption reason code (BT-121) is "$code". UBL.BE takes a '
          'Belgian code, BETE- followed by the Belgian category, in place of the '
          'European VATEX list.',
      'VAT breakdown $index',
    );
  }
}

Iterable<RuleViolation> _be12(Invoice invoice, RuleDescriptor rule) sync* {
  for (final (index, entry) in invoice.vatBreakdown.indexed) {
    final reason = entry.exemptionReason;
    if (reason == null || ublBeExemptionReasons.contains(reason.trim())) {
      continue;
    }
    yield _at(
      rule,
      'The VAT exemption reason (BT-120) is "$reason", which is not one of '
          'the wordings UBL.BE lists in ublBeExemptionReasons.',
      'VAT breakdown $index',
    );
  }
}

// --- The rules of the standard UBL.BE holds its own way --------------------

Iterable<RuleViolation> _br51(Invoice invoice, RuleDescriptor rule) sync* {
  final card = invoice.paymentInstructions?.card;
  if (card == null) return;
  final length = card.primaryAccountNumber.length;
  if (length >= 4 && length <= 6) return;
  yield _at(
    rule,
    'The card primary account number (BT-87) is $length characters long. '
    'UBL.BE takes the last four to six digits of the card and nothing more.',
  );
}

Iterable<RuleViolation> _co25(Invoice invoice, RuleDescriptor rule) sync* {
  // UBL.BE holds the rule on an invoice only. A credit note owes nothing.
  if (isCreditNote(invoice.typeCode)) return;
  final due = invoice.totals.amountDueForPayment;
  if (due.sign <= 0) return;
  if (invoice.dueDate != null || !_blank(invoice.paymentTerms)) return;
  yield _at(
    rule,
    'An amount of $due is due for payment (BT-115), and the invoice gives '
    'neither a due date (BT-9) nor payment terms (BT-20). The buyer cannot '
    'tell when to pay.',
  );
}

// --- The Peppol rules UBL.BE edited ----------------------------------------

Iterable<RuleViolation> _r002(Invoice invoice, RuleDescriptor rule) sync* {
  if (invoice.notes.length <= 1) return;
  yield _at(
    rule,
    'The invoice carries ${invoice.notes.length} notes (BT-22), where UBL.BE '
    'allows one.',
  );
}

Iterable<RuleViolation> _r004(Invoice invoice, RuleDescriptor rule) sync* {
  if (isUblBe(invoice)) return;
  yield _at(
    rule,
    'The specification identifier (BT-24) is '
    '"${invoice.specificationIdentifier}", where a UBL.BE invoice carries '
    'ublBeSpecification.',
  );
}

Iterable<RuleViolation> _r007(Invoice invoice, RuleDescriptor rule) sync* {
  final process = invoice.businessProcess?.trim();
  if (process != null && _billingProcess.hasMatch(process)) return;
  yield _at(
    rule,
    process == null || process.isEmpty
        ? 'The business process (BT-23) is missing. UBL.BE wants a Peppol '
            'billing process, which ublBeBusinessProcess names.'
        : 'The business process (BT-23) is "$process", where UBL.BE expects '
            'urn:fdc:peppol.eu:2017:poacc:billing:NN:1.0.',
  );
}

Iterable<RuleViolation> _p0100(Invoice invoice, RuleDescriptor rule) sync* {
  final process = _billingProcess.firstMatch(
    invoice.businessProcess?.trim() ?? '',
  );
  if (process?.group(1) != '01') return;
  if (isCreditNote(invoice.typeCode)) return;
  final code = invoice.typeCode.value;
  if (ublBeBillingInvoiceTypes.contains(code)) return;
  yield _at(
    rule,
    'The invoice type code (BT-3) is "$code", which billing process 01 does '
    'not accept under UBL.BE.',
  );
}

/// A Peppol billing process, capturing its number.
final RegExp _billingProcess = RegExp(
  r'^urn:fdc:peppol\.eu:2017:poacc:billing:([0-9]{2}):1\.0$',
);

bool _blank(String? value) => value == null || value.trim().isEmpty;

RuleViolation _at(RuleDescriptor rule, String message, [String? path]) =>
    RuleViolation(rule: rule, message: message, path: path);
