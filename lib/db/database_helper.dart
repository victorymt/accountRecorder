import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../crypto/crypto_helper.dart';
import '../crypto/native_key_derivation.dart';

class Account {
  Account({
    this.id,
    required this.title,
    required this.username,
    required this.password,
    required this.extra,
    this.tags = const [],
    this.createdAt,
    this.updatedAt,
    this.secretsDecrypted = false,
  });

  final int? id;
  String title;
  String username;
  String password;
  String extra;
  List<String> tags;
  final int? createdAt;
  int? updatedAt;
  bool secretsDecrypted;

  static const String tagsSeparator = ',';

  Map<String, Object?> toLegacyMap() {
    return {
      'id': id,
      'title': title,
      'username': username,
      'password': password,
      'extra': extra,
      'tags': tags.join(tagsSeparator),
      'created_at': createdAt ?? DateTime.now().millisecondsSinceEpoch,
      'updated_at': updatedAt ?? DateTime.now().millisecondsSinceEpoch,
    };
  }

  factory Account.fromLegacyMap(Map<String, Object?> map) {
    final rawTags = map['tags'] as String? ?? '';
    return Account(
      id: map['id'] as int?,
      title: map['title'] as String,
      username: map['username'] as String,
      password: map['password'] as String,
      extra: map['extra'] as String,
      tags: rawTags.isEmpty
          ? const []
          : rawTags
                .split(tagsSeparator)
                .map((tag) => tag.trim())
                .where((tag) => tag.isNotEmpty)
                .toList(),
      createdAt: map['created_at'] as int?,
      updatedAt: map['updated_at'] as int?,
    );
  }
}

class ImportResult {
  const ImportResult({
    required this.imported,
    required this.skipped,
    this.updated = 0,
  });

  final int imported;
  final int skipped;
  final int updated;
}

class ImportPreview {
  const ImportPreview({required this.total, required this.conflicts});

  final int total;
  final int conflicts;

  int get newAccounts => total - conflicts;
}

enum ImportConflictPolicy { skip, overwrite, keepBoth }

String accountIdentityKey(String title, String username) {
  return '${title.trim().toLowerCase()}\u0000${username.trim().toLowerCase()}';
}

Duration unlockBackoffForFailureCount(int failureCount) {
  return switch (failureCount) {
    <= 2 => Duration.zero,
    3 => const Duration(seconds: 5),
    4 => const Duration(seconds: 15),
    5 => const Duration(seconds: 30),
    _ => const Duration(minutes: 1),
  };
}

class DatabaseHelper {
  DatabaseHelper._() : _databaseName = _dbName;

  @visibleForTesting
  DatabaseHelper.forTesting(this._databaseName);

  static final DatabaseHelper instance = DatabaseHelper._();

  static const int _databaseVersion = 3;
  static const String _dbName = 'accounts.db';
  static const String _legacyTable = 'accounts';
  static const String _vaultTable = 'vault_items';

  static const String _legacySaltKey = 'salt';
  static const String _legacyVerifierKey = 'verifier';
  static const String _legacyIterationsKey = 'iterations';
  static const String _wrappedVaultKey = 'wrapped_vault_key';
  static const String _vaultKdfSaltKey = 'vault_kdf_salt';
  static const String _vaultKdfIterationsKey = 'vault_kdf_iterations';
  static const String _vaultFormatVersionKey = 'vault_format_version';

  static const String _failedUnlockCountKey = 'failed_unlock_count';
  static const String _lastFailedUnlockKey = 'last_failed_unlock_at';
  static const String _unlockBlockedUntilKey = 'unlock_blocked_until';
  static const Duration _unlockFailureWindow = Duration(minutes: 10);

  final String _databaseName;
  Database? _db;
  Uint8List? _vaultKey;
  List<Account>? _cache;
  Future<List<Account>>? _cacheLoad;
  int _generation = 0;

