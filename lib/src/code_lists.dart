import 'package:en16931/en16931.dart';
import 'package:en16931_ublbe/src/catalogue.g.dart';

/// A code the rule reads, and where it sits in the invoice.
typedef _Code = (String value, String? path);

/// What each list rule reads from an invoice, and what the term is called.
///
/// The standard's own readers are private to it, so the rules UBL.BE holds
/// with another list are read again here, term for term, and compared with
/// the list UBL.BE holds. A test holds this table to `ublBeCodeLists`, so a
/// release that rewrites one more list cannot go unread.
final Map<String, (String, List<_Code> Function(Invoice))> ublBeListReaders = {
  'BR-CL-01': ('invoice type code (BT-3)', (i) => _one(i.typeCode.value)),
  'BR-CL-03': (
    'currency (BT-5, BT-6)',
    (i) => [..._one(i.currency), ..._one(i.vatAccountingCurrency)],
  ),
  'BR-CL-04': ('invoice currency code (BT-5)', (i) => _one(i.currency)),
  'BR-CL-05': (
    'VAT accounting currency code (BT-6)',
    (i) => _one(i.vatAccountingCurrency),
  ),
  'BR-CL-07': (
    'object identifier scheme (BT-18-1)',
    (i) => _one(i.objectIdentifier?.scheme),
  ),
  'BR-CL-10': ('party identifier scheme', _partySchemes),
  'BR-CL-11': ('legal registration identifier scheme', _registrationSchemes),
  'BR-CL-13': ('item classification scheme (BT-158-1)', _classifications),
  'BR-CL-15': ('item origin country (BT-159)', _origins),
  'BR-CL-16': (
    'payment means code (BT-81)',
    (i) => _one(i.paymentInstructions?.means.value),
  ),
  'BR-CL-19': (
    'allowance reason code (BT-98, BT-140)',
    (i) => _reasons(i, AllowanceOrCharge.allowance),
  ),
  'BR-CL-20': (
    'charge reason code (BT-105, BT-145)',
    (i) => _reasons(i, AllowanceOrCharge.charge),
  ),
  'BR-CL-21': ('item standard identifier scheme (BT-157-1)', _standardSchemes),
  'BR-CL-25': (
    'electronic address scheme (BT-34-1, BT-49-1)',
    _electronicAddressSchemes,
  ),
  'BR-CL-26': (
    'delivery location identifier scheme (BT-71-1)',
    (i) => _one(i.delivery?.locationIdentifier?.scheme),
  ),
  'BR-CO-09': ('VAT identifier country prefix', _vatPrefixes),
};

/// Reports the codes the UBL.BE list for [rule] does not hold.
Iterable<RuleViolation> checkUblBeList(
  Invoice invoice,
  RuleDescriptor rule,
) sync* {
  final allowed = ublBeCodeLists[rule.id];
  final reader = ublBeListReaders[rule.id];
  if (allowed == null || reader == null) return;
  final (term, read) = reader;
  for (final (value, path) in read(invoice)) {
    if (value.trim().isEmpty || allowed.contains(value.trim())) continue;
    yield RuleViolation(
      rule: rule,
      message: 'The $term is "$value", which the list UBL.BE holds does not.',
      path: path,
    );
  }
}

List<_Code> _one(String? value) => value == null ? const [] : [(value, null)];

List<_Code> _partySchemes(Invoice invoice) => [
      for (final (index, identifier) in invoice.seller.identifiers.indexed)
        if (identifier.scheme != null)
          (identifier.scheme!, 'seller identifier $index'),
      if (invoice.buyer.identifier?.scheme case final scheme?)
        (scheme, 'buyer identifier'),
      if (invoice.payee?.identifier?.scheme case final scheme?)
        (scheme, 'payee identifier'),
    ];

List<_Code> _registrationSchemes(Invoice invoice) => [
      if (invoice.seller.legalRegistrationIdentifier?.scheme case final scheme?)
        (scheme, 'seller registration'),
      if (invoice.buyer.legalRegistrationIdentifier?.scheme case final scheme?)
        (scheme, 'buyer registration'),
      if (invoice.payee?.legalRegistrationIdentifier?.scheme case final scheme?)
        (scheme, 'payee registration'),
    ];

List<_Code> _classifications(Invoice invoice) => [
      for (final line in invoice.lines)
        for (final identifier in line.item.classificationIdentifiers)
          if (identifier.scheme != null) (identifier.scheme!, _line(line)),
    ];

List<_Code> _origins(Invoice invoice) => [
      for (final line in invoice.lines)
        if (line.item.originCountry case final country?) (country, _line(line)),
    ];

List<_Code> _reasons(Invoice invoice, AllowanceOrCharge kind) {
  final noun = kind == AllowanceOrCharge.allowance ? 'allowance' : 'charge';
  return [
    for (final (index, entry) in invoice.allowancesAndCharges.indexed)
      if (entry.kind == kind && entry.reasonCode != null)
        (entry.reasonCode!, 'document $noun $index'),
    for (final line in invoice.lines)
      for (final (index, entry) in line.allowancesAndCharges.indexed)
        if (entry.kind == kind && entry.reasonCode != null)
          (entry.reasonCode!, '${_line(line)}, $noun $index'),
  ];
}

List<_Code> _standardSchemes(Invoice invoice) => [
      for (final line in invoice.lines)
        if (line.item.standardIdentifier?.scheme case final scheme?)
          (scheme, _line(line)),
    ];

List<_Code> _electronicAddressSchemes(Invoice invoice) => [
      if (invoice.seller.electronicAddress?.scheme case final scheme?)
        (scheme, 'seller'),
      if (invoice.buyer.electronicAddress?.scheme case final scheme?)
        (scheme, 'buyer'),
    ];

/// The country prefix of every VAT identifier the invoice carries.
///
/// The standard only asks for two letters there. UBL.BE asks for two letters
/// its list holds, so a prefix it does not know is reported under the rule
/// the standard uses for the shape.
List<_Code> _vatPrefixes(Invoice invoice) => [
      for (final (vat, path) in [
        (invoice.seller.vatIdentifier, 'seller'),
        (invoice.buyer.vatIdentifier, 'buyer'),
        (invoice.taxRepresentative?.vatIdentifier, 'tax representative'),
      ])
        if (vat != null && vat.trim().length >= 2)
          (vat.trim().substring(0, 2), path),
    ];

String _line(InvoiceLine line) => 'line ${line.id}';
