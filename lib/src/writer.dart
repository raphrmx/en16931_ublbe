// `namespace` is deprecated in xml 7 and is the only spelling xml 6 has.
// Writing it the 7 way would put the floor of this package back on
// Dart 3.11, which is what xml 7 asks for.
// ignore_for_file: deprecated_member_use

import 'package:decimal/decimal.dart';
import 'package:en16931/en16931.dart';
import 'package:en16931_ubl/en16931_ubl.dart';
import 'package:en16931_ublbe/src/catalogue.g.dart';
import 'package:en16931_ublbe/src/tax_category.dart';
import 'package:xml/xml.dart';

const String _cac =
    'urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2';
const String _cbc =
    'urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2';

/// Names the Belgian VAT category of one line, where its breakdown entry
/// cannot.
typedef UblBeLineTaxCategoryOf = String? Function(InvoiceLine line);

/// Raised when an invoice cannot be written as UBL.BE.
///
/// Carries every problem at once, so one attempt tells the whole story.
final class UblBeWriteException implements Exception {
  /// An invoice that could not be written, for each of [problems].
  const UblBeWriteException(this.problems);

  /// What stood in the way, one sentence each.
  final List<String> problems;

  @override
  String toString() => 'UblBeWriteException: ${problems.length} problem(s)\n'
      '${problems.map((problem) => ' - $problem').join('\n')}';
}

/// [invoice] as a UBL.BE document.
///
/// The document `writeUbl` writes, with the three things UBL.BE adds that the
/// semantic model has no term for:
///
///  * the Belgian VAT category of every VAT breakdown entry, which a Belgian
///    accounting package books the turnover by;
///  * the same category on every invoiced item;
///  * the VAT of every line.
///
/// The Belgian category of an entry comes from [taxCategoryOf], which reads
/// what the entry says by default: see [ublBeTaxCategoryOf]. A line takes the
/// category of the breakdown entry at its own VAT category and rate. When two
/// entries share both, which happens when exempt turnover is split under two
/// Belgian categories, [lineTaxCategoryOf] has to say which a line is.
///
/// The VAT of a line is the share of its breakdown entry's VAT that its net
/// amount makes up, rounded to the cent, with the last line of the entry
/// taking what rounding leaves. The lines of an entry therefore add up to the
/// VAT the entry declares, which is the figure a Belgian accounting package
/// reconciles against.
///
/// Throws [UblBeWriteException] when a category cannot be named, or names
/// one UBL.BE does not list.
String writeUblBe(
  Invoice invoice, {
  bool pretty = true,
  UblBeTaxCategoryOf taxCategoryOf = ublBeTaxCategoryOf,
  UblBeLineTaxCategoryOf? lineTaxCategoryOf,
}) {
  final problems = <String>[];

  final entryNames = <String?>[];
  for (final (index, entry) in invoice.vatBreakdown.indexed) {
    final name = taxCategoryOf(entry);
    entryNames.add(name);
    _checkName(problems, name, 'VAT breakdown entry $index', entry);
  }

  final lineNames = <String?>[];
  for (final line in invoice.lines) {
    final given = lineTaxCategoryOf?.call(line);
    if (given != null) {
      lineNames.add(given);
      if (!ublBeTaxCategories.contains(given)) {
        problems.add(
          'Line ${line.id} is named Belgian category "$given", which UBL.BE '
          'does not list.',
        );
      }
      continue;
    }
    final candidates = {
      for (final (index, entry) in invoice.vatBreakdown.indexed)
        if (_sameGroup(entry, line)) entryNames[index],
    }.nonNulls.toSet();
    if (candidates.length == 1) {
      lineNames.add(candidates.single);
      continue;
    }
    lineNames.add(null);
    problems.add(
      candidates.isEmpty
          ? 'Line ${line.id} is ${_describe(line.vatCategory, line.vatRate)}, '
              'and no VAT breakdown entry names a Belgian category for it.'
          : 'Line ${line.id} is ${_describe(line.vatCategory, line.vatRate)}, '
              'which the breakdown splits under ${candidates.join(' and ')}. '
              'lineTaxCategoryOf has to say which the line is.',
    );
  }

  if (problems.isNotEmpty) throw UblBeWriteException(problems);

  final lineVat = _lineVat(invoice, entryNames, lineNames.cast<String>());
  final document = XmlDocument.parse(writeUbl(invoice, pretty: false));
  final root = document.rootElement;

  final subtotals = root
      .findElements('TaxTotal', namespace: _cac)
      .expand((total) => total.findElements('TaxSubtotal', namespace: _cac))
      .toList();
  for (final (index, subtotal) in subtotals.indexed) {
    final category = subtotal.getElement('TaxCategory', namespace: _cac)!;
    _nameCategory(category, entryNames[index]!);
  }

  final lines = root.childElements
      .where(
        (element) =>
            element.name.local == 'InvoiceLine' ||
            element.name.local == 'CreditNoteLine',
      )
      .toList();
  for (final (index, element) in lines.indexed) {
    final item = element.getElement('Item', namespace: _cac)!;
    final classified = item.getElement(
      'ClassifiedTaxCategory',
      namespace: _cac,
    )!;
    _nameCategory(classified, lineNames[index]!);
    element.children.insert(
      element.children.indexOf(item),
      _taxTotal(lineVat[index], invoice.currency),
    );
  }

  return pretty
      ? document.toXmlString(
          pretty: true,
          indent: '  ',
          preserveWhitespace: _significantWhitespace,
        )
      : document.toXmlString();
}

