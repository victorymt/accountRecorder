import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class BiometricVault {
  BiometricVault._();

  static const _channel = MethodChannel('account_book/crypto');

  static Future<bool> isAvailable() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await _channel.invokeMethod<bool>('isBiometricAvailable') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isEnabled() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await _channel.invokeMethod<bool>('isBiometricEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> enable(Uint8List vaultKey) async {
    await _channel.invokeMethod<void>('enableBiometric', <String, Object>{
      'vaultKey': base64Encode(vaultKey),
    });
  }

  static Future<Uint8List> unlock() async {
    final encoded = await _channel.invokeMethod<String>('unlockWithBiometric');
    if (encoded == null) {
      throw const FormatException('Missing biometric Vault Key');
    }
    final key = base64Decode(encoded);
    if (key.length != 32) {
      key.fillRange(0, key.length, 0);
      throw const FormatException('Invalid biometric Vault Key');
    }
    return Uint8List.fromList(key);
  }

  static Future<void> disable() {
    return _channel.invokeMethod<void>('disableBiometric');
  }
}
