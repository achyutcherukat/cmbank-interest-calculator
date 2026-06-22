import '../../features/admin/data/audit_log_repository.dart';
import '../settings/app_settings_repository.dart';

/// Detects unclean shutdowns via a `clean_shutdown` flag (Part 7).
///
/// SQLite already rolls back incomplete transactions on open via its journal;
/// this adds the user-facing "app was closed unexpectedly" notice. The flag is
/// set to `false` while the app runs and `true` when it is backgrounded or
/// detached. If a launch sees `false`, the previous run did not exit cleanly.
class CrashRecovery {
  CrashRecovery._();
  static final CrashRecovery instance = CrashRecovery._();

  final _settings = AppSettingsRepository();

  Future<bool> wasUncleanShutdown() async {
    final value = await _settings.getString('clean_shutdown');
    return value == 'false';
  }

  Future<void> markRunning() => _set('false');

  Future<void> markClean() => _set('true');

  Future<void> logRecovery() async {
    try {
      await AuditLogRepository.instance.log(
        actionCategory: AuditCategory.admin,
        action: 'CRASH_RECOVERY',
        entityType: 'app',
        reason: 'App was closed unexpectedly on the previous run.',
      );
    } catch (_) {
      // Never let logging block startup.
    }
  }

  Future<void> _set(String value) async {
    try {
      await _settings.upsertMany({
        'clean_shutdown': (value: value, type: 'bool'),
      });
    } catch (_) {
      // Ignore — non-critical.
    }
  }
}
