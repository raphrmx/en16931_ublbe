import 'package:en16931/en16931.dart';
import 'package:en16931_peppol/en16931_peppol.dart';
import 'package:en16931_ubl/en16931_ubl.dart';

/// BT-24 for an invoice claimed under UBL.BE.
///
/// Conformant rather than compliant: UBL.BE adds terms the standard does not
/// have, the Belgian VAT category above all, and departs from a handful of its
/// rules where Belgian VAT practice does. An invoice claiming this is an
/// extension of EN 16931, not a narrowing of it, which is why Belgian law does
/// not let it be sent to a customer as the invoice itself. It is what a
/// Belgian accounting package imports.
const String ublBeSpecification =
    'urn:cen.eu:en16931:2017#conformant#urn:UBL.BE:1.0.0.20180214';

/// BT-23 for an invoice under UBL.BE.
///
/// UBL.BE carries the Peppol rules along with its own, and those refuse an
/// invoice that names no Peppol billing process. Every published UBL.BE test
/// case names this one.
const String ublBeBusinessProcess = peppolBillingProcess;

/// BT-122 of the reference that says which software wrote the invoice.
///
/// UBL.BE wants exactly one such reference, with the software's name and
/// version as its description (BT-123).
const String ublBeSoftwareReference = 'UBL.BE';

/// BT-123 of the rendering of an invoice.
const String ublBeInvoiceRendering = 'CommercialInvoice';

/// BT-123 of the rendering of a credit note.
const String ublBeCreditNoteRendering = 'CreditNote';

/// The reference that names the software writing the invoice.
///
/// [software] is its name and version, `COMAPPS Backoffice 4.2` for instance.
SupportingDocument ublBeSoftware(String software) =>
    SupportingDocument(ublBeSoftwareReference, description: software);

/// The description UBL.BE wants on the rendering of a document of [type].
///
/// A document that goes out under the CreditNote root is described as a
/// credit note, and anything else as an invoice.
String ublBeRenderingFor(InvoiceTypeCode type) =>
    isCreditNote(type) ? ublBeCreditNoteRendering : ublBeInvoiceRendering;

/// Whether [invoice] claims UBL.BE.
bool isUblBe(Invoice invoice) =>
    invoice.specificationIdentifier?.trim().startsWith(ublBeSpecification) ??
    false;
