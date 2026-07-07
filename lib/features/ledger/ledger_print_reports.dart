import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../app/app_branding.dart';
import '../../core/constants/business_info.dart';
import '../../core/services/ledger_report_service.dart';
import '../../core/services/print_service.dart';
import '../../core/utils/ledger_amount_formatter.dart';
import 'data/chart_of_accounts_repository.dart';
import 'data/ledger_account_model.dart';

/// PDF generation for the ledger reports (Prompt 9), built for manual
/// verification of postings against production data — printed from either
/// flavor, so every header carries the flavor tag unambiguously.
///
/// Follows the Cash Book / Stock Register print conventions: A4, strict
/// black & white, Noto Sans (for the ₹ glyph), letterhead on every page,
/// output through [PrintService]'s print dialog / save-to-Downloads paths.
/// Amounts use the ledger-specific conditional-decimal formatter.
class LedgerPrintReports {
  const LedgerPrintReports._();

  // ─── B&W palette (matches the Cash Book report) ────────────────────────────
  static const PdfColor _black = PdfColors.black;
  static const PdfColor _white = PdfColors.white;
  static const PdfColor _greyText = PdfColor.fromInt(0xFF555555);
  static const PdfColor _greyRow = PdfColor.fromInt(0xFFEFEFEF);
  static const PdfColor _balanceBg = PdfColor.fromInt(0xFFE0E0E0);

  /// Business name for the report header/footer, straight from
  /// [BusinessInfo]. File names still carry the flavor via [filePrefix].
  static String get businessLabel => BusinessInfo.name;

  /// Flavor prefix for file names, e.g. `CMB_GeneralLedger_...pdf`.
  static String get filePrefix => AppBranding.flavor.toUpperCase();

  // ─── General Ledger ─────────────────────────────────────────────────────────

