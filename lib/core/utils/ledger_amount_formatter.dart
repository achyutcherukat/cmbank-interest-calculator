import 'package:flutter/services.dart';

/// Amount formatting for the LEDGER FEATURE ONLY.
///
/// The app-wide `money()` helper rounds to whole rupees, which is correct for
/// pledge/loan amounts (whole-rupee business rules) but silently hides paise
/// on ledger figures. Ledger screens use this formatter instead so legacy
/// screens keep their whole-number behaviour untouched.
class LedgerAmountFormatter {
  const LedgerAmountFormatter._();

  /// `20000.0` → `₹20,000` (no trailing .00); `20000.45` → `₹20,000.45`.
  /// Indian comma grouping, at most 2 decimal places, minus sign preserved.
  static String format(double amount) {
    final isNegative = amount < 0;
    final paise = (amount.abs() * 100).round();
    final rupees = (paise ~/ 100).toString();
    final frac = paise % 100;
    final body = frac == 0
        ? groupIndian(rupees)
        : '${groupIndian(rupees)}.${frac.toString().padLeft(2, '0')}';
    return '${isNegative ? '-' : ''}₹$body';
  }

  /// Indian digit grouping (last 3, then 2s): `1234567` → `12,34,567`.
  static String groupIndian(String digits) {
    if (digits.length <= 3) return digits;
    final last3 = digits.substring(digits.length - 3);
    final rest = digits.substring(0, digits.length - 3);
    final buf = StringBuffer();
    final start = rest.length % 2;
    if (start > 0) buf.write(rest.substring(0, start));
    for (var i = start; i < rest.length; i += 2) {
      if (buf.isNotEmpty) buf.write(',');
      buf.write(rest.substring(i, i + 2));
    }
    return '$buf,$last3';
  }
}

/// Input formatter for ledger amount fields (currently the Opening Balance
/// Wizard): digits with Indian comma grouping plus an optional decimal point
/// with at most 2 digits after it. Do NOT use on pledge/loan amount fields —
/// those stay whole-number-only via the app-wide IndianNumberFormatter.
class LedgerDecimalInputFormatter extends TextInputFormatter {
  static final _valid = RegExp(r'^\d*\.?\d{0,2}$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text.replaceAll(',', '');
    if (raw.isEmpty) return const TextEditingValue(text: '');
    if (!_valid.hasMatch(raw)) return oldValue;

    final dot = raw.indexOf('.');
    final intPart = dot >= 0 ? raw.substring(0, dot) : raw;
    final decPart = dot >= 0 ? raw.substring(dot) : '';
    final formatted =
        '${intPart.isEmpty ? '' : LedgerAmountFormatter.groupIndian(intPart)}'
        '$decPart';
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
