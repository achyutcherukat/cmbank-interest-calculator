import '../database/app_database.dart';

/// `operation` values for backup_log.
class BackupOperation {
  const BackupOperation._();
  static const backup = 'backup';
  static const restore = 'restore';
}

/// `backup_type` values for backup_log.
class BackupType {
  const BackupType._();
  static const database = 'database';
  static const photo = 'photo';
}

/// `destination` values for backup_log.
class BackupDestination {
  const BackupDestination._();
  static const local = 'local';
  static const drive = 'drive';
}

/// `status` values for backup_log (CHECK allows success/failed only — `partial`
/// photo runs are recorded as `failed` with a descriptive message).
class BackupStatus {
  const BackupStatus._();
  static const success = 'success';
  static const failed = 'failed';
}

class BackupLogEntry {
  const BackupLogEntry({
    required this.id,
    required this.operation,
    required this.backupType,
    required this.destination,
    required this.status,
    this.fileName,
    this.fileSize,
    this.driveStorageFree,
    this.message,
    required this.createdAt,
  });

  final int id;
  final String operation;
  final String backupType;
  final String destination;
  final String status;
  final String? fileName;
  final double? fileSize;
  final double? driveStorageFree;
  final String? message;
  final String createdAt;

  factory BackupLogEntry.fromMap(Map<String, dynamic> map) => BackupLogEntry(
        id: map['id'] as int,
        operation: map['operation'] as String? ?? '',
        backupType: map['backup_type'] as String? ?? '',
        destination: map['destination'] as String? ?? '',
        status: map['status'] as String? ?? '',
        fileName: map['file_name'] as String?,
        fileSize: (map['file_size'] as num?)?.toDouble(),
        driveStorageFree: (map['drive_storage_free'] as num?)?.toDouble(),
        message: map['message'] as String?,
        createdAt: map['created_at'] as String? ?? '',
      );
}

class BackupLogRepository {
  BackupLogRepository._();
  static final BackupLogRepository instance = BackupLogRepository._();

  Future<void> log({
    required String operation,
    required String backupType,
    required String destination,
    required String status,
    String? fileName,
    double? fileSize,
    double? driveStorageFree,
    String? message,
    int? createdBy,
  }) async {
    final db = await AppDatabase.instance.database;
    await db.insert('backup_log', {
      'operation': operation,
      'backup_type': backupType,
      'destination': destination,
      'status': status,
      'file_name': fileName,
      'file_size': fileSize,
      'drive_storage_free': driveStorageFree,
      'message': message,
      'created_by': createdBy,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Most recent entry matching the filters, or null.
  Future<BackupLogEntry?> latest({
    String? operation,
    String? backupType,
    String? destination,
    String? status,
  }) async {
    final db = await AppDatabase.instance.database;
    final where = <String>[];
    final args = <Object?>[];
    if (operation != null) {
      where.add('operation = ?');
      args.add(operation);
    }
    if (backupType != null) {
      where.add('backup_type = ?');
      args.add(backupType);
    }
    if (destination != null) {
      where.add('destination = ?');
      args.add(destination);
    }
    if (status != null) {
      where.add('status = ?');
      args.add(status);
    }
    final rows = await db.query(
      'backup_log',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return BackupLogEntry.fromMap(rows.first);
  }

  Future<List<BackupLogEntry>> recent({int limit = 100}) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'backup_log',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(BackupLogEntry.fromMap).toList();
  }
}
