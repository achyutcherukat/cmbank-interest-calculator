import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';

/// Canonical `action_category` values (matches the CHECK constraint).
class AuditCategory {
  const AuditCategory._();

  static const pledge = 'PLEDGE';
  static const settings = 'SETTINGS';
  static const dayManagement = 'DAY_MANAGEMENT';
  static const admin = 'ADMIN';
}

class AuditLogEntry {
  const AuditLogEntry({
    required this.id,
    required this.actionCategory,
    required this.action,
    required this.entityType,
    this.entityId,
    this.oldValueJson,
    this.newValueJson,
    this.reason,
    this.createdBy,
    required this.createdAt,
    this.createdByName,
    this.pledgeNo,
  });

  final int id;
  final String actionCategory;
  final String action;
  final String entityType;
  final String? entityId;
  final String? oldValueJson;
  final String? newValueJson;
  final String? reason;
  final int? createdBy;
  final String createdAt;
  final String? createdByName;
  final String? pledgeNo;

  factory AuditLogEntry.fromMap(Map<String, dynamic> map) {
    return AuditLogEntry(
      id: map['id'] as int,
      actionCategory: map['action_category'] as String? ?? '',
      action: map['action'] as String? ?? '',
      entityType: map['entity_type'] as String? ?? '',
      entityId: map['entity_id'] as String?,
      oldValueJson: map['old_value_json'] as String?,
      newValueJson: map['new_value_json'] as String?,
      reason: map['reason'] as String?,
      createdBy: map['created_by'] as int?,
      createdAt: map['created_at'] as String? ?? '',
      createdByName: map['created_by_name'] as String?,
      pledgeNo: map['pledge_no'] as String?,
    );
  }
}

class AuditLogRepository {
  AuditLogRepository._();
  static final AuditLogRepository instance = AuditLogRepository._();

  /// Write an audit entry. Pass [txn] to participate in an existing
  /// transaction.
  Future<void> log({
    required String actionCategory,
    required String action,
    required String entityType,
    String? entityId,
    String? oldValueJson,
    String? newValueJson,
    String? reason,
    int? createdBy,
    DatabaseExecutor? txn,
  }) async {
    final db = txn ?? await AppDatabase.instance.database;
    await db.insert('audit_log', {
      'action_category': actionCategory,
      'action': action,
      'entity_type': entityType,
      'entity_id': entityId,
      'old_value_json': oldValueJson,
      'new_value_json': newValueJson,
      'reason': reason,
      'created_by': createdBy,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Count of all entries in the log.
  Future<int> getCount() async {
    final db = await AppDatabase.instance.database;
    final r = await db.rawQuery('SELECT COUNT(*) as c FROM audit_log');
    return (r.first['c'] as int?) ?? 0;
  }

  /// Delete entries older than [retentionDays]. Returns the number deleted.
  Future<int> purge(int retentionDays) async {
    final db = await AppDatabase.instance.database;
    final cutoff = DateTime.now()
        .subtract(Duration(days: retentionDays))
        .toIso8601String();
    return db.delete('audit_log', where: 'created_at < ?', whereArgs: [cutoff]);
  }

  /// Read entries, optionally filtered by [category] ('ALL' or null = no
  /// filter). Joins the user name for display.
  Future<List<AuditLogEntry>> getEntries({String? category, int limit = 200}) async {
    final db = await AppDatabase.instance.database;
    final hasFilter = category != null && category != 'ALL';
    final rows = await db.rawQuery(
      '''
      SELECT a.*, u.name AS created_by_name,
        CASE WHEN a.entity_type = 'pledges' THEN p.pledge_no ELSE NULL END AS pledge_no
      FROM audit_log a
      LEFT JOIN users u ON u.id = a.created_by
      LEFT JOIN pledges p ON a.entity_type = 'pledges'
        AND p.id = CAST(a.entity_id AS INTEGER)
      ${hasFilter ? 'WHERE a.action_category = ?' : ''}
      ORDER BY a.created_at DESC
      LIMIT ?
      ''',
      hasFilter ? [category, limit] : [limit],
    );
    return rows.map(AuditLogEntry.fromMap).toList();
  }
}
