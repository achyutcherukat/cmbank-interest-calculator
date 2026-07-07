/// Business identity shown on printed reports (Cash Book, Stock Register).
///
/// Intentionally isolated from the print/report logic so it can be swapped per
/// product flavor (e.g. GMC) in a future phase without touching any PDF code.
class BusinessInfo {
  const BusinessInfo._();

  static const String name = 'Chaliyil Mankave Bankers';

  /// TODO: replace with the actual registered business address.
  static const String address =
      'Ashirvad Building, Olavanna Junction, Olavanna, Calicut - 673025';

  /// Logo rendered (left-aligned) in the report letterhead. Loaded from assets
  /// at print time via [PrintService.loadLogo].
  static const String logoAssetPath = 'assets/images/cmb_logo.png';
}
