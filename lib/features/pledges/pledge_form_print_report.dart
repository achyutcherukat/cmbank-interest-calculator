import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/constants/business_info.dart';
import '../../core/database/app_database.dart';
import '../../core/services/print_service.dart';
import '../../shared/widgets/flow_widgets.dart' show formatIndian;

/// A pre-rendered text image (bytes + logical point size) from
/// [PrintService.renderTextImage], used to embed shaped Malayalam text.
typedef _TextImage = ({Uint8List png, double width, double height});

/// Per-item pre-rendered images for the Articles column (only set when the
/// article/note actually contains Malayalam).
typedef _ItemImage = ({_TextImage? article, _TextImage? note});

/// Builds the two-page double-sided A4 pledge form (Form E).
///
/// Page 1 (front) is pre-filled from the pledge + customer + items. Page 2
/// (back) is a completely blank template staff fill in by hand on the physical
/// printout. B&W only (black / white) for laser printing. Rendered with
/// `pw.Page` (fixed single-page layouts) so it can never spill onto a third
/// page.
///
/// Layout mirrors the statutory pre-printed FORM E (Rule 8) pad: plain white
/// table headers with Gr./Mg. and Rs./Ps sub-columns, open table bodies with
/// vertical rules only (handwriting space), and dotted fill-in lines.
class PledgeFormPrintReport {
  const PledgeFormPrintReport._();

  static const PdfColor _black = PdfColors.black;
  static const PdfColor _grey = PdfColors.grey700;

  static const pw.BorderSide _side = pw.BorderSide(color: _black, width: 0.5);

  /// Very faint rule used above the items-table Total row.
  static const pw.BorderSide _faint =
      pw.BorderSide(color: PdfColors.grey400, width: 0.3);

  static const pw.BorderSide _dotted =
      pw.BorderSide(color: _black, width: 0.7, style: pw.BorderStyle.dotted);

  /// Dashed vertical tear guideline separating the Form E area from the (future)
  /// Pledge Card area on the right.
  static const pw.BorderSide _tearDash =
      pw.BorderSide(color: _black, width: 0.8, style: pw.BorderStyle.dashed);

  // ── Landscape page geometry (A4 landscape ≈ 29.7cm × 21cm) ──────────────────
  // The Form E content lives in the left 17cm; the right ~12.7cm is left blank
  // for a future Pledge Card. A dashed tear line sits at x = 17cm, full height,
  // on BOTH pages so a single vertical cut aligns whichever side is checked.
  static double get _leftMargin => 12 * PdfPageFormat.mm;
  static double get _topMargin => 10 * PdfPageFormat.mm;
  static double get _bottomMargin => 10 * PdfPageFormat.mm;
  static double get _tearX => 17 * PdfPageFormat.cm;
  static double get _tearGap => 8 * PdfPageFormat.mm;

  /// Usable width of the Form E content column (left of the tear line).
  static double get _contentW => _tearX - _leftMargin - _tearGap;

  /// Usable height of the Form E content column. Fixed so the front page can
  /// pin its signature block to the bottom and stretch the items table to fill.
  static double get _contentH =>
      PdfPageFormat.a4.landscape.height - _topMargin - _bottomMargin;

  /// Width of the right leftover region (right of the vertical tear line).
  static double get _rightRegionW =>
      PdfPageFormat.a4.landscape.width - _tearX;

  /// Height of the bottom tear-off strip within the right region.
  static double get _bottomStripH => 3 * PdfPageFormat.cm;

  /// Fixed label width for "2. Full Address:" so a wrapped/second line aligns
  /// under the address text, not under the label.
  static const double _addrLabelW = 84;

  /// Fixed width of the double rule under the "Rs." amount, sized to fit the
  /// largest supported amount ("Rs. 9,99,999") — not dynamic.
  static const double _amtRuleW = 95;

