import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/services/print_service.dart';
import '../../shared/widgets/flow_widgets.dart' show FlowColors;
import 'pledge_form_print_report.dart';

/// Generates the double-sided Pledge Form (Form E) for [pledgeId] and presents
/// the Print / Save-as-PDF options.
///
/// This is the shared flow used both on the New Loan success screen and from the
/// printer icon in the open-pledge detail header, so the two entry points stay
/// in sync. A modal loader is shown while the PDF is built.
Future<void> showPledgeFormPrintOptions(
  BuildContext context, {
  required int pledgeId,
  required String pledgeNo,
}) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  final pw.Document doc;
  try {
    doc = await PledgeFormPrintReport.generate(pledgeId);
  } catch (e) {
    if (!context.mounted) return;
    Navigator.pop(context); // dismiss loader
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not generate pledge form: $e')),
    );
    return;
  }

  if (!context.mounted) return;
  Navigator.pop(context); // dismiss loader
  _showPrintSheet(context, doc, pledgeNo);
}

void _showPrintSheet(BuildContext context, pw.Document doc, String pledgeNo) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 8),
          Text('Pledge Form — #$pledgeNo',
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: FlowColors.primary)),
          ListTile(
            leading: const Icon(Icons.print, color: FlowColors.primary),
            title: const Text('Print'),
            onTap: () {
              Navigator.pop(ctx);
              PrintService.printDocument(
                  pdf: doc,
                  documentName: 'PledgeForm_$pledgeNo',
                  landscape: true);
            },
          ),
          ListTile(
            leading: const Icon(Icons.save_alt, color: FlowColors.primary),
            title: const Text('Save as PDF'),
            onTap: () {
              Navigator.pop(ctx);
              PrintService.saveAsPdf(
                  pdf: doc,
                  fileName: 'PledgeForm_$pledgeNo.pdf',
                  context: context);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