void _checkName(
  List<String> problems,
  String? name,
  String where,
  VatBreakdown entry,
) {
  final what = _describe(entry.category, entry.rate);
  if (name == null) {
    problems.add(
      'The $where is $what, which does not say which Belgian category it is. '
      'Give it a BETE- exemption reason code, or name it through '
      'taxCategoryOf.',
    );
  } else if (!ublBeTaxCategories.contains(name)) {
    problems.add(
      'The $where is named Belgian category "$name", which UBL.BE does not '
      'list.',
    );
  }
}

String _describe(VatCategory category, Decimal? rate) => rate == null
    ? 'category ${category.code}'
    : 'category ${category.code} at $rate%';

bool _sameGroup(VatBreakdown entry, InvoiceLine line) =>
    entry.category == line.vatCategory && _sameRate(entry.rate, line.vatRate);

/// Whether two rates are the same, a missing one counting as zero.
///
/// Turnover outside the scope of VAT has no rate, and a document read from
/// elsewhere sometimes writes zero for it on one side and nothing on the
/// other.
bool _sameRate(Decimal? a, Decimal? b) =>
    (a ?? Decimal.zero) == (b ?? Decimal.zero);

/// The VAT of every line, in the order of the lines.
List<Decimal> _lineVat(
  Invoice invoice,
  List<String?> entryNames,
  List<String> lineNames,
) {
  final vat = List<Decimal>.filled(invoice.lines.length, Decimal.zero);
  final groups = <(VatCategory, Decimal?, String), List<int>>{};
  for (final (index, line) in invoice.lines.indexed) {
    groups.putIfAbsent((
      line.vatCategory,
      line.vatRate,
      lineNames[index],
    ), () => []).add(index);
  }
  for (final MapEntry(key: (category, rate, name), value: members)
      in groups.entries) {
    final declared = [
      for (final (index, entry) in invoice.vatBreakdown.indexed)
        if (entry.category == category &&
            _sameRate(entry.rate, rate) &&
            entryNames[index] == name)
          entry.taxAmount,
    ];
    final net = members.fold(
      Decimal.zero,
      (total, index) => total + invoice.lines[index].netAmount,
    );
    if (declared.isEmpty || net == Decimal.zero) {
      for (final index in members) {
        vat[index] = _round(
          invoice.lines[index].netAmount * (rate ?? Decimal.zero),
          Decimal.fromInt(100),
        );
      }
      continue;
    }
    final total = declared.fold(Decimal.zero, (sum, amount) => sum + amount);
    var left = total;
    for (final index in members.take(members.length - 1)) {
      final share = _round(total * invoice.lines[index].netAmount, net);
      vat[index] = share;
      left -= share;
    }
    vat[members.last] = left;
  }
  return vat;
}

Decimal _round(Decimal numerator, Decimal denominator) =>
    (numerator / denominator)
        .toDecimal(scaleOnInfinitePrecision: 10)
        .round(scale: 2);

/// Puts the Belgian category after the European one, where UBL orders it.
void _nameCategory(XmlElement category, String name) {
  final id = category.getElement('ID', namespace: _cbc)!;
  category.children.insert(
    category.children.indexOf(id) + 1,
    XmlElement(const XmlName.parts('Name', prefix: 'cbc'), [], [XmlText(name)]),
  );
}

/// The VAT of one line, which UBL puts just before the item.
XmlElement _taxTotal(Decimal amount, String currency) =>
    XmlElement(const XmlName.parts('TaxTotal', prefix: 'cac'), [], [
      XmlElement(
        const XmlName.parts('TaxAmount', prefix: 'cbc'),
        [XmlAttribute(const XmlName.parts('currencyID'), currency)],
        [XmlText(amount.toStringAsFixed(2))],
      ),
    ]);

/// Whether the space inside an element is part of what it says, as the UBL
/// writer holds it: the payment terms are read back line by line.
bool _significantWhitespace(XmlNode node) =>
    node is XmlElement &&
    node.name.local == 'Note' &&
    node.parentElement?.name.local == 'PaymentTerms';
