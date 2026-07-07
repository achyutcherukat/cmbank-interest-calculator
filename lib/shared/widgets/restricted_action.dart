import 'package:flutter/material.dart';

import '../../core/settings/device_mode_service.dart';

/// Wraps any write/action control and renders it greyed-out and inert on
/// read-only Secondary devices; on Primary devices the [child] is returned
/// unchanged.
///
/// This is the single mechanism for write-restriction — screens wrap their
/// write buttons in this rather than checking `device_mode` directly. Tapping a
/// restricted control does nothing (the pointer is absorbed): no error, no
/// snackbar, just inert. Works for any widget type (ElevatedButton, IconButton,
/// GestureDetector cards, …) without needing per-button disabled styling.
class RestrictedAction extends StatelessWidget {
  const RestrictedAction({super.key, required this.child, this.restricted});

  final Widget child;

  /// Optional override. When null (the default) restriction follows the
  /// Secondary-device flag. Pass an explicit value to force the state.
  final bool? restricted;

  /// Opacity applied to a restricted control to read as visibly disabled.
  static const double _disabledOpacity = 0.4;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: DeviceModeService.instance.isSecondary,
      builder: (context, isSecondary, _) {
        final blocked = restricted ?? isSecondary;
        if (!blocked) return child;
        return Opacity(
          opacity: _disabledOpacity,
          child: AbsorbPointer(child: child),
        );
      },
    );
  }
}
