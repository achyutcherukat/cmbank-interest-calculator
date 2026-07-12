import '../../app/app_branding.dart';

/// Business identity shown on printed reports (Pledge Form, Cash Book, Stock
/// Register, Ledger).
///
/// Values switch per product flavor (CMB / GMC) via [AppBranding.isGmc], which
/// is a compile-time constant from the `APP_FLAVOR` Dart define. Update the
/// CMB block and the GMC block below independently.
class BusinessInfo {
  const BusinessInfo._();

  /// Registered business name (used as the header title, upper-cased on the
  /// Pledge Form).
  static String get name => AppBranding.isGmc ? _gmcName : _cmbName;

  /// Full address as a single comma-separated string. On the Pledge Form it is
  /// split on commas into a compact block of up to three lines (first part on
  /// line 1, middle parts joined on line 2, last part on line 3), so place your
  /// commas at the desired line breaks.
  static String get address => AppBranding.isGmc ? _gmcAddress : _cmbAddress;

  // ── CMB — Chaliyil Mankave Bankers ──────────────────────────────────────────
  static const String _cmbName = 'Chaliyil Mankave Bankers';
  static const String _cmbAddress =
      'Ashirvad Building Room No.O.P. 14/840, Olavanna Junction, Calicut - 673 019, Licence No. 32110581486';

  // ── GMC ─────────────────────────────────────────────────────────────────────
  // TODO(GMC): replace with the registered GMC business name and address.
  static const String _gmcName = 'GANGADHARA MENON & CO';
  static const String _gmcAddress =
      'Licence No. 32110526147,24/1916, Mankavu, Calicut - 673007';
}
