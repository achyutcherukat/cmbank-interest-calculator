import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/constants/business_info.dart';
import '../../core/services/print_service.dart';
import '../../shared/widgets/flow_widgets.dart' show money;
import '../ledger/data/chart_of_accounts_repository.dart';
import '../pledges/data/payment_model.dart';
import '../pledges/data/payments_repository.dart';
import '../pledges/data/pledge_repository.dart';
import 'data/bank_account_repository.dart';
import 'data/daily_account_balance_model.dart';
import 'data/daily_account_balance_repository.dart';
import 'data/daily_balance_repository.dart';

/// Builds the printable Cash Book PDF for a single locked business day.
///
/// Data is pulled through the same repositories the Cash Book screen uses, so
/// the printout always matches what the screen shows. Only locked days can be
/// printed — [generate] throws if the day is not locked.
///
/// Layout is tuned for a black & white laser printer: no colour fills (only
/// black / white / light-grey), visual hierarchy from bold text + borders. All
/// tables share identical column widths so the Cash / Bank / Total figures line
/// up vertically top-to-bottom for easy tallying on a calculator.
class CashBookPrintReport {
  const CashBookPrintReport._();

  // ─── B&W palette ─────────────────────────────────────────────────────────────
  static const PdfColor _black = PdfColors.black;
  static const PdfColor _white = PdfColors.white;
  static const PdfColor _greyRow = PdfColors.grey200;
  static const PdfColor _greyText = PdfColors.grey600;

  // Shared column geometry. No dedicated Bank Account column — the bank name
  // for a bank-routed row is appended in brackets at the end of Remarks
  // instead, freeing width that goes mostly to Remarks with the rest spread
  // across the others. The opening/closing tables collapse the first three
  // (Time + Remarks + Pledge No = 1.3 + 3.8 + 1.7 = 6.8) into one label
  // column, so every Cash / Bank / Total boundary lands at the same
  // x-position across all tables.
  static const Map<int, pw.TableColumnWidth> _sixCol = {
    0: pw.FlexColumnWidth(1.3), // Time
    1: pw.FlexColumnWidth(3.8), // Remarks
    2: pw.FlexColumnWidth(1.7), // Pledge No
    3: pw.FlexColumnWidth(1.8), // Cash
    4: pw.FlexColumnWidth(1.8), // Bank
    5: pw.FlexColumnWidth(2.0), // Total
  };
  static const Map<int, pw.TableColumnWidth> _fourCol = {
    0: pw.FlexColumnWidth(6.8), // Label (spans Time + Remarks + Pledge No)
    1: pw.FlexColumnWidth(1.8), // Cash
    2: pw.FlexColumnWidth(1.8), // Bank
    3: pw.FlexColumnWidth(2.0), // Total
  };

  /// [businessDate] is the DB date string ('YYYY-MM-DD').
  static Future<pw.Document> generate(String businessDate) async {
    final balance =
        await DailyBalanceRepository.instance.getForDate(businessDate);
    if (balance == null || !balance.isLocked) {
      throw StateError('Cash Book can only be printed for a locked day.');
    }

    final inPayments =
        await PaymentsRepository.instance.getPaymentsInForDate(businessDate);
    final outPayments =
        await PaymentsRepository.instance.getPaymentsOutForDate(businessDate);

    // Resolve pledge numbers + customer names for linked rows (cached per
    // pledge). Customer name is blank when the pledge has no snapshot.
    final pledgeNos = <int, String>{};
    final customerNames = <int, String>{};
    for (final p in [...inPayments, ...outPayments]) {
      final id = p.pledgeId;
      if (id != null && !pledgeNos.containsKey(id)) {
        final pledge = await PledgeRepository.instance.getPledgeById(id);
        pledgeNos[id] = pledge?.pledgeNumber ?? '';
        customerNames[id] = pledge?.customerName ?? '';
      }
    }

    // Chart-of-accounts names — CAPITAL rows reference the partner solely by
    // ledger_account_id, so labels resolve the current name at print time.
    final ledgerNames = <int, String>{
      for (final a in await ChartOfAccountsRepository.instance.getAll())
        if (a.id != null) a.id!: a.name,
    };

    // Bank account names, keyed by bank_account_id — resolves the current
    // name at print time (renames shouldn't stale-date old printouts).
    final bankAccountNames = <int, String>{
      for (final b in await BankAccountRepository.instance.getAll())
        if (b.id != null) b.id!: b.name,
    };

    // Per-account Opening/In/Out/Closing for the Bank Breakdown section — day
    // is already confirmed locked above, so the frozen daily_account_balance
    // rows are read directly (same data the on-screen Bank Breakdown uses).
    final bankTotals = await DailyAccountBalanceRepository.instance
        .getTotalsForDate(businessDate, isLocked: true, dailyBalanceId: balance.id);

    // Noto Sans includes the ₹ glyph (U+20B9), which the default PDF font
    // (Helvetica) lacks. Set it as the document theme so every pw.Text renders
    // the rupee sign correctly without per-widget font wiring. Loaded from a
    // bundled asset (not google_fonts' runtime fetch) so it works offline.
    final baseFont = await PrintService.notoSansRegular();
    final boldFont = await PrintService.notoSansBold();
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
    );

