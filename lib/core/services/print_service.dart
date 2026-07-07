import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../constants/business_info.dart';
import 'local_backup_service.dart';
import '../../shared/widgets/flow_widgets.dart' show money;

/// Shared PDF infrastructure for the Cash Book and Stock Register reports.
///
/// Holds the common letterhead, the brand palette, the rupee/amount formatter
/// and the two output paths (Android print dialog + save to Downloads). Reports
/// build their own body widgets on top of [buildLetterhead].
class PrintService {
  const PrintService._();

  // ─── Brand palette (matches app theme) ──────────────────────────────────────
  static const PdfColor navy = PdfColor.fromInt(0xFF0D1B3E);
  static const PdfColor gold = PdfColor.fromInt(0xFFD4A843);
  static const PdfColor grey = PdfColor.fromInt(0xFF777777);
  static const PdfColor rowAlt = PdfColor.fromInt(0xFFF5F5F5);
  static const PdfColor subtotalBg = PdfColor.fromInt(0xFFE8ECF5);
  static const PdfColor green = PdfColor.fromInt(0xFF2E7D32);
  static const PdfColor red = PdfColor.fromInt(0xFFC62828);
  static const PdfColor white = PdfColors.white;

  // ─── Amount formatting ───────────────────────────────────────────────────────

  /// Indian-grouped whole-rupee amount for PDF output. Reuses the app's [money]
  /// formatter, swapping the ₹ glyph for "Rs." because the built-in PDF fonts
  /// (Helvetica) have no rupee glyph and would render a blank box.
  static String rupees(num value) => money(value).replaceAll('₹', 'Rs. ');

  // ─── Logo ────────────────────────────────────────────────────────────────────

  /// Loads the business logo asset as a PDF image provider.
  static Future<pw.ImageProvider> loadLogo() async {
    final bytes = await rootBundle.load(BusinessInfo.logoAssetPath);
    return pw.MemoryImage(bytes.buffer.asUint8List());
  }

  // ─── Letterhead ───────────────────────────────────────────────────────────────

  /// Shared report header: logo + business name/address on the left, report
  /// title + date on the right, closed by a thin gold divider.
  static pw.Widget buildLetterhead({
    required pw.ImageProvider logo,
    required String reportTitle,
    required String reportDate,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              height: 60,
              width: 60,
              child: pw.Image(logo, fit: pw.BoxFit.contain),
            ),
            pw.SizedBox(width: 14),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    BusinessInfo.name,
                    style: pw.TextStyle(
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                      color: navy,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    BusinessInfo.address,
                    style: const pw.TextStyle(fontSize: 9, color: grey),
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  reportTitle,
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                    color: navy,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  reportDate,
                  style: const pw.TextStyle(fontSize: 11, color: grey),
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Container(height: 2, color: gold),
        pw.SizedBox(height: 14),
      ],
    );
  }

  /// Footer divider + right-aligned print timestamp.
  static pw.Widget buildFooter() {
    final now = DateTime.now();
    final stamp = '${_two(now.day)}/${_two(now.month)}/${now.year} '
        '${_two(now.hour)}:${_two(now.minute)}';
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.SizedBox(height: 10),
        pw.Container(height: 0.5, color: grey),
        pw.SizedBox(height: 4),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Printed on $stamp',
            style: const pw.TextStyle(fontSize: 8, color: grey),
          ),
        ),
      ],
    );
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  // ─── Output: print ────────────────────────────────────────────────────────────

  /// Sends [pdf] to Android's print dialog (PrintManager) via the printing
  /// package. [documentName] is shown in the Android print queue.
  static Future<void> printDocument({
    required pw.Document pdf,
    required String documentName,
  }) async {
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: documentName,
    );
  }

  // ─── Output: save to Downloads ─────────────────────────────────────────────────

  /// Saves [pdf] to the device Downloads/CMBank folder (survives uninstall),
  /// reusing the same storage-permission flow as local backups. Shows a snackbar
  /// with the resulting path on success.
  static Future<void> saveAsPdf({
    required pw.Document pdf,
    required String fileName,
    required BuildContext context,
  }) async {
    final granted =
        await LocalBackupService.instance.ensureStoragePermission();
    if (!context.mounted) return;
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Storage permission denied.')),
      );
      return;
    }

    try {
      const dirPath = '/storage/emulated/0/Download/CMBank';
      final dir = Directory(dirPath);
      if (!await dir.exists()) await dir.create(recursive: true);

      final path = '$dirPath/$fileName';
      await File(path).writeAsBytes(await pdf.save(), flush: true);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved to Download/CMBank/$fileName'),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save PDF: $e')),
      );
    }
  }
}
