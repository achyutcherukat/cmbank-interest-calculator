class InterestCalculator {
  const InterestCalculator._();

  static ({double interest, double total, String note}) calculate({
    required double principal,
    required DateTime fromDate,
    required DateTime toDate,
    required double ratePercent,
  }) {
    // Spec: exclude from date, include to date
    final rawDays = toDate.difference(fromDate).inDays;
    String note = '';

    int effectiveDays = rawDays;
    if (rawDays < 7) {
      effectiveDays = 7;
      note = 'Minimum 7 days applied';
    }

    final double interest =
        (principal * effectiveDays / 360) * (ratePercent / 100);

    if (interest < 50.0) {
      return (
        interest: 50.0,
        total: principal + 50.0,
        note: 'Minimum ₹50 interest applied',
      );
    }

    return (interest: interest, total: principal + interest, note: note);
  }

  static int effectiveDays(DateTime fromDate, DateTime toDate) {
    final rawDays = toDate.difference(fromDate).inDays;
    return rawDays < 7 ? 7 : rawDays;
  }
}
