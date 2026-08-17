import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../domain/invoice_model.dart';
import '../../patients/domain/patient_model.dart';
import 'package:intl/intl.dart';

class InvoiceExporter {
  static Future<Uint8List> generatePdf(
    Invoice invoice, {
    Patient? patient,
    String? invoiceNumber,
  }) async {
    final pdf = pw.Document();

    if (patient == null && invoice.patientId.isNotEmpty) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('patients')
            .doc(invoice.patientId)
            .get();
        if (doc.exists) {
          patient = Patient.fromMap(doc.data()!, doc.id);
        }
      } catch (_) {}
    }

    final String finalInvoiceNumber =
        invoiceNumber ??
        (invoice.invoiceNumber.isNotEmpty
            ? invoice.invoiceNumber
            : (invoice.invoiceId.length > 8
                ? invoice.invoiceId.substring(0, 8).toUpperCase()
                : invoice.invoiceId));

    // Load assets
    pw.MemoryImage? logoImage;
    try {
      final logoData = await rootBundle.load('assets/Shifa_Logo-BG.png');
      logoImage = pw.MemoryImage(logoData.buffer.asUint8List());
    } catch (_) {}

    final fromDateVal = invoice.fromDate ?? invoice.createdAt;
    final toDateVal = invoice.toDate ?? invoice.createdAt.add(const Duration(days: 15));

    final fromDateStr = DateFormat('dd/MM/yyyy').format(fromDateVal);
    final toDateStr = DateFormat('dd/MM/yyyy').format(toDateVal);

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          buildBackground: (context) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Container(color: PdfColors.white),
          ),
        ),
        build: (context) {
          return [
            // ─── Header ───
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                // Logo & Tagline
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (logoImage != null)
                      pw.Container(
                        width: 260,
                        height: 80,
                        alignment: pw.Alignment.topLeft,
                        child: pw.Image(
                          logoImage,
                          fit: pw.BoxFit.contain,
                          alignment: pw.Alignment.topLeft,
                        ),
                      ),
                    pw.SizedBox(height: 6),
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(left: 4),
                      child: pw.Text(
                        'Your Health, Our Mission',
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: const PdfColor.fromInt(0xFF1565C0),
                        ),
                      ),
                    ),
                  ],
                ),
                // Invoice Title & #
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 6),
                      child: pw.Text(
                        'INVOICE',
                        style: pw.TextStyle(
                          fontSize: 26,
                          fontWeight: pw.FontWeight.bold,
                          color: const PdfColor.fromInt(0xFF1565C0),
                        ),
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Row(
                      mainAxisSize: pw.MainAxisSize.min,
                      children: [
                        pw.Text(
                          'Invoice #: ',
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            color: const PdfColor.fromInt(0xFF1E293B),
                          ),
                        ),
                        pw.Text(
                          finalInvoiceNumber,
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            color: const PdfColor.fromInt(0xFFDC2626),
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 6),
                    pw.Row(
                      mainAxisSize: pw.MainAxisSize.min,
                      children: [
                        pw.SizedBox(
                          width: 42,
                          child: pw.Text(
                            'FROM:',
                            style: pw.TextStyle(
                              fontSize: 8.5,
                              fontWeight: pw.FontWeight.bold,
                              color: const PdfColor.fromInt(0xFF64748B),
                            ),
                          ),
                        ),
                        pw.Text(
                          fromDateStr,
                          style: pw.TextStyle(
                            fontSize: 8.5,
                            fontWeight: pw.FontWeight.bold,
                            color: const PdfColor.fromInt(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 2),
                    pw.Row(
                      mainAxisSize: pw.MainAxisSize.min,
                      children: [
                        pw.SizedBox(
                          width: 42,
                          child: pw.Text(
                            'TO:',
                            style: pw.TextStyle(
                              fontSize: 8.5,
                              fontWeight: pw.FontWeight.bold,
                              color: const PdfColor.fromInt(0xFF64748B),
                            ),
                          ),
                        ),
                        pw.Text(
                          toDateStr,
                          style: pw.TextStyle(
                            fontSize: 8.5,
                            fontWeight: pw.FontWeight.bold,
                            color: const PdfColor.fromInt(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Container(
              height: 1,
              color: const PdfColor.fromInt(0xFFDBEAFE),
            ),
            pw.SizedBox(height: 14),

            // ─── Patient Info Card ───
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(12),
              decoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFF0F4FA),
                borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Column(
                children: [
                  pw.Row(
                    children: [
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'MR NUMBER',
                              style: pw.TextStyle(
                                fontSize: 8.5,
                                fontWeight: pw.FontWeight.bold,
                                color: const PdfColor.fromInt(0xFF1565C0),
                              ),
                            ),
                            pw.SizedBox(height: 2),
                            pw.Text(
                              patient?.mrNumber ?? 'N/A',
                              style: pw.TextStyle(
                                fontSize: 12,
                                fontWeight: pw.FontWeight.bold,
                                color: const PdfColor.fromInt(0xFF0F172A),
                              ),
                            ),
                          ],
                        ),
                      ),
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'PATIENT NAME',
                              style: pw.TextStyle(
                                fontSize: 8.5,
                                fontWeight: pw.FontWeight.bold,
                                color: const PdfColor.fromInt(0xFF1565C0),
                              ),
                            ),
                            pw.SizedBox(height: 2),
                            pw.Text(
                              (patient?.patientName ?? 'N/A').toUpperCase(),
                              style: pw.TextStyle(
                                fontSize: 12,
                                fontWeight: pw.FontWeight.bold,
                                color: const PdfColor.fromInt(0xFF0F172A),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 10),
                  pw.Row(
                    children: [
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'PHONE',
                              style: pw.TextStyle(
                                fontSize: 8.5,
                                fontWeight: pw.FontWeight.bold,
                                color: const PdfColor.fromInt(0xFF1565C0),
                              ),
                            ),
                            pw.SizedBox(height: 2),
                            pw.Text(
                              patient?.phone ?? 'N/A',
                              style: pw.TextStyle(
                                fontSize: 12,
                                fontWeight: pw.FontWeight.bold,
                                color: const PdfColor.fromInt(0xFF0F172A),
                              ),
                            ),
                          ],
                        ),
                      ),
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'ADDRESS',
                              style: pw.TextStyle(
                                fontSize: 8.5,
                                fontWeight: pw.FontWeight.bold,
                                color: const PdfColor.fromInt(0xFF1565C0),
                              ),
                            ),
                            pw.SizedBox(height: 2),
                            pw.Text(
                              patient?.address ?? 'N/A',
                              style: pw.TextStyle(
                                fontSize: 12,
                                fontWeight: pw.FontWeight.bold,
                                color: const PdfColor.fromInt(0xFF0F172A),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            // ─── Services Table ───
            pw.TableHelper.fromTextArray(
              headers: ['#', 'DESCRIPTION', 'PRICE', 'DAYS', 'TOTAL'],
              data: invoice.items.asMap().entries.map((entry) {
                final idx = entry.key + 1;
                final item = entry.value;
                return [
                  idx.toString(),
                  item.serviceName.toUpperCase(),
                  NumberFormat('#,##0').format(item.price),
                  item.quantity.toString(),
                  NumberFormat('#,##0').format(item.total),
                ];
              }).toList(),
              border: const pw.TableBorder(
                horizontalInside: pw.BorderSide(color: PdfColor.fromInt(0xFFE2E8F0), width: 0.5),
                bottom: pw.BorderSide(color: PdfColor.fromInt(0xFFE2E8F0), width: 0.5),
              ),
              headerStyle: pw.TextStyle(
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
                fontSize: 9,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFF1565C0),
              ),
              cellStyle: pw.TextStyle(
                fontSize: 9.5,
                fontWeight: pw.FontWeight.bold,
                color: const PdfColor.fromInt(0xFF0F172A),
              ),
              cellHeight: 28,
              cellAlignments: {
                0: pw.Alignment.center,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.center,
                3: pw.Alignment.center,
                4: pw.Alignment.centerRight,
              },
              columnWidths: {
                0: const pw.FlexColumnWidth(0.8),
                1: const pw.FlexColumnWidth(5.2),
                2: const pw.FlexColumnWidth(2),
                3: const pw.FlexColumnWidth(2),
                4: const pw.FlexColumnWidth(2.5),
              },
            ),
            pw.SizedBox(height: 18),

            // ─── Bank Transfer + Policy + Totals ───
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Left Column: Bank Details & Important Policy Notice
                pw.Expanded(
                  flex: 3,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      // Bank Details Card
                      pw.Container(
                        width: double.infinity,
                        padding: const pw.EdgeInsets.all(10),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: const PdfColor.fromInt(0xFFE2E8F0)),
                          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                          color: PdfColors.white,
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'BANK TRANSFER DETAILS',
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 9.5,
                                color: const PdfColor.fromInt(0xFF1565C0),
                              ),
                            ),
                            pw.SizedBox(height: 4),
                            pw.Container(
                              height: 0.5,
                              color: const PdfColor.fromInt(0xFFE2E8F0),
                            ),
                            pw.SizedBox(height: 6),
                            _bankRow('BANK:', 'Meezan Bank'),
                            _bankRow('TITLE:', 'SHIFA HOME HEALTH CARE'),
                            _bankRow('A/C #:', '10270115184708'),
                            _bankRow('IBAN:', 'PK23MEZN0010270115184708')
                          ],
                        ),
                      ),
                      pw.SizedBox(height: 10),
                      // Policy Notice Card
                      pw.Container(
                        width: double.infinity,
                        padding: const pw.EdgeInsets.all(8),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: const PdfColor.fromInt(0xFFFDE68A), width: 1),
                          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                          color: const PdfColor.fromInt(0xFFFFFBEB),
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'IMPORTANT POLICY NOTICE',
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 8.5,
                                color: const PdfColor.fromInt(0xFFB45309),
                              ),
                            ),
                            pw.SizedBox(height: 3),
                            pw.Text(
                              'Please be advised that the payment for medical equipment rentals and purchases is non-refundable. Upon agreement, the full payment is required in advance to secure the equipment. Once the transaction is completed, there are no returns or refunds.',
                              style: const pw.TextStyle(
                                fontSize: 7.5,
                                color: PdfColor.fromInt(0xFF78350F),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(width: 16),

                // Right Column: Totals
                pw.Expanded(
                  flex: 2,
                  child: pw.Column(
                    children: [
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'SUBTOTAL:',
                            style: pw.TextStyle(
                              fontSize: 9.5,
                              fontWeight: pw.FontWeight.bold,
                              color: const PdfColor.fromInt(0xFF64748B),
                            ),
                          ),
                          pw.Text(
                            '${NumberFormat('#,##0').format(invoice.subtotal)} PKR',
                            style: pw.TextStyle(
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                              color: const PdfColor.fromInt(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 6),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'DISCOUNT:',
                            style: pw.TextStyle(
                              fontSize: 9.5,
                              fontWeight: pw.FontWeight.bold,
                              color: const PdfColor.fromInt(0xFF64748B),
                            ),
                          ),
                          pw.Text(
                            '${NumberFormat('#,##0').format(invoice.discount)} PKR',
                            style: pw.TextStyle(
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                              color: const PdfColor.fromInt(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 8),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: const pw.BoxDecoration(
                          color: PdfColor.fromInt(0xFF1565C0),
                          borderRadius: pw.BorderRadius.all(
                            pw.Radius.circular(6),
                          ),
                        ),
                        child: pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text(
                              'TOTAL',
                              style: pw.TextStyle(
                                color: PdfColors.white,
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                            pw.Text(
                              '${NumberFormat('#,##0').format(invoice.grandTotal)} PKR',
                              style: pw.TextStyle(
                                color: PdfColors.white,
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      pw.SizedBox(height: 10),
                      pw.Container(
                        width: double.infinity,
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: pw.BoxDecoration(
                          color: invoice.paymentStatus == 'Paid'
                              ? const PdfColor.fromInt(0xFF16A34A)
                              : (invoice.paymentStatus == 'Partial'
                                  ? const PdfColor.fromInt(0xFFD97706)
                                  : const PdfColor.fromInt(0xFFDC2626)),
                          borderRadius: const pw.BorderRadius.all(
                            pw.Radius.circular(6),
                          ),
                        ),
                        child: pw.Center(
                          child: pw.Text(
                            invoice.paymentStatus.toUpperCase(),
                            style: pw.TextStyle(
                              color: PdfColors.white,
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            pw.Spacer(),
            pw.Divider(color: const PdfColor.fromInt(0xFFE2E8F0), thickness: 0.5),
            pw.SizedBox(height: 6),
            pw.Center(
              child: pw.Text(
                'THIS IS A COMPUTERIZED GENERATED INVOICE. NO SIGNATURE REQUIRED.',
                style: pw.TextStyle(
                  fontSize: 7.5,
                  color: const PdfColor.fromInt(0xFF94A3B8),
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _bankRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 48,
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
                color: const PdfColor.fromInt(0xFF64748B),
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
                color: const PdfColor.fromInt(0xFF0F172A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Future<Uint8List> generateImage(
    Invoice invoice, {
    Patient? patient,
    String? invoiceNumber,
    bool isPng = true,
  }) async {
    final pdfBytes = await generatePdf(
      invoice,
      patient: patient,
      invoiceNumber: invoiceNumber,
    );
    await for (final page in Printing.raster(pdfBytes, pages: [0], dpi: 300)) {
      return await page.toPng();
    }
    throw Exception('Failed to rasterize invoice');
  }
}
