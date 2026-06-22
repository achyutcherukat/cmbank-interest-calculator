import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';

/// `photo_type` values for photo_sync_log (matches the CHECK constraint).
class PhotoType {
  const PhotoType._();
  static const idProof = 'id_proof';
  static const gold = 'gold';
  static const document = 'document';
}

class PhotoSyncEntry {
  const PhotoSyncEntry({
    required this.id,
    this.pledgeId,
    this.customerId,
    required this.photoType,
    required this.localPath,
    this.drivePath,
    required this.isSynced,
    this.syncedAt,
    this.syncError,
    required this.createdAt,
  });

  final int id;
  final int? pledgeId;
  final int? customerId;
  final String photoType;
  final String localPath;
  final String? drivePath;
  final bool isSynced;
  final String? syncedAt;
  final String? syncError;
  final String createdAt;

  factory PhotoSyncEntry.fromMap(Map<String, dynamic> map) => PhotoSyncEntry(
        id: map['id'] as int,
        pledgeId: map['pledge_id'] as int?,
        customerId: map['customer_id'] as int?,
        photoType: map['photo_type'] as String? ?? '',
        localPath: map['local_path'] as String? ?? '',
        drivePath: map['drive_path'] as String?,
        isSynced: (map['is_synced'] as int? ?? 0) == 1,
        syncedAt: map['synced_at'] as String?,
        syncError: map['sync_error'] as String?,
        createdAt: map['created_at'] as String? ?? '',
      );
}

/// CRUD over photo_sync_log (Part 10 inserts + Part 5 backup/restore reads).
class PhotoSyncRepository {
  PhotoSyncRepository._();
  static final PhotoSyncRepository instance = PhotoSyncRepository._();

  /// Records a newly-saved photo as pending sync. Pass [txn] to join an
  /// existing transaction (so the row is rolled back if the parent write fails).
  Future<int> insertPhoto({
    int? pledgeId,
    int? customerId,
    required String photoType,
    required String localPath,
    DatabaseExecutor? txn,
  }) async {
    final db = txn ?? await AppDatabase.instance.database;
    return db.insert('photo_sync_log', {
      'pledge_id': pledgeId,
      'customer_id': customerId,
      'photo_type': photoType,
      'local_path': localPath,
      'drive_path': null,
      'is_synced': 0,
      'synced_at': null,
      'sync_error': null,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Convenience: record several photo paths of one type at once.
  Future<void> insertPhotos({
    int? pledgeId,
    int? customerId,
    required String photoType,
    required Iterable<String> localPaths,
    DatabaseExecutor? txn,
  }) async {
    for (final p in localPaths) {
      if (p.trim().isEmpty) continue;
      await insertPhoto(
        pledgeId: pledgeId,
        customerId: customerId,
        photoType: photoType,
        localPath: p,
        txn: txn,
      );
    }
  }

  /// Idempotently records photo paths for an entity — inserts only paths that
  /// aren't already tracked (safe to call on both create and update).
  Future<void> registerPhotos({
    int? pledgeId,
    int? customerId,
    required String photoType,
    required Iterable<String> localPaths,
  }) async {
    final db = await AppDatabase.instance.database;
    for (final path in localPaths) {
      if (path.trim().isEmpty) continue;
      final existing = await db.query('photo_sync_log',
          columns: ['id'], where: 'local_path = ?', whereArgs: [path], limit: 1);
      if (existing.isNotEmpty) continue;
      await insertPhoto(
        pledgeId: pledgeId,
        customerId: customerId,
        photoType: photoType,
        localPath: path,
      );
    }
  }

  Future<List<PhotoSyncEntry>> getUnsynced() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('photo_sync_log',
        where: 'is_synced = 0', orderBy: 'created_at ASC');
    return rows.map(PhotoSyncEntry.fromMap).toList();
  }

  Future<List<PhotoSyncEntry>> getSynced() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('photo_sync_log',
        where: 'is_synced = 1', orderBy: 'created_at ASC');
    return rows.map(PhotoSyncEntry.fromMap).toList();
  }

  Future<int> countPending() async {
    final db = await AppDatabase.instance.database;
    final rows = await db
        .rawQuery('SELECT COUNT(*) AS c FROM photo_sync_log WHERE is_synced = 0');
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<int> countTotal() async {
    final db = await AppDatabase.instance.database;
    final rows =
        await db.rawQuery('SELECT COUNT(*) AS c FROM photo_sync_log');
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<void> markSynced(int id, String drivePath) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'photo_sync_log',
      {
        'drive_path': drivePath,
        'is_synced': 1,
        'synced_at': DateTime.now().toIso8601String(),
        'sync_error': null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markError(int id, String error) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'photo_sync_log',
      {'sync_error': error, 'is_synced': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Records a restore-side download failure without changing [is_synced].
  /// The photo remains marked as synced (it still exists on Drive) so future
  /// restore attempts will retry it. Use [markError] for upload failures only.
  Future<void> markDownloadError(int id, String error) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'photo_sync_log',
      {'sync_error': error},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateLocalPath(int id, String localPath) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'photo_sync_log',
      {'local_path': localPath},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Finds the sync record matching a given local path (used by inline restore).
  Future<PhotoSyncEntry?> findByLocalPath(String localPath) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('photo_sync_log',
        where: 'local_path = ?', whereArgs: [localPath], limit: 1);
    if (rows.isEmpty) return null;
    return PhotoSyncEntry.fromMap(rows.first);
  }
}