  static Future<pw.Document> generate(int pledgeId) async {
    final db = await AppDatabase.instance.database;

    final pledgeRows = await db.rawQuery('''
      SELECT p.pledge_no, p.start_date, p.principal_amount, p.gold_rate,
             c.name AS customer_name, c.phone,
             c.address, c.district, c.state, c.pin_code,
             c.id_proof_type, c.id_proof_number
      FROM pledges p
      LEFT JOIN customers c ON p.customer_id = c.id
      WHERE p.id = ?
    ''', [pledgeId]);
    if (pledgeRows.isEmpty) {
      throw StateError('Pledge #$pledgeId not found.');
    }
    final p = pledgeRows.first;

    final itemRows = await db.rawQuery('''
      SELECT item_type, purity, quantity, gross_weight, net_weight, notes,
             gold_rate
      FROM pledge_items
      WHERE pledge_id = ?
      ORDER BY id ASC
    ''', [pledgeId]);

    final rateRows = await db
        .rawQuery("SELECT value FROM settings WHERE key = 'interest_rate'");
    final interestRate = rateRows.isEmpty
        ? ''
        : _fmtRate(rateRows.first['value']?.toString() ?? '');

    // ── Pledge fields (null-safe) ──
    final pledgeNo = (p['pledge_no'] as String?) ?? '';
    final startDate = _ddmmyyyy(p['start_date'] as String?);
    final principal = ((p['principal_amount'] as num?) ?? 0).toDouble();
    final goldRate = ((p['gold_rate'] as num?) ?? 0).toDouble();

    final customerName = (p['customer_name'] as String?)?.trim() ?? '';
    final phone = (p['phone'] as String?)?.trim() ?? '';
    final address = (p['address'] as String?)?.trim() ?? '';
    final district = (p['district'] as String?)?.trim() ?? '';
    final state = (p['state'] as String?)?.trim() ?? '';
    final pinCode = (p['pin_code'] as String?)?.trim() ?? '';
    final idProofType = (p['id_proof_type'] as String?)?.trim() ?? '';
    final idProofNumber = (p['id_proof_number'] as String?)?.trim() ?? '';

    // ── Fonts (₹), bundled locally so they work offline ──
    final notoRegular = await PrintService.notoSansRegular();
    final notoBold = await PrintService.notoSansBold();

    // The Malayalam declaration is pre-rendered to an image by Flutter's text
    // engine (the `pdf` package can't shape Malayalam) and embedded as a picture.
    final malayalamImage = await PrintService.renderTextImage(
      text: _declarationText,
      fontSize: 8,
      maxWidth: _contentW,
    );

    // Customer name / address may be Malayalam — the `pdf` package would show
    // unknown boxes for those, so rasterize them (only when they actually
    // contain Malayalam; Latin values stay as normal, selectable text).
    final addressFull = [address, district, state, pinCode]
        .where((s) => s.isNotEmpty)
        .join(', ');
    final nameImage = _hasMalayalam(customerName)
        ? await PrintService.renderTextImage(
            text: customerName,
            fontSize: 9,
            bold: true,
            maxWidth: _contentW - 90,
            tightWidth: true)
        : null;
    final addressImage = _hasMalayalam(addressFull)
        ? await PrintService.renderTextImage(
            text: addressFull,
            fontSize: 9,
            maxWidth: _contentW - _addrLabelW - 4,
            tightWidth: true)
        : null;
    final stubNameImage = _hasMalayalam(customerName)
        ? await PrintService.renderTextImage(
            text: customerName,
            fontSize: 9,
            center: true,
            maxWidth: _rightRegionW / 3 - 8,
            tightWidth: true)
        : null;

    // Per-item article/note may be Malayalam too (notes especially) — rasterize
    // those cells the same way so they don't print as unknown boxes.
    final itemImages = <_ItemImage>[];
    for (final it in itemRows) {
      final itemType = (it['item_type'] as String?)?.trim() ?? '';
      final purity = (it['purity'] as String?)?.trim() ?? '';
      final article = purity.isNotEmpty ? '$itemType ($purity)' : itemType;
      final note = (it['notes'] as String?)?.trim() ?? '';
      itemImages.add((
        article: _hasMalayalam(article)
            ? await PrintService.renderTextImage(
                text: article,
                fontSize: 8,
                maxWidth: _articleTextW,
                tightWidth: true)
            : null,
        note: _hasMalayalam(note)
            ? await PrintService.renderTextImage(
                text: note,
                fontSize: 6.5,
                maxWidth: _articleTextW,
                tightWidth: true)
            : null,
      ));
    }

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: notoRegular, bold: notoBold),
    );

    final landscape = PdfPageFormat.a4.landscape;

    doc.addPage(
      pw.Page(
        pageFormat: landscape,
        margin: pw.EdgeInsets.zero,
        build: (context) => _pageFrame(
          _frontPage(
            notoBold: notoBold,
            malayalamImage: malayalamImage,
            nameImage: nameImage,
            addressImage: addressImage,
            pledgeNo: pledgeNo,
            startDate: startDate,
            principal: principal,
            goldRate: goldRate,
            interestRate: interestRate,
            customerName: customerName,
            phone: phone,
            address: address,
            district: district,
            state: state,
            pinCode: pinCode,
            idProofType: idProofType,
            idProofNumber: idProofNumber,
            items: itemRows,
            itemImages: itemImages,
          ),
          bottomStub: _bottomStub(
            pledgeNo: pledgeNo,
            customerName: customerName,
            nameImage: stubNameImage,
            date: startDate,
            principal: principal,
          ),
        ),
      ),
    );

    doc.addPage(
      pw.Page(
        pageFormat: landscape,
        margin: pw.EdgeInsets.zero,
        build: (context) => _pageFrame(_backPage()),
      ),
    );

    return doc;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PAGE FRAME — landscape wrapper (left Form E area + blank right + tear line)
  // ══════════════════════════════════════════════════════════════════════════

  /// Lays [child] (the Form E content) in the left 17cm region and draws the
  /// full-height dashed tear line at x = 17cm. The right ~12.7cm is left blank
  /// (reserved for a future Pledge Card). Content is given the full content box
  /// (width × height) so pages can pin blocks to the bottom / stretch to fill.
  static pw.Widget _pageFrame(pw.Widget child, {pw.Widget? bottomStub}) {
    final fmt = PdfPageFormat.a4.landscape;
    final stripTop = fmt.height - _bottomStripH;
    final third = _rightRegionW / 3;
    return pw.Stack(
      children: [
        pw.Positioned(
          left: _leftMargin,
          top: _topMargin,
          child: pw.SizedBox(width: _contentW, height: _contentH, child: child),
        ),
        // Vertical tear line at 17cm, full page height.
        pw.Positioned(
          left: _tearX,
          top: 0,
          child: pw.Container(
            width: 0.8,
            height: fmt.height,
            decoration:
                const pw.BoxDecoration(border: pw.Border(left: _tearDash)),
          ),
        ),
        // Horizontal tear line across the right leftover area, exactly 3cm from
        // the bottom — splitting the 12.7cm-wide right region into a top
        // section (12.7 × 18cm) and a bottom strip (12.7 × 3cm).
        pw.Positioned(
          left: _tearX,
          top: stripTop,
          child: pw.Container(
            width: _rightRegionW,
            height: 0.8,
            decoration:
                const pw.BoxDecoration(border: pw.Border(top: _tearDash)),
          ),
        ),
        // Two vertical tear lines splitting the bottom strip into three equal
        // sections (each 12.7/3 cm wide).
        for (var i = 1; i <= 2; i++)
          pw.Positioned(
            left: _tearX + third * i,
            top: stripTop,
            child: pw.Container(
              width: 0.8,
              height: _bottomStripH,
              decoration:
                  const pw.BoxDecoration(border: pw.Border(left: _tearDash)),
            ),
          ),
        // Middle section of the bottom strip — pledge details (front page only).
        if (bottomStub != null)
          pw.Positioned(
            left: _tearX + third,
            top: stripTop,
            child: pw.SizedBox(
                width: third, height: _bottomStripH, child: bottomStub),
          ),
      ],
    );
  }

  /// Unlabelled pledge summary printed in the middle section of the bottom
  /// tear-off strip: pledge number, customer name, pledge date, principal.
  static pw.Widget _bottomStub({
    required String pledgeNo,
    required String customerName,
    required String date,
    required double principal,
    _TextImage? nameImage,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(pledgeNo,
              textAlign: pw.TextAlign.center,
              maxLines: 1,
              style:
                  pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 3),
          if (nameImage == null)
            pw.Text(customerName,
                textAlign: pw.TextAlign.center,
                maxLines: 2,
                style: const pw.TextStyle(fontSize: 9))
          else
            pw.Image(pw.MemoryImage(nameImage.png),
                width: nameImage.width, height: nameImage.height),
          pw.SizedBox(height: 3),
          pw.Text(date,
              textAlign: pw.TextAlign.center,
              maxLines: 1,
              style: const pw.TextStyle(fontSize: 9)),
          pw.SizedBox(height: 3),
          pw.Text(_rupee(principal),
              textAlign: pw.TextAlign.center,
              maxLines: 1,
              style:
                  pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PAGE 1 — FRONT (pre-filled)
  // ══════════════════════════════════════════════════════════════════════════

  static pw.Widget _frontPage({
    required pw.Font notoBold,
    required _TextImage malayalamImage,
    _TextImage? nameImage,
    _TextImage? addressImage,
    required String pledgeNo,
    required String startDate,
    required double principal,
    required double goldRate,
    required String interestRate,
    required String customerName,
    required String phone,
    required String address,
    required String district,
    required String state,
    required String pinCode,
    required String idProofType,
    required String idProofNumber,
    required List<Map<String, dynamic>> items,
    required List<_ItemImage> itemImages,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _header(),
        pw.SizedBox(height: 2),
        _amountRow(principal, pledgeNo, startDate),
        pw.SizedBox(height: 6),
        // Fields 1–4.
        _field1(customerName, image: nameImage),
        pw.SizedBox(height: 4),
        _field2(address, district, state, pinCode, idProofType, idProofNumber,
            addressImage: addressImage),
        pw.SizedBox(height: 4),
        _field3(principal),
        pw.SizedBox(height: 4),
        _field4(interestRate),
        pw.SizedBox(height: 6),
        // Field 5 — items table. Stretches to fill the area down to the
        // bottom-pinned declaration + signature, giving a constant length with
        // ample room for ~4 rows of data.
        pw.Text('5. Description of Security furnished :',
            style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 3),
        pw.Expanded(
            child: _itemsTable(items, goldRate, principal, itemImages)),
        pw.SizedBox(height: 8),
        _malayalamDeclaration(malayalamImage),
        pw.SizedBox(height: 10),
        // Phone + Name & Signature — always at the bottom of the page.
        _signatureRow(phone),
      ],
    );
  }

  /// Centred company header. "FORM E / Rule 8" sits on the left with a matching
  /// spacer on the right so the company name + address stay page-centred. (G.L.
  /// No. and Date now live on the amount line — see [_amountRow].)
  static pw.Widget _header() {
    // Left/right reference blocks are kept the same width so the centre column
    // is truly centred across the Form E area.
    const sideBlockW = 36.0;
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: sideBlockW,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('FORM E',
                  style: pw.TextStyle(
                      fontSize: 8, fontWeight: pw.FontWeight.bold)),
              pw.Text('Rule 8', style: const pw.TextStyle(fontSize: 8)),
            ],
          ),
        ),
        // Company name (caps) + 3-line address + 2 reserved blank lines.
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(BusinessInfo.name.toUpperCase(),
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                      fontSize: 15, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 2),
              for (final l in _companyAddressLines())
                pw.Text(l,
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 8)),
              // Reserve a little space for 2 future blank lines (kept tight so
              // the amount sits close under the address).
              pw.SizedBox(height: 10),
            ],
          ),
        ),
        pw.SizedBox(width: sideBlockW),
      ],
    );
  }

  /// The "Rs. `amount`" block on the left, with G.L. No. + Date right-aligned on
  /// the same line so the header above can stay centred.
  static pw.Widget _amountRow(
      double principal, String pledgeNo, String date) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _amountBlock(principal),
        pw.Spacer(),
        pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text('GL. No: $pledgeNo',
                textAlign: pw.TextAlign.right,
                style:
                    pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.Text('Date: $date',
                textAlign: pw.TextAlign.right,
                style: const pw.TextStyle(fontSize: 11)),
          ],
        ),
      ],
    );
  }

  /// "₹ `amount`" over a fixed-width double rule ([_amtRuleW], sized for the
  /// largest supported amount). Sizes to its content so it can sit at the left
  /// of [_amountRow].
  static pw.Widget _amountBlock(double principal) {
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisSize: pw.MainAxisSize.min,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text('₹ ',
                style: pw.TextStyle(
                    fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.Text(_indian(principal),
                style: pw.TextStyle(
                    fontSize: 13, fontWeight: pw.FontWeight.bold)),
          ],
        ),
        pw.SizedBox(height: 2),
        pw.Container(width: _amtRuleW, height: 0.8, color: _black),
        pw.SizedBox(height: 1.2),
        pw.Container(width: _amtRuleW, height: 0.8, color: _black),
      ],
    );
  }

  // ── Fields 1–4 ──────────────────────────────────────────────────────────────

  static pw.Widget _field1(String name, {_TextImage? image}) {
    // Label + name on line 1; the dotted fill-in line drops to the next line
    // (matching sections 3 and 4). A Malayalam name comes in as a pre-shaped
    // image instead of a bold text span.
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        if (image == null)
          pw.RichText(
            text: pw.TextSpan(
              style: const pw.TextStyle(fontSize: 9),
              children: [
                const pw.TextSpan(text: '1. Name of Pawner: '),
                pw.TextSpan(
                    text: name,
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              ],
            ),
          )
        else
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('1. Name of Pawner: ',
                  style: const pw.TextStyle(fontSize: 9)),
              pw.Image(pw.MemoryImage(image.png),
                  width: image.width, height: image.height),
            ],
          ),
        _line(),
      ],
    );
  }

  static pw.Widget _field2(String address, String district, String state,
      String pin, String idProofType, String idProofNumber,
      {_TextImage? addressImage}) {
    // Full address as one comma-joined line (wraps to a 2nd line when long).
    final parts =
        [address, district, state, pin].where((s) => s.isNotEmpty).toList();
    final full = parts.join(', ');

    // ID proof is always shown on the line after the address (even when the
    // address wrapped). A "none" placeholder from the data counts as absent, so
    // it renders blank rather than the word "none".
    final idText = [idProofType, idProofNumber]
        .where((s) => s.isNotEmpty && s.toLowerCase() != 'none')
        .join(': ');

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: _addrLabelW,
              child: pw.Text('2. Full Address: ',
                  style: const pw.TextStyle(fontSize: 9)),
            ),
            pw.Expanded(
              child: addressImage == null
                  ? pw.Text(
                      full,
                      maxLines: 2,
                      style: const pw.TextStyle(fontSize: 9),
                    )
                  : pw.Align(
                      alignment: pw.Alignment.topLeft,
                      child: pw.Image(pw.MemoryImage(addressImage.png),
                          width: addressImage.width,
                          height: addressImage.height),
                    ),
            ),
          ],
        ),
        // ID proof on the next line, aligned under the address text (blank when
        // absent).
        if (idText.isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: _addrLabelW, top: 1),
            child: pw.Text(idText, style: const pw.TextStyle(fontSize: 9)),
          ),
        pw.SizedBox(height: 4),
        // Replaces the former Occupation / Introducer fields (B4): one extended
        // blank dotted line, no label.
        _line(),
      ],
    );
  }

  static pw.Widget _field3(double principal) {
    final words = _amountInWords(principal.toInt());
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.RichText(
          text: pw.TextSpan(
            style: const pw.TextStyle(fontSize: 9),
            children: [
              const pw.TextSpan(
                  text: '3. Amount of Principal Loan: '),
              pw.TextSpan(text: 'Rupees $words Only'),
            ],
          ),
        ),
        _line(),
      ],
    );
  }

  static pw.Widget _field4(String interestRate) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text('4. Rate of Interest Charged: $interestRate% P.A.',
            style: const pw.TextStyle(fontSize: 9)),
        _line(),
      ],
    );
  }

  // ── Field 5 — items table ─────────────────────────────────────────────────
  //
  // 9 columns (Paise sub-columns dropped; amounts carry the ₹ symbol inline):
  // Articles | No | Gross Wt. (Gr.|Mg.) | Net Wt. (Gr.|Mg.) |
  // Value per gram | Total Value | Amount Advanced
  //
  // Header and body share the same flex list so the vertical rules align. The
  // space freed by dropping the two Paise columns is given to Articles.
  static const List<int> _itemFlex = [30, 6, 7, 7, 7, 7, 11, 11, 11];

  /// Text width available inside the Articles column (its flex share minus the
  /// cell's horizontal padding) — the wrap width for article/note text/images.
  static double get _articleTextW {
    final f = _itemFlex;
    final flexSum = f.reduce((a, b) => a + b);
    return _contentW * f[0] / flexSum - 6;
  }

  static pw.Widget _itemsTable(List<Map<String, dynamic>> items,
      double goldRate, double principal, List<_ItemImage> itemImages) {
    final f = _itemFlex;

    final header = pw.Container(
      height: 28,
      decoration: pw.BoxDecoration(border: pw.Border.all(color: _black, width: 0.5)),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _thSingle('Articles', f[0]),
          _thSingle('No', f[1]),
          _thGroup('Gross Wt.', ['Gr.', 'Mg.'], [f[2], f[3]]),
          _thGroup('Net Wt.', ['Gr.', 'Mg.'], [f[4], f[5]]),
          _thSingle('Value per\ngram', f[6]),
          _thSingle('Total Value', f[7]),
          _thSingle('Amount\nAdvanced', f[8], rightBorder: false),
        ],
      ),
    );

    // A Total row is shown only when the pledge has more than one item; the
    // combined advance figure then moves onto it (leaving the per-row Amount
    // Advanced cells blank). A single-item pledge keeps the advance on its row.
    final showTotal = items.length > 1;

    final dataRows = <pw.Widget>[];
    var sumQty = 0;
    var sumGross = 0.0, sumNet = 0.0, sumValue = 0.0;
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      final itemType = (it['item_type'] as String?)?.trim() ?? '';
      final purity = (it['purity'] as String?)?.trim() ?? '';
      final article = purity.isNotEmpty ? '$itemType ($purity)' : itemType;
      final qty = ((it['quantity'] as num?) ?? 0).toInt();
      final grossWt = ((it['gross_weight'] as num?) ?? 0).toDouble();
      final netWt = ((it['net_weight'] as num?) ?? 0).toDouble();
      final gross = _grMg(grossWt);
      final net = _grMg(netWt);
      // Value/gram is the per-item, per-purity market rate captured at entry
      // time (pledge_items.gold_rate); 0 means no snapshot (pre-feature rows)
      // so fall back to the pledge-level flat rate.
      final itemRate = ((it['gold_rate'] as num?) ?? 0).toDouble();
      final rate = itemRate > 0 ? itemRate : goldRate;
      final totalValue = netWt * rate;
      final note = (it['notes'] as String?)?.trim() ?? '';

      sumQty += qty;
      sumGross += grossWt;
      sumNet += netWt;
      sumValue += totalValue;

      // The single advance figure sits on this row only when there is no Total
      // row (i.e. a single-item pledge).
      final showAdvanceHere = !showTotal;

      final imgs = i < itemImages.length ? itemImages[i] : null;
      dataRows.add(pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _tdArticleCell(article, note, f[0],
              articleImage: imgs?.article, noteImage: imgs?.note),
          _tdCell('$qty', f[1], align: pw.TextAlign.center),
          _tdCell('${gross.$1}', f[2]),
          _tdCell('${gross.$2}', f[3]),
          _tdCell('${net.$1}', f[4]),
          _tdCell('${net.$2}', f[5]),
          _tdCell(_rupee(rate), f[6]),
          _tdCell(_rupee(totalValue), f[7]),
          _tdCell(showAdvanceHere ? _rupee(principal) : '', f[8],
              bold: showAdvanceHere),
        ],
      ));
    }

    if (showTotal) {
      final gross = _grMg(sumGross);
      final net = _grMg(sumNet);
      dataRows.add(pw.Container(
        decoration: const pw.BoxDecoration(border: pw.Border(top: _faint)),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _tdCell('Total', f[0], align: pw.TextAlign.left, bold: true),
            _tdCell('$sumQty', f[1], align: pw.TextAlign.center, bold: true),
            _tdCell('${gross.$1}', f[2], bold: true),
            _tdCell('${gross.$2}', f[3], bold: true),
            _tdCell('${net.$1}', f[4], bold: true),
            _tdCell('${net.$2}', f[5], bold: true),
            _tdCell('', f[6]),
            _tdCell(_rupee(sumValue), f[7], bold: true),
            _tdCell(_rupee(principal), f[8], bold: true),
          ],
        ),
      ));
    }

    // Continuous vertical column rules, painted as a full-height background so
    // the data/total rows (and the blank handwriting area below them) all share
    // the same grid without depending on any per-row fixed height.
    final columnRules = pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        for (var c = 0; c < f.length; c++)
          pw.Expanded(
            flex: f[c],
            child: pw.Container(
              decoration: c == f.length - 1
                  ? null
                  : const pw.BoxDecoration(border: pw.Border(right: _side)),
            ),
          ),
      ],
    );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        header,
        pw.Expanded(
          child: pw.Container(
            decoration: const pw.BoxDecoration(
              border: pw.Border(left: _side, right: _side, bottom: _side),
            ),
            child: pw.Stack(
              children: [
                pw.Positioned.fill(child: columnRules),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: dataRows,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Splits a gram weight into whole grams + milligrams (e.g. 12.50 → 12/500).
  static (int, int) _grMg(double weight) {
    var gr = weight.floor();
    var mg = ((weight - gr) * 1000).round();
    if (mg >= 1000) {
      gr += 1;
      mg = 0;
    }
    return (gr, mg);
  }

  // ── Table header cells (plain white, black bold text, like the pad) ───────

  static pw.TextStyle get _thStyle =>
      pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold);

  /// Single-level header cell spanning the full header height.
  static pw.Widget _thSingle(String label, int flex,
      {bool rightBorder = true}) {
    return pw.Expanded(
      flex: flex,
      child: pw.Container(
        decoration: rightBorder
            ? const pw.BoxDecoration(border: pw.Border(right: _side))
            : null,
        alignment: pw.Alignment.center,
        padding: const pw.EdgeInsets.symmetric(horizontal: 2),
        child: pw.Text(label, textAlign: pw.TextAlign.center, style: _thStyle),
      ),
    );
  }

  /// Two-level header cell: group label on top, sub-columns underneath.
  static pw.Widget _thGroup(
      String label, List<String> subs, List<int> flexes,
      {bool rightBorder = true}) {
    var total = 0;
    for (final x in flexes) {
      total += x;
    }
    return pw.Expanded(
      flex: total,
      child: pw.Container(
        decoration: rightBorder
            ? const pw.BoxDecoration(border: pw.Border(right: _side))
            : null,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Expanded(
              child: pw.Container(
                alignment: pw.Alignment.center,
                padding: const pw.EdgeInsets.symmetric(horizontal: 1),
                child: pw.Text(label,
                    textAlign: pw.TextAlign.center, style: _thStyle),
              ),
            ),
            pw.Container(height: 0.5, color: _black),
            pw.SizedBox(
              height: 11,
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < subs.length; i++)
                    pw.Expanded(
                      flex: flexes[i],
                      child: pw.Container(
                        decoration: i < subs.length - 1
                            ? const pw.BoxDecoration(
                                border: pw.Border(right: _side))
                            : null,
                        alignment: pw.Alignment.center,
                        child: pw.Text(subs[i],
                            textAlign: pw.TextAlign.center, style: _thStyle),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Body cell — no borders (the column rules are painted as a full-height
  /// background behind the rows). Text is top-aligned so every column lines up
  /// with the first line of the (possibly multi-line) Articles cell.
  static pw.Widget _tdCell(String text, int flex,
      {bool bold = false, pw.TextAlign align = pw.TextAlign.right}) {
    return pw.Expanded(
      flex: flex,
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 3),
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.start,
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              text,
              textAlign: align,
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Articles cell — like [_tdCell] but also renders a per-item note beneath the
  /// article name, so notes sit within their own item's row rather than in a
  /// separate global section. Borderless (rules are painted behind the rows).
  static pw.Widget _tdArticleCell(String article, String note, int flex,
      {_TextImage? articleImage, _TextImage? noteImage}) {
    return pw.Expanded(
      flex: flex,
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 3),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisAlignment: pw.MainAxisAlignment.start,
          children: [
            // A Malayalam article/note arrives as a pre-shaped image.
            if (articleImage == null)
              pw.Text(article, style: const pw.TextStyle(fontSize: 8))
            else
              pw.Image(pw.MemoryImage(articleImage.png),
                  width: articleImage.width, height: articleImage.height),
            if (note.isNotEmpty)
              if (noteImage == null)
                pw.Text(note,
                    style: const pw.TextStyle(fontSize: 6.5, color: _grey))
              else
                pw.Image(pw.MemoryImage(noteImage.png),
                    width: noteImage.width, height: noteImage.height),
          ],
        ),
      ),
    );
  }

  // ── Malayalam legal declaration ───────────────────────────────────────────

  /// The statutory Malayalam declaration. Edit this string to change the wording;
  /// it is rendered to an image by Flutter's text engine (see
  /// [PrintService.renderMalayalamImage]) so the complex script shapes correctly.
  static const _declarationText =
      'മേപ്പടി പണ്ടം എൻ്റെ സ്വന്തമാണെന്നും 6 മാസത്തിനുള്ളിൽ മടക്കി എടുക്കാമെന്നും അങ്ങനെ സാധിക്കാതെ വന്നാൽ 6 മാസം കൂടുമ്പോൾ പലിശ അടച്ചു പരമാവധി 12 മാസത്തിനുള്ളിൽ പണ്ടം മടക്കിയെടുക്കാമെന്നും ബോദ്ധ്യപ്പെടുത്തുകയും സമ്മതിക്കുകയും ചെയ്തിരിക്കുന്നു.';

  static pw.Widget _malayalamDeclaration(
      ({Uint8List png, double width, double height}) img) {
    return pw.Image(
      pw.MemoryImage(img.png),
      width: img.width,
      height: img.height,
    );
  }

  // ── Signature row ─────────────────────────────────────────────────────────

  /// A signing field: an open signing area [height] tall with a line at the
  /// bottom to sign on, and a centered [label] beneath it. [dotted] chooses a
  /// dotted fill-in line vs a solid line. Shared by the page-1 signature block
  /// and the page-2 received-back acknowledgement.
  static pw.Widget _signField({
    required String label,
    required double height,
    bool dotted = false,
  }) {
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          height: height,
          decoration: pw.BoxDecoration(
            border: pw.Border(
                bottom: dotted
                    ? _dotted
                    : const pw.BorderSide(color: _black, width: 0.7)),
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(label,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
      ],
    );
  }

  static pw.Widget _signatureRow(String phone) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        // Left — phone (enlarged value).
        pw.Expanded(
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('Ph. No. ', style: const pw.TextStyle(fontSize: 9)),
              pw.Expanded(
                child: phone.isNotEmpty
                    ? pw.Text(phone,
                        style: pw.TextStyle(
                            fontSize: 11, fontWeight: pw.FontWeight.bold))
                    : _line(),
              ),
            ],
          ),
        ),
        pw.SizedBox(width: 60),
        // Right — open signing space (solid line + label below).
        pw.Expanded(
          child: _signField(
              label: 'Name & Signature', height: 16 * PdfPageFormat.mm),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PAGE 2 — BACK (blank template)
  // ══════════════════════════════════════════════════════════════════════════

  static pw.Widget _backPage() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(
            '6.  Details of amount repaid outstanding and interest remitted',
            style: const pw.TextStyle(fontSize: 9.5)),
        pw.SizedBox(height: 4),
        _repaymentTable(),
        pw.SizedBox(height: 6),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Signature of the Pawn Broker or his Agent',
              style: const pw.TextStyle(fontSize: 9)),
        ),
        // White space for the broker to sign, above the signature line. Uses the
        // height freed by the shortened section 6 table below.
        pw.SizedBox(height: 48),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.SizedBox(width: 200, child: _line()),
        ),
        pw.SizedBox(height: 16),
        // Section 7 — dotted line trails the label, as on the pad.
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text('7.  Date of redemption of Sale in Auction',
                style: const pw.TextStyle(fontSize: 9)),
            pw.Expanded(child: _line()),
          ],
        ),
        pw.SizedBox(height: 16),
        // Section 8.
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
                '8.  Name and Address of the person redeeming or purchasing '
                'at Sale in Auction',
                style: const pw.TextStyle(fontSize: 9)),
            pw.Expanded(child: _line()),
          ],
        ),
        pw.SizedBox(height: 12),
        _line(),
        pw.SizedBox(height: 12),
        _line(),
        pw.Spacer(),
        _closureSection(),
      ],
    );
  }

  // ── Section 6 repayment table ─────────────────────────────────────────────
  //
  // 8 columns (Rs./Ps sub-columns dropped; the freed width goes to the new
  // Interest Collected → Period sub-column):
  // Date | Amount Paid | Date | Amount Repaid | Balance |
  // Interest Collected (Period | Amount) | Remarks
  static const List<int> _repayFlex = [12, 11, 12, 11, 11, 20, 11, 14];

  static pw.Widget _repaymentTable() {
    final f = _repayFlex;

    final header = pw.Container(
      height: 34,
      decoration: pw.BoxDecoration(border: pw.Border.all(color: _black, width: 0.5)),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _thSingle('Date', f[0]),
          _thSingle('Amount\nPaid', f[1]),
          _thSingle('Date', f[2]),
          _thSingle('Amount\nRepaid', f[3]),
          _thSingle('Balance', f[4]),
          _thGroup('Interest Collected', ['Period', 'Amount'], [f[5], f[6]]),
          _thSingle('Remarks', f[7], rightBorder: false),
        ],
      ),
    );

    // Open handwriting area: vertical rules only, no row grid. Shortened by 20%
    // (190 → 152) to free white space for the pawn-broker signature above.
    final body = pw.Container(
      height: 152,
      decoration: const pw.BoxDecoration(
        border: pw.Border(left: _side, right: _side, bottom: _side),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          for (var c = 0; c < f.length; c++)
            pw.Expanded(
              flex: f[c],
              child: pw.Container(
                decoration: c == f.length - 1
                    ? null
                    : const pw.BoxDecoration(border: pw.Border(right: _side)),
              ),
            ),
        ],
      ),
    );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [header, body],
    );
  }

  // ── Closing summary + acknowledgement ─────────────────────────────────────

  static pw.Widget _closureSection() {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _closureTable(),
        pw.SizedBox(width: 40),
        // Received-back acknowledgement — "RECEIVED BACK" lifted level with the
        // box grid top, then Name & Signature and Date, each with the label on
        // the left and the dotted fill-in line running to the right.
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // Drop past the ₹ header row so this lines up with the grid top.
              pw.SizedBox(height: 13),
              pw.Text('RECEIVED BACK JEWELLERY INTACT',
                  style: pw.TextStyle(
                      fontSize: 10, fontWeight: pw.FontWeight.bold)),
              // Open white space to write the name and sign, above the fields.
              // Sized so the Date line lines up with the bottom of the
              // Amount/Interest/Total box on the left.
              pw.SizedBox(height: 35),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Name & Signature: ',
                      style: const pw.TextStyle(fontSize: 9)),
                  pw.Expanded(child: _line()),
                ],
              ),
              // Date sits directly below Name & Signature.
              pw.SizedBox(height: 8),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Date: ', style: const pw.TextStyle(fontSize: 9)),
                  pw.Expanded(child: _line()),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Blank Amount/Interest/Total box: a single ₹ amount column (Paise dropped),
  /// row labels outside the border on the left, empty cells for handwriting.
  static pw.Widget _closureTable() {
    const labelW = 52.0, rsW = 80.0, rowH = 26.0;

    pw.Widget boxCell({required bool lastRow}) {
      return pw.Container(
        width: rsW,
        height: rowH,
        decoration: pw.BoxDecoration(
          border: pw.Border(
            left: _side,
            top: _side,
            right: _side,
            bottom: lastRow ? _side : pw.BorderSide.none,
          ),
        ),
      );
    }

    const labels = ['Amount', 'Interest', 'Total'];
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(children: [
          pw.SizedBox(width: labelW),
          pw.SizedBox(
              width: rsW,
              child: pw.Text('₹',
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(fontSize: 9))),
        ]),
        pw.SizedBox(height: 2),
        for (var r = 0; r < labels.length; r++)
          pw.Row(children: [
            pw.Container(
              width: labelW,
              height: rowH,
              alignment: pw.Alignment.centerLeft,
              child: pw.Text(labels[r], style: const pw.TextStyle(fontSize: 9)),
            ),
            boxCell(lastRow: r == labels.length - 1),
          ]),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Shared helpers
  // ══════════════════════════════════════════════════════════════════════════

  /// A thin dotted fill-in line, matching the pre-printed pad.
  static pw.Widget _line() => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 1.5),
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: _dotted),
        ),
        child: pw.SizedBox(height: 10, width: double.infinity),
      );

  /// Splits [BusinessInfo.address] into a compact address block of up to 3
  /// lines (normal case). A 4+ part address collapses its middle parts onto the
  /// centre line so the head and tail stay on their own lines.
  static List<String> _companyAddressLines() {
    final parts = BusinessInfo.address
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.length <= 3) return parts;
    return [
      parts.first,
      parts.sublist(1, parts.length - 1).join(', '),
      parts.last,
    ];
  }

  /// Indian-grouped whole number, no symbol (e.g. 125000 → "1,25,000").
  static String _indian(num v) => formatIndian(v.round().toString());

  /// Indian-grouped amount prefixed with the ₹ symbol (the bundled Noto Sans
  /// fonts include U+20B9, so it renders in the PDF).
  static String _rupee(num v) => '₹${_indian(v)}';

  /// Matches any character in the Malayalam Unicode block — used to decide when
  /// a name/address must be rasterized (the `pdf` package can't shape Malayalam).
  static final RegExp _malayalamRe = RegExp('[ഀ-ൿ]');
  static bool _hasMalayalam(String s) => _malayalamRe.hasMatch(s);

  /// Normalises a settings rate value ("18" / "18.00") to a clean number.
  static String _fmtRate(String raw) {
    final d = double.tryParse(raw.trim());
    if (d == null) return raw.trim();
    return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
  }

  static String _ddmmyyyy(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final datePart = iso.split('T').first;
    final parts = datePart.split('-');
    if (parts.length != 3) return datePart;
    return '${parts[2]}/${parts[1]}/${parts[0]}';
  }

  // ── Amount in words (Indian numbering) ────────────────────────────────────

  static const _ones = [
    '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight',
    'Nine', 'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen',
    'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen'
  ];
  static const _tens = [
    '', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy',
    'Eighty', 'Ninety'
  ];

  /// Indian-system words for [amount], first letter of each word capitalised,
  /// without a "Rupees"/"Only" wrapper (the caller adds those).
  static String _amountInWords(int amount) {
    if (amount <= 0) return 'Zero';
    return _numToWords(amount);
  }

  static String _numToWords(int n) {
    if (n == 0) return '';
    if (n < 1000) return _threeDigits(n);
    final crore = n ~/ 10000000;
    final lakh = (n % 10000000) ~/ 100000;
    final thousand = (n % 100000) ~/ 1000;
    final below = n % 1000;
    final parts = <String>[
      if (crore > 0) '${_numToWords(crore)} ${crore > 1 ? 'Crores' : 'Crore'}',
      if (lakh > 0) '${_numToWords(lakh)} ${lakh > 1 ? 'Lakhs' : 'Lakh'}',
      if (thousand > 0) '${_numToWords(thousand)} Thousand',
      if (below > 0) _threeDigits(below),
    ];
    return parts.join(' ');
  }

  static String _threeDigits(int n) {
    final h = n ~/ 100;
    final rest = n % 100;
    final parts = <String>[
      if (h > 0) '${_ones[h]} Hundred',
      if (rest > 0) _twoDigits(rest),
    ];
    return parts.join(' ');
  }

  static String _twoDigits(int n) {
    if (n < 20) return _ones[n];
    final t = _tens[n ~/ 10];
    final o = n % 10;
    return o == 0 ? t : '$t ${_ones[o]}';
  }
}
