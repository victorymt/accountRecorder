import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/gcm.dart';

class CryptoHelper {
  CryptoHelper._();

  static final Random _random = Random.secure();

  static const int iterations = 60000;
  static const int legacyIterations = 120000;
  static const int vaultKdfIterations = 600000;
  static const String _marker = 'account_book_v1';

  static String randomSalt() {
    return base64Encode(_randomBytes(16));
  }

  static List<int> _randomBytes(int length) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }

  static Uint8List randomKey([int length = 32]) {
    return Uint8List.fromList(_randomBytes(length));
  }

  static Uint8List deriveKey(
    String password,
    String saltB64, {
    int iterations = CryptoHelper.iterations,
  }) {
    final salt = base64Decode(saltB64);
    final hmac = Hmac(sha256, utf8.encode(password));
    final dk = List<int>.filled(32, 0);
    var u = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
    for (var i = 0; i < 32; i++) {
      dk[i] ^= u[i];
    }
    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < 32; j++) {
        dk[j] ^= u[j];
      }
    }
    return Uint8List.fromList(dk);
  }

  static String encrypt(
    String plain,
    Uint8List key, {
    List<int> associatedData = const [],
  }) {
    return encryptBytes(
      Uint8List.fromList(utf8.encode(plain)),
      key,
      associatedData: associatedData,
    );
  }

  static String encryptBytes(
    Uint8List plain,
    Uint8List key, {
    List<int> associatedData = const [],
  }) {
    final nonce = Uint8List.fromList(_randomBytes(12));
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(
          KeyParameter(key),
          128,
          nonce,
          Uint8List.fromList(associatedData),
        ),
      );
    final output = Uint8List.fromList(cipher.process(plain));
    return base64Encode([...nonce, ...output]);
  }

  static String decrypt(
    String stored,
    Uint8List key, {
    List<int> associatedData = const [],
  }) {
    return utf8.decode(
      decryptBytes(stored, key, associatedData: associatedData),
    );
  }

  static Uint8List decryptBytes(
    String stored,
    Uint8List key, {
    List<int> associatedData = const [],
  }) {
    final raw = base64Decode(stored);
    if (raw.length < 28) {
      throw const FormatException('Invalid encrypted value');
    }
    final nonce = Uint8List.sublistView(Uint8List.fromList(raw), 0, 12);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(
          KeyParameter(key),
          128,
          nonce,
          Uint8List.fromList(associatedData),
        ),
      );
    final input = Uint8List.sublistView(Uint8List.fromList(raw), 12);
    return Uint8List.fromList(cipher.process(input));
  }

  static String makeVerifier(Uint8List key) {
    return encrypt(_marker, key);
  }

  static bool checkVerifier(String stored, Uint8List key) {
    try {
      return decrypt(stored, key) == _marker;
    } catch (_) {
      return false;
    }
  }
}
