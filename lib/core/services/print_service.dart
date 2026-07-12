import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, FontLoader;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../constants/business_info.dart';
import 'local_backup_service.dart';
import '../../shared/widgets/flow_widgets.dart' show money;

/// Shared PDF infrastructure for the Cash Book and Stock Register reports.
///
/// Holds the common letterhead, the brand palette, the bundled Noto Sans
/// fonts, the rupee/amount formatter and the two output paths (Android print
/// dialog + save to Downloads). Reports build their own body widgets on top
/// of [buildLetterhead].
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

  // ─── Fonts ───────────────────────────────────────────────────────────────────

  /// Loads Noto Sans (regular weight) from the bundled asset instead of
  /// google_fonts' runtime network fetch, so the ₹ glyph (U+20B9) renders in
  /// generated PDFs even with no internet connection.
  static Future<pw.Font> notoSansRegular() async {
    final data = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
    return pw.Font.ttf(data);
  }

  /// Bold companion to [notoSansRegular], bundled the same way.
  static Future<pw.Font> notoSansBold() async {
    final data = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
    return pw.Font.ttf(data);
  }

  /// Noto Sans Malayalam (regular weight), bundled the same way, for the
  /// Malayalam script used in the Pledge Form's legal declaration.
  static Future<pw.Font> notoSansMalayalam() async {
    final data =
        await rootBundle.load('assets/fonts/NotoSansMalayalam-Regular.ttf');
    return pw.Font.ttf(data);
  }

  // ─── Complex-script (Malayalam) rendering ───────────────────────────────────
  //
  // The `pdf` package draws glyphs without complex-script shaping, so Malayalam
  // conjuncts/vowel-signs come out mangled (or as unknown boxes with a Latin
  // font). We instead render such text with Flutter's own text engine (which
  // shapes correctly) into a transparent PNG and embed that image in the PDF.
  // Used for the Malayalam declaration and for any Malayalam customer
  // name/address on the pledge form.

  static bool _malayalamFontLoaded = false;

  /// Registers the bundled Noto Sans Malayalam font with the Flutter engine
  /// (once) so [renderTextImage] can shape it, independent of device fonts.
  static Future<void> _ensureMalayalamFont() async {
    if (_malayalamFontLoaded) return;
    final loader = FontLoader('NotoSansMalayalam')
      ..addFont(rootBundle.load('assets/fonts/NotoSansMalayalam-Regular.ttf'));
    await loader.load();
    _malayalamFontLoaded = true;
  }

  /// Renders [text] (possibly complex-script and/or multi-line, wrapped to
  /// [maxWidth]) to a transparent PNG via Flutter's text engine — which performs
  /// the glyph shaping the `pdf` package cannot — returning the bytes plus the
  /// logical point size at which to display it. Embed with
  /// `pw.Image(pw.MemoryImage(png), width: width, height: height)`.
  ///
  /// [bold]/[center] style the text; [tightWidth] sizes the image to the actual
  /// rendered text width (for short inline values) instead of the full
  /// [maxWidth] (for full-width paragraphs).
  static Future<({Uint8List png, double width, double height})> renderTextImage({
    required String text,
    required double fontSize,
    required double maxWidth,
    bool bold = false,
    bool center = false,
    bool tightWidth = false,
    double lineHeight = 1.35,
    double pixelRatio = 4,
  }) async {
    await _ensureMalayalamFont();

    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: center ? ui.TextAlign.center : ui.TextAlign.left,
      fontFamily: 'NotoSansMalayalam',
      fontSize: fontSize,
      fontWeight: bold ? ui.FontWeight.bold : ui.FontWeight.normal,
      height: lineHeight,
    ))
      ..pushStyle(ui.TextStyle(color: const ui.Color(0xFF000000)))
      ..addText(text);
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: maxWidth));
    final width =
        tightWidth ? paragraph.longestLine.clamp(1.0, maxWidth) : maxWidth;
    final height = paragraph.height;

    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder)
      ..scale(pixelRatio)
      ..drawParagraph(paragraph, ui.Offset.zero);
    final picture = recorder.endRecording();
    final image = await picture.toImage(
        (width * pixelRatio).ceil(), (height * pixelRatio).ceil());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    image.dispose();

    return (png: data!.buffer.asUint8List(), width: width, height: height);
  }

  // ─── Letterhead ───────────────────────────────────────────────────────────────

  /// Shared report header: business name/address on the left, report title +
  /// date on the right, closed by a thin gold divider.
  static pw.Widget buildLetterhead({
    required String reportTitle,
    required String reportDate,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
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
  ///
  /// Pass [landscape] `true` to make the print dialog open with landscape
  /// orientation pre-selected (the plugin derives the default orientation from
  /// the [format] we hand it). Duplex/two-sided cannot be preset — Android's
  /// system print framework leaves that to the per-printer dialog options.
  static Future<void> printDocument({
    required pw.Document pdf,
    required String documentName,
    bool landscape = false,
  }) async {
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: documentName,
      format: landscape ? PdfPageFormat.a4.landscape : PdfPageFormat.standard,
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