    final cashIn = _sum(inPayments, (p) => p.cashAmount);
    final bankIn = _sum(inPayments, (p) => p.bankAmount);
    final cashOut = _sum(outPayments, (p) => p.cashAmount);
    final bankOut = _sum(outPayments, (p) => p.bankAmount);

    // Closing values are frozen on the locked row.
    final closingCash = balance.closingCash ?? balance.openingCash;
    final closingBank = balance.closingUpi ?? balance.openingUpi;

    // Print timestamp is fixed for the whole document (shown on every page).
    final now = DateTime.now();
    final printStamp = '${_two(now.day)}/${_two(now.month)}/${now.year} '
        '${_two(now.hour)}:${_two(now.minute)}';
    final reportDate = _ddmmyyyy(businessDate);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 22),
        header: (context) => _letterhead(reportDate),
        footer: (context) => _footer(context, printStamp),
        build: (context) => [
          // Reads straight down: opening → money in → money out → closing,
          // each block visually separated by a gap.
          _openingTable(balance),
          pw.SizedBox(height: 14),
          _movementSection(
            title: 'MONEY IN',
            payments: inPayments,
            pledgeNos: pledgeNos,
            customerNames: customerNames,
            ledgerNames: ledgerNames,
            bankAccountNames: bankAccountNames,
            isIn: true,
            cashTotal: cashIn,
            bankTotal: bankIn,
          ),
          pw.SizedBox(height: 14),
          _movementSection(
            title: 'MONEY OUT',
            payments: outPayments,
            pledgeNos: pledgeNos,
            customerNames: customerNames,
            ledgerNames: ledgerNames,
            bankAccountNames: bankAccountNames,
            isIn: false,
            cashTotal: cashOut,
            bankTotal: bankOut,
          ),
          pw.SizedBox(height: 14),
          _closingTable(closingCash, closingBank),
          if (bankTotals.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            _bankBreakdownSection(bankTotals),
          ],
        ],
      ),
    );

    return doc;
  }

  // ─── Letterhead (every page, black divider) ──────────────────────────────────

  static pw.Widget _letterhead(String reportDate) {
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
                pw.Text('Cash Book',
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
        pw.SizedBox(height: 10),
      ],
    );
  }

  // ─── Footer (every page: printed-on + page X of Y) ───────────────────────────

  static pw.Widget _footer(pw.Context context, String printStamp) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(height: 0.5, color: _black),
        pw.SizedBox(height: 4),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Printed on $printStamp',
                style: const pw.TextStyle(fontSize: 9, color: _greyText)),
            pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
                style: const pw.TextStyle(fontSize: 9, color: _greyText)),
          ],
        ),
      ],
    );
  }

  // ─── Opening balance (5-column, aligned with movement tables) ────────────────

  static pw.Widget _openingTable(DailyBalance b) {
    final total = b.openingCash + b.openingUpi;
    return pw.Table(
      columnWidths: _fourCol,
      // 0.8px grid all cells; the header/data separator is thickened to 1.5px.
      border: pw.TableBorder(
        top: const pw.BorderSide(color: _black, width: 0.8),
        bottom: const pw.BorderSide(color: _black, width: 0.8),
        left: const pw.BorderSide(color: _black, width: 0.8),
        right: const pw.BorderSide(color: _black, width: 0.8),
        horizontalInside: const pw.BorderSide(color: _black, width: 1.5),
        verticalInside: const pw.BorderSide(color: _black, width: 0.8),
      ),
      children: [
        pw.TableRow(children: [
          _cell('', bold: true),
          _cell('Cash', bold: true, align: pw.TextAlign.right),
          _cell('Bank', bold: true, align: pw.TextAlign.right),
          _cell('Total', bold: true, align: pw.TextAlign.right),
        ]),
        pw.TableRow(children: [
          _cell('Opening Balance', bold: true),
          _cell(money(b.openingCash), align: pw.TextAlign.right),
          _cell(money(b.openingUpi), align: pw.TextAlign.right),
          _cell(money(total), align: pw.TextAlign.right),
        ]),
      ],
    );
  }

  // ─── Money IN / OUT section (band + column headers + rows + sub-total) ────────

  static pw.Widget _movementSection({
    required String title,
    required List<PaymentModel> payments,
    required Map<int, String> pledgeNos,
    required Map<int, String> customerNames,
    required Map<int, String> ledgerNames,
    required Map<int, String> bankAccountNames,
    required bool isIn,
    required double cashTotal,
    required double bankTotal,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        // Section band: black fill, white bold text, thick black border.
        pw.Container(
          decoration: pw.BoxDecoration(
            color: _black,
            border: pw.Border.all(color: _black, width: 1.5),
          ),
          padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 6),
          child: pw.Text(title,
              style: pw.TextStyle(
                  color: _white, fontSize: 12.5, fontWeight: pw.FontWeight.bold)),
        ),
        pw.Table(
          columnWidths: _sixCol,
          children: [
            // Column headers: white bg, black bold, thick bottom border.
            pw.TableRow(children: [
              _headerCell('Time'),
              _headerCell('Remarks'),
              _headerCell('Pledge No'),
              _headerCell('Cash', align: pw.TextAlign.right),
              _headerCell('Bank', align: pw.TextAlign.right),
              _headerCell('Total', align: pw.TextAlign.right),
            ]),
            // Data rows (alternating light-grey / white).
            if (payments.isEmpty)
              pw.TableRow(children: [
                _cell('No entries.', color: _greyText),
                _cell(''),
                _cell(''),
                _cell(''),
                _cell(''),
                _cell(''),
              ])
            else
              for (var i = 0; i < payments.length; i++)
                _paymentRow(payments[i], pledgeNos, customerNames, ledgerNames,
                    bankAccountNames, isIn,
                    alt: i.isOdd),
            // Sub-total: white bg, black bold, thick top border.
            pw.TableRow(children: [
              _subtotalCell(''),
              _subtotalCell('Total'),
              _subtotalCell(''),
              _subtotalCell(money(cashTotal),
                  align: pw.TextAlign.right),
              _subtotalCell(money(bankTotal),
                  align: pw.TextAlign.right),
              _subtotalCell(money(cashTotal + bankTotal),
                  align: pw.TextAlign.right),
            ]),
          ],
        ),
      ],
    );
  }

  static pw.TableRow _paymentRow(
      PaymentModel p,
      Map<int, String> pledgeNos,
      Map<int, String> customerNames,
      Map<int, String> ledgerNames,
      Map<int, String> bankAccountNames,
      bool isIn,
      {required bool alt}) {
    final bg = alt ? _greyRow : _white;
    final total = p.cashAmount + p.bankAmount;
    // Adjustment / expense rows have no linked pledge → render a plain hyphen
    // (never null, empty, or a non-ASCII dash that the font may lack).
    final pledgeNo = p.pledgeId != null ? pledgeNos[p.pledgeId] : null;
    final remarks = _remarksWithBank(
        p, isIn, customerNames, ledgerNames, bankAccountNames);
    return pw.TableRow(
      decoration: pw.BoxDecoration(color: bg),
      children: [
        _cell(_time(p.createdAt)),
        _cell(remarks),
        _cell(pledgeNo?.isNotEmpty == true ? pledgeNo! : '-'),
        _cell(money(p.cashAmount), align: pw.TextAlign.right),
        _cell(money(p.bankAmount), align: pw.TextAlign.right),
        _cell(money(total), align: pw.TextAlign.right),
      ],
    );
  }

  // ─── Closing balance (5-column, thick outer border box) ──────────────────────

  static pw.Widget _closingTable(double cash, double bank) {
    final total = cash + bank;
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _black, width: 1.5),
      ),
      child: pw.Table(
        columnWidths: _fourCol,
        border: const pw.TableBorder(
          horizontalInside: pw.BorderSide(color: _black, width: 0.5),
          verticalInside: pw.BorderSide(color: _black, width: 0.5),
        ),
        children: [
          pw.TableRow(children: [
            _cell('', bold: true),
            _cell('Cash', bold: true, align: pw.TextAlign.right),
            _cell('Bank', bold: true, align: pw.TextAlign.right),
            _cell('Total', bold: true, align: pw.TextAlign.right),
          ]),
          pw.TableRow(children: [
            _cell('Closing Balance', bold: true, size: 13),
            _cell(money(cash),
                bold: true, size: 13, align: pw.TextAlign.right),
            _cell(money(bank),
                bold: true, size: 13, align: pw.TextAlign.right),
            _cell(money(total),
                bold: true, size: 14, align: pw.TextAlign.right),
          ]),
        ],
      ),
    );
  }

  // ─── Bank Breakdown (band + column headers + rows + totals row) ───────────────

  /// Per-bank-account Opening/In/Out/Closing for the day, mirroring the
  /// on-screen Bank Breakdown view (same [DailyAccountTotals] data, already
  /// frozen since Cash Book only prints for locked days).
  static pw.Widget _bankBreakdownSection(List<DailyAccountTotals> totals) {
    const columns = <int, pw.TableColumnWidth>{
      0: pw.FlexColumnWidth(2.6), // Bank Account
      1: pw.FlexColumnWidth(1.6), // Opening
      2: pw.FlexColumnWidth(1.6), // Bank In
      3: pw.FlexColumnWidth(1.6), // Bank Out
      4: pw.FlexColumnWidth(1.8), // Closing
    };

    final closingTotal = totals.fold(0.0, (s, t) => s + t.closingBalance);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        // Section band: black fill, white bold text, thick black border.
        pw.Container(
          decoration: pw.BoxDecoration(
            color: _black,
            border: pw.Border.all(color: _black, width: 1.5),
          ),
          padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 6),
          child: pw.Text('BANK BREAKDOWN',
              style: pw.TextStyle(
                  color: _white, fontSize: 12.5, fontWeight: pw.FontWeight.bold)),
        ),
        pw.Table(
          columnWidths: columns,
          children: [
            pw.TableRow(children: [
              _headerCell('Bank Account'),
              _headerCell('Opening', align: pw.TextAlign.right),
              _headerCell('Bank In', align: pw.TextAlign.right),
              _headerCell('Bank Out', align: pw.TextAlign.right),
              _headerCell('Closing', align: pw.TextAlign.right),
            ]),
            for (var i = 0; i < totals.length; i++)
              pw.TableRow(
                decoration:
                    pw.BoxDecoration(color: i.isOdd ? _greyRow : _white),
                children: [
                  _cell(totals[i].bankAccount.name),
                  _cell(money(totals[i].openingBalance),
                      align: pw.TextAlign.right),
                  _cell(money(totals[i].amountIn),
                      align: pw.TextAlign.right),
                  _cell(money(totals[i].amountOut),
                      align: pw.TextAlign.right),
                  _cell(money(totals[i].closingBalance),
                      align: pw.TextAlign.right),
                ],
              ),
            // Sub-total: white bg, black bold, thick top border.
            pw.TableRow(children: [
              _subtotalCell(''),
              _subtotalCell(''),
              _subtotalCell(''),
              _subtotalCell('Total Closing', align: pw.TextAlign.right),
              _subtotalCell(money(closingTotal), align: pw.TextAlign.right),
            ]),
          ],
        ),
      ],
    );
  }

  // ─── Cell builders ───────────────────────────────────────────────────────────

  static pw.Widget _cell(
    String text, {
    bool bold = false,
    double size = 10,
    PdfColor color = _black,
    pw.TextAlign align = pw.TextAlign.left,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 5),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: size,
          color: color,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  /// Column-header cell: white bg, black bold text, thick 1.5px bottom border.
  static pw.Widget _headerCell(String text,
      {pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Container(
      decoration: const pw.BoxDecoration(
        color: _white,
        border: pw.Border(bottom: pw.BorderSide(color: _black, width: 1.5)),
      ),
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 5),
      child: pw.Text(text,
          textAlign: align,
          style: pw.TextStyle(
              fontSize: 10.5, color: _black, fontWeight: pw.FontWeight.bold)),
    );
  }

  /// Sub-total cell: white bg, black bold text, thick 1.5px top border.
  static pw.Widget _subtotalCell(String text,
      {pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Container(
      decoration: const pw.BoxDecoration(
        color: _white,
        border: pw.Border(top: pw.BorderSide(color: _black, width: 1.5)),
      ),
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 5),
      child: pw.Text(text,
          textAlign: align,
          style: pw.TextStyle(
              fontSize: 10.5, color: _black, fontWeight: pw.FontWeight.bold)),
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────────

  static double _sum(List<PaymentModel> ps, double Function(PaymentModel) f) =>
      ps.fold(0.0, (s, p) => s + f(p));

  /// [_remarks] plus the bank account name in brackets appended at the very
  /// end, for any row that actually moved money through a bank account —
  /// there is no separate Bank Account column, so this is the only place that
  /// identity shows up in the printout.
  static String _remarksWithBank(
      PaymentModel p,
      bool isIn,
      Map<int, String> customerNames,
      Map<int, String> ledgerNames,
      Map<int, String> bankAccountNames) {
    final base = _remarks(p, isIn, customerNames, ledgerNames);
    final isBankTxn = p.bankAmount > 0.005 && p.bankAccountId != null;
    if (!isBankTxn) return base;
    final bankName = bankAccountNames[p.bankAccountId] ?? '';
    if (bankName.isEmpty) return base;
    return base.isEmpty ? '[$bankName]' : '$base [$bankName]';
  }

  /// Human-readable Remarks label for a payment, per report spec. Loan-linked
  /// types show the pledge's customer name (blank if none on file) instead of
  /// a type label — the Pledge No column already carries the loan identity.
  static String _remarks(PaymentModel p, bool isIn, Map<int, String> customerNames,
      Map<int, String> ledgerNames) {
    switch (p.paymentType) {
      case PaymentType.loanFullClosure:
      case PaymentType.renewalInterestPaid:
      case PaymentType.partPaymentReceived:
      case PaymentType.loanDisbursed:
      case PaymentType.loanIncreaseDisbursed:
        return p.pledgeId != null ? customerNames[p.pledgeId] ?? '' : '';
      case PaymentType.expense:
        final sub = p.subCategory ?? 'Expense';
        final notes = p.notes?.trim();
        return notes != null && notes.isNotEmpty ? '$sub : $notes' : sub;
      case PaymentType.capital:
        final kind = switch (p.subCategory) {
          PaymentSubCategory.drawings => 'Drawings',
          PaymentSubCategory.tdsPayment => 'TDS Payment',
          _ => 'Capital Contribution',
        };
        final partner = p.ledgerAccountId != null
            ? ledgerNames[p.ledgerAccountId]
            : null;
        return partner != null ? '$kind — $partner' : kind;
      case PaymentType.adjustment:
        return _adjustmentLabel(p.subCategory);
      default:
        return p.paymentType;
    }
  }

  static String _adjustmentLabel(String? sub) {
    switch (sub) {
      case PaymentSubCategory.addCash:
        return 'Cash Adjustment';
      case PaymentSubCategory.addUpi:
      case PaymentSubCategory.addBank:
        return 'Bank Adjustment';
      case PaymentSubCategory.cashToUpi:
      case PaymentSubCategory.cashToBank:
        return 'Cash to Bank Transfer';
      case PaymentSubCategory.upiToCash:
      case PaymentSubCategory.bankToCash:
        return 'Bank to Cash Transfer';
      case PaymentSubCategory.bankToBank:
        return 'Bank to Bank Transfer';
      default:
        return 'Adjustment';
    }
  }

  /// 12-hour time (h:mm AM/PM) from a created_at ISO datetime.
  static String _time(String iso) {
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '--';
    final isPm = dt.hour >= 12;
    var h = dt.hour % 12;
    if (h == 0) h = 12;
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m ${isPm ? 'PM' : 'AM'}';
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String _ddmmyyyy(String iso) {
    final parts = iso.split('-');
    if (parts.length != 3) return iso;
    return '${parts[2]}/${parts[1]}/${parts[0]}';
  }
}
