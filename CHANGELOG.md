## 0.1.0

First release.

- `ublBeSpecification` carries BT-24 for an invoice claimed under UBL.BE.
  The identifier is conformant rather than compliant: UBL.BE is an extension
  of EN 16931, not a narrowing of it.
- `validateUblBe` checks the standard as UBL.BE holds it, the Peppol rules it
  carries, and its own, in one pass. The artefact is a copy of the standard's
  rules edited in place, so the rules it comments out or deleted are set
  aside, the code lists it rewrote under the standard's rule names are
  checked against its own, and two rules the standard has since renamed are
  reported under the name UBL.BE gives them.
- A profile that widens a code list has to take the narrower rule off. The
  Belgian exemption reason codes are such a widening: BR-CL-22 is off and
  UBL.BE's own rule is on, and a Belgian VAT number is taken as a legal
  registration identifier where the standard's list refuses it.
- `writeUblBe` writes what UBL.BE adds that the semantic model has no term
  for: the Belgian VAT category of every breakdown entry and every item, and
  the VAT of every line, shared out so that the lines add up to what the
  breakdown declares. `ublBeTaxCategoryOf` reads the category off an entry
  where the entry says which, and nothing is guessed where the seller has a
  choice.
- `ublBeSoftware`, `ublBeInvoiceRendering` and `ublBeCreditNoteRendering`
  write the two references UBL.BE asks for.
- The Peppol rules UBL.BE did not edit are the Peppol package's, run at the
  severity UBL.BE gives them. The four it edited are answered here.
- The catalogue is read from UBL.BE release V1.31, pinned by tag on the
  mirror that carries it and checked against its digest. None of its content
  is reproduced: what is taken is which rules exist, how severe each is,
  which terms each bears on and the codes a rule compares against. Every
  message and every check here is this package's own.
- The test cases UBL.BE publishes are checked. Run
  `dart run tool/fetch_examples.dart` to pull them in. They found two faults
  in the package this one writes with, and one document that carries a term
  the model cannot.
- A test fails when a rule of the catalogue has no answer, so what is covered
  is a fact rather than a claim.
