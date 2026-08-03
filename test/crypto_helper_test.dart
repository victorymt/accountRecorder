import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/pbkdf2.dart';
import 'package:pointycastle/macs/hmac.dart';

import 'package:account_book/crypto/crypto_helper.dart';

String _hex(Uint8List bytes) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

Uint8List _pbkdf2Pointycastle(String password, String saltB64, int iterations) {
  final salt = base64Decode(saltB64);
  final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
    ..init(Pbkdf2Parameters(Uint8List.fromList(salt), iterations, 32));
  return derivator.process(utf8.encode(password));
}

void main() {
  const password = 'TestPass123';
  const saltB64 = 'c2FsdA==';

  test('PBKDF2-HMAC-SHA256 符合 RFC 标准向量', () {
    // P="password", S="salt", c=4096, dkLen=32
    final key = CryptoHelper.deriveKey(
      'password',
      'c2FsdA==',
      iterations: 4096,
    );
    expect(
      _hex(key),
      'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a',
    );
  });

  test('新实现与旧 pointycastle 实现字节一致（老数据兼容）', () {
    for (final iterations in [1, 1000, 4096, 60000, 120000]) {
      final expected = _pbkdf2Pointycastle(password, saltB64, iterations);
      final actual = CryptoHelper.deriveKey(
        password,
        saltB64,
        iterations: iterations,
      );
      expect(_hex(actual), _hex(expected), reason: 'iterations=$iterations');
    }
  });

  test('加密解密与验证器流程', () {
    final key = CryptoHelper.deriveKey(password, saltB64);
    final cipher = CryptoHelper.encrypt('机密内容', key);
    expect(CryptoHelper.decrypt(cipher, key), '机密内容');

    final verifier = CryptoHelper.makeVerifier(key);
    expect(CryptoHelper.checkVerifier(verifier, key), isTrue);
    final wrongKey = CryptoHelper.deriveKey('WrongPass', saltB64);
    expect(CryptoHelper.checkVerifier(verifier, wrongKey), isFalse);
  });

  test('Vault Key 使用 AAD 包装且不能跨用途解密', () {
    final wrappingKey = CryptoHelper.deriveKey(password, saltB64);
    final vaultKey = CryptoHelper.randomKey();
    final wrapped = CryptoHelper.encryptBytes(
      vaultKey,
      wrappingKey,
      associatedData: utf8.encode('vault-key:v1'),
    );

    expect(
      CryptoHelper.decryptBytes(
        wrapped,
        wrappingKey,
        associatedData: utf8.encode('vault-key:v1'),
      ),
      vaultKey,
    );
    expect(
      () => CryptoHelper.decryptBytes(
        wrapped,
        wrappingKey,
        associatedData: utf8.encode('vault-item:v1'),
      ),
      throwsA(anything),
    );
  });
}
