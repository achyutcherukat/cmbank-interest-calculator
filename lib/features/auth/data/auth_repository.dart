import 'package:local_auth/local_auth.dart';

import '../../../core/security/pin_hasher.dart';
import '../../../core/settings/app_settings_repository.dart';

class AuthRepository {
  AuthRepository({
    AppSettingsRepository? settingsRepository,
    LocalAuthentication? localAuthentication,
  })  : _settingsRepository = settingsRepository ?? AppSettingsRepository(),
        _localAuthentication = localAuthentication ?? LocalAuthentication();

  final AppSettingsRepository _settingsRepository;
  final LocalAuthentication _localAuthentication;

  Future<bool> verifyCommonPin(String pin) async {
    final storedHash = await _settingsRepository.getString('common_pin_hash');
    if (storedHash == null || storedHash.isEmpty) return false;
    return PinHasher.hash(pin) == storedHash;
  }

  Future<bool> isBiometricLoginAvailable() async {
    final enabled = await _settingsRepository.getBool('biometric_enabled');
    if (!enabled) return false;

    final canCheckBiometrics = await _localAuthentication.canCheckBiometrics;
    final isDeviceSupported = await _localAuthentication.isDeviceSupported();
    return canCheckBiometrics && isDeviceSupported;
  }

  Future<bool> authenticateWithBiometrics() async {
    return _localAuthentication.authenticate(
      localizedReason: 'Unlock CM Bank',
      options: const AuthenticationOptions(
        biometricOnly: true,
        stickyAuth: true,
      ),
    );
  }
}
