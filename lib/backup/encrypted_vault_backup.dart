import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../crypto/crypto_helper.dart';
import '../crypto/native_key_derivation.dart';
import '../db/database_helper.dart';
import '../totp/totp_service.dart';

class BackupFormatException implements Exception {
  const BackupFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BackupDecryptException implements Exception {
  const BackupDecryptException();
}

class VaultBackupData {
  VaultBackupData({required this.createdAt, required this.accounts});

  final DateTime createdAt;
  final List<Account> accounts;

  void wipe() {
    for (final account in accounts) {
      account
        ..title = ''
        ..username = ''
        ..password = ''
        ..extra = ''
        ..tags = const [];
      account.totp?.wipe();
      account
        ..totp = null
        ..deletedAt = null
        ..secretsDecrypted = false;
    }
    accounts.clear();
  }
}

class EncryptedVaultBackup {
  EncryptedVaultBackup._();

  static const int maxFileBytes = 32 * 1024 * 1024;
  static const int maxAccountCount = 100000;
  static const int kdfIterations = CryptoHelper.vaultKdfIterations;
  static const int _minimumKdfIterations = 10000;
  static const int _maximumKdfIterations = 2000000;
  static const String _format = 'ACCOUNT_BOOK_ENCRYPTED_BACKUP';
  static const int _version = 1;
  static const String _kdfAlgorithm = 'PBKDF2-HMAC-SHA256';
  static const String _cipherAlgorithm = 'AES-256-GCM';
  static final List<int> _associatedData = utf8.encode(
    'account_book:encrypted_backup:v1',
  );

  static Future<String> create(
    List<Account> accounts,
    String password, {
    int iterations = kdfIterations,
  }) async {
    if (password.isEmpty) {
      throw const BackupFormatException('Backup password is empty');
    }
    if (iterations < _minimumKdfIterations ||
        iterations > _maximumKdfIterations) {
      throw const BackupFormatException('Invalid KDF iterations');
    }

    final createdAt = DateTime.now().millisecondsSinceEpoch;
    final items = await compute(_encodeAccountsInIsolate, (
      accounts,
      createdAt,
    ));
    final salt = CryptoHelper.randomSalt();
    Uint8List? key;
    try {
      key = await _deriveBackupKey(password, salt, iterations);
      final encryptedPayload = await compute(_encryptBackupPayload, (
        createdAt,
        items,
        key,
      ));
      return jsonEncode({
        'format': _format,
        'version': _version,
        'kdf': {
          'algorithm': _kdfAlgorithm,
          'iterations': iterations,
          'salt': salt,
        },
        'cipher': {'algorithm': _cipherAlgorithm, 'payload': encryptedPayload},
      });
    } finally {
      key?.fillRange(0, key.length, 0);
    }
  }

  static Future<VaultBackupData> open(String source, String password) async {
    final envelopeData = await compute(_decodeEnvelopeDataInIsolate, source);
    if (envelopeData['ok'] != true) {
      throw BackupFormatException(envelopeData['message'] as String);
    }
    final envelope = _BackupEnvelope(
      iterations: envelopeData['iterations'] as int,
      salt: envelopeData['salt'] as String,
      payload: envelopeData['payload'] as String,
    );
    Uint8List? key;
    try {
      key = await _deriveBackupKey(
        password,
        envelope.salt,
        envelope.iterations,
      );
      final decoded = await compute(_decryptBackupPayload, (
        envelope.payload,
        key,
      ));
      final createdAt = decoded['createdAt'];
      final rawAccounts = decoded['accounts'];
      if (createdAt is! int || rawAccounts is! List) {
        throw const BackupDecryptException();
      }
      return VaultBackupData(
        createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt),
        accounts: [
          for (final raw in rawAccounts.cast<Map<String, Object?>>())
            _accountFromBackupMap(raw),
        ],
      );
    } on BackupFormatException {
      rethrow;
    } on BackupDecryptException {
      rethrow;
    } catch (_) {
      throw const BackupDecryptException();
    } finally {
      key?.fillRange(0, key.length, 0);
    }
  }

  static _BackupEnvelope _decodeEnvelope(String source) {
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } catch (_) {
      throw const BackupFormatException('Invalid backup JSON');
    }
    if (decoded is! Map<String, dynamic> || decoded['format'] != _format) {
      throw const BackupFormatException('Not an Account Book backup');
    }
    if (decoded['version'] != _version) {
      throw const BackupFormatException('Unsupported backup version');
    }

