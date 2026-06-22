import 'dart:typed_data';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/googleapis_auth.dart' as gauth;

/// Lightweight metadata for a file stored on Drive.
class DriveFile {
  const DriveFile({
    required this.id,
    required this.name,
    required this.sizeBytes,
    required this.modifiedTime,
  });

  final String id;
  final String name;
  final int sizeBytes;
  final DateTime? modifiedTime;

  double get sizeMb => sizeBytes / (1024 * 1024);
}

/// Drive storage figures, in MB.
class DriveQuota {
  const DriveQuota({required this.usedMb, required this.totalMb, required this.freeMb});
  final double usedMb;
  final double totalMb; // 0 == unlimited / unknown
  final double freeMb;
}

/// Thin wrapper over Google Sign-In + Drive v3 (driveFile scope).
///
/// Requires an OAuth client to be configured in the Google Cloud console with
/// the app's package name + signing SHA-1 (external setup, see backup docs).
class DriveService {
  DriveService._();

  static final DriveService instance = DriveService._();

  static const driveBackupsFolder = 'CM Bank Backups';
  static const drivePhotosFolder = 'CM Bank Photos';

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: <String>[drive.DriveApi.driveFileScope],
  );

  GoogleSignInAccount? _account;
  // Cache folder path -> folder id to avoid repeated lookups within a session.
  final Map<String, String> _folderCache = {};

  // ── Auth ───────────────────────────────────────────────────────────────────

  /// Attempts a silent sign-in (called on app launch). Returns true if a
  /// previously authorized account was restored.
  Future<bool> trySilentSignIn() async {
    try {
      _account = await _googleSignIn.signInSilently();
      return _account != null;
    } catch (_) {
      return false;
    }
  }

  /// Interactive sign-in (shown only from admin backup settings).
  Future<bool> signIn() async {
    try {
      _account = await _googleSignIn.signIn();
      return _account != null;
    } catch (_) {
      return false;
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _account = null;
    _folderCache.clear();
  }

  bool isAuthenticated() => _account != null;

  String getSignedInEmail() => _account?.email ?? '';

  Future<drive.DriveApi> _api() async {
    _account ??= await _googleSignIn.signInSilently();
    if (_account == null) {
      throw StateError('Not signed in to Google.');
    }
    final gauth.AuthClient? client = await _googleSignIn.authenticatedClient();
    if (client == null) {
      throw StateError('Could not obtain an authenticated Drive client.');
    }
    return drive.DriveApi(client);
  }

  // ── Storage quota ────────────────────────────────────────────────────────────

  Future<DriveQuota> getStorageQuota() async {
    final api = await _api();
    final about = await api.about.get($fields: 'storageQuota');
    final quota = about.storageQuota;
    final usage = double.tryParse(quota?.usage ?? '0') ?? 0;
    final limit = double.tryParse(quota?.limit ?? '0') ?? 0;
    const mb = 1024 * 1024;
    final usedMb = usage / mb;
    final totalMb = limit / mb; // 0 if unlimited (limit absent)
    final freeMb = totalMb > 0 ? (totalMb - usedMb) : double.infinity;
    return DriveQuota(usedMb: usedMb, totalMb: totalMb, freeMb: freeMb);
  }

  // ── Folders ──────────────────────────────────────────────────────────────────

  /// Resolves (creating if necessary) a possibly-nested folder path like
  /// `CM Bank Photos/gold/42` and returns the leaf folder id.
  Future<String> createFolderIfNotExists(String folderPath) async {
    final cached = _folderCache[folderPath];
    if (cached != null) return cached;

    final api = await _api();
    String? parentId;
    final segments =
        folderPath.split('/').where((s) => s.trim().isNotEmpty).toList();

    for (final segment in segments) {
      parentId = await _findOrCreateFolder(api, segment, parentId);
    }
    _folderCache[folderPath] = parentId!;
    return parentId;
  }

  Future<String> _findOrCreateFolder(
    drive.DriveApi api,
    String name,
    String? parentId,
  ) async {
    final escaped = name.replaceAll("'", "\\'");
    final parentClause =
        parentId != null ? "and '$parentId' in parents" : '';
    final q =
        "mimeType = 'application/vnd.google-apps.folder' and name = '$escaped' "
        "and trashed = false $parentClause";
    final result = await api.files.list(q: q, $fields: 'files(id,name)');
    if (result.files != null && result.files!.isNotEmpty) {
      return result.files!.first.id!;
    }
    final folder = drive.File()
      ..name = name
      ..mimeType = 'application/vnd.google-apps.folder'
      ..parents = parentId != null ? [parentId] : null;
    final created = await api.files.create(folder, $fields: 'id');
    return created.id!;
  }

  // ── Files ────────────────────────────────────────────────────────────────────

  Future<String> uploadFile(
    String fileName,
    Uint8List data,
    String folderPath,
  ) async {
    final api = await _api();
    final folderId = await createFolderIfNotExists(folderPath);
    final media = drive.Media(Stream.value(data), data.length);
    final file = drive.File()
      ..name = fileName
      ..parents = [folderId];
    final created =
        await api.files.create(file, uploadMedia: media, $fields: 'id');
    return created.id!;
  }

  Future<Uint8List> downloadFile(String driveFileId) async {
    final api = await _api();
    final media = await api.files.get(
      driveFileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    final builder = BytesBuilder();
    await for (final chunk in media.stream) {
      builder.add(chunk);
    }
    return builder.toBytes();
  }

  Future<List<DriveFile>> listFiles(String folderPath) async {
    final api = await _api();
    final folderId = await createFolderIfNotExists(folderPath);
    final result = await api.files.list(
      q: "'$folderId' in parents and trashed = false",
      $fields: 'files(id,name,size,modifiedTime)',
      orderBy: 'modifiedTime desc',
    );
    final files = result.files ?? [];
    return files
        .map((f) => DriveFile(
              id: f.id ?? '',
              name: f.name ?? '',
              sizeBytes: int.tryParse(f.size ?? '0') ?? 0,
              modifiedTime: f.modifiedTime,
            ))
        .toList();
  }

  Future<void> deleteFile(String driveFileId) async {
    final api = await _api();
    await api.files.delete(driveFileId);
  }
}
