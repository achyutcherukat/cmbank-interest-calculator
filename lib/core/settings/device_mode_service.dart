import 'package:flutter/foundation.dart';

import 'app_settings_repository.dart';

/// Single source of truth for whether this install is a read-only Secondary
/// device. Backed by `settings.device_mode` and cached reactively so the UI can
/// gate write actions without scattering async device-mode checks across
/// screens.
///
/// [refresh] is called at startup and after any flow that can change
/// device_mode (e.g. a restore). Widgets consume [isSecondary] via the
/// `RestrictedAction` wrapper; nothing should read device_mode directly for
/// write-restriction purposes.
class DeviceModeService {
  DeviceModeService._();

  static final DeviceModeService instance = DeviceModeService._();

  /// Reactive flag — true on Secondary devices. Defaults to false (Primary) so
  /// the safe default before the first load is "writes allowed" on the device
  /// that is genuinely a Primary; Secondary devices flip to true once loaded.
  final ValueNotifier<bool> isSecondary = ValueNotifier<bool>(false);

  Future<void> refresh() async {
    isSecondary.value = await AppSettingsRepository().isSecondaryDevice();
  }
}
