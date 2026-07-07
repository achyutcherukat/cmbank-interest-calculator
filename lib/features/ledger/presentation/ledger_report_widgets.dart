import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/services/print_service.dart';
import '../../../core/utils/ledger_amount_formatter.dart';
import '../../../shared/widgets/flow_widgets.dart';

/// "₹X Dr" / "₹X Cr" for a signed net balance (positive = debit).
/// Ledger amounts keep paise when present (conditional 2-decimal display).
String drCr(double net) {
  if (net.abs() < 0.005) return '₹0';
  return net > 0
      ? '${LedgerAmountFormatter.format(net)} Dr'
      : '${LedgerAmountFormatter.format(-net)} Cr';
}

/// Small Print/Save chooser shared by the Trial Balance, P&L and Balance
/// Sheet screens (which need no scope/date options beyond what's already on
/// screen). Returns `'print'`, `'save'`, or null if cancelled.
Future<String?> showLedgerPrintDialog({
  required BuildContext context,
  required String title,
  required String contextLine,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title,
          style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: FlowColors.primary)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(contextLine, style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 4),
          const Text('Choose print or save as PDF.',
              style: TextStyle(fontSize: 12, color: FlowColors.medText)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'save'),
          child: const Text('SAVE PDF',
              style: TextStyle(color: FlowColors.primary)),
        ),
        ElevatedButton(
          style:
              ElevatedButton.styleFrom(backgroundColor: FlowColors.primary),
          onPressed: () => Navigator.pop(ctx, 'print'),
          child: const Text('PRINT',
              style: TextStyle(color: FlowColors.textOnNavyLarge)),
        ),
      ],
    ),
  );
}

/// Shared "generate then print or save" runner for the ledger reports: shows a
/// blocking spinner while [build] produces the document, then routes it to the
/// print dialog or the save-to-Downloads flow via [PrintService], with a
/// single error path. Mirrors the General Ledger screen's own handler.
Future<void> runLedgerPdf({
  required BuildContext context,
  required Future<pw.Document> Function() build,
  required String fileName,
  required String documentName,
  required bool save,
}) async {
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  void showError() => messenger.showSnackBar(const SnackBar(
      content: Text('Could not generate the PDF. Please try again.')));

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  final pw.Document doc;
  try {
    doc = await build();
  } catch (_) {
    if (context.mounted) navigator.pop();
    showError();
    return;
  }
  if (context.mounted) navigator.pop(); // dismiss the spinner

  try {
    if (save) {
      if (!context.mounted) return;
      await PrintService.saveAsPdf(
          pdf: doc, fileName: fileName, context: context);
    } else {
      await PrintService.printDocument(
          pdf: doc, documentName: documentName);
    }
  } catch (_) {
    showError();
  }
}

/// Warning shown on every ledger report while the Opening Balance Wizard has
/// not been run — reports still render, they are just incomplete.
class OpeningBalancePendingBanner extends StatelessWidget {
  const OpeningBalancePendingBanner({super.key, required this.ledgerStartDate});

  /// ISO YYYY-MM-DD from `settings.ledger_start_date`.
  final String ledgerStartDate;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: FlowColors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: FlowColors.orange.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: FlowColors.orange, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Opening balance not yet posted — figures below reflect '
              'activity from ${isoToDisplay(ledgerStartDate)} onward only, '
              'not the full picture.',
              style: const TextStyle(
                  fontSize: 13,
                  color: FlowColors.darkText,
                  fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
