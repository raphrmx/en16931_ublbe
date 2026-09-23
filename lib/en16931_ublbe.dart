/// UBL.BE, the profile a Belgian accounting package imports invoices under.
///
/// UBL.BE is an extension of EN 16931 rather than a narrowing of it. It adds
/// the Belgian VAT category, which is what the turnover is booked by, and it
/// departs from a handful of the standard's rules where Belgian VAT practice
/// does. So this package says both what UBL.BE asks of the invoice and which
/// of the standard's rules it holds differently, and it writes the document,
/// since the terms UBL.BE adds are ones the semantic model does not carry.
///
/// The model and the rules of the standard are in `en16931`, and the UBL
/// itself is `en16931_ubl`'s.
library;

export 'src/catalogue.g.dart';
export 'src/code_lists.dart' show checkUblBeList;
export 'src/profile.dart';
export 'src/rules.dart'
    show
        UblBeCheck,
        ublBeForTheSyntax,
        ublBeMetByConstruction,
        ublBePeppolRules,
        ublBeRenamedRules,
        ublBeRules;
export 'src/tax_category.dart';
export 'src/validator.dart';
export 'src/writer.dart';
