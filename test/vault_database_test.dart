import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:account_book/crypto/crypto_helper.dart';
import 'package:account_book/db/database_helper.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'v2 数据在正确解锁后原子迁移到全 payload 加密的 v3',
    () async {
      final path =
          '/tmp/account_book_migration_${pid}_${DateTime.now().microsecondsSinceEpoch}.db';
      addTearDown(() => databaseFactory.deleteDatabase(path));
      const password = 'LegacyPass123';
      await _createLegacyDatabase(path, password);

      final helper = DatabaseHelper.forTesting(path);
      expect(await helper.isSetup(), isTrue);
      expect(await helper.unlock('wrong-password'), isNull);
      await helper.close();

      var raw = await databaseFactory.openDatabase(path);
      expect(await _tableNames(raw), contains('accounts'));
      expect(await _metaValue(raw, 'wrapped_vault_key'), isNull);
      await raw.close();

      final migrator = DatabaseHelper.forTesting(path);
      expect(await migrator.unlock(password), hasLength(32));
      final migrated = await migrator.listAccounts('');
      expect(migrated, hasLength(1));
      expect(migrated.single.title, 'GitHub');
      expect(migrated.single.username, 'user@example.com');
      expect(migrated.single.password, '  secret with spaces  ');
      expect(migrated.single.extra, '恢复代码在保险箱');
      expect(migrated.single.tags, ['工作', '代码']);

      await migrator.insertAccount(
        Account(
          title: '银行',
          username: '13800000000',
          password: 'bank-secret',
          extra: '',
          tags: const ['金融'],
        ),
      );
      await migrator.close();

      raw = await databaseFactory.openDatabase(path);
      expect(await _tableNames(raw), isNot(contains('accounts')));
      expect(await _tableNames(raw), contains('vault_items'));
      final rows = await raw.query('vault_items', orderBy: 'id ASC');
      expect(rows, hasLength(2));
      for (final row in rows) {
        final cipher = row['encrypted_payload'] as String;
        expect(cipher, isNot(contains('GitHub')));
        expect(cipher, isNot(contains('user@example.com')));
        expect(cipher, isNot(contains('银行')));
      }
      expect(await _metaValue(raw, 'wrapped_vault_key'), isNotNull);
      expect(
        await _metaValue(raw, 'vault_kdf_iterations'),
        '${CryptoHelper.vaultKdfIterations}',
      );
      await raw.close();

      final reopened = DatabaseHelper.forTesting(path);
      expect(await reopened.unlock(password), hasLength(32));
      final restored = await reopened.listAccounts('');
      expect(
        restored.map((account) => account.title),
        containsAll(['GitHub', '银行']),
      );
      await reopened.close();
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('新建 Vault 锁定后可重新解锁且错误密码不可解包', () async {
    final path =
        '/tmp/account_book_new_${pid}_${DateTime.now().microsecondsSinceEpoch}.db';
    addTearDown(() => databaseFactory.deleteDatabase(path));
    const password = 'NewVaultPass123';

    final helper = DatabaseHelper.forTesting(path);
    expect(await helper.isSetup(), isFalse);
    expect(await helper.setupMasterPassword(password), hasLength(32));
    await helper.insertAccount(
      Account(
        title: '邮箱',
        username: 'mail@example.com',
        password: 'mail-secret',
        extra: '主邮箱',
      ),
    );
    await helper.close();

    final reopened = DatabaseHelper.forTesting(path);
    expect(await reopened.unlock('wrong-password'), isNull);
    expect(await reopened.unlock(password), hasLength(32));
    final accounts = await reopened.listAccounts('邮箱');
    expect(accounts.single.username, 'mail@example.com');
    expect(accounts.single.password, 'mail-secret');
    await reopened.close();
  }, timeout: const Timeout(Duration(minutes: 3)));

  test(
    '新建 Vault 可用 Vault Key 快速解锁且错误 Key 会失败',
    () async {
      final path =
          '/tmp/account_book_vault_key_${pid}_${DateTime.now().microsecondsSinceEpoch}.db';
      addTearDown(() => databaseFactory.deleteDatabase(path));

      final creator = DatabaseHelper.forTesting(path);
      final vaultKey = await creator.setupMasterPassword('VaultKeyPass123');
      await creator.insertAccount(
        Account(
          title: '快速解锁测试',
          username: 'vault-key-user',
          password: 'vault-key-secret',
          extra: '',
        ),
      );
      await creator.close();

      final quickUnlock = DatabaseHelper.forTesting(path);
      expect(await quickUnlock.unlockWithVaultKey(vaultKey), isTrue);
      final accounts = await quickUnlock.listAccounts('快速解锁');
      expect(accounts.single.username, 'vault-key-user');
      expect(accounts.single.password, 'vault-key-secret');
      await quickUnlock.close();

      final wrongKey = Uint8List(32);
      final rejected = DatabaseHelper.forTesting(path);
      expect(await rejected.unlockWithVaultKey(wrongKey), isFalse);
      await rejected.close();

      vaultKey.fillRange(0, vaultKey.length, 0);
      wrongKey.fillRange(0, wrongKey.length, 0);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<void> _createLegacyDatabase(String path, String password) async {
  final db = await databaseFactory.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE accounts(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            username TEXT NOT NULL,
            password TEXT NOT NULL,
            extra TEXT NOT NULL DEFAULT '',
            tags TEXT NOT NULL DEFAULT '',
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE meta(
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
      },
    ),
  );
  final salt = CryptoHelper.randomSalt();
  final legacyKey = CryptoHelper.deriveKey(
    password,
    salt,
    iterations: CryptoHelper.iterations,
  );
  await db.insert('meta', {'key': 'salt', 'value': salt});
  await db.insert('meta', {
    'key': 'verifier',
    'value': CryptoHelper.makeVerifier(legacyKey),
  });
  await db.insert('meta', {
    'key': 'iterations',
    'value': '${CryptoHelper.iterations}',
  });
  await db.insert(
    'accounts',
    Account(
      id: 1,
      title: 'GitHub',
      username: CryptoHelper.encrypt('user@example.com', legacyKey),
      password: CryptoHelper.encrypt('  secret with spaces  ', legacyKey),
      extra: CryptoHelper.encrypt('恢复代码在保险箱', legacyKey),
      tags: const ['工作', '代码'],
      createdAt: 1700000000000,
      updatedAt: 1700000001000,
    ).toLegacyMap(),
  );
  await db.close();
}

Future<Set<String>> _tableNames(Database db) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table'",
  );
  return rows.map((row) => row['name'] as String).toSet();
}

Future<String?> _metaValue(Database db, String key) async {
  final rows = await db.query('meta', where: 'key = ?', whereArgs: [key]);
  return rows.isEmpty ? null : rows.single['value'] as String;
}
