class InterestCalculator {
  const InterestCalculator._();

  // Rounds value UP to the nearest multiple of 5 (e.g. 82→85, 87→90, 90→90)
  static double _roundUpTo5(double value) {
    return (value / 5).ceil() * 5.0;
  }

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

    final double rawInterest =
        (principal * effectiveDays / 360) * (ratePercent / 100);
    final double interest = _roundUpTo5(rawInterest);

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
