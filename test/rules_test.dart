import 'package:en16931/en16931.dart';
import 'package:en16931_ublbe/en16931_ublbe.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  test('the valid invoice breaks nothing', () {
    expect(validateUblBe(validInvoice()), isEmpty);
  });

  group('the claim', () {
    test('is the UBL.BE identifier', () {
      expect(
        fatal(validInvoice(specificationIdentifier: en16931Specification)),
        {'PEPPOL-EN16931-R004'},
      );
    });

    test('names a Peppol billing process', () {
      final violations = broken(validInvoice(businessProcess: null));
      expect(violations, containsAll(['PEPPOL-EN16931-R007']));
      // Missing, the process is a warning under R001 and fatal under R007,
      // which is how UBL.BE holds the two.
      expect(
        ublBeRuleFor('PEPPOL-EN16931-R001').severity,
        RuleSeverity.warning,
      );
      expect(fatal(validInvoice(businessProcess: 'urn:example:process')), {
        'PEPPOL-EN16931-R007',
      });
    });

    test('accepts under billing process 01 fewer type codes than Peppol', () {
      final invoice = validInvoice(typeCode: const InvoiceTypeCode('326'));
      expect(broken(invoice), contains('PEPPOL-EN16931-P0100'));
    });
  });

  group('the references', () {
    test('are two at least', () {
      expect(
        broken(validInvoice(supportingDocuments: [rendering()])),
        containsAll(['ubl-BE-01', 'ubl-BE-03']),
      );
    });

    test('include one rendering, described for what it is', () {
      expect(
        broken(
          validInvoice(
            supportingDocuments: [ublBeSoftware('Test 1.0'), rendering('PDF')],
          ),
        ),
        {'ubl-BE-02'},
      );
      expect(
        broken(
          validInvoice(
            supportingDocuments: [
              ublBeSoftware('Test 1.0'),
              rendering(),
              rendering(),
            ],
          ),
        ),
        {'ubl-BE-02'},
      );
    });

    test('include one naming the software', () {
      expect(
        broken(
          validInvoice(
            supportingDocuments: [
              ublBeSoftware('Test 1.0'),
              ublBeSoftware('Test 2.0'),
              rendering(),
            ],
          ),
        ),
        {'ubl-BE-03'},
      );
    });

    test('are every one described', () {
      expect(
        broken(
          validInvoice(
            supportingDocuments: [
              ublBeSoftware('Test 1.0'),
              rendering(),
              const SupportingDocument('folder-7'),
            ],
          ),
        ),
        {'ubl-BE-04'},
      );
    });

    test('describe a credit note as one', () {
      expect(
        ublBeRenderingFor(InvoiceTypeCode.creditNote),
        ublBeCreditNoteRendering,
      );
      expect(
        ublBeRenderingFor(InvoiceTypeCode.commercialInvoice),
        ublBeInvoiceRendering,
      );
    });
  });

  group('the exemption reason', () {
    Invoice exempt(String code, String reason) => validInvoice(
          lines: [
            InvoiceLine.of(
              id: '1',
              item: const Item(name: 'Training'),
              quantity: 1,
              unitPrice: 500,
              vatCategory: VatCategory.exempt,
              vatRate: 0,
            ),
          ],
          exemptionReasons: {VatCategory.exempt: reason},
        ).withExemptionCode(code);

    test('is a Belgian code, and the European list is set aside', () {
      final invoice = exempt('BETE-EX', 'Exempt');
      // The standard refuses BETE-EX under BR-CL-22. UBL.BE comments that
      // rule out and asks for its own code instead, so the invoice that
      // obeys it has to pass.
      expect(validate(invoice).map((v) => v.rule.id), contains('BR-CL-22'));
      expect(broken(invoice), isEmpty);
    });

    test('is refused as a VATEX code', () {
      expect(broken(exempt('VATEX-EU-132', 'Exempt')), {'ubl-BE-11'});
    });

    test('is worded as UBL.BE lists it', () {
      expect(broken(exempt('BETE-EX', 'Exempt from VAT')), {'ubl-BE-12'});
    });
  });

  group('the standard as UBL.BE holds it', () {
    test('lets the VAT of a category part from the rate', () {
      // Belgian VAT may be rounded per line, and a till rounds it per
      // ticket, so over a busy day the VAT of a category can stray from its
      // base times its rate by more than the unit of currency the standard
      // tolerates. UBL.BE deleted the rules that say otherwise.
      final invoice = cashBook(vatAt21: 12);
      final standard = validate(invoice).map((v) => v.rule.id).toSet();
      expect(standard, contains('BR-S-09'));
      expect(ublBeAbsentRules, containsAll(['BR-S-08', 'BR-S-09', 'BR-CO-17']));
      expect(
        broken(invoice).intersection({'BR-S-08', 'BR-S-09', 'BR-CO-17'}),
        isEmpty,
      );
    });

    test('takes the Belgian VAT number as a registration scheme', () {
      const buyer = Buyer(
        name: 'Client SA',
        vatIdentifier: 'BE0987654321',
        legalRegistrationIdentifier: Identifier('BE0987654321', scheme: '9925'),
        electronicAddress: Identifier('0987654321', scheme: '0208'),
        address: Address(country: 'BE'),
      );
      final invoice = validInvoice(buyer: buyer);
      expect(validate(invoice).map((v) => v.rule.id), contains('BR-CL-11'));
      expect(broken(invoice), isEmpty);
    });

    test('refuses a scheme registered after its copy was taken', () {
      const buyer = Buyer(
        name: 'Client SA',
        vatIdentifier: 'BE0987654321',
        legalRegistrationIdentifier: Identifier('X-1', scheme: '0230'),
        electronicAddress: Identifier('0987654321', scheme: '0208'),
        address: Address(country: 'BE'),
      );
      final invoice = validInvoice(buyer: buyer);
      expect(
        validate(invoice).map((v) => v.rule.id),
        isNot(contains('BR-CL-11')),
      );
      expect(broken(invoice), {'BR-CL-11'});
    });

    test('reports the Canary Islands rules under their old name', () {
      final invoice = validInvoice(
        lines: [
          InvoiceLine.of(
            id: '1',
            item: const Item(name: 'Goods'),
            quantity: 1,
            unitPrice: 100,
            vatCategory: VatCategory.canaryIslands,
            vatRate: 7,
          ),
        ],
      ).withoutSellerVat();
      final ids = broken(invoice);
      expect(ids, contains('BR-IG-02'));
      expect(ids.where((id) => id.startsWith('BR-AF-')), isEmpty);
    });

    test('holds the card number to four to six digits, fatally', () {
      final invoice = validInvoice(
        paymentInstructions: const PaymentInstructions(
          means: PaymentMeansCode.bankCard,
          card: PaymentCard('1234567'),
        ),
      );
      expect(fatal(invoice), {'BR-51'});
    });

    test('asks when an amount due is to be paid', () {
      expect(fatal(validInvoice(paymentTerms: null)), {'BR-CO-25'});
      expect(
        broken(
          validInvoice(paymentTerms: null, dueDate: DateTime(2026, 10, 13)),
        ),
        isEmpty,
      );
    });

    test('allows one note', () {
      expect(
        broken(
          validInvoice(notes: const [InvoiceNote('One'), InvoiceNote('Two')]),
        ),
        {'PEPPOL-EN16931-R002'},
      );
    });
  });
}