  /// One continuous PDF of ledger account sections for [fromDate, toDate]
  /// (ISO dates). [accountId] null = every active account, grouped by
  /// account_type in the app's canonical order; accounts with no lines AND a
  /// zero opening/closing balance are skipped in that scope (nothing to
  /// verify — printing them would only waste pages). Single-account scope
  /// always prints the account, even if empty.
  ///
  /// Sections flow continuously with black section bands rather than one
  /// page per account — the same multi-section style the Cash Book report
  /// uses, and far more print-efficient for small accounts.
  static Future<pw.Document> generalLedger({
    int? accountId,
    required String fromDate,
    required String toDate,
    required bool includeVirtual,
  }) async {
    final all = await ChartOfAccountsRepository.instance.getAll();
    final accounts = accountId != null
        ? all.where((a) => a.id == accountId).toList()
        : [
            for (final type in LedgerAccountType.all)
              ...all.where((a) => a.isActive && a.accountType == type),
          ];

    // Balance as of the day before the range = the opening balance row.
    final from = DateTime.parse(fromDate);
    final dayBeforeFrom = _isoOf(from.subtract(const Duration(days: 1)));

    final service = LedgerReportService.instance;
    final sections = <_AccountSection>[];
    for (final account in accounts) {
      final opening =
          await service.getAccountBalance(account.id!, dayBeforeFrom);
      final lines = await service.getAccountLines(
          account.id!, fromDate, toDate,
          includeVirtual: includeVirtual);
      final closing = await service.getAccountBalance(account.id!, toDate);
      if (accountId == null &&
          lines.isEmpty &&
          opening.abs() < 0.005 &&
          closing.abs() < 0.005) {
        continue;
      }
      sections.add(_AccountSection(account, opening, lines, closing));
    }

    final rangeLabel = '${_display(fromDate)} to ${_display(toDate)}';
    final doc = await _newDocument();
    final logo = await PrintService.loadLogo();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 22),
        header: (context) =>
            _letterhead(logo, 'General Ledger', rangeLabel),
        footer: _footer,
        build: (context) => [
          if (sections.isEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 20),
              child: pw.Text('No transactions in this period.',
                  style: const pw.TextStyle(
                      fontSize: 11, color: _greyText)),
            )
          else
            ..._generalLedgerBody(sections,
                fromDate: fromDate, toDate: toDate),
        ],
      ),
    );
    return doc;
  }

  static List<pw.Widget> _generalLedgerBody(
    List<_AccountSection> sections, {
    required String fromDate,
    required String toDate,
  }) {
    final widgets = <pw.Widget>[];
    for (var i = 0; i < sections.length; i++) {
      final section = sections[i];
      // Each account starts on its own page — except expense accounts, which
      // flow one after another on the same page (separated by a gap + their
      // black name band) to avoid wasting a page each. The first section stays
      // on the letterhead page.
      final isExpense =
          section.account.accountType == LedgerAccountType.expense;
      final prevIsExpense = i > 0 &&
          sections[i - 1].account.accountType == LedgerAccountType.expense;
      if (i > 0) {
        if (isExpense && prevIsExpense) {
          widgets.add(pw.SizedBox(height: 18));
        } else {
          widgets.add(pw.NewPage());
        }
      }
      widgets.addAll(_accountSection(section, fromDate, toDate));
    }
    return widgets;
  }

  /// Returns the account's black name band and its table as two separate
  /// widgets (not wrapped in a Column). The table must be a direct child of
  /// the [pw.MultiPage] build list so it can span pages — nesting it inside a
  /// Column makes the whole account one unbreakable block, which throws when a
  /// high-volume account (e.g. with virtual entries) exceeds a single page.
  static List<pw.Widget> _accountSection(
      _AccountSection section, String fromDate, String toDate) {
    final account = section.account;
    final isGrouped =
        LedgerReportService.groupedViewCodes.contains(account.code);

    const columns = <int, pw.TableColumnWidth>{
      0: pw.FlexColumnWidth(1.3), // Date
      1: pw.FlexColumnWidth(3.3), // Narration
      2: pw.FlexColumnWidth(1.8), // Debit
      3: pw.FlexColumnWidth(1.8), // Credit
      4: pw.FlexColumnWidth(2.2), // Balance
    };

    var running = section.opening;
    final lineRows = <pw.TableRow>[];
    if (isGrouped) {
      final groups =
          LedgerReportService.groupByDay(section.lines, section.opening);
      for (var i = 0; i < groups.length; i++) {
        lineRows.add(_groupedPdfRow(groups[i], alt: i.isOdd));
      }
    } else {
      for (var i = 0; i < section.lines.length; i++) {
        final line = section.lines[i];
        running += line.debit - line.credit;
        lineRows.add(_lineRow(line, running, alt: i.isOdd));
      }
    }

    return [
      // Account band: black fill, white bold text. Full-width via
      // width: double.infinity now that it is not inside a stretch Column.
      pw.Container(
        width: double.infinity,
        decoration: pw.BoxDecoration(
          color: _black,
          border: pw.Border.all(color: _black, width: 1.5),
        ),
        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 6),
        child: pw.Text(
          account.name,
          style: pw.TextStyle(
              color: _white,
              fontSize: 12.5,
              fontWeight: pw.FontWeight.bold),
        ),
      ),
      // Direct MultiPage child, so it spans pages for long accounts.
      pw.Table(
        columnWidths: columns,
        children: [
          pw.TableRow(children: [
            _headerCell('Date'),
            _headerCell('Narration'),
            _headerCell('Debit', align: pw.TextAlign.right),
            _headerCell('Credit', align: pw.TextAlign.right),
            _headerCell('Balance', align: pw.TextAlign.right),
          ]),
          _balanceRow('Opening Balance', _display(fromDate),
              section.opening),
          ...lineRows,
          if (section.lines.isEmpty)
            pw.TableRow(children: [
              _cell('No transactions in this period.', color: _greyText),
              _cell(''),
              _cell(''),
              _cell(''),
              _cell(''),
            ]),
          _balanceRow(
              'Closing Balance', _display(toDate), section.closing,
              emphasized: true),
        ],
      ),
    ];
  }

  static pw.TableRow _lineRow(GeneralLedgerLine line, double running,
      {required bool alt}) {
    final isDebit = line.debit > 0;
    // Reversed entries stay in the list (they cancel against their
    // reversal) — marked so the reader knows why both appear.
    final marker = line.isReversed ? '[REVERSED]' : '';
    final text = _pdfSafe(line.narration);
    final narration = marker.isEmpty ? text : '$marker $text';
    final textColor = line.isReversed ? _greyText : _black;

    return pw.TableRow(
      decoration: pw.BoxDecoration(color: alt ? _greyRow : _white),
      children: [
        _cell(_display(line.entryDate), color: textColor),
        _cell(narration, color: textColor),
        _cell(isDebit ? LedgerAmountFormatter.format(line.debit) : '',
            align: pw.TextAlign.right, color: textColor),
        _cell(!isDebit ? LedgerAmountFormatter.format(line.credit) : '',
            align: pw.TextAlign.right, color: textColor),
        _cell(_drCr(running), align: pw.TextAlign.right, color: textColor),
      ],
    );
  }

  static pw.TableRow _groupedPdfRow(DayGroupedLine group,
      {required bool alt}) {
    final isCredit = group.isCredit;
    return pw.TableRow(
      decoration: pw.BoxDecoration(color: alt ? _greyRow : _white),
      children: [
        _cell(_display(group.date)),
        _cell(group.narration), // "By Cash" or "To Cash"
        _cell(
            !isCredit
                ? LedgerAmountFormatter.format(group.totalDebit)
                : '',
            align: pw.TextAlign.right),
        _cell(
            isCredit
                ? LedgerAmountFormatter.format(group.totalCredit)
                : '',
            align: pw.TextAlign.right),
        _cell(_drCr(group.runningBalance), align: pw.TextAlign.right),
      ],
    );
  }

  static pw.TableRow _balanceRow(String label, String date, double balance,
      {bool emphasized = false}) {
    pw.Widget bold(String text, {pw.TextAlign align = pw.TextAlign.left}) =>
        pw.Padding(
          padding:
              const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 4),
          child: pw.Text(text,
              textAlign: align,
              style: pw.TextStyle(
                  fontSize: 10.5,
                  fontWeight: pw.FontWeight.bold,
                  color: _black)),
        );
    return pw.TableRow(
      decoration: pw.BoxDecoration(
        color: _balanceBg,
        border: emphasized
            ? const pw.Border(
                top: pw.BorderSide(color: _black, width: 1))
            : null,
      ),
      children: [
        bold(date),
        bold(label),
        bold(''),
        bold(''),
        bold(_drCr(balance), align: pw.TextAlign.right),
      ],
    );
  }

  // ─── Trial Balance ──────────────────────────────────────────────────────────

  /// Every active account's net balance as of [asOfDate], grouped by account
  /// type, each shown in the Debit or Credit column matching its actual sign.
  /// Totals of the two columns must always be equal; a mismatch prints a loud
  /// note (it means a posting-engine bug, per the on-screen report).
  static Future<pw.Document> trialBalance({
    required String asOfDate,
    required bool includeZero,
  }) async {
    final all = await LedgerReportService.instance.getTrialBalance(asOfDate);
    final rows = includeZero
        ? all
        : all.where((r) => r.net.abs() >= 0.005).toList();
    final totalDebits =
        rows.where((r) => r.net > 0).fold(0.0, (s, r) => s + r.net);
    final totalCredits =
        rows.where((r) => r.net < 0).fold(0.0, (s, r) => s - r.net);
    final mismatch = ((totalDebits - totalCredits) * 100).round() != 0;

    const columns = <int, pw.TableColumnWidth>{
      0: pw.FlexColumnWidth(3.6), // Account
      1: pw.FlexColumnWidth(1.7), // Debit
      2: pw.FlexColumnWidth(1.7), // Credit
    };

    final tableRows = <pw.TableRow>[
      pw.TableRow(children: [
        _headerCell('Account'),
        _headerCell('Debit', align: pw.TextAlign.right),
        _headerCell('Credit', align: pw.TextAlign.right),
      ]),
    ];
    for (final type in LedgerAccountType.all) {
      final group = rows.where((r) => r.accountType == type).toList();
      if (group.isEmpty) continue;
      tableRows.add(_typeSubheaderRow(_typeLabel(type), 3));
      for (var i = 0; i < group.length; i++) {
        final r = group[i];
        final isDebit = r.net > 0;
        final isZero = r.net.abs() < 0.005;
        tableRows.add(pw.TableRow(
          decoration: pw.BoxDecoration(color: i.isOdd ? _greyRow : _white),
          children: [
            _cell(r.name),
            _cell(!isZero && isDebit
                ? LedgerAmountFormatter.format(r.net)
                : '', align: pw.TextAlign.right),
            _cell(!isZero && !isDebit
                ? LedgerAmountFormatter.format(-r.net)
                : '', align: pw.TextAlign.right),
          ],
        ));
      }
    }
    tableRows.add(_totalsTableRow(mismatch ? 'TOTALS — MISMATCH' : 'TOTALS', [
      LedgerAmountFormatter.format(totalDebits),
      LedgerAmountFormatter.format(totalCredits),
    ]));

    final doc = await _newDocument();
    final logo = await PrintService.loadLogo();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 22),
      header: (context) =>
          _letterhead(logo, 'Trial Balance', 'As of ${_display(asOfDate)}'),
      footer: _footer,
      build: (context) => [
        pw.Table(columnWidths: columns, children: tableRows),
        if (mismatch)
          _mismatchNote(
              'Debits and credits do not match — this indicates a posting '
              'bug, not a data-entry problem.'),
      ],
    ));
    return doc;
  }

  // ─── Profit & Loss ──────────────────────────────────────────────────────────

  /// Income and expense account movements for [fromDate, toDate], with Total
  /// Income, Total Expenses and the Net Profit / Net Loss highlighted.
  static Future<pw.Document> profitLoss({
    required String fromDate,
    required String toDate,
    required bool includeZero,
  }) async {
    final service = LedgerReportService.instance;
    final income = await service.getTypeMovements('income', fromDate, toDate);
    final expenses =
        await service.getTypeMovements('expense', fromDate, toDate);
    // Income accounts are credit-natured (figure = −net); expenses = net.
    double incomeValue(TrialBalanceRow r) => -r.net;
    double expenseValue(TrialBalanceRow r) => r.net;
    List<TrialBalanceRow> visible(List<TrialBalanceRow> rows) => includeZero
        ? rows
        : rows.where((r) => r.net.abs() >= 0.005).toList();
    final totalIncome = income.fold(0.0, (s, r) => s + incomeValue(r));
    final totalExpenses = expenses.fold(0.0, (s, r) => s + expenseValue(r));
    final net = totalIncome - totalExpenses;

    const columns = <int, pw.TableColumnWidth>{
      0: pw.FlexColumnWidth(4.2), // Account
      1: pw.FlexColumnWidth(1.8), // Amount
    };

    pw.Widget sectionTable(
        String title, List<TrialBalanceRow> rows,
        double Function(TrialBalanceRow) value) {
      final tableRows = <pw.TableRow>[
        pw.TableRow(children: [
          _headerCell(title),
          _headerCell('Amount', align: pw.TextAlign.right),
        ]),
      ];
      if (rows.isEmpty) {
        tableRows.add(pw.TableRow(children: [
          _cell('No activity in this period.', color: _greyText),
          _cell(''),
        ]));
      } else {
        for (var i = 0; i < rows.length; i++) {
          tableRows.add(pw.TableRow(
            decoration: pw.BoxDecoration(color: i.isOdd ? _greyRow : _white),
            children: [
              _cell(rows[i].name),
              _cell(LedgerAmountFormatter.format(value(rows[i])),
                  align: pw.TextAlign.right),
            ],
          ));
        }
      }
      return pw.Table(columnWidths: columns, children: tableRows);
    }

    final doc = await _newDocument();
    final logo = await PrintService.loadLogo();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 22),
      header: (context) => _letterhead(logo, 'Profit & Loss',
          '${_display(fromDate)} to ${_display(toDate)}'),
      footer: _footer,
      build: (context) => [
        sectionTable('Income', visible(income), incomeValue),
        pw.SizedBox(height: 12),
        sectionTable('Expenses', visible(expenses), expenseValue),
        _summaryBox([
          _summaryLine(
              'Total Income', LedgerAmountFormatter.format(totalIncome)),
          _summaryLine('Total Expenses',
              LedgerAmountFormatter.format(totalExpenses)),
          _thinDivider(),
          _summaryLine(net >= 0 ? 'NET PROFIT' : 'NET LOSS',
              LedgerAmountFormatter.format(net.abs()),
              emphasized: true),
        ]),
      ],
    ));
    return doc;
  }

  // ─── Balance Sheet ──────────────────────────────────────────────────────────

  /// Assets vs Liabilities + Capital as of [asOfDate], including the computed,
  /// display-only "Current Year Earnings (Unposted)" line (ledger start →
  /// as-of date), clearly marked as not a posted balance. Ends with the
  /// balance check.
  static Future<pw.Document> balanceSheet({
    required String asOfDate,
    required String ledgerStartDate,
  }) async {
    final service = LedgerReportService.instance;
    final allRows = await service.getTrialBalance(asOfDate);
    final earnings = ledgerStartDate.isEmpty
        ? 0.0
        : await service.getEarnings(ledgerStartDate, asOfDate);

    List<TrialBalanceRow> ofType(String type) => allRows
        .where((r) => r.accountType == type && r.net.abs() >= 0.005)
        .toList();
    final totalAssets = allRows
        .where((r) => r.accountType == LedgerAccountType.asset)
        .fold(0.0, (s, r) => s + r.net);
    final totalLiabilities = allRows
        .where((r) => r.accountType == LedgerAccountType.liability)
        .fold(0.0, (s, r) => s - r.net);
    final totalPostedCapital = allRows
        .where((r) => r.accountType == LedgerAccountType.capital)
        .fold(0.0, (s, r) => s - r.net);
    final totalLiabCapEarnings =
        totalLiabilities + totalPostedCapital + earnings;
    final mismatch =
        ((totalAssets - totalLiabCapEarnings) * 100).round() != 0;

    const columns = <int, pw.TableColumnWidth>{
      0: pw.FlexColumnWidth(4.2), // Account
      1: pw.FlexColumnWidth(1.8), // Amount
    };

    // Section table for assets / liabilities. [debitNatured] assets show net;
    // liabilities show −net (credit-natured).
    pw.Widget sectionTable(String title, String type,
        {required bool debitNatured}) {
      final rows = ofType(type);
      final tableRows = <pw.TableRow>[
        pw.TableRow(children: [
          _headerCell(title),
          _headerCell('Amount', align: pw.TextAlign.right),
        ]),
      ];
      if (rows.isEmpty) {
        tableRows.add(pw.TableRow(children: [
          _cell('No balances.', color: _greyText),
          _cell(''),
        ]));
      } else {
        for (var i = 0; i < rows.length; i++) {
          final v = debitNatured ? rows[i].net : -rows[i].net;
          tableRows.add(pw.TableRow(
            decoration: pw.BoxDecoration(color: i.isOdd ? _greyRow : _white),
            children: [
              _cell(rows[i].name),
              _cell(LedgerAmountFormatter.format(v),
                  align: pw.TextAlign.right),
            ],
          ));
        }
      }
      return pw.Table(columnWidths: columns, children: tableRows);
    }

    // Capital section carries the extra unposted-earnings row.
    pw.Widget capitalTable() {
      final rows = ofType(LedgerAccountType.capital);
      final tableRows = <pw.TableRow>[
        pw.TableRow(children: [
          _headerCell('Capital'),
          _headerCell('Amount', align: pw.TextAlign.right),
        ]),
      ];
      for (var i = 0; i < rows.length; i++) {
        tableRows.add(pw.TableRow(
          decoration: pw.BoxDecoration(color: i.isOdd ? _greyRow : _white),
          children: [
            _cell(rows[i].name),
            _cell(LedgerAmountFormatter.format(-rows[i].net),
                align: pw.TextAlign.right),
          ],
        ));
      }
      tableRows.add(pw.TableRow(
        decoration: const pw.BoxDecoration(color: _balanceBg),
        children: [
          _cell(
              'Current Year Earnings (Unposted — transfers to Partner '
              'Capital at year-end close)',
              color: _black),
          _cell(LedgerAmountFormatter.format(earnings),
              align: pw.TextAlign.right),
        ],
      ));
      return pw.Table(columnWidths: columns, children: tableRows);
    }

    final doc = await _newDocument();
    final logo = await PrintService.loadLogo();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 22),
      header: (context) =>
          _letterhead(logo, 'Balance Sheet', 'As of ${_display(asOfDate)}'),
      footer: _footer,
      build: (context) => [
        sectionTable('Assets', LedgerAccountType.asset, debitNatured: true),
        pw.SizedBox(height: 12),
        sectionTable('Liabilities', LedgerAccountType.liability,
            debitNatured: false),
        pw.SizedBox(height: 12),
        capitalTable(),
        _summaryBox([
          _summaryLine(
              'Total Assets', LedgerAmountFormatter.format(totalAssets)),
          _summaryLine('Total Liabilities',
              LedgerAmountFormatter.format(totalLiabilities)),
          _summaryLine('Total Capital (posted)',
              LedgerAmountFormatter.format(totalPostedCapital)),
          _summaryLine('Current Year Earnings (unposted)',
              LedgerAmountFormatter.format(earnings)),
          _thinDivider(),
          _summaryLine(
              'Balance Check (Assets vs Liabilities + Capital + Earnings)',
              '${LedgerAmountFormatter.format(totalAssets)} vs '
                  '${LedgerAmountFormatter.format(totalLiabCapEarnings)}',
              emphasized: true),
        ]),
        if (mismatch)
          _mismatchNote(
              'Assets do not equal Liabilities + Capital + Earnings — this '
              'indicates a posting bug, not a data-entry problem.'),
      ],
    ));
    return doc;
  }

  // ─── Shared building blocks (reused by the other ledger reports) ────────────

  /// Noto Sans document theme — same font setup as the Cash Book report, so
  /// the ₹ glyph renders.
  static Future<pw.Document> _newDocument() async {
    final baseFont = await PdfGoogleFonts.notoSansRegular();
    final boldFont = await PdfGoogleFonts.notoSansBold();
    return pw.Document(
      theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
    );
  }

  /// Letterhead on every page: business + flavor tag, report title, the
  /// report's own date/period context, and the generation timestamp.
  static pw.Widget _letterhead(
      pw.ImageProvider logo, String reportTitle, String reportContext) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              height: 50,
              width: 50,
              child: pw.Image(logo, fit: pw.BoxFit.contain),
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(businessLabel,
                      style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                          color: _black)),
                  pw.SizedBox(height: 2),
                  pw.Text(BusinessInfo.address,
                      style: const pw.TextStyle(
                          fontSize: 9, color: _greyText)),
                  pw.SizedBox(height: 2),
                  pw.Text('Generated on ${_nowStamp()}',
                      style: const pw.TextStyle(
                          fontSize: 9, color: _greyText)),
                ],
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(reportTitle,
                    style: pw.TextStyle(
                        fontSize: 15,
                        fontWeight: pw.FontWeight.bold,
                        color: _black)),
                pw.SizedBox(height: 2),
                pw.Text(reportContext,
                    style: const pw.TextStyle(
                        fontSize: 10, color: _greyText)),
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

  static pw.Widget _footer(pw.Context context) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.SizedBox(height: 6),
        pw.Container(height: 0.5, color: _greyText),
        pw.SizedBox(height: 3),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(businessLabel,
                style: const pw.TextStyle(fontSize: 8, color: _greyText)),
            pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
                style: const pw.TextStyle(fontSize: 8, color: _greyText)),
          ],
        ),
      ],
    );
  }

  static pw.Widget _headerCell(String text,
      {pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Container(
      decoration: const pw.BoxDecoration(
        border:
            pw.Border(bottom: pw.BorderSide(color: _black, width: 1)),
      ),
      padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 4),
      child: pw.Text(text,
          textAlign: align,
          style: pw.TextStyle(
              fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: _black)),
    );
  }

  static pw.Widget _cell(String text,
      {pw.TextAlign align = pw.TextAlign.left, PdfColor color = _black}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: pw.Text(text,
          textAlign: align,
          style: pw.TextStyle(fontSize: 10, color: color)),
    );
  }

  /// Bold cell used by section subheaders and totals rows.
  static pw.Widget _boldCell(String text,
      {pw.TextAlign align = pw.TextAlign.left, double fontSize = 10.5}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 4),
      child: pw.Text(text,
          textAlign: align,
          style: pw.TextStyle(
              fontSize: fontSize,
              fontWeight: pw.FontWeight.bold,
              color: _black)),
    );
  }

  /// A grey account-type band spanning [cols] columns (label in the first,
  /// blanks after) — the Trial Balance's Assets/Liabilities/… dividers.
  static pw.TableRow _typeSubheaderRow(String label, int cols) {
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: _balanceBg),
      children: [
        _boldCell(label),
        for (var i = 1; i < cols; i++) _boldCell(''),
      ],
    );
  }

  /// Bottom totals row: bold label in the first column, right-aligned bold
  /// [amounts] filling the remaining columns, with a rule above.
  static pw.TableRow _totalsTableRow(String label, List<String> amounts) {
    return pw.TableRow(
      decoration: const pw.BoxDecoration(
        color: _balanceBg,
        border: pw.Border(top: pw.BorderSide(color: _black, width: 1)),
      ),
      children: [
        _boldCell(label),
        for (final a in amounts) _boldCell(a, align: pw.TextAlign.right),
      ],
    );
  }

  /// Bordered summary block for the P&L / Balance Sheet totals.
  static pw.Widget _summaryBox(List<pw.Widget> lines) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 14),
      padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration:
          pw.BoxDecoration(border: pw.Border.all(color: _black, width: 1.2)),
      child: pw.Column(children: lines),
    );
  }

  /// One label/value line inside a [_summaryBox].
  static pw.Widget _summaryLine(String label, String value,
      {bool emphasized = false}) {
    final size = emphasized ? 12.0 : 10.5;
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Text(label,
                style: pw.TextStyle(
                    fontSize: size,
                    fontWeight: emphasized
                        ? pw.FontWeight.bold
                        : pw.FontWeight.normal,
                    color: _black)),
          ),
          pw.SizedBox(width: 10),
          pw.Text(value,
              style: pw.TextStyle(
                  fontSize: size,
                  fontWeight: pw.FontWeight.bold,
                  color: _black)),
        ],
      ),
    );
  }

  static pw.Widget _thinDivider() => pw.Container(
        margin: const pw.EdgeInsets.symmetric(vertical: 6),
        height: 0.8,
        color: _black,
      );

  static pw.Widget _mismatchNote(String text) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 12),
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration:
          pw.BoxDecoration(border: pw.Border.all(color: _black, width: 1.2)),
      child: pw.Text(text,
          style: pw.TextStyle(
              fontSize: 10, fontWeight: pw.FontWeight.bold, color: _black)),
    );
  }

  /// Plural account-type label for report section headers.
  static String _typeLabel(String? type) => switch (type) {
        'asset' => 'Assets',
        'liability' => 'Liabilities',
        'capital' => 'Capital',
        'income' => 'Income',
        'expense' => 'Expenses',
        _ => type ?? '',
      };

  // ─── Formatting helpers ──────────────────────────────────────────────────────

  static String _drCr(double net) {
    if (net.abs() < 0.005) return '₹0';
    return net > 0
        ? '${LedgerAmountFormatter.format(net)} Dr'
        : '${LedgerAmountFormatter.format(-net)} Cr';
  }

  /// The bundled Noto Sans font has no arrow glyph, so renewal/transfer
  /// narrations (e.g. "Pledge #96333 → #96325", "HDFC → PNB") print a blank
  /// box for the ₹→. Render those arrows as ASCII "->" instead — display
  /// only, the stored narration keeps the real arrow.
  static String _pdfSafe(String text) =>
      text.replaceAll('→', '->').replaceAll('⟶', '->');

  /// ISO YYYY-MM-DD → DD/MM/YYYY.
  static String _display(String iso) {
    final p = iso.split('T').first.split('-');
    if (p.length < 3) return iso;
    return '${p[2]}/${p[1]}/${p[0]}';
  }

  static String _isoOf(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String _nowStamp() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(now.day)}/${two(now.month)}/${now.year} '
        '${two(now.hour)}:${two(now.minute)}';
  }

  /// DDMMYYYY stamp for file names, e.g. `04072026`.
  static String fileStamp(String isoDate) {
    final p = isoDate.split('-');
    if (p.length < 3) return isoDate;
    return '${p[2]}${p[1]}${p[0]}';
  }
}

/// One account's printed section: opening balance, its lines in range, and
/// the closing balance.
class _AccountSection {
  const _AccountSection(this.account, this.opening, this.lines, this.closing);

  final LedgerAccount account;
  final double opening;
  final List<GeneralLedgerLine> lines;
  final double closing;
}
