import 'package:decimal/decimal.dart';
import 'package:en16931/en16931.dart';

/// Names the Belgian VAT category of one VAT breakdown entry.
///
/// Returns one of `ublBeTaxCategories`, or null when the entry does not say
/// enough to tell.
typedef UblBeTaxCategoryOf = String? Function(VatBreakdown entry);

/// The prefix UBL.BE puts before a Belgian category to make it an exemption
/// reason code (BT-121).
const String _exemptionPrefix = 'BETE-';

/// The one exemption reason code whose category is spelled differently.
const Map<String, String> _renamed = {'EX': 'NA'};

/// The Belgian VAT category of [entry], when the entry itself says which.
///
/// The Belgian category is finer than the European one: exempt turnover
/// alone splits into a dozen, and which applies is the seller's call. What
/// can be read off the entry is read, and nothing is guessed:
///
///  * a Belgian exemption reason code (BT-121) names its category, as
///    `BETE-46/GO` names `46/GO`;
///  * standard rated turnover at 6, 12 and 21 per cent is `01`, `02` and
///    `03`, the three Belgian rates;
///  * zero rated turnover is `00`, reverse charge `45` and turnover outside
///    the scope of VAT `NS`.
///
/// Anything else is null, and the caller has to name the category.
String? ublBeTaxCategoryOf(VatBreakdown entry) {
  final code = entry.exemptionReasonCode?.trim();
  if (code != null && code.startsWith(_exemptionPrefix)) {
    final category = code.substring(_exemptionPrefix.length);
    return _renamed[category] ?? category;
  }
  return switch (entry.category) {
    VatCategory.standardRate => _standardRates[entry.rate?.toString()],
    VatCategory.zeroRated => '00',
    VatCategory.reverseCharge => '45',
    VatCategory.outsideScope => 'NS',
    _ => null,
  };
}

/// The Belgian categories of standard rated turnover, by rate.
final Map<String, String> _standardRates = {
  for (final (rate, category) in const [(6, '01'), (12, '02'), (21, '03')])
    Decimal.fromInt(rate).toString(): category,
};
