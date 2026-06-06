import 'package:flutter/material.dart';

class HistoryDetailScreen extends StatelessWidget {
  final Map<String, dynamic> entry;

  const HistoryDetailScreen({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final principal = double.parse(entry['principal'].toString());
    final si = double.parse(entry['simpleInterest'].toString());
    final total = double.parse(entry['totalAmount'].toString());
    final note = entry['minimumChargeNote']?.toString() ?? '';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A237E),
        title: const Text('Calculation Detail',
            style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white, size: 30),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),

            // Calculated On
            Center(
              child: Text(
                'Calculated on ${_formatDateTime(entry['calculatedOn'])}',
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ),

            const SizedBox(height: 24),

            // Input Details Card
            _sectionTitle('Input Details'),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: _cardDecoration(),
              child: Column(
                children: [
                  _detailRow('Principal Amount', '₹ ${principal.toStringAsFixed(2)}'),
                  _divider(),
                  _detailRow('From Date', entry['fromDate']),
                  _divider(),
                  _detailRow('To Date', entry['toDate']),
                  _divider(),
                  _detailRow('Number of Days', '${entry['numberOfDays']} days'),
                  _divider(),
                  _detailRow('Interest Rate', '${entry['interestRate']}% per annum'),
                ],
              ),
            ),

            if (entry['notes'] != null && entry['notes'].toString().isNotEmpty) ...[
              const SizedBox(height: 24),
              _sectionTitle('Notes / Pledge Reference'),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF3949AB), width: 1.5),
                ),
                child: Text(
                  entry['notes'].toString(),
                  style: const TextStyle(fontSize: 20, color: Colors.black87),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Result Card
            _sectionTitle('Result'),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFE8EAF6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF3949AB), width: 1.5),
              ),
              child: Column(
                children: [
                  _detailRow('Simple Interest', '₹ ${si.toStringAsFixed(2)}',
                      valueColor: const Color(0xFF1A237E)),
                  _divider(),
                  _detailRow('Total Amount', '₹ ${total.toStringAsFixed(2)}',
                      valueColor: const Color(0xFF1A237E), bold: true),
                  if (note.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.info_outline,
                            color: Colors.orange, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            note,
                            style: const TextStyle(
                                fontSize: 17,
                                color: Colors.orange,
                                fontStyle: FontStyle.italic),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(title,
        style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A237E)));
  }

  Widget _detailRow(String label, String value,
      {Color? valueColor, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 18, color: Colors.black54)),
          Text(value,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: bold ? FontWeight.bold : FontWeight.w600,
                  color: valueColor ?? Colors.black87)),
        ],
      ),
    );
  }

  Widget _divider() => const Divider(height: 1, thickness: 1, color: Color(0xFFDDDDDD));

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFF3949AB), width: 1.5),
      boxShadow: [
        BoxShadow(
          color: Colors.grey.withOpacity(0.15),
          blurRadius: 6,
          offset: const Offset(0, 3),
        ),
      ],
    );
  }

  String _formatDateTime(String iso) {
    final dt = DateTime.parse(iso);
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final hour = dt.hour > 12 ? dt.hour - 12 : dt.hour == 0 ? 12 : dt.hour;
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final min = dt.minute.toString().padLeft(2, '0');
    return '${dt.day.toString().padLeft(2, '0')} ${months[dt.month]} ${dt.year} at $hour:$min $ampm';
  }
}