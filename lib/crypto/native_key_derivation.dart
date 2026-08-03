import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NativeKeyDerivation {
  NativeKeyDerivation._();

  static const _channel = MethodChannel('account_book/crypto');

  static Future<Uint8List?> derivePbkdf2Sha256(
    String password,
    String saltBase64,
    int iterations,
  ) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return null;
    }
    if (password.codeUnits.any((unit) => unit > 0x7f)) return null;
    try {
      final encoded = await _channel.invokeMethod<String>(
        'derivePbkdf2Sha256',
        <String, Object>{
          'password': password,
          'salt': saltBase64,
          'iterations': iterations,
        },
      );
      if (encoded == null) return null;
      final key = base64Decode(encoded);
      return key.length == 32 ? Uint8List.fromList(key) : null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } catch (_) {
      return null;
    }
  }
}
