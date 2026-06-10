import 'dart:convert';

import 'package:crypto/crypto.dart';

class PinHasher {
  const PinHasher._();

  static String hash(String pin) {
    final bytes = utf8.encode('cm_bank_pin_v1:${pin.trim()}');
    return sha256.convert(bytes).toString();
  }
}
