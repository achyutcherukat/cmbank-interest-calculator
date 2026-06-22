import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../security/pin_hasher.dart';
import '../settings/app_settings_repository.dart';

/// AES-256 encryption for all backup payloads.
///
/// Key handling:
///  - A random 256-bit AES key is generated once and stored raw in the Android
///    Keystore via flutter_secure_storage under `cmb_backup_key`.
///  - A password-protected copy is also stored in the `settings` table
///    (`backup_key_encrypted`) so the key can be recovered after a device reset
///    using the admin PIN. Format: base64(iv + ciphertext) + ':' + base64(salt).
///  - The raw key is never written to plain text and never logged.
class EncryptionService {
  EncryptionService._();

  static final EncryptionService instance = EncryptionService._();

  static const _keystoreKey = 'cmb_backup_key';
  static const _encryptedKeySetting = 'backup_key_encrypted';
  static const _adminPinHashSetting = 'admin_pin_hash';
  static const _pbkdf2Iterations = 100000;
  static const _keyLengthBytes = 32; // 256-bit
  static const _ivLengthBytes = 16;
  static const _saltLengthBytes = 16;

  final _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  final _settings = AppSettingsRepository();
  final _random = Random.secure();

  // In-memory cache of the raw key (cleared on app restart).
  Uint8List? _cachedKey;

  // ── Key lifecycle ──────────────────────────────────────────────────────────

  /// Ensures an AES key exists. Generates one on first call. Requires the admin
  /// PIN so a recoverable password-protected copy can be stored. Idempotent.
  Future<void> ensureKeyInitialized(String adminPin) async {
    final existing = await _readKeystoreKey();
    if (existing != null) {
      _cachedKey = existing;
      // Make sure a recovery copy exists too (e.g. legacy installs).
      final encrypted = await _settings.getString(_encryptedKeySetting);
      if (encrypted == null || encrypted.isEmpty) {
        await _storeRecoveryCopy(existing, adminPin);
      }
      return;
    }

    final key = _randomBytes(_keyLengthBytes);
    await _secureStorage.write(
      key: _keystoreKey,
      value: base64Encode(key),
    );
    await _storeRecoveryCopy(key, adminPin);
    _cachedKey = key;
  }

  /// Whether a raw key is present in the Android Keystore.
  Future<bool> hasKeystoreKey() async => (await _readKeystoreKey()) != null;

  /// Recovers the raw key from the password-protected settings copy using the
  /// admin PIN and re-stores it in the Android Keystore. Used when the keystore
  /// key is lost after a device reset. Throws on wrong PIN / corrupt copy.
  Future<void> recoverKeyWithPin(String adminPin) async {
    final key = await _decryptRecoveryCopy(adminPin);
    await _secureStorage.write(
      key: _keystoreKey,
      value: base64Encode(key),
    );
    _cachedKey = key;
  }

  // ── Public crypto API ──────────────────────────────────────────────────────

  /// Encrypts [data] with the raw AES key (must be initialized). Output is
  /// `iv(16) + ciphertext`.
  Future<Uint8List> encryptBytes(Uint8List data) async {
    final key = await _requireKey(null);
    final iv = enc.IV(_randomBytes(_ivLengthBytes));
    final encrypter = enc.Encrypter(enc.AES(enc.Key(key), mode: enc.AESMode.cbc));
    final encrypted = encrypter.encryptBytes(data, iv: iv);
    final out = BytesBuilder();
    out.add(iv.bytes);
    out.add(encrypted.bytes);
    return out.toBytes();
  }

  /// Decrypts [encrypted] (`iv(16) + ciphertext`). Uses the keystore key when
  /// present; otherwise recovers it from the password copy using [adminPin].
  Future<Uint8List> decryptBytes(Uint8List encrypted, String adminPin) async {
    if (encrypted.length <= _ivLengthBytes) {
      throw const FormatException('Encrypted payload too short.');
    }
    final key = await _requireKey(adminPin);
    final iv = enc.IV(Uint8List.fromList(encrypted.sublist(0, _ivLengthBytes)));
    final cipher = Uint8List.fromList(encrypted.sublist(_ivLengthBytes));
    final encrypter = enc.Encrypter(enc.AES(enc.Key(key), mode: enc.AESMode.cbc));
    final decrypted = encrypter.decryptBytes(enc.Encrypted(cipher), iv: iv);
    return Uint8List.fromList(decrypted);
  }