  Future<Database> get database async {
    _db ??= await openDatabase(
      _databaseName,
      version: _databaseVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE meta(
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
        await _createVaultTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE $_legacyTable ADD COLUMN tags TEXT NOT NULL DEFAULT \'\'',
          );
        }
        if (oldVersion < 3) {
          await _createVaultTable(db);
        }
      },
    );
    return _db!;
  }

  Future<bool> isSetup() async {
    final db = await database;
    return await _readMeta(db, _wrappedVaultKey) != null ||
        await _readMeta(db, _legacySaltKey) != null;
  }

  Future<bool> needsVaultMigration() async {
    final db = await database;
    return await _readMeta(db, _wrappedVaultKey) == null &&
        await _readMeta(db, _legacySaltKey) != null;
  }

  Future<Uint8List> setupMasterPassword(String password) async {
    final db = await database;
    _clearVaultKey();
    final salt = CryptoHelper.randomSalt();
    final vaultKey = CryptoHelper.randomKey();
    final wrappingKey = await _deriveKey(
      password,
      salt,
      CryptoHelper.vaultKdfIterations,
    );
    try {
      final wrappedKey = CryptoHelper.encryptBytes(
        vaultKey,
        wrappingKey,
        associatedData: _vaultKeyAssociatedData,
      );
      await db.transaction((txn) async {
        await _writeVaultMetadata(txn, salt, wrappedKey);
        await txn.execute('DROP TABLE IF EXISTS $_legacyTable');
      });
      _setVaultKey(vaultKey);
      return Uint8List.fromList(vaultKey);
    } finally {
      _wipeBytes(wrappingKey);
      _wipeBytes(vaultKey);
    }
  }

  Future<Uint8List?> unlock(String password) async {
    final db = await database;
    _clearVaultKey();
    final wrappedKey = await _readMeta(db, _wrappedVaultKey);
    if (wrappedKey != null) {
      return _unlockCurrentVault(db, password, wrappedKey);
    }
    return _unlockAndMigrateLegacyVault(db, password);
  }

  Future<bool> unlockWithVaultKey(Uint8List vaultKey) async {
    if (vaultKey.length != 32) return false;
    final db = await database;
    if (await _readMeta(db, _wrappedVaultKey) == null) return false;
    _invalidateCache();
    _setVaultKey(vaultKey);
    try {
      final rows = await db.query(_vaultTable, limit: 1);
      if (rows.isNotEmpty) {
        final accounts = await compute(_decryptVaultRowsIsolate, (
          rows,
          _vaultKey!,
        ));
        for (final account in accounts) {
          _wipeAccount(account);
        }
      }
      return true;
    } catch (_) {
      _invalidateCache();
      _clearVaultKey();
      return false;
    }
  }

  Uint8List? copyVaultKey() {
    final key = _vaultKey;
    return key == null ? null : Uint8List.fromList(key);
  }

  Future<Uint8List?> _unlockCurrentVault(
    Database db,
    String password,
    String wrappedKey,
  ) async {
    final formatVersion = await _readMeta(db, _vaultFormatVersionKey);
    final salt = await _readMeta(db, _vaultKdfSaltKey);
    final rawIterations = await _readMeta(db, _vaultKdfIterationsKey);
    final iterations = int.tryParse(rawIterations ?? '');
    if (formatVersion != '1' ||
        salt == null ||
        iterations == null ||
        iterations < 10000 ||
        iterations > 2000000) {
      return null;
    }

    Uint8List? wrappingKey;
    Uint8List? vaultKey;
    try {
      final derivedWrappingKey = await _deriveKey(password, salt, iterations);
      wrappingKey = derivedWrappingKey;
      vaultKey = CryptoHelper.decryptBytes(
        wrappedKey,
        derivedWrappingKey,
        associatedData: _vaultKeyAssociatedData,
      );
      if (vaultKey.length != 32) return null;
      _setVaultKey(vaultKey);
      return Uint8List.fromList(vaultKey);
    } catch (_) {
      return null;
    } finally {
      _wipeBytes(wrappingKey);
      _wipeBytes(vaultKey);
    }
  }

  Future<Uint8List?> _unlockAndMigrateLegacyVault(
    Database db,
    String password,
  ) async {
    final salt = await _readMeta(db, _legacySaltKey);
    final verifier = await _readMeta(db, _legacyVerifierKey);
    if (salt == null || verifier == null) return null;
    final rawIterations = await _readMeta(db, _legacyIterationsKey);
    final iterations =
        int.tryParse(rawIterations ?? '') ?? CryptoHelper.legacyIterations;

    Uint8List? legacyKey;
    try {
      final derivedLegacyKey = await _deriveKey(password, salt, iterations);
      legacyKey = derivedLegacyKey;
      if (!CryptoHelper.checkVerifier(verifier, derivedLegacyKey)) return null;
      final vaultKey = await _migrateLegacyVault(
        db,
        password,
        derivedLegacyKey,
      );
      _setVaultKey(vaultKey);
      _wipeBytes(vaultKey);
      return Uint8List.fromList(_vaultKey!);
    } finally {
      _wipeBytes(legacyKey);
    }
  }

  Future<Uint8List> _migrateLegacyVault(
    Database db,
    String password,
    Uint8List legacyKey,
  ) async {
    final legacyRows = await db.query(_legacyTable, orderBy: 'id ASC');
    final accounts = await compute(_decryptLegacyAccountsStrictIsolate, (
      legacyRows,
      legacyKey,
    ));
    final vaultKey = CryptoHelper.randomKey();
    final newSalt = CryptoHelper.randomSalt();
    final wrappingKey = await _deriveKey(
      password,
      newSalt,
      CryptoHelper.vaultKdfIterations,
    );
    try {
      final wrappedKey = CryptoHelper.encryptBytes(
        vaultKey,
        wrappingKey,
        associatedData: _vaultKeyAssociatedData,
      );
      final encryptedRows = [
        for (final account in accounts)
          _vaultRowForAccount(account, account.id!, vaultKey),
      ];
      await db.transaction((txn) async {
        await txn.delete(_vaultTable);
        for (final row in encryptedRows) {
          await txn.insert(_vaultTable, row);
        }
        await _writeVaultMetadata(txn, newSalt, wrappedKey);
        await txn.delete(
          'meta',
          where: 'key IN (?, ?, ?)',
          whereArgs: [_legacySaltKey, _legacyVerifierKey, _legacyIterationsKey],
        );
        await txn.execute('DROP TABLE $_legacyTable');
      });
      return Uint8List.fromList(vaultKey);
    } finally {
      _wipeBytes(wrappingKey);
      _wipeBytes(vaultKey);
      for (final account in accounts) {
        _wipeAccount(account);
      }
    }
  }

  Future<Duration> remainingUnlockDelay({DateTime? now}) async {
    final db = await database;
    final rows = await db.query(
      'meta',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_unlockBlockedUntilKey],
    );
    if (rows.isEmpty) return Duration.zero;
    final blockedUntil = int.tryParse(rows.first['value'] as String) ?? 0;
    final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final remaining = blockedUntil - nowMs;
    return remaining > 0 ? Duration(milliseconds: remaining) : Duration.zero;
  }

  Future<Duration> recordUnlockFailure({DateTime? now}) async {
    final db = await database;
    final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'meta',
        where: 'key IN (?, ?)',
        whereArgs: [_failedUnlockCountKey, _lastFailedUnlockKey],
      );
      final values = {
        for (final row in rows) row['key'] as String: row['value'] as String,
      };
      var failureCount = int.tryParse(values[_failedUnlockCountKey] ?? '') ?? 0;
      final lastFailure = int.tryParse(values[_lastFailedUnlockKey] ?? '') ?? 0;
      if (lastFailure == 0 ||
          nowMs - lastFailure > _unlockFailureWindow.inMilliseconds) {
        failureCount = 0;
      }
      failureCount++;
      final delay = unlockBackoffForFailureCount(failureCount);
      final blockedUntil = nowMs + delay.inMilliseconds;
      for (final entry in {
        _failedUnlockCountKey: '$failureCount',
        _lastFailedUnlockKey: '$nowMs',
        _unlockBlockedUntilKey: '$blockedUntil',
      }.entries) {
        await txn.insert('meta', {
          'key': entry.key,
          'value': entry.value,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      return delay;
    });
  }

  Future<void> clearUnlockFailures() async {
    final db = await database;
    await db.delete(
      'meta',
      where: 'key IN (?, ?, ?)',
      whereArgs: [
        _failedUnlockCountKey,
        _lastFailedUnlockKey,
        _unlockBlockedUntilKey,
      ],
    );
  }

  Future<List<Account>> listAccounts(String query, {String? tag}) async {
    final accounts = await _getCache();
    final normalizedQuery = query.toLowerCase();
    return accounts
        .where(
          (account) =>
              (normalizedQuery.isEmpty ||
                  account.title.toLowerCase().contains(normalizedQuery) ||
                  account.username.toLowerCase().contains(normalizedQuery)) &&
              (tag == null || tag.isEmpty || account.tags.contains(tag)),
        )
        .toList();
  }

  Future<List<Account>> _getCache() async {
    final cached = _cache;
    if (cached != null) return cached;
    return _cacheLoad ??= _loadCache();
  }

  Future<List<Account>> _loadCache() async {
    try {
      final generation = _generation;
      final db = await database;
      final key = _vaultKey;
      if (key == null) return [];
      final rows = await db.query(_vaultTable, orderBy: 'updated_at DESC');
      final accounts = await compute(_decryptVaultRowsIsolate, (rows, key));
      if (generation != _generation) {
        for (final account in accounts) {
          _wipeAccount(account);
        }
        return [];
      }
      _cache = accounts;
      return accounts;
    } finally {
      _cacheLoad = null;
    }
  }

  void _invalidateCache() {
    final cached = _cache;
    if (cached != null) {
      for (final account in cached) {
        _wipeAccount(account);
      }
    }
    _cache = null;
    _cacheLoad = null;
    _generation++;
  }

  Future<void> decryptSecret(Account account) async {
    account.secretsDecrypted = true;
  }

  Future<int> insertAccount(Account account) async {
    final db = await database;
    final key = _vaultKey;
    if (key == null) return -1;
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await db.transaction(
      (txn) => _insertVaultAccount(txn, account, key),
    );
    final cached = _cache;
    if (cached != null) {
      cached.insert(
        0,
        Account(
          id: id,
          title: account.title,
          username: account.username,
          password: account.password,
          extra: account.extra,
          tags: List<String>.of(account.tags),
          createdAt: account.createdAt ?? now,
          updatedAt: now,
          secretsDecrypted: true,
        ),
      );
    } else {
      _generation++;
      _cacheLoad = null;
    }
    return id;
  }

  Future<int> updateAccount(Account account) async {
    final db = await database;
    final key = _vaultKey;
    final id = account.id;
    if (key == null || id == null) return -1;
    final now = DateTime.now().millisecondsSinceEpoch;
    final count = await db.update(
      _vaultTable,
      _vaultUpdateForAccount(account, id, key, updatedAt: now),
      where: 'id = ?',
      whereArgs: [id],
    );
    if (count > 0) {
      account.updatedAt = now;
      final cached = _cache;
      if (cached != null) {
        final index = cached.indexWhere((item) => item.id == id);
        if (index >= 0 && !identical(cached[index], account)) {
          _wipeAccount(cached[index]);
          cached[index] = account;
        }
      } else {
        _generation++;
        _cacheLoad = null;
      }
    }
    return count;
  }

  Future<ImportPreview> previewImportAccounts(List<Account> accounts) async {
    final existing = await _getCache();
    final keys = existing
        .map((account) => accountIdentityKey(account.title, account.username))
        .toSet();
    var conflicts = 0;
    for (final account in accounts) {
      if (!keys.add(accountIdentityKey(account.title, account.username))) {
        conflicts++;
      }
    }
    return ImportPreview(total: accounts.length, conflicts: conflicts);
  }

  Future<ImportResult> importAccounts(
    List<Account> accounts, {
    ImportConflictPolicy conflictPolicy = ImportConflictPolicy.skip,
  }) async {
    final db = await database;
    final key = _vaultKey;
    if (key == null || accounts.isEmpty) {
      return const ImportResult(imported: 0, skipped: 0);
    }
    final existingAccounts = await _getCache();
    final existingByKey = {
      for (final account in existingAccounts)
        accountIdentityKey(account.title, account.username): account,
    };
    final usedTitles = existingAccounts
        .map((account) => account.title.trim().toLowerCase())
        .toSet();
    var imported = 0;
    var skipped = 0;
    var updated = 0;
    await db.transaction((txn) async {
      for (final source in accounts) {
        final identity = accountIdentityKey(source.title, source.username);
        final existing = existingByKey[identity];
        if (existing != null) {
          switch (conflictPolicy) {
            case ImportConflictPolicy.skip:
              skipped++;
              continue;
            case ImportConflictPolicy.overwrite:
              await txn.update(
                _vaultTable,
                _vaultUpdateForAccount(source, existing.id!, key),
                where: 'id = ?',
                whereArgs: [existing.id],
              );
              existingByKey[identity] = _copyImportedAccount(
                source,
                id: existing.id,
                createdAt: existing.createdAt,
              );
              updated++;
              continue;
            case ImportConflictPolicy.keepBoth:
              final copyTitle = _uniqueCopyTitle(source.title, usedTitles);
              final copy = _copyImportedAccount(source, title: copyTitle);
              final id = await _insertVaultAccount(txn, copy, key);
              existingByKey[accountIdentityKey(copy.title, copy.username)] =
                  _copyImportedAccount(copy, id: id);
              imported++;
              continue;
          }
        }
        usedTitles.add(source.title.trim().toLowerCase());
        final id = await _insertVaultAccount(txn, source, key);
        existingByKey[identity] = _copyImportedAccount(source, id: id);
        imported++;
      }
    });
    _invalidateCache();
    return ImportResult(imported: imported, skipped: skipped, updated: updated);
  }

  Future<int> restoreAccountsAtomically(List<Account> accounts) async {
    final db = await database;
    final vaultKey = _vaultKey;
    if (vaultKey == null) {
      throw StateError('Vault is locked');
    }

    final snapshots = <Map<String, Object?>>[];
    for (final account in accounts) {
      final id = account.id;
      final createdAt = account.createdAt;
      final updatedAt = account.updatedAt;
      if (id == null ||
          id <= 0 ||
          createdAt == null ||
          createdAt <= 0 ||
          updatedAt == null ||
          updatedAt <= 0) {
        throw ArgumentError('Invalid backup account');
      }
      snapshots.add({
        'id': id,
        'title': account.title,
        'username': account.username,
        'password': account.password,
        'extra': account.extra,
        'tags': List<String>.of(account.tags),
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      });
    }

    final keyCopy = Uint8List.fromList(vaultKey);
    late final List<Map<String, Object?>> encryptedRows;
    try {
      encryptedRows = await compute(_encryptRestoredRowsIsolate, (
        snapshots,
        keyCopy,
      ));
    } finally {
      _wipeBytes(keyCopy);
    }

    await db.transaction((txn) async {
      await txn.delete(_vaultTable);
      for (final row in encryptedRows) {
        await txn.insert(
          _vaultTable,
          row,
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
    });
    _invalidateCache();
    return encryptedRows.length;
  }

  Future<int> deleteAccount(int id) async {
    final db = await database;
    final count = await db.delete(
      _vaultTable,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (count > 0) {
      final cached = _cache;
      if (cached != null) {
        final index = cached.indexWhere((account) => account.id == id);
        if (index >= 0) {
          final removed = cached.removeAt(index);
          _wipeAccount(removed);
        }
      } else {
        _generation++;
        _cacheLoad = null;
      }
    }
    return count;
  }

  Future<void> close() async {
    _invalidateCache();
    _clearVaultKey();
    await _db?.close();
    _db = null;
  }

  void _setVaultKey(Uint8List key) {
    _clearVaultKey();
    _vaultKey = Uint8List.fromList(key);
  }

  void _clearVaultKey() {
    _wipeBytes(_vaultKey);
    _vaultKey = null;
  }

  Future<Uint8List> _deriveKey(
    String password,
    String salt,
    int iterations,
  ) async {
    final nativeKey = await NativeKeyDerivation.derivePbkdf2Sha256(
      password,
      salt,
      iterations,
    );
    if (nativeKey != null) return nativeKey;
    return compute(_deriveKeyIsolate, (password, salt, iterations));
  }
}

final List<int> _vaultKeyAssociatedData = utf8.encode(
  'account_book:vault_key:v1',
);

Future<void> _createVaultTable(DatabaseExecutor db) {
  return db.execute('''
    CREATE TABLE IF NOT EXISTS ${DatabaseHelper._vaultTable}(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      encrypted_payload TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''');
}

Future<String?> _readMeta(DatabaseExecutor db, String key) async {
  final rows = await db.query(
    'meta',
    columns: ['value'],
    where: 'key = ?',
    whereArgs: [key],
  );
  return rows.isEmpty ? null : rows.first['value'] as String;
}

Future<void> _putMeta(DatabaseExecutor db, String key, String value) async {
  await db.insert('meta', {
    'key': key,
    'value': value,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}

Future<void> _writeVaultMetadata(
  DatabaseExecutor db,
  String salt,
  String wrappedKey,
) async {
  await _putMeta(db, DatabaseHelper._wrappedVaultKey, wrappedKey);
  await _putMeta(db, DatabaseHelper._vaultKdfSaltKey, salt);
  await _putMeta(
    db,
    DatabaseHelper._vaultKdfIterationsKey,
    '${CryptoHelper.vaultKdfIterations}',
  );
  await _putMeta(db, DatabaseHelper._vaultFormatVersionKey, '1');
}

Future<int> _insertVaultAccount(
  DatabaseExecutor db,
  Account account,
  Uint8List key,
) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  final createdAt = account.createdAt ?? now;
  final id = await db.insert(DatabaseHelper._vaultTable, {
    'encrypted_payload': '',
    'created_at': createdAt,
    'updated_at': now,
  });
  await db.update(
    DatabaseHelper._vaultTable,
    _vaultUpdateForAccount(account, id, key, updatedAt: now),
    where: 'id = ?',
    whereArgs: [id],
  );
  return id;
}

Map<String, Object?> _vaultRowForAccount(
  Account account,
  int id,
  Uint8List key,
) {
  final now = DateTime.now().millisecondsSinceEpoch;
  return {
    'id': id,
    'encrypted_payload': _encryptAccountPayload(account, id, key),
    'created_at': account.createdAt ?? now,
    'updated_at': account.updatedAt ?? now,
  };
}

Map<String, Object?> _vaultUpdateForAccount(
  Account account,
  int id,
  Uint8List key, {
  int? updatedAt,
}) {
  return {
    'encrypted_payload': _encryptAccountPayload(account, id, key),
    'updated_at': updatedAt ?? DateTime.now().millisecondsSinceEpoch,
  };
}

String _encryptAccountPayload(Account account, int id, Uint8List key) {
  final payload = jsonEncode({
    'version': 1,
    'title': account.title,
    'username': account.username,
    'password': account.password,
    'extra': account.extra,
    'tags': account.tags,
  });
  return CryptoHelper.encrypt(
    payload,
    key,
    associatedData: _accountAssociatedData(id),
  );
}

Account _decryptVaultRow(Map<String, Object?> row, Uint8List key) {
  final id = row['id'] as int;
  final plain = CryptoHelper.decrypt(
    row['encrypted_payload'] as String,
    key,
    associatedData: _accountAssociatedData(id),
  );
  final decoded = jsonDecode(plain);
  if (decoded is! Map<String, dynamic> || decoded['version'] != 1) {
    throw const FormatException('Unsupported vault item');
  }
  final rawTags = decoded['tags'];
  if (rawTags is! List) {
    throw const FormatException('Invalid vault item tags');
  }
  return Account(
    id: id,
    title: decoded['title'] as String,
    username: decoded['username'] as String,
    password: decoded['password'] as String,
    extra: decoded['extra'] as String,
    tags: rawTags.whereType<String>().toList(),
    createdAt: row['created_at'] as int,
    updatedAt: row['updated_at'] as int,
    secretsDecrypted: true,
  );
}

List<int> _accountAssociatedData(int id) {
  return utf8.encode('account_book:vault_item:v1:$id');
}

Account _copyImportedAccount(
  Account source, {
  int? id,
  int? createdAt,
  String? title,
}) {
  return Account(
    id: id,
    title: title ?? source.title,
    username: source.username,
    password: source.password,
    extra: source.extra,
    tags: List<String>.of(source.tags),
    createdAt: createdAt ?? source.createdAt,
    updatedAt: DateTime.now().millisecondsSinceEpoch,
    secretsDecrypted: true,
  );
}

String _uniqueCopyTitle(String title, Set<String> usedTitles) {
  final base = '${title.trim()}（副本）';
  var candidate = base;
  var suffix = 2;
  while (!usedTitles.add(candidate.toLowerCase())) {
    candidate = '$base $suffix';
    suffix++;
  }
  return candidate;
}

Uint8List _deriveKeyIsolate((String, String, int) args) {
  final (password, salt, iterations) = args;
  return CryptoHelper.deriveKey(password, salt, iterations: iterations);
}

List<Account> _decryptVaultRowsIsolate(
  (List<Map<String, Object?>>, Uint8List) args,
) {
  final (rows, key) = args;
  return [for (final row in rows) _decryptVaultRow(row, key)];
}

List<Map<String, Object?>> _encryptRestoredRowsIsolate(
  (List<Map<String, Object?>>, Uint8List) args,
) {
  final (snapshots, key) = args;
  final rows = <Map<String, Object?>>[];
  try {
    for (final snapshot in snapshots) {
      final account = Account(
        id: snapshot['id'] as int,
        title: snapshot['title'] as String,
        username: snapshot['username'] as String,
        password: snapshot['password'] as String,
        extra: snapshot['extra'] as String,
        tags: (snapshot['tags'] as List).cast<String>().toList(),
        createdAt: snapshot['createdAt'] as int,
        updatedAt: snapshot['updatedAt'] as int,
        secretsDecrypted: true,
      );
      try {
        rows.add(_vaultRowForAccount(account, account.id!, key));
      } finally {
        _wipeAccount(account);
      }
    }
    return rows;
  } finally {
    key.fillRange(0, key.length, 0);
  }
}

List<Account> _decryptLegacyAccountsStrictIsolate(
  (List<Map<String, Object?>>, Uint8List) args,
) {
  final (rows, key) = args;
  final result = <Account>[];
  for (final row in rows) {
    final account = Account.fromLegacyMap(row);
    account.username = CryptoHelper.decrypt(account.username, key);
    account.password = CryptoHelper.decrypt(account.password, key);
    if (account.extra.isNotEmpty) {
      account.extra = CryptoHelper.decrypt(account.extra, key);
    }
    if (account.tags.isEmpty && account.extra.isNotEmpty) {
      account.tags = _extractLegacyTags(account.extra);
    }
    account.secretsDecrypted = true;
    result.add(account);
  }
  return result;
}

List<String> _extractLegacyTags(String extra) {
  final tags = <String>[];
  for (final line in extra.split('\n')) {
    final text = line.trim();
    if (text.startsWith('标签：')) {
      tags.addAll(
        text
            .substring(3)
            .split('，')
            .map((tag) => tag.trim())
            .where((tag) => tag.isNotEmpty),
      );
    }
  }
  return tags;
}

void _wipeBytes(Uint8List? bytes) {
  bytes?.fillRange(0, bytes.length, 0);
}

void _wipeAccount(Account account) {
  account.title = '';
  account.username = '';
  account.password = '';
  account.extra = '';
  account.tags = const [];
  account.secretsDecrypted = false;
}
