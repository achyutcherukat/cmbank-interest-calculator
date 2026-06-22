import 'package:disk_space_plus/disk_space_plus.dart';
import 'package:flutter/foundation.dart';

/// Free device-storage lookup for the launch storage warnings (Part 7).
class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  static const double lowMb = 100;
  static const double criticalMb = 50;

  /// Free space on the device in MB, or null if it cannot be determined.
  Future<double?> freeDeviceMb() async {
    try {
      return await DiskSpacePlus().getFreeDiskSpace;
    } catch (e) {
      debugPrint('StorageService.freeDeviceMb failed: $e');
      return null;
    }
  }
}
