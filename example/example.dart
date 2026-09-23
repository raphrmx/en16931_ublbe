// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:typed_data';

import 'package:en16931/en16931.dart';
import 'package:en16931_ublbe/en16931_ublbe.dart';

/// Builds an invoice claimed under UBL.BE, checks it, and writes it with the
/// Belgian VAT categories an accounting package books it by.
void main() {
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
        attachment: Attachment(
          bytes: Uint8List.fromList(utf8.encode('%PDF-1.4')),
          mimeCode: 'application/pdf',
          filename: '2026-0042.pdf',
        ),
      ),
    ],
    lines: [
      InvoiceLine.of(
        id: '1',
        item: const Item(name: 'Consultancy'),
        quantity: 8,
        unitPrice: 100,
        vatRate: 21,
        unit: UnitCode.hour,
      ),
      InvoiceLine.of(
        id: '2',
        item: const Item(name: 'Books'),
        quantity: 3,
        unitPrice: 33.33,
        vatRate: 6,
        unit: UnitCode.piece,
      ),
    ],
  );

  final violations = validateUblBe(invoice);
  if (violations.isNotEmpty) {
    violations.forEach(print);
    return;
  }
  print(writeUblBe(invoice));
}
