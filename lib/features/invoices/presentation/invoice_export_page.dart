import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import '../domain/invoice_model.dart';
import '../utils/invoice_exporter.dart';
import '../data/invoice_repository.dart';

class InvoiceExportPage extends ConsumerWidget {
  final Invoice invoice;

  const InvoiceExportPage({super.key, required this.invoice});

  Future<void> _exportFile(BuildContext context, WidgetRef ref, String format) async {
    try {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Text('Saving ${format.toUpperCase()} invoice... Please wait'),
              ],
            ),
            backgroundColor: const Color(0xFF004B93),
            duration: const Duration(seconds: 15),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      Uint8List bytes;
      String extension;
      final invoiceNum = invoice.invoiceNumber.isNotEmpty
          ? invoice.invoiceNumber
          : (invoice.invoiceId.length > 8 ? invoice.invoiceId.substring(0, 8) : invoice.invoiceId);
      final fileName = 'invoice_$invoiceNum';

      if (format == 'pdf') {
        bytes = await InvoiceExporter.generatePdf(invoice);
        extension = 'pdf';
      } else if (format == 'png') {
        bytes = await InvoiceExporter.generateImage(invoice, isPng: true);
        extension = 'png';
      } else if (format == 'jpeg') {
        bytes = await InvoiceExporter.generateImage(invoice, isPng: false);
        extension = 'jpg';
      } else {
        if (context.mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
        return;
      }

      final fullFileName = '$fileName.$extension';

      if (kIsWeb) {
        if (context.mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
        await Printing.sharePdf(
          bytes: bytes,
          filename: fullFileName,
        );
      } else {
        bool isSavedToGallery = false;

        if (Platform.isAndroid &&
            (fullFileName.endsWith('.png') ||
                fullFileName.endsWith('.jpg') ||
                fullFileName.endsWith('.jpeg'))) {
          try {
            final channel =
                MethodChannel('com.shifa.shifa_management/media_scanner');
            await channel.invokeMethod('saveImageToGallery', {
              'bytes': Uint8List.fromList(bytes),
              'filename': fullFileName,
            });
            isSavedToGallery = true;
          } catch (_) {}
        }

        List<String> savedPaths = [];
        if (Platform.isAndroid) {
          final downloadDir = Directory('/storage/emulated/0/Download');
          if (await downloadDir.exists()) {
            final file = File('${downloadDir.path}/$fullFileName');
            await file.writeAsBytes(bytes);
            savedPaths.add(file.path);
          }
        }

        if (savedPaths.isEmpty) {
          Directory? dir;
          try {
            dir = await getDownloadsDirectory();
          } catch (_) {}
          dir ??= await getApplicationDocumentsDirectory();

          final file = File('${dir.path}/$fullFileName');
          await file.writeAsBytes(bytes);
          savedPaths.add(file.path);
        }

        for (final path in savedPaths) {
          try {
            final channel = MethodChannel('com.shifa.shifa_management/media_scanner');
            await channel.invokeMethod('scanFile', {'path': path});
          } catch (_) {}
        }

        if (context.mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isSavedToGallery
                    ? '✓ Saved $fullFileName directly to Photos Gallery & Downloads'
                    : '✓ Saved $fullFileName to Downloads folder',
              ),
              backgroundColor: const Color(0xFF16A34A),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }

      if (context.mounted) {
        ref.invalidate(staffInvoicesProvider);
        ref.invalidate(allInvoicesProvider(false));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoice Preview'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'Export PDF',
            onPressed: () => _exportFile(context, ref, 'pdf'),
          ),
          IconButton(
            icon: const Icon(Icons.image),
            tooltip: 'Export PNG',
            onPressed: () => _exportFile(context, ref, 'png'),
          ),
          IconButton(
            icon: const Icon(Icons.photo),
            tooltip: 'Export JPEG',
            onPressed: () => _exportFile(context, ref, 'jpeg'),
          ),
        ],
      ),
      body: PdfPreview(
        build: (format) => InvoiceExporter.generatePdf(invoice),
        allowPrinting: true,
        allowSharing: false, // We use custom app bar actions for direct format exports
        canChangeOrientation: false,
        canChangePageFormat: false, // Force A4
        initialPageFormat: PdfPageFormat.a4,
      ),
    );
  }
}
