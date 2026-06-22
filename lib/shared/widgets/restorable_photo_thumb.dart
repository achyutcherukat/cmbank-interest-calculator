import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/services/photo_backup_service.dart';

/// Displays a photo thumbnail that gracefully handles missing local files.
///
/// States:
///   • file exists  → shows Image.file; tap calls [onView] with the local path
///   • file missing → tappable cloud-download placeholder; tap triggers
///                    [PhotoBackupService.restoreSinglePhoto] and refreshes
///   • restoring    → spinner placeholder
///
/// On failure [restoreSinglePhoto] returns null): shows a snack and stays in
/// the missing state so the user can retry.
class RestorablePhotoThumb extends StatefulWidget {
  const RestorablePhotoThumb({
    super.key,
    required this.localPath,
    required this.width,
    required this.height,
    this.label,
    this.onView,
  });

  final String localPath;
  final double width;
  final double height;
  final String? label;

  /// Called with the resolved local path when the user taps a loaded image.
  final void Function(String path)? onView;

  @override
  State<RestorablePhotoThumb> createState() => _RestorablePhotoThumbState();
}

class _RestorablePhotoThumbState extends State<RestorablePhotoThumb> {
  late String _path;
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    _path = widget.localPath;
    PhotoBackupService.instance.photosRestored
        .addListener(_onBulkRestoreComplete);
  }

  @override
  void dispose() {
    PhotoBackupService.instance.photosRestored
        .removeListener(_onBulkRestoreComplete);
    super.dispose();
  }

  void _onBulkRestoreComplete() {
    if (!mounted || _restoring) return;
    if (File(_path).existsSync()) setState(() {});
  }

  Future<void> _tryRestore() async {
    if (_restoring) return;
    setState(() => _restoring = true);
    final newPath =
        await PhotoBackupService.instance.restoreSinglePhoto(widget.localPath);
    if (!mounted) return;
    if (newPath != null) {
      setState(() {
        _path = newPath;
        _restoring = false;
      });
    } else {
      setState(() => _restoring = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not restore photo. Check that Drive is connected '
            'and the photo was synced to Drive before the backup.',
          ),
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _thumb(),
        if (widget.label != null && widget.label!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(widget.label!,
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ],
      ],
    );
  }

  Widget _thumb() {
    if (_restoring) {
      return _placeholder(icon: null, onTap: null);
    }

    final file = File(_path);
    if (file.existsSync()) {
      return GestureDetector(
        onTap: () => widget.onView?.call(_path),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.file(
            file,
            height: widget.height,
            width: widget.width,
            fit: BoxFit.cover,
            errorBuilder: (_, e, s) =>
                _placeholder(icon: Icons.cloud_download_outlined, onTap: _tryRestore),
          ),
        ),
      );
    }

    return _placeholder(icon: Icons.cloud_download_outlined, onTap: _tryRestore);
  }

  Widget _placeholder({required IconData? icon, required VoidCallback? onTap}) {
    final child = ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: widget.height,
        width: widget.width,
        color: Colors.black12,
        child: _restoring
            ? const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : Icon(icon, color: Colors.blueGrey, size: 28),
      ),
    );
    if (onTap != null) return GestureDetector(onTap: onTap, child: child);
    return child;
  }
}
