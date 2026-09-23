import 'package:decimal/decimal.dart';
import 'package:en16931/en16931.dart';
import 'package:en16931_ubl/en16931_ubl.dart';
import 'package:en16931_ublbe/en16931_ublbe.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support.dart';

XmlElement _root(String xml) => XmlDocument.parse(xml).rootElement;

List<String> _children(XmlElement element) =>
    element.childElements.map((child) => child.localName).toList();

Iterable<XmlElement> _lines(XmlElement root) => root.childElements.where(
  (element) =>
      element.localName == 'InvoiceLine' ||
      element.localName == 'CreditNoteLine',
);

void main() {
  group('the Belgian category', () {
    test('names every breakdown entry, right after the European one', () {
      final root = _root(writeUblBe(validInvoice()));
      final categories = root
          .findAllElements('cac:TaxSubtotal')
          .map((subtotal) => subtotal.findElements('cac:TaxCategory').single)
          .toList();
      expect(categories.map((c) => c.getElement('cbc:Name')?.innerText), [
        '03',
        '01',
      ]);
      for (final category in categories) {
        expect(_children(category).take(2), ['ID', 'Name']);
      }
    });

    test('names every item', () {
      final root = _root(writeUblBe(validInvoice()));
      final names = [
        for (final line in _lines(root))
          line
              .findAllElements('cac:ClassifiedTaxCategory')
              .single
              .getElement('cbc:Name')!
              .innerText,
      ];
      expect(names, ['03', '01']);
    });

    test('is read from a Belgian exemption code', () {
      final entry = VatBreakdown(
        category: VatCategory.intraCommunitySupply,
        taxableAmount: Decimal.fromInt(100),
        taxAmount: Decimal.zero,
        exemptionReasonCode: 'BETE-46/GO',
      );
      expect(ublBeTaxCategoryOf(entry), '46/GO');
    });

    test('is Belgian exempt turnover under its own spelling', () {
      final entry = VatBreakdown(
        category: VatCategory.exempt,
        taxableAmount: Decimal.fromInt(100),
        taxAmount: Decimal.zero,
        exemptionReasonCode: 'BETE-EX',
      );
      expect(ublBeTaxCategoryOf(entry), 'NA');
    });

    test('is not guessed where the seller has a choice', () {
      final entry = VatBreakdown(
        category: VatCategory.exempt,
        taxableAmount: Decimal.fromInt(100),
        taxAmount: Decimal.zero,
      );
      expect(ublBeTaxCategoryOf(entry), isNull);
      final invoice = validInvoice(
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
        exemptionReasons: {VatCategory.exempt: 'Exempt'},
      );
      expect(
        () => writeUblBe(invoice),
        throwsA(
          isA<UblBeWriteException>().having(
            (e) => e.problems,
            'problems',
            hasLength(2),
          ),
        ),
      );
      final written = writeUblBe(invoice, taxCategoryOf: (entry) => 'NA');
      expect(written, contains('<cbc:Name>NA</cbc:Name>'));
    });

    test('is refused when UBL.BE does not list it', () {
      expect(
        () => writeUblBe(validInvoice(), taxCategoryOf: (entry) => '21'),
        throwsA(isA<UblBeWriteException>()),
      );
    });

    test('is asked of the line when the breakdown splits its category', () {
      final invoice = validInvoice(
        lines: [
          for (final id in ['1', '2'])
            InvoiceLine.of(
              id: id,
              item: const Item(name: 'Service'),
              quantity: 1,
              unitPrice: 100,
              vatCategory: VatCategory.intraCommunitySupply,
              vatRate: 0,
            ),
        ],
        exemptionReasons: {VatCategory.intraCommunitySupply: 'IC supply'},
      );
      final split = Invoice(
        number: invoice.number,
        issueDate: invoice.issueDate,
        typeCode: invoice.typeCode,
        currency: invoice.currency,
        seller: invoice.seller,
        buyer: invoice.buyer,
        lines: invoice.lines,
        totals: invoice.totals,
        supportingDocuments: invoice.supportingDocuments,
        vatBreakdown: [
          for (final code in ['BETE-46/GO', 'BETE-44'])
            VatBreakdown(
              category: VatCategory.intraCommunitySupply,
              taxableAmount: Decimal.fromInt(100),
              taxAmount: Decimal.zero,
              rate: Decimal.zero,
              exemptionReasonCode: code,
            ),
        ],
      );
      expect(() => writeUblBe(split), throwsA(isA<UblBeWriteException>()));
      final written = writeUblBe(
        split,
        lineTaxCategoryOf: (line) => line.id == '1' ? '46/GO' : '44',
      );
      expect(written, contains('<cbc:Name>44</cbc:Name>'));
    });
  });

  group('the VAT of a line', () {
    test('comes before the item, where UBL puts it', () {
      final root = _root(writeUblBe(validInvoice()));
      for (final line in _lines(root)) {
        final children = _children(line);
        expect(children.indexOf('TaxTotal') + 1, children.indexOf('Item'));
      }
    });

    test('adds up to the VAT its breakdown entry declares', () {
      // The till signed 10.51 on a base of 50.00 at 21%. Split over three
      // lines, the shares have to come back to the signed figure rather
      // than to 10.50.
      final lines = [
        for (final (id, amount) in [('1', 20), ('2', 20), ('3', 10)])
          InvoiceLine.of(
            id: id,
            item: const Item(name: 'Sales'),
            quantity: 1,
            unitPrice: amount,
            vatRate: 21,
          ),
      ];
      final base = cashBook();
      final invoice = Invoice(
        number: base.number,
        issueDate: base.issueDate,
        typeCode: base.typeCode,
        currency: base.currency,
        specificationIdentifier: base.specificationIdentifier,
        businessProcess: base.businessProcess,
        seller: base.seller,
        buyer: base.buyer,
        lines: lines,
        supportingDocuments: base.supportingDocuments,
        totals: InvoiceTotals(
          sumOfLineNetAmounts: exact(50),
          totalWithoutVat: exact(50),
          totalWithVat: exact(60.51),
          amountDueForPayment: exact(60.51),
          totalVat: exact(10.51),
        ),
        vatBreakdown: [
          VatBreakdown(
            category: VatCategory.standardRate,
            taxableAmount: exact(50),
            taxAmount: exact(10.51),
            rate: exact(21),
          ),
        ],
      );
      final root = _root(writeUblBe(invoice));
      final shares = [
        for (final line in _lines(root))
          Decimal.parse(
            line.findElements('cac:TaxTotal').single.innerText.trim(),
          ),
      ];
      expect(shares, [
        Decimal.parse('4.20'),
        Decimal.parse('4.20'),
        Decimal.parse('2.11'),
      ]);
      expect(shares.reduce((a, b) => a + b), Decimal.parse('10.51'));
    });

    test('is written for a credit note as well', () {
      final root = _root(
        writeUblBe(
          validInvoice(
            typeCode: InvoiceTypeCode.creditNote,
            supportingDocuments: [
              ublBeSoftware('Test 1.0'),
              rendering(ublBeCreditNoteRendering),
            ],
          ),
        ),
      );
      expect(root.localName, 'CreditNote');
      for (final line in _lines(root)) {
        expect(_children(line), contains('TaxTotal'));
      }
    });
  });

  test('reads back as the invoice it was written from', () {
    final invoice = validInvoice();
    final again = readUbl(writeUblBe(invoice));
    expect(validateUblBe(again), isEmpty);
    expect(writeUbl(again), writeUbl(invoice));
  });

  test('leaves the payment terms as they were written', () {
    const terms = 'Line one.\n  Line two.';
    final written = writeUblBe(validInvoice(paymentTerms: terms));
    expect(written, contains(terms));
  });
}
