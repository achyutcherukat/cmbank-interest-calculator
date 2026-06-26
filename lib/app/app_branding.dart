/// Single source of truth for per-flavor branding.
///
/// The flavor is injected at build time via a Dart define, e.g.
///   flutter build apk --flavor gmc --dart-define=APP_FLAVOR=gmc
/// It is read here as a compile-time constant, so it is available
/// synchronously from the very first frame (including the splash).
///
/// Defaults to `cmb`, so any build without the define behaves exactly like
/// the original CMB app. The ONLY thing that varies per flavor is the brand
/// asset below — no business logic branches on the flavor.
class AppBranding {
  const AppBranding._();

  static const String flavor =
      String.fromEnvironment('APP_FLAVOR', defaultValue: 'cmb');

  static bool get isGmc => flavor == 'gmc';

  /// Brand logo for login/lock screen, drawer header, restore/setup screen,
  /// and startup splash.
  static String get logoAsset =>
      isGmc ? 'assets/images/gmc_logo.png' : 'assets/images/cmb_logo.png';

  /// Brand image for the main AppBar header only.
  /// GMC uses a wide plaque; CMB falls back to the standard logo.
  static String get headerAsset =>
      isGmc ? 'assets/images/GMC_APP_HEADER.png' : 'assets/images/cmb_logo.png';
}
