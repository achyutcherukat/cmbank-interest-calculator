import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/constants/business_info.dart';
import '../../core/database/app_database.dart';
import '../../core/services/print_service.dart';
import '../../shared/widgets/flow_widgets.dart' show formatIndian;

/// Builds the two-page double-sided A4 pledge form (Form E).
///
/// Page 1 (front) is pre-filled from the pledge + customer + items. Page 2
/// (back) is a completely blank template staff fill in by hand on the physical
/// printout. B&W only (black / white) for laser printing. Rendered with
/// `pw.Page` (fixed single-page layouts) so it can never spill onto a third
/// page.
class PledgeFormPrintReport {
  const PledgeFormPrintReport._();

  static const PdfColor _black = PdfColors.black;
  static const PdfColor _white = PdfColors.white;

  /// 12mm page margin in PDF points.
  static double get _margin => 12 * PdfPageFormat.mm;

  static Future<pw.Document> generate(int pledgeId) async {
    final db = await AppDatabase.instance.database;

    final pledgeRows = await db.rawQuery('''
      SELECT p.pledge_no, p.start_date, p.principal_amount, p.gold_rate,
             c.name AS customer_name, c.phone,
             c.address, c.district, c.state, c.pin_code
      FROM pledges p
      LEFT JOIN customers c ON p.customer_id = c.id
      WHERE p.id = ?
    ''', [pledgeId]);
    if (pledgeRows.isEmpty) {
      throw StateError('Pledge #$pledgeId not found.');
    }
    final p = pledgeRows.first;

    final itemRows = await db.rawQuery('''
      SELECT item_type, purity, quantity, gross_weight, net_weight
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

    // ── Fonts (₹ + Malayalam) ──
    final notoRegular = await PdfGoogleFonts.notoSansRegular();
    final notoBold = await PdfGoogleFonts.notoSansBold();
    final notoMalayalam = await PdfGoogleFonts.notoSansMalayalamRegular();

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: notoRegular, bold: notoBold),
    );

    final logo = await PrintService.loadLogo();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(_margin),
        build: (context) => _frontPage(
          logo: logo,
          notoBold: notoBold,
          notoMalayalam: notoMalayalam,
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
          items: itemRows,
        ),
      ),
    );

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(_margin),
        build: (context) => _backPage(),
      ),
    );

    return doc;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PAGE 1 — FRONT (pre-filled)
  // ══════════════════════════════════════════════════════════════════════════

  static pw.Widget _frontPage({
    required pw.ImageProvider logo,
    required pw.Font notoBold,
    required pw.Font notoMalayalam,
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
    required List<Map<String, dynamic>> items,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _header(logo, pledgeNo, startDate),
        pw.SizedBox(height: 4),
        pw.Container(height: 0.8, color: _black),
        pw.SizedBox(height: 5),
        // Amount prominence row.
        pw.Text('₹ ${_indian(principal)}',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Container(height: 0.8, color: _black),
        pw.SizedBox(height: 6),
        // Fields 1–4.
        _field1(customerName),
        pw.SizedBox(height: 5),
        _field2(address, district, state, pinCode),
        pw.SizedBox(height: 5),
        _field3(principal),
        pw.SizedBox(height: 5),
        _field4(interestRate),
        pw.SizedBox(height: 6),
        // Field 5 — items table.
        pw.Text('5. Description of Security furnished:',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 3),
        _itemsTable(items, goldRate, principal),
        pw.SizedBox(height: 8),
        _malayalamDeclaration(notoMalayalam, notoBold),
        pw.Spacer(),
        _signatureRow(phone),
      ],
    );
  }

  static pw.Widget _header(pw.ImageProvider logo, String pledgeNo, String date) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Left 20% — Form reference.
        pw.Expanded(
          flex: 20,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('FORM E',
                  style:
                      pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
              pw.Text('Rule 8', style: const pw.TextStyle(fontSize: 8)),
            ],
          ),
        ),
        // Centre 60% — logo + business name + address.
        pw.Expanded(
          flex: 60,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.SizedBox(
                  height: 45, child: pw.Image(logo, fit: pw.BoxFit.contain)),
              pw.SizedBox(height: 2),
              pw.Text(BusinessInfo.name,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                      fontSize: 15, fontWeight: pw.FontWeight.bold)),
              pw.Text(BusinessInfo.address,
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(fontSize: 8)),
            ],
          ),
        ),
        // Right 20% — GL No + Date.
        pw.Expanded(
          flex: 20,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('GL. No: $pledgeNo',
                  textAlign: pw.TextAlign.right,
                  style:
                      pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
              pw.Text('Date: $date',
                  textAlign: pw.TextAlign.right,
                  style: const pw.TextStyle(fontSize: 9)),
            ],
          ),
        ),
      ],
    );
  }

  // ── Fields 1–4 ──────────────────────────────────────────────────────────────

  static pw.Widget _field1(String name) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
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
        ),
        pw.Expanded(child: _line()),
      ],
    );
  }

  static pw.Widget _field2(
      String address, String district, String state, String pin) {
    // Compose up to three address lines, skipping any empty parts.
    final line2Parts = [district, state].where((s) => s.isNotEmpty).toList();
    final addrLines = <String>[
      if (address.isNotEmpty) address,
      if (line2Parts.isNotEmpty) line2Parts.join(', '),
      if (pin.isNotEmpty) 'PIN: $pin',
    ];

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text('2. Full Address: ',
                style: const pw.TextStyle(fontSize: 9)),
            pw.Expanded(
              child: pw.Text(
                addrLines.isNotEmpty ? addrLines.first : '',
                style: const pw.TextStyle(fontSize: 9),
              ),
            ),
          ],
        ),
        for (final l in addrLines.skip(1))
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: 12, top: 1),
            child: pw.Text(l, style: const pw.TextStyle(fontSize: 9)),
          ),
        pw.SizedBox(height: 3),
        // Occupation + Introducer — blank dotted lines only.
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text('   Occupation: ', style: const pw.TextStyle(fontSize: 9)),
            pw.Expanded(flex: 4, child: _line()),
            pw.Text('   Name of the Introducer: ',
                style: const pw.TextStyle(fontSize: 9)),
            pw.Expanded(flex: 5, child: _line()),
          ],
        ),
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
              const pw.TextSpan(text: '3. Amount of Principal loan: '),
              pw.TextSpan(
                text: 'Rupees $words Only',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
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

  static pw.Widget _itemsTable(
      List<Map<String, dynamic>> items, double goldRate, double principal) {
    const headers = [
      'Articles',
      'No',
      'Gross Wt (g)',
      'Net Wt (g)',
      'Value/gram ₹',
      'Total Value ₹',
      'Amount Advanced ₹',
    ];
    const cols = {
      0: pw.FlexColumnWidth(2.6),
      1: pw.FlexColumnWidth(0.7),
      2: pw.FlexColumnWidth(1.3),
      3: pw.FlexColumnWidth(1.3),
      4: pw.FlexColumnWidth(1.4),
      5: pw.FlexColumnWidth(1.5),
      6: pw.FlexColumnWidth(1.6),
    };

    // Header row: black bg, white bold text.
    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _black),
        children: [
          for (var i = 0; i < headers.length; i++)
            _itemCell(headers[i],
                bold: true,
                color: _white,
                align: i == 0
                    ? pw.TextAlign.left
                    : (i == 1 ? pw.TextAlign.center : pw.TextAlign.right)),
        ],
      ),
    ];

    final lastIdx = items.length - 1;
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      final itemType = (it['item_type'] as String?)?.trim() ?? '';
      final purity = (it['purity'] as String?)?.trim() ?? '';
      final article = purity.isNotEmpty ? '$itemType ($purity)' : itemType;
      final qty = ((it['quantity'] as num?) ?? 0).toInt();
      final gross = ((it['gross_weight'] as num?) ?? 0).toDouble();
      final net = ((it['net_weight'] as num?) ?? 0).toDouble();
      final totalValue = (net * goldRate).round();
      final isLast = i == lastIdx;

      rows.add(pw.TableRow(children: [
        _itemCell(article, align: pw.TextAlign.left),
        _itemCell('$qty', align: pw.TextAlign.center),
        _itemCell(gross.toStringAsFixed(2), align: pw.TextAlign.right),
        _itemCell(net.toStringAsFixed(2), align: pw.TextAlign.right),
        _itemCell(_indian(goldRate), align: pw.TextAlign.right),
        _itemCell(_indian(totalValue), align: pw.TextAlign.right),
        // Single combined advance figure on the last item row only.
        _itemCell(isLast ? _indian(principal) : '',
            bold: isLast, align: pw.TextAlign.right),
      ]));
    }

    // Pad to a minimum of 5 rows for physical-form consistency.
    final blanksNeeded = 5 - items.length;
    for (var i = 0; i < blanksNeeded; i++) {
      rows.add(pw.TableRow(
        children: [for (var c = 0; c < headers.length; c++) _itemCell('')],
      ));
    }

    return pw.Table(
      border: pw.TableBorder.all(color: _black, width: 0.5),
      columnWidths: cols,
      children: rows,
    );
  }

  static pw.Widget _itemCell(String text,
      {bool bold = false,
      PdfColor color = _black,
      pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 3),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: 8,
          color: color,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  // ── Malayalam legal declaration (mixed-script RichText) ───────────────────

  static pw.Widget _malayalamDeclaration(
      pw.Font malayalam, pw.Font boldLatin) {
    pw.TextSpan mal(String t) => pw.TextSpan(text: t);
    pw.TextSpan num(String t) => pw.TextSpan(
        text: t,
        style: pw.TextStyle(
            font: boldLatin, fontSize: 9, fontWeight: pw.FontWeight.bold));

    return pw.RichText(
      text: pw.TextSpan(
        style: pw.TextStyle(font: malayalam, fontSize: 9, lineSpacing: 4),
        children: [
          mal('മേപ്പടി പണം എന്റെ സ്വന്തമാണെന്നും.......'),
          num('6'),
          mal('......മാസത്തിനുള്ളിൽ മടക്കി എടുക്കാമെന്നും അങ്ങിനെ '
              'സാധിക്കാതെ വന്നാൽ.......'),
          num('6'),
          mal('......മാസം കൂടുമ്പോൾ പലിശ അടച്ച് പരമാവധി......'),
          num('12'),
          mal('...... മാസത്തിനുള്ളിൽ പണം മടക്കിയെടുക്കാമെന്നും '
              'ബോദ്ധ്യപ്പെടുത്തുകയും സമ്മതിക്കുകയും ചെയ്തിരിക്കുന്നു'),
        ],
      ),
    );
  }

  // ── Signature row ─────────────────────────────────────────────────────────

  static pw.Widget _signatureRow(String phone) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        // Left — phone.
        pw.Expanded(
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('Phone: ', style: const pw.TextStyle(fontSize: 9)),
              pw.Expanded(
                child: phone.isNotEmpty
                    ? pw.Text(phone, style: const pw.TextStyle(fontSize: 9))
                    : _line(),
              ),
            ],
          ),
        ),
        pw.SizedBox(width: 24),
        // Right — signature.
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.SizedBox(height: 18),
              pw.Container(height: 0.5, color: _black),
              pw.SizedBox(height: 2),
              pw.Text('Name & Signature',
                  textAlign: pw.TextAlign.right,
                  style: const pw.TextStyle(fontSize: 8)),
            ],
          ),
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
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        _repaymentTable(),
        pw.SizedBox(height: 6),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Signature of the Pawn Broker or his Agent',
              style: const pw.TextStyle(fontSize: 9)),
        ),
        pw.SizedBox(height: 4),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.SizedBox(width: 200, child: _line()),
        ),
        pw.SizedBox(height: 14),
        // Section 7.
        pw.Text('7.  Date of redemption of Sale in Auction',
            style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 6),
        _line(),
        pw.SizedBox(height: 14),
        // Section 8.
        pw.Text(
            '8.  Name and Address of the person redeeming or purchasing at '
            'Sale in Auction',
            style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 6),
        _line(),
        pw.SizedBox(height: 10),
        _line(),
        pw.SizedBox(height: 10),
        _line(),
        pw.Spacer(),
        _closureSection(),
      ],
    );
  }

  static pw.Widget _repaymentTable() {
    const headers = [
      'Date',
      'Amount Paid ₹',
      'Ps',
      'Date',
      'Amount Paid ₹',
      'Ps',
      'Balance ₹',
      'Ps',
      'Interest Collected ₹',
      'Ps',
      'Remarks',
    ];
    const cols = {
      0: pw.FlexColumnWidth(1.4),
      1: pw.FlexColumnWidth(1.6),
      2: pw.FlexColumnWidth(0.7),
      3: pw.FlexColumnWidth(1.4),
      4: pw.FlexColumnWidth(1.6),
      5: pw.FlexColumnWidth(0.7),
      6: pw.FlexColumnWidth(1.4),
      7: pw.FlexColumnWidth(0.7),
      8: pw.FlexColumnWidth(1.9),
      9: pw.FlexColumnWidth(0.7),
      10: pw.FlexColumnWidth(1.8),
    };

    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _black),
        children: [
          for (final h in headers)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 2),
              child: pw.Text(h,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                      fontSize: 7,
                      color: _white,
                      fontWeight: pw.FontWeight.bold)),
            ),
        ],
      ),
    ];

    // 10 blank rows, ≥18px tall for handwriting.
    for (var r = 0; r < 10; r++) {
      rows.add(pw.TableRow(
        children: [
          for (var c = 0; c < headers.length; c++)
            pw.Container(height: 18),
        ],
      ));
    }

    return pw.Table(
      border: pw.TableBorder.all(color: _black, width: 0.5),
      columnWidths: cols,
      children: rows,
    );
  }

  static pw.Widget _closureSection() {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Left — 3×3 blank amount table.
        pw.Expanded(
          child: pw.Table(
            border: pw.TableBorder.all(color: _black, width: 0.5),
            columnWidths: const {
              0: pw.FlexColumnWidth(1.2),
              1: pw.FlexColumnWidth(1.4),
              2: pw.FlexColumnWidth(1.2),
            },
            children: [
              _closureRow('Amount'),
              _closureRow('Interest'),
              _closureRow('Total'),
            ],
          ),
        ),
        pw.SizedBox(width: 24),
        // Right — received-back acknowledgement.
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Text('RECEIVED BACK JEWELLERY INTACT',
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(
                      fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 16),
              pw.Text('Name & Signature: .........................',
                  textAlign: pw.TextAlign.right,
                  style: const pw.TextStyle(fontSize: 9)),
              pw.SizedBox(height: 6),
              pw.Text('Date: .....................................',
                  textAlign: pw.TextAlign.right,
                  style: const pw.TextStyle(fontSize: 9)),
            ],
          ),
        ),
      ],
    );
  }

  static pw.TableRow _closureRow(String label) {
    pw.Widget cell(String t, {pw.TextAlign align = pw.TextAlign.left}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 4),
          child: pw.Text(t,
              textAlign: align, style: const pw.TextStyle(fontSize: 9)),
        );
    return pw.TableRow(children: [
      cell(label),
      cell('₹'),
      cell('Ps'),
    ]);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Shared helpers
  // ══════════════════════════════════════════════════════════════════════════

  /// A thin horizontal fill-in line.
  static pw.Widget _line() => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 1.5),
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: _black, width: 0.5)),
        ),
        child: pw.SizedBox(height: 10, width: double.infinity),
      );

  /// Indian-grouped whole number, no symbol (e.g. 125000 → "1,25,000").
  static String _indian(num v) => formatIndian(v.round().toString());

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
