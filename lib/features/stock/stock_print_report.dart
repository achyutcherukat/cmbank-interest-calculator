import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/constants/business_info.dart';
import '../../core/services/print_service.dart';
import '../../shared/widgets/flow_widgets.dart' show money;
import '../gold_stock/data/gold_stock_repository.dart';
import '../gold_stock/data/stock_adjustments_repository.dart';

/// Builds the printable Stock Register PDF for a single locked day.
///
/// Reuses the same repository queries the Stock Register screen uses
/// (item-aggregated Gold IN/OUT, purity breakdown) so the printout matches the
/// screen. Only locked days can be printed — [generate] throws otherwise.
///
/// Layout is tuned for a black & white laser printer: no colour fills (only
/// black / white / light-grey), visual hierarchy from bold text + borders.
class StockPrintReport {
  const StockPrintReport._();

  // ─── B&W palette ─────────────────────────────────────────────────────────────
  static const PdfColor _black = PdfColors.black;
  static const PdfColor _white = PdfColors.white;
  static const PdfColor _greyRow = PdfColors.grey200;
  static const PdfColor _greyText = PdfColors.grey600;

  /// [stockDate] is the DB date string ('YYYY-MM-DD').
  static Future<pw.Document> generate(String stockDate) async {
    final record = await GoldStockRepository.instance.getForDate(stockDate);
    if (record == null || !record.isLocked) {
      throw StateError('Stock Register can only be printed for a locked day.');
    }

    final inPledges =
        await GoldStockRepository.instance.getGoldInPledges(stockDate);
    final outPledges =
        await GoldStockRepository.instance.getGoldOutPledges(stockDate);
    final adjustments = await StockAdjustmentsRepository.instance
        .getAdjustmentsForDate(stockDate);

    final logo = await PrintService.loadLogo();

    // Noto Sans includes glyphs (e.g. the U+2212 minus sign used in signed
    // adjustments) that the default PDF font (Helvetica) lacks. Set it as the
    // document theme so every pw.Text renders correctly.
    final baseFont = await PdfGoogleFonts.notoSansRegular();
    final boldFont = await PdfGoogleFonts.notoSansBold();
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 24),
        build: (context) => [
          _letterhead(logo, _ddmmyyyy(stockDate)),
          _summaryCard(record),
          pw.SizedBox(height: 14),
          _movementSection(
            title: 'GOLD IN',
            entries: inPledges,
            grossTotal: record.goldInGrossWeight,
            netTotal: record.goldInWeight,
          ),
          pw.SizedBox(height: 14),
          _movementSection(
            title: 'GOLD OUT',
            entries: outPledges,
            grossTotal: record.goldOutGrossWeight,
            netTotal: record.goldOutWeight,
          ),
          if (adjustments.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            _adjustmentsSection(adjustments),
          ],
        ],
        footer: (context) => PrintService.buildFooter(),
      ),
    );

    return doc;
  }

  // ─── Letterhead (black divider) ──────────────────────────────────────────────

  static pw.Widget _letterhead(pw.ImageProvider logo, String reportDate) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              height: 54,
              width: 54,
              child: pw.Image(logo, fit: pw.BoxFit.contain),
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(BusinessInfo.name,
                      style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                          color: _black)),
                  pw.SizedBox(height: 2),
                  pw.Text(BusinessInfo.address,
                      style: const pw.TextStyle(fontSize: 9, color: _greyText)),
                ],
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('Stock Register',
                    style: pw.TextStyle(
                        fontSize: 17,
                        fontWeight: pw.FontWeight.bold,
                        color: _black)),
                pw.SizedBox(height: 2),
                pw.Text(reportDate,
                    style: const pw.TextStyle(fontSize: 11, color: _greyText)),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Container(height: 1.2, color: _black),
        pw.SizedBox(height: 12),
      ],
    );
  }

  // ─── Summary card (boxed, bold closing row) ──────────────────────────────────

  static pw.Widget _summaryCard(DailyStockRecord r) {
    pw.TableRow row(String label, double grossWeight, double netWeight,
        {bool closing = false}) {
      final style = pw.TextStyle(
        fontSize: closing ? 12 : 10,
        fontWeight: closing ? pw.FontWeight.bold : pw.FontWeight.normal,
        color: _black,
      );
      return pw.TableRow(
        children: [
          _pad(pw.Text(label, style: style)),
          _pad(pw.Text(_grams(grossWeight),
              textAlign: pw.TextAlign.right, style: style)),
          _pad(pw.Text(_grams(netWeight),
              textAlign: pw.TextAlign.right, style: style)),
        ],
      );
    }

    // Bold header row with no border of its own — the table's own
    // horizontalInside stroke already separates it from the row below, so
    // giving it a border too would draw two lines stacked on top of each
    // other above "Opening Stock".
    final headerStyle = pw.TextStyle(
        fontSize: 9, color: _black, fontWeight: pw.FontWeight.bold);
    final headerRow = pw.TableRow(children: [
      _pad(pw.Text('', style: headerStyle)),
      _pad(pw.Text('Gross Wt', textAlign: pw.TextAlign.right, style: headerStyle)),
      _pad(pw.Text('Net Wt', textAlign: pw.TextAlign.right, style: headerStyle)),
    ]);

    // Thick outer box (headline figure) + thin internal grid; no colour fills.
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _black, width: 1.5),
      ),
      child: pw.Table(
        border: const pw.TableBorder(
          horizontalInside: pw.BorderSide(color: _black, width: 0.5),
          verticalInside: pw.BorderSide(color: _black, width: 0.5),
        ),
        columnWidths: const {
          0: pw.FlexColumnWidth(2),
          1: pw.FlexColumnWidth(1.4),
          2: pw.FlexColumnWidth(1.4),
        },
        children: [
          headerRow,
          row('Opening Stock', r.openingGrossWeight, r.openingWeight),
          row('Gold IN', r.goldInGrossWeight, r.goldInWeight),
          row('Gold OUT', r.goldOutGrossWeight, r.goldOutWeight),
          if (r.adjustmentWeight != 0 || r.adjustmentGrossWeight != 0)
            row('Adjustments', r.adjustmentGrossWeight, r.adjustmentWeight),
          row('Closing Stock', r.closingGrossWeight, r.closingWeight,
              closing: true),
        ],
      ),
    );
  }

  // ─── Gold IN / OUT section ───────────────────────────────────────────────────

  static pw.Widget _movementSection({
    required String title,
    required List<GoldPledgeEntry> entries,
    required double grossTotal,
    required double netTotal,
  }) {
    // Explicit per-column alignment — Pledge No is a plain-digit identifier,
    // not a quantity, so the text-based numeric auto-detect must not apply to
    // it (see _isNumericCell); fixing it here also keeps Item Count aligned
    // consistently between its data rows and its worded "N items" total.
    const aligns = [
      pw.TextAlign.left, // Pledge No
      pw.TextAlign.center, // Item Count
      pw.TextAlign.right, // Principal
      pw.TextAlign.right, // Gross Wt
      pw.TextAlign.right, // Net Wt
    ];

    final rows = <pw.TableRow>[
      _headerRow(['Pledge No', 'Item Count', 'Principal', 'Gross Wt', 'Net Wt'],
          aligns: aligns),
    ];

    if (entries.isEmpty) {
      rows.add(pw.TableRow(children: [
        _pad(pw.Text('No entries.',
            style: const pw.TextStyle(fontSize: 9, color: _greyText))),
        for (var i = 0; i < 4; i++) _pad(pw.SizedBox()),
      ]));
    } else {
      for (var i = 0; i < entries.length; i++) {
        final e = entries[i];
        rows.add(_dataRow([
          e.pledgeNumber.isNotEmpty ? e.pledgeNumber : '-',
          '${e.itemCount}',
          money(e.principal),
          _grams(e.grossWeight),
          _grams(e.netWeight),
        ], alt: i.isOdd, aligns: aligns));
      }
    }

    // Sub-total: sum of the Item Count column (not the daily-stock aggregate),
    // plus principal, gross weight and net weight.
    final itemCountTotal = entries.fold(0, (s, e) => s + e.itemCount);
    final principalTotal = entries.fold(0.0, (s, e) => s + e.principal);
    rows.add(_subtotalRow([
      'Total',
      '$itemCountTotal',
      money(principalTotal),
      _grams(grossTotal),
      _grams(netTotal),
    ], aligns: aligns));

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _band(title),
        pw.Table(
          columnWidths: const {
            0: pw.FlexColumnWidth(1.6), // Pledge No
            1: pw.FlexColumnWidth(1.3), // Item Count
            2: pw.FlexColumnWidth(1.8), // Principal
            3: pw.FlexColumnWidth(1.5), // Gross Wt
            4: pw.FlexColumnWidth(1.5), // Net Wt
          },
          children: rows,
        ),
      ],
    );
  }

  // ─── Adjustments section ─────────────────────────────────────────────────────

  static pw.Widget _adjustmentsSection(List<StockAdjustment> adjustments) {
    final rows = <pw.TableRow>[
      _headerRow(['Time', 'Weight Change', 'Count Change', 'Reason']),
    ];

    for (var i = 0; i < adjustments.length; i++) {
      final a = adjustments[i];
      rows.add(_dataRow([
        _time(a.createdAt),
        _signedGrams(a.weight),
        _signedCount(a.count),
        a.reason,
      ], alt: i.isOdd));
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _band('ADJUSTMENTS'),
        pw.Table(
          columnWidths: const {
            0: pw.FlexColumnWidth(1.3),
            1: pw.FlexColumnWidth(1.6),
            2: pw.FlexColumnWidth(1.4),
            3: pw.FlexColumnWidth(3.0),
          },
          children: rows,
        ),
      ],
    );
  }

  // ─── Shared builders ─────────────────────────────────────────────────────────

  static pw.Widget _pad(pw.Widget child) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 6),
        child: child,
      );

  /// Section band: black fill, white bold text, thick 1.5px black border.
  static pw.Widget _band(String title) {
    return pw.Container(
      width: double.infinity,
      decoration: pw.BoxDecoration(
        color: _black,
        border: pw.Border.all(color: _black, width: 1.5),
      ),
      padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 6),
      child: pw.Text(title,
          style: pw.TextStyle(
              color: _white, fontSize: 11, fontWeight: pw.FontWeight.bold)),
    );
  }

  /// Column-header row: white bg, black bold text, thick 1.5px bottom border.
  /// [aligns], when given, fixes each column's alignment explicitly instead of
  /// guessing from the header text (see [_dataRow]).
  static pw.TableRow _headerRow(List<String> cells,
      {List<pw.TextAlign>? aligns}) {
    return pw.TableRow(
      children: [
        for (var i = 0; i < cells.length; i++)
          pw.Container(
            decoration: const pw.BoxDecoration(
              color: _white,
              border:
                  pw.Border(bottom: pw.BorderSide(color: _black, width: 1.5)),
            ),
            padding:
                const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 6),
            child: pw.Text(
              cells[i],
              textAlign: aligns != null
                  ? aligns[i]
                  : (_isNumericHeader(cells[i])
                      ? pw.TextAlign.right
                      : pw.TextAlign.left),
              style: pw.TextStyle(
                  color: _black, fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
          ),
      ],
    );
  }

  static bool _isNumericHeader(String h) =>
      h.contains('Wt') ||
      h.contains('Weight') ||
      h.contains('Count') ||
      h.contains('Change') ||
      h.contains('Principal');

  /// Data row: alternating light-grey / white background, no fill otherwise.
  /// [aligns], when given, fixes each column's alignment explicitly — needed
  /// wherever the text-based auto-detect (bare digits = numeric) would
  /// misfire, e.g. a plain-digit pledge number is not a quantity.
  static pw.TableRow _dataRow(List<String> cells,
      {required bool alt, List<pw.TextAlign>? aligns}) {
    return pw.TableRow(
      decoration: pw.BoxDecoration(color: alt ? _greyRow : _white),
      children: [
        for (var i = 0; i < cells.length; i++)
          _pad(pw.Text(
            cells[i],
            textAlign: aligns != null
                ? aligns[i]
                : (_isNumericCell(cells[i])
                    ? pw.TextAlign.right
                    : pw.TextAlign.left),
            style: const pw.TextStyle(fontSize: 9),
          )),
      ],
    );
  }

  /// Sub-total row: white bg, black bold text, thick 1.5px top border.
  static pw.TableRow _subtotalRow(List<String> cells,
      {List<pw.TextAlign>? aligns}) {
    return pw.TableRow(
      children: [
        for (var i = 0; i < cells.length; i++)
          pw.Container(
            decoration: const pw.BoxDecoration(
              color: _white,
              border: pw.Border(top: pw.BorderSide(color: _black, width: 1.5)),
            ),
            padding:
                const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 6),
            child: pw.Text(
              cells[i],
              textAlign: aligns != null
                  ? aligns[i]
                  : (_isNumericCell(cells[i])
                      ? pw.TextAlign.right
                      : pw.TextAlign.left),
              style: pw.TextStyle(
                  color: _black, fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
          ),
      ],
    );
  }

  // A cell is numeric (right-aligned) when it is a grams value (e.g. "22.450g",
  // "−1.000g"), a bare signed/unsigned integer count, or a ₹-formatted amount
  // (money() output, e.g. "₹1,23,000") — never a stray word that merely ends
  // in 'g' (e.g. a customer name).
  static bool _isNumericCell(String s) =>
      RegExp(r'^[+−-]?[\d.,]+g$').hasMatch(s) ||
      RegExp(r'^[+−-]?\d+$').hasMatch(s) ||
      RegExp(r'^₹[\d,]+$').hasMatch(s);

  // ─── Formatters & label helpers ──────────────────────────────────────────────

  static String _grams(double w) => '${w.toStringAsFixed(3)}g';

  static String _signedGrams(double w) {
    final sign = w > 0 ? '+' : (w < 0 ? '−' : '');
    return '$sign${w.abs().toStringAsFixed(3)}g';
  }

  static String _signedCount(int c) {
    if (c > 0) return '+$c';
    if (c < 0) return '−${c.abs()}';
    return '0';
  }

  /// 12-hour time (h:mm AM/PM) from an ISO datetime; '--' when absent/date-only.
  static String _time(String? iso) {
    if (iso == null) return '--';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '--';
    final isPm = dt.hour >= 12;
    var h = dt.hour % 12;
    if (h == 0) h = 12;
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m ${isPm ? 'PM' : 'AM'}';
  }

  static String _ddmmyyyy(String iso) {
    final parts = iso.split('-');
    if (parts.length != 3) return iso;
    return '${parts[2]}/${parts[1]}/${parts[0]}';
  }
}
