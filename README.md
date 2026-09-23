<a alt="ComApps Logo" href="https://comapps.be" target="_blank" rel="noreferrer"><img src="https://www.comapps.be/wp-content/uploads/2026/09/CompleteLogoHorizontalMini.png" style="margin: 15px"></a>

# EN 16931 UBL.BE

![Build](https://img.shields.io/github/actions/workflow/status/raphrmx/en16931_ublbe/ci.yml?branch=main&label=build)
[![Pub Version](https://img.shields.io/pub/v/en16931_ublbe?color=blue)](https://pub.dev/packages/en16931_ublbe)
[![Maintainer](https://img.shields.io/badge/Maintainer-Raphael_Vrient-purple)](https://pub.dev/publishers/comapps.be/packages)
[![License](https://img.shields.io/badge/Licence-MIT-blue)](https://pub.dev/packages/en16931_ublbe/license)
![Maintenance](https://img.shields.io/badge/Maintained-yes-success)

UBL.BE: the Belgian extension of EN 16931, the rules it holds an invoice to,
and the Belgian terms it carries beyond the standard.

A Belgian accounting package imports sales and purchases in UBL.BE. It books
the turnover by the Belgian VAT category, which EN 16931 has no term for, so
an invoice can satisfy the standard and still not be importable. This checks
it and writes it.

## Install

```yaml
dependencies:
  en16931: ^0.1.2
  en16931_ublbe: ^0.1.0
```

## Check and write an invoice

Claim the profile on the invoice, name the software and the rendering, then
check it and write it.

```dart
import 'package:en16931/en16931.dart';
import 'package:en16931_ublbe/en16931_ublbe.dart';

final invoice = Invoice.fromLines(
  number: '2026-0042',
  issueDate: DateTime(2026, 9, 13),
  dueDate: DateTime(2026, 10, 13),
  specificationIdentifier: ublBeSpecification,
  businessProcess: ublBeBusinessProcess,
  buyerReference: 'PO-77',
  seller: const Seller(
    name: 'COMAPPS SRL',
    vatIdentifier: 'BE0840559537',
    electronicAddress: Identifier('0840559537', scheme: '0208'),
    address: Address(city: 'Bruxelles', postalCode: '1000', country: 'BE'),
  ),
  buyer: const Buyer(
    name: 'Client SA',
    vatIdentifier: 'BE0987654321',
    electronicAddress: Identifier('0987654321', scheme: '0208'),
    address: Address(city: 'Liège', postalCode: '4000', country: 'BE'),
  ),
  supportingDocuments: [
    ublBeSoftware('COMAPPS Backoffice 4.2'),
    SupportingDocument(
      '2026-0042.pdf',
      description: ublBeInvoiceRendering,
      attachment: Attachment(bytes: pdf, mimeCode: 'application/pdf', filename: '2026-0042.pdf'),
    ),
  ],
  lines: [...],
);

for (final violation in validateUblBe(invoice)) {
  print(violation);
}
final xml = writeUblBe(invoice);
```

## What UBL.BE adds

**The Belgian VAT category.** Every VAT breakdown entry and every item carries
one: `03` for 21 per cent, `45` for a reverse charge, `46/GO` for goods
delivered in another member state, and so on. `writeUblBe` writes it. Where
the entry says which it is, by its rate or by a Belgian exemption reason code,
`ublBeTaxCategoryOf` reads it off; where the seller has a choice, as exempt
turnover does, it is asked for rather than guessed.

**The VAT of every line.** `writeUblBe` shares out the VAT of each breakdown
entry over its lines, so the lines add up to what the entry declares rather
than to a figure worked out again.

**Two references.** One names the software that wrote the invoice,
`ublBeSoftware` writes it. The other is the rendering, described as a
`CommercialInvoice` or a `CreditNote`.

**Belgian exemption reasons.** A reason code is `BETE-` followed by the
Belgian category, in place of the European VATEX list, and the reason is
worded as UBL.BE lists it.

## Worth knowing up front

UBL.BE is conformant, not compliant. It extends the standard rather than
narrowing it, so Belgian law does not let it stand as the invoice sent to a
customer. It is what goes from one piece of software into an accounting
package.

It is not written as a layer on top of EN 16931. Its artefact holds a copy of
the standard's rules, a copy of the Peppol rules and its own, edited in
place. So `validateUblBe` checks the standard as UBL.BE holds it:

- It sets aside the rules UBL.BE comments out or deleted, where Belgian VAT
  practice parts from the standard: the VAT of a category may stray from its
  base times its rate, and exempt turnover is split by Belgian category.
  `ublBeSuspendedRules` and `ublBeAbsentRules` name them.
- It checks the code lists UBL.BE holds under the standard's rule names
  against UBL.BE's list, which is older in places and wider in others. A
  Belgian VAT number is a legal registration identifier under it, and a
  register added since is not. `ublBeCodeLists` holds them.
- A profile that widens a list has to take the narrower rule off, or the
  invoice breaks the standard for obeying the profile. The Belgian exemption
  codes are that case: the standard's BR-CL-22 is off, and UBL.BE's own rule
  is on.
- It carries the Peppol rules, so the buyer needs an electronic address and
  the invoice a Peppol billing process, as `ublBeBusinessProcess` names.

A document read from elsewhere loses what the model has no term for: the
Belgian categories, the legal mentions, a line taxed on another amount than
its net amount. `ublBeMetByConstruction` and `ublBeForTheSyntax` say which
rules that touches. The rule catalogue is read from the UBL.BE artefact, so it
is complete by construction, and a test fails when a rule has no answer.

## What it does not do

It says whether an invoice is ready for an accounting package, and writes
it. The model and the rules of the standard are in
[en16931](https://pub.dev/packages/en16931), and the UBL is written by
[en16931_ubl](https://pub.dev/packages/en16931_ubl). What a platform adds on
top of UBL.BE is that platform's business, and stays with its caller.

## License

Released under the [MIT licence](https://pub.dev/packages/en16931_ublbe/license).

The rule catalogue is generated from the artefact UBL.BE publishes, which
carries no licence. None of its content is redistributed: what is taken from
it is which rules exist, how severe each is, which terms each bears on and
the codes a rule compares against.
