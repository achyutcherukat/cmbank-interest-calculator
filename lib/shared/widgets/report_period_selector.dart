import 'package:flutter/material.dart';

import 'flow_widgets.dart';

/// Report period options shared by Admin Reports and the ledger P&L report.
/// Quarters follow the Indian financial year (Q1 = Apr–Jun … Q4 = Jan–Mar).
enum ReportPeriod { q1, q2, q3, q4, yearly, custom }

/// ISO from/to range for [p], relative to [now]'s financial year.
/// Extracted verbatim from the Admin Reports screen so every report area
/// shares the same quarter boundaries and FY convention.
({String from, String to}) reportPeriodRange(ReportPeriod p, DateTime now,
    {DateTime? customFrom, DateTime? customTo}) {
  String fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // Indian FY: April of fyStartYear to March of fyStartYear+1
  final fyStartYear = now.month >= 4 ? now.year : now.year - 1;

  switch (p) {
    case ReportPeriod.q1: // Apr–Jun
      return (
        from: fmt(DateTime(fyStartYear, 4, 1)),
        to: fmt(DateTime(fyStartYear, 6, 30)),
      );
    case ReportPeriod.q2: // Jul–Sep
      return (
        from: fmt(DateTime(fyStartYear, 7, 1)),
        to: fmt(DateTime(fyStartYear, 9, 30)),
      );
    case ReportPeriod.q3: // Oct–Dec
      return (
        from: fmt(DateTime(fyStartYear, 10, 1)),
        to: fmt(DateTime(fyStartYear, 12, 31)),
      );
    case ReportPeriod.q4: // Jan–Mar
      return (
        from: fmt(DateTime(fyStartYear + 1, 1, 1)),
        to: fmt(DateTime(fyStartYear + 1, 3, 31)),
      );
    case ReportPeriod.yearly:
      return (
        from: fmt(DateTime(fyStartYear, 4, 1)),
        to: fmt(DateTime(fyStartYear + 1, 3, 31)),
      );
    case ReportPeriod.custom:
      final f = customFrom ?? DateTime(now.year, 4, 1);
      final t = customTo ?? now;
      return (from: fmt(f), to: fmt(t));
  }
}

/// Horizontal Q1/Q2/Q3/Q4/Yearly/Custom chip bar. The parent owns the
/// selection state and the custom-range picking flow.
class ReportPeriodBar extends StatelessWidget {
  const ReportPeriodBar({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  final ReportPeriod selected;
  final void Function(ReportPeriod period) onSelect;

  @override
  Widget build(BuildContext context) {
    const periods = [
      (ReportPeriod.q1, 'Q1'),
      (ReportPeriod.q2, 'Q2'),
      (ReportPeriod.q3, 'Q3'),
      (ReportPeriod.q4, 'Q4'),
      (ReportPeriod.yearly, 'Yearly'),
      (ReportPeriod.custom, 'Custom'),
    ];

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: periods.map((pair) {
            final active = selected == pair.$1;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => onSelect(pair.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: active ? FlowColors.primary : FlowColors.bg,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                        color: active
                            ? FlowColors.primary
                            : FlowColors.primaryLight),
                  ),
                  child: Text(
                    pair.$2,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: active ? Colors.white : FlowColors.primary,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
