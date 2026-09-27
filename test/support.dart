import 'dart:convert';
import 'dart:typed_data';

import 'package:en16931/en16931.dart';
import 'package:en16931_ublbe/en16931_ublbe.dart';

/// A Belgian invoice that satisfies UBL.BE.
///
/// Every test starts from this and breaks one thing, so a violation that
/// comes back is the one the test is about and not a second omission.
Invoice validInvoice({
  String? specificationIdentifier = ublBeSpecification,
  String? businessProcess = ublBeBusinessProcess,
  InvoiceTypeCode typeCode = InvoiceTypeCode.commercialInvoice,
  DateTime? dueDate,
  String? paymentTerms = '30 days after the invoice date.',
  Buyer? buyer,
  PaymentInstructions? paymentInstructions,
  List<SupportingDocument>? supportingDocuments,
  List<InvoiceLine>? lines,
  Map<VatCategory, String> exemptionReasons = const {},
  List<InvoiceNote> notes = const [],
}) =>
    Invoice.fromLines(
      number: '2026-0042',
      issueDate: DateTime(2026, 9, 13),
      dueDate: dueDate,
      specificationIdentifier: specificationIdentifier,
      businessProcess: businessProcess,
      typeCode: typeCode,
      buyerReference: 'PO-77',
      seller: validSeller,
      buyer: buyer ?? validBuyer,
      paymentTerms: paymentTerms,
      paymentInstructions: paymentInstructions,
      exemptionReasons: exemptionReasons,
      notes: notes,
      supportingDocuments:
          supportingDocuments ?? [ublBeSoftware('Test 1.0'), rendering()],
      lines: lines ??
          [
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

/// The rendering of an invoice, as UBL.BE wants it described.
SupportingDocument rendering([String description = ublBeInvoiceRendering]) =>
    SupportingDocument(
      '2026-0042.pdf',
      description: description,
      attachment: Attachment(
        bytes: Uint8List.fromList(utf8.encode('%PDF-1.4')),
        mimeCode: 'application/pdf',
        filename: '2026-0042.pdf',
      ),
    );

const Seller validSeller = Seller(
  name: 'COMAPPS SRL',
  vatIdentifier: 'BE0840559537',
  legalRegistrationIdentifier: Identifier('0840559537', scheme: '0208'),
  electronicAddress: Identifier('0840559537', scheme: '0208'),
  address: Address(
    line1: 'Rue Haute 1',
    city: 'Bruxelles',
    postalCode: '1000',
    country: 'BE',
  ),
);

const Buyer validBuyer = Buyer(
  name: 'Client SA',
  vatIdentifier: 'BE0987654321',
  electronicAddress: Identifier('0987654321', scheme: '0208'),
  address: Address(city: 'Liège', postalCode: '4000', country: 'BE'),
);

/// The day's takings of a shop, booked as one document.
///
/// Walk-in customers have no name, so the buyer is a label and a country. The
/// VAT is the figure the till signed rather than one worked out again, which
/// is why the constructor that carries the totals over is used. There is no
/// order and no contract to refer to, and the rendering goes along as a PDF.
Invoice cashBook({
  Buyer buyer = const Buyer(
    name: 'Clients divers',
    address: Address(country: 'BE'),
  ),
  String? paymentTerms,
  List<SupportingDocument>? supportingDocuments,
  num vatAt21 = 10.51,
}) =>
    Invoice(
      number: 'LC-2000000123-20260922',
      issueDate: CalendarDate(2026, 9, 22),
      currency: 'EUR',
      typeCode: InvoiceTypeCode.commercialInvoice,
      specificationIdentifier: ublBeSpecification,
      businessProcess: ublBeBusinessProcess,
      buyerReference: '2000000123',
      paymentTerms: paymentTerms,
      seller: validSeller,
      buyer: buyer,
      vatBreakdown: [
        VatBreakdown(
          category: VatCategory.standardRate,
          taxableAmount: exact(100),
          taxAmount: exact(6),
          rate: exact(6),
        ),
        VatBreakdown(
          category: VatCategory.standardRate,
          taxableAmount: exact(50),
          taxAmount: exact(vatAt21),
          rate: exact(21),
        ),
      ],
      totals: InvoiceTotals(
        sumOfLineNetAmounts: exact(150),
        totalWithoutVat: exact(150),
        totalWithVat: exact(156) + exact(vatAt21),
        amountDueForPayment: exact(156) + exact(vatAt21),
        totalVat: exact(6) + exact(vatAt21),
      ),
      lines: [
        InvoiceLine.of(
          id: '1',
          item: const Item(name: 'Sales at 6%'),
          quantity: 1,
          unitPrice: 100,
          unit: UnitCode.piece,
          vatRate: 6,
        ),
        InvoiceLine.of(
          id: '2',
          item: const Item(name: 'Sales at 21%'),
          quantity: 1,
          unitPrice: 50,
          unit: UnitCode.piece,
          vatRate: 21,
        ),
      ],
      supportingDocuments:
          supportingDocuments ?? [ublBeSoftware('Test 1.0'), rendering()],
    );

/// The identifiers of what [invoice] breaks under UBL.BE.
Set<String> broken(Invoice invoice) =>
    validateUblBe(invoice).map((violation) => violation.rule.id).toSet();

/// The identifiers of what [invoice] breaks under UBL.BE that is fatal.
Set<String> fatal(Invoice invoice) => validateUblBe(invoice)
    .where((violation) => violation.rule.severity == RuleSeverity.fatal)
    .map((violation) => violation.rule.id)
    .toSet();