extension on Invoice {
  /// This invoice with [code] as the exemption reason code of every entry.
  Invoice withExemptionCode(String code) => Invoice(
        number: number,
        issueDate: issueDate,
        typeCode: typeCode,
        currency: currency,
        specificationIdentifier: specificationIdentifier,
        businessProcess: businessProcess,
        buyerReference: buyerReference,
        paymentTerms: paymentTerms,
        seller: seller,
        buyer: buyer,
        lines: lines,
        supportingDocuments: supportingDocuments,
        totals: totals,
        vatBreakdown: [
          for (final entry in vatBreakdown)
            VatBreakdown(
              category: entry.category,
              taxableAmount: entry.taxableAmount,
              taxAmount: entry.taxAmount,
              rate: entry.rate,
              exemptionReason: entry.exemptionReason,
              exemptionReasonCode: code,
            ),
        ],
      );

  /// This invoice with a seller that gives no VAT identifier.
  Invoice withoutSellerVat() => Invoice(
        number: number,
        issueDate: issueDate,
        typeCode: typeCode,
        currency: currency,
        specificationIdentifier: specificationIdentifier,
        businessProcess: businessProcess,
        buyerReference: buyerReference,
        paymentTerms: paymentTerms,
        seller: Seller(
          name: seller.name,
          address: seller.address,
          legalRegistrationIdentifier: seller.legalRegistrationIdentifier,
          electronicAddress: seller.electronicAddress,
        ),
        buyer: buyer,
        lines: lines,
        supportingDocuments: supportingDocuments,
        totals: totals,
        vatBreakdown: vatBreakdown,
      );
}
