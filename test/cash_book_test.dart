import 'dart:convert';
import 'dart:typed_data';

import 'package:en16931/en16931.dart';
import 'package:en16931_ubl/en16931_ubl.dart';
import 'package:en16931_ublbe/en16931_ublbe.dart';
import 'package:test/test.dart';

import 'support.dart';

/// The day's takings of a shop, as an accounting package imports them.
///
/// Three things set this document apart from an invoice to a customer, and
/// each is checked here against what UBL.BE says about it.
void main() {
  group('a buyer who is nobody in particular', () {
    test('is named, and needs nothing else of the standard', () {
      // BT-44 is the one term of the buyer the standard insists on, besides
      // the country. A label for walk-in customers fills it.
      final standard = validate(cashBook()).map((v) => v.rule.id);
      expect(standard, isNot(contains('BR-07')));
      expect(fatal(cashBook()), isNot(contains('BR-07')));
    });

    test('still needs an address to be delivered to under UBL.BE', () {
      // UBL.BE carries the Peppol rules, and Peppol wants the buyer's
      // electronic address (BT-49) whatever the buyer is.
      expect(fatal(cashBook()), contains('PEPPOL-EN16931-R010'));
      final named = cashBook(
        buyer: const Buyer(
          name: 'Clients divers',
          address: Address(country: 'BE'),
          electronicAddress: Identifier('PKE_WALK-IN', scheme: '0193'),
        ),
      );
      expect(fatal(named), isNot(contains('PEPPOL-EN16931-R010')));
    });
  });

  group('a document with no order and no contract', () {
    test('is referred to by the buyer reference alone', () {
      final invoice = cashBook();
      expect(invoice.purchaseOrderReference, isNull);
      expect(invoice.contractReference, isNull);
      expect(broken(invoice), isNot(contains('PEPPOL-EN16931-R003')));
    });

    test('says when it is due, or that it is paid', () {
      expect(fatal(cashBook()), contains('BR-CO-25'));
      expect(
        fatal(cashBook(paymentTerms: 'Paid at the till.')),
        isNot(contains('BR-CO-25')),
      );
    });

    test('breaks nothing else', () {
      final invoice = cashBook(
        buyer: const Buyer(
          name: 'Clients divers',
          address: Address(country: 'BE'),
          electronicAddress: Identifier('PKE_WALK-IN', scheme: '0193'),
        ),
        paymentTerms: 'Paid at the till.',
      );
      expect(validateUblBe(invoice), isEmpty);
    });
  });

  group('a rendering carried as a PDF', () {
    test('is the one UBL.BE describes as the invoice', () {
      expect(
        broken(cashBook()).where((id) => id.startsWith('ubl-BE')),
        isEmpty,
      );
    });

    test('goes out in base64 and comes back byte for byte', () {
      final bytes = Uint8List.fromList(List.generate(3000, (i) => i % 256));
      final invoice = cashBook(
        supportingDocuments: [
          ublBeSoftware('Test 1.0'),
          SupportingDocument(
            'LC-2000000123-20260922.pdf',
            description: ublBeInvoiceRendering,
            attachment: Attachment(
              bytes: bytes,
              mimeCode: 'application/pdf',
              filename: 'LC-2000000123-20260922.pdf',
            ),
          ),
        ],
      );
      final written = writeUblBe(invoice);
      expect(written, contains(base64Encode(bytes)));
      final attachment = readUbl(written)
          .supportingDocuments
          .singleWhere((document) => document.attachment != null)
          .attachment!;
      expect(attachment.bytes, bytes);
    });
  });
}