    final kdf = decoded['kdf'];
    final cipher = decoded['cipher'];
    if (kdf is! Map<String, dynamic> ||
        kdf['algorithm'] != _kdfAlgorithm ||
        cipher is! Map<String, dynamic> ||
        cipher['algorithm'] != _cipherAlgorithm) {
      throw const BackupFormatException('Unsupported backup encryption');
    }
    final iterations = kdf['iterations'];
    final salt = kdf['salt'];
    final payload = cipher['payload'];
    if (iterations is! int ||
        iterations < _minimumKdfIterations ||
        iterations > _maximumKdfIterations ||
        salt is! String ||
        payload is! String) {
      throw const BackupFormatException('Invalid backup parameters');
    }
    try {
      if (base64Decode(salt).length != 16 ||
          base64Decode(payload).length < 28) {
        throw const FormatException();
      }
    } catch (_) {
      throw const BackupFormatException('Invalid backup encoding');
    }
    return _BackupEnvelope(
      iterations: iterations,
      salt: salt,
      payload: payload,
    );
  }

  static List<Map<String, Object?>> _encodeAccounts(
    List<Account> accounts,
    int fallbackTimestamp,
  ) {
    if (accounts.length > maxAccountCount) {
      throw const BackupFormatException('Too many accounts');
    }
    final ids = <int>{};
    return [
      for (final account in accounts)
        _accountToBackupMap(account, fallbackTimestamp, ids),
    ];
  }

  static Map<String, Object?> _accountToBackupMap(
    Account account,
    int fallbackTimestamp,
    Set<int> ids,
  ) {
    final id = account.id;
    if (id == null || id <= 0 || !ids.add(id) || account.title.trim().isEmpty) {
      throw const BackupFormatException('Invalid account in Vault');
    }
    final createdAt = account.createdAt ?? fallbackTimestamp;
    final updatedAt = account.updatedAt ?? createdAt;
    return {
      'id': id,
      'title': account.title,
      'username': account.username,
      'password': account.password,
      'extra': account.extra,
      'tags': List<String>.of(account.tags),
      'totp': account.totp?.toJson(),
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'deletedAt': account.deletedAt,
    };
  }

  static Account _accountFromBackupMap(Map<String, Object?> raw) {
    final id = raw['id'];
    final title = raw['title'];
    final username = raw['username'];
    final password = raw['password'];
    final extra = raw['extra'];
    final tags = raw['tags'];
    final createdAt = raw['createdAt'];
    final updatedAt = raw['updatedAt'];
    final deletedAt = raw['deletedAt'];
    if (id is! int ||
        id <= 0 ||
        title is! String ||
        title.trim().isEmpty ||
        username is! String ||
        password is! String ||
        extra is! String ||
        tags is! List ||
        tags.any((tag) => tag is! String || tag.trim().isEmpty) ||
        createdAt is! int ||
        createdAt <= 0 ||
        updatedAt is! int ||
        updatedAt <= 0 ||
        (deletedAt != null && (deletedAt is! int || deletedAt <= 0))) {
      throw const BackupDecryptException();
    }
    return Account(
      id: id,
      title: title,
      username: username,
      password: password,
      extra: extra,
      tags: tags.cast<String>().toList(),
      totp: raw['totp'] == null ? null : TotpConfig.fromJson(raw['totp']),
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt as int?,
      secretsDecrypted: true,
    );
  }

  static Future<Uint8List> _deriveBackupKey(
    String password,
    String salt,
    int iterations,
  ) async {
    final native = await NativeKeyDerivation.derivePbkdf2Sha256(
      password,
      salt,
      iterations,
    );
    if (native != null) return native;
    return compute(_deriveBackupKeyInIsolate, (password, salt, iterations));
  }
}

List<Map<String, Object?>> _encodeAccountsInIsolate((List<Account>, int) args) {
  final (accounts, fallbackTimestamp) = args;
  return EncryptedVaultBackup._encodeAccounts(accounts, fallbackTimestamp);
}

Map<String, Object?> _decodeEnvelopeDataInIsolate(String source) {
  try {
    final envelope = EncryptedVaultBackup._decodeEnvelope(source);
    return {
      'ok': true,
      'iterations': envelope.iterations,
      'salt': envelope.salt,
      'payload': envelope.payload,
    };
  } on BackupFormatException catch (error) {
    return {'ok': false, 'message': error.message};
  } catch (_) {
    return {'ok': false, 'message': 'Invalid backup envelope'};
  }
}

class _BackupEnvelope {
  const _BackupEnvelope({
    required this.iterations,
    required this.salt,
    required this.payload,
  });

  final int iterations;
  final String salt;
  final String payload;
}

Uint8List _deriveBackupKeyInIsolate((String, String, int) args) {
  final (password, salt, iterations) = args;
  return CryptoHelper.deriveKey(password, salt, iterations: iterations);
}

String _encryptBackupPayload(
  (int, List<Map<String, Object?>>, Uint8List) args,
) {
  final (createdAt, accounts, key) = args;
  final plain = Uint8List.fromList(
    utf8.encode(
      jsonEncode({'version': 1, 'createdAt': createdAt, 'accounts': accounts}),
    ),
  );
  try {
    return CryptoHelper.encryptBytes(
      plain,
      key,
      associatedData: EncryptedVaultBackup._associatedData,
    );
  } finally {
    plain.fillRange(0, plain.length, 0);
    key.fillRange(0, key.length, 0);
  }
}

Map<String, Object?> _decryptBackupPayload((String, Uint8List) args) {
  final (payload, key) = args;
  Uint8List? plain;
  try {
    plain = CryptoHelper.decryptBytes(
      payload,
      key,
      associatedData: EncryptedVaultBackup._associatedData,
    );
    final decoded = jsonDecode(utf8.decode(plain));
    if (decoded is! Map<String, dynamic> || decoded['version'] != 1) {
      throw const FormatException('Invalid backup payload');
    }
    final createdAt = decoded['createdAt'];
    final accounts = decoded['accounts'];
    if (createdAt is! int || createdAt <= 0 || accounts is! List) {
      throw const FormatException('Invalid backup payload');
    }
    if (accounts.length > EncryptedVaultBackup.maxAccountCount) {
      throw const FormatException('Too many accounts');
    }
    final ids = <int>{};
    final normalized = <Map<String, Object?>>[];
    for (final raw in accounts) {
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('Invalid backup account');
      }
      final item = Map<String, Object?>.from(raw);
      final id = item['id'];
      if (id is! int || !ids.add(id)) {
        throw const FormatException('Duplicate backup account');
      }
      normalized.add(item);
    }
    return {'createdAt': createdAt, 'accounts': normalized};
  } finally {
    plain?.fillRange(0, plain.length, 0);
    key.fillRange(0, key.length, 0);
  }
}