  /// Verifies an admin PIN against the stored hash.
  Future<bool> verifyAdminPin(String pin) async {
    final stored = await _settings.getString(_adminPinHashSetting);
    if (stored == null || stored.isEmpty) return false;
    return PinHasher.hash(pin) == stored;
  }

  /// SHA-256 hex checksum of [data].
  String generateChecksum(Uint8List data) => sha256.convert(data).toString();

  /// Constant-ish comparison of [data]'s checksum against [checksum].
  bool verifyChecksum(Uint8List data, String checksum) =>
      generateChecksum(data) == checksum.toLowerCase();

  // ── Internals ──────────────────────────────────────────────────────────────

  Future<Uint8List> _requireKey(String? adminPin) async {
    if (_cachedKey != null) return _cachedKey!;
    final fromStore = await _readKeystoreKey();
    if (fromStore != null) {
      _cachedKey = fromStore;
      return fromStore;
    }
    if (adminPin != null) {
      final recovered = await _decryptRecoveryCopy(adminPin);
      _cachedKey = recovered;
      return recovered;
    }
    throw StateError('Encryption key not initialized.');
  }

  Future<Uint8List?> _readKeystoreKey() async {
    final raw = await _secureStorage.read(key: _keystoreKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final bytes = base64Decode(raw);
      if (bytes.length != _keyLengthBytes) return null;
      return Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    }
  }

  Future<void> _storeRecoveryCopy(Uint8List key, String adminPin) async {
    final salt = _randomBytes(_saltLengthBytes);
    final derived = _pbkdf2(
      utf8.encode(adminPin.trim()),
      salt,
      _pbkdf2Iterations,
      _keyLengthBytes,
    );
    final iv = enc.IV(_randomBytes(_ivLengthBytes));
    final encrypter =
        enc.Encrypter(enc.AES(enc.Key(derived), mode: enc.AESMode.cbc));
    final encrypted = encrypter.encryptBytes(key, iv: iv);
    final payload = BytesBuilder()
      ..add(iv.bytes)
      ..add(encrypted.bytes);
    final value =
        '${base64Encode(payload.toBytes())}:${base64Encode(salt)}';
    await _settings.upsertMany({
      _encryptedKeySetting: (value: value, type: 'string'),
    });
  }

  Future<Uint8List> _decryptRecoveryCopy(String adminPin) async {
    final stored = await _settings.getString(_encryptedKeySetting);
    if (stored == null || stored.isEmpty || !stored.contains(':')) {
      throw StateError('No recovery key copy available.');
    }
    final parts = stored.split(':');
    final payload = base64Decode(parts[0]);
    final salt = base64Decode(parts[1]);
    final derived = _pbkdf2(
      utf8.encode(adminPin.trim()),
      Uint8List.fromList(salt),
      _pbkdf2Iterations,
      _keyLengthBytes,
    );
    final iv = enc.IV(Uint8List.fromList(payload.sublist(0, _ivLengthBytes)));
    final cipher = Uint8List.fromList(payload.sublist(_ivLengthBytes));
    final encrypter =
        enc.Encrypter(enc.AES(enc.Key(derived), mode: enc.AESMode.cbc));
    final key = encrypter.decryptBytes(enc.Encrypted(cipher), iv: iv);
    if (key.length != _keyLengthBytes) {
      throw const FormatException('Recovered key has invalid length.');
    }
    return Uint8List.fromList(key);
  }

  Uint8List _randomBytes(int length) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }

  /// PBKDF2-HMAC-SHA256 key derivation (the `crypto` package has no built-in).
  Uint8List _pbkdf2(
    List<int> password,
    Uint8List salt,
    int iterations,
    int keyLength,
  ) {
    final hmac = Hmac(sha256, password);
    final numBlocks = (keyLength / 32).ceil();
    final output = BytesBuilder();

    for (var block = 1; block <= numBlocks; block++) {
      final blockIndex = Uint8List(4)
        ..[0] = (block >> 24) & 0xff
        ..[1] = (block >> 16) & 0xff
        ..[2] = (block >> 8) & 0xff
        ..[3] = block & 0xff;

      var u = hmac.convert([...salt, ...blockIndex]).bytes;
      final t = List<int>.from(u);
      for (var i = 1; i < iterations; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < t.length; j++) {
          t[j] ^= u[j];
        }
      }
      output.add(t);
    }

    return Uint8List.fromList(output.toBytes().sublist(0, keyLength));
  }
}
