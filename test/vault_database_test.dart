import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:account_book/crypto/crypto_helper.dart';
import 'package:account_book/db/database_helper.dart';
import 'package:account_book/totp/totp_service.dart';

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
        totp: TotpConfig(
          secret: 'JBSWY3DPEHPK3PXP',
          issuer: '邮箱',
          accountName: 'mail@example.com',
        ),
      ),
    );
    await helper.close();

    final reopened = DatabaseHelper.forTesting(path);
    expect(await reopened.unlock('wrong-password'), isNull);
    expect(await reopened.unlock(password), hasLength(32));
    final accounts = await reopened.listAccounts('邮箱');
    expect(accounts.single.username, 'mail@example.com');
    expect(accounts.single.password, 'mail-secret');
    expect(accounts.single.totp?.secret, 'JBSWY3DPEHPK3PXP');
    expect(accounts.single.totp?.issuer, '邮箱');
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

  test(
    '修改主密码只重新包装 Vault Key 且错误密码不改动元数据',
    () async {
      final path =
          '/tmp/account_book_password_change_${pid}_${DateTime.now().microsecondsSinceEpoch}.db';
      addTearDown(() => databaseFactory.deleteDatabase(path));
      const oldPassword = 'OldVaultPass123';
      const newPassword = 'NewVaultPass456';

      final creator = DatabaseHelper.forTesting(path);
      final initialKey = await creator.setupMasterPassword(oldPassword);
      initialKey.fillRange(0, initialKey.length, 0);
      await creator.insertAccount(
        Account(
          title: '密码修改测试',
          username: 'change-user',
          password: 'unchanged-secret',
          extra: '密文不应重写',
          tags: const ['安全'],
        ),
      );
      await creator.close();

      var raw = await databaseFactory.openDatabase(path);
      final metadataBefore = await _vaultMetadata(raw);
      final payloadBefore = await _encryptedPayloads(raw);
      await raw.close();

      final changer = DatabaseHelper.forTesting(path);
      final unlockedKey = await changer.unlock(oldPassword);
      expect(unlockedKey, hasLength(32));
      unlockedKey?.fillRange(0, unlockedKey.length, 0);
      expect(
        await changer.changeMasterPassword('WrongCurrentPass', newPassword),
        isFalse,
      );
      await changer.close();

      raw = await databaseFactory.openDatabase(path);
      expect(await _vaultMetadata(raw), metadataBefore);
      expect(await _encryptedPayloads(raw), payloadBefore);
      await raw.close();

      final verifiedChanger = DatabaseHelper.forTesting(path);
      final verifiedOldKey = await verifiedChanger.unlock(oldPassword);
      expect(verifiedOldKey, hasLength(32));
      verifiedOldKey?.fillRange(0, verifiedOldKey.length, 0);
      expect(
        await verifiedChanger.changeMasterPassword(oldPassword, newPassword),
        isTrue,
      );
      final stillReadable = await verifiedChanger.listAccounts('密码修改');
      expect(stillReadable.single.username, 'change-user');
      expect(stillReadable.single.password, 'unchanged-secret');
      await verifiedChanger.close();

      raw = await databaseFactory.openDatabase(path);
      final metadataAfter = await _vaultMetadata(raw);
      expect(
        metadataAfter['wrapped_vault_key'],
        isNot(metadataBefore['wrapped_vault_key']),
      );
      expect(
        metadataAfter['vault_kdf_salt'],
        isNot(metadataBefore['vault_kdf_salt']),
      );
      expect(await _encryptedPayloads(raw), payloadBefore);
      await raw.close();

      final oldPasswordAttempt = DatabaseHelper.forTesting(path);
      expect(await oldPasswordAttempt.unlock(oldPassword), isNull);
      await oldPasswordAttempt.close();

      final newPasswordAttempt = DatabaseHelper.forTesting(path);
      final newKey = await newPasswordAttempt.unlock(newPassword);
      expect(newKey, hasLength(32));
      newKey?.fillRange(0, newKey.length, 0);
      final persisted = await newPasswordAttempt.listAccounts('');
      expect(persisted.single.title, '密码修改测试');
      expect(persisted.single.extra, '密文不应重写');
      await newPasswordAttempt.close();
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test('恢复账号使用单一事务，写入失败时保留原 Vault', () async {
    final path =
        '/tmp/account_book_restore_${pid}_${DateTime.now().microsecondsSinceEpoch}.db';
    addTearDown(() => databaseFactory.deleteDatabase(path));
    const password = 'RestorePass123';

    final helper = DatabaseHelper.forTesting(path);
    final vaultKey = await helper.setupMasterPassword(password);
    vaultKey.fillRange(0, vaultKey.length, 0);
    await helper.insertAccount(
      Account(
        title: '原账号',
        username: 'original-user',
        password: 'original-secret',
        extra: '',
      ),
    );

    final duplicateIds = [
      Account(
        id: 7,
        title: '恢复账号 A',
        username: 'a',
        password: 'a-secret',
        extra: '',
        createdAt: 1700000000000,
        updatedAt: 1700000001000,
      ),
      Account(
        id: 7,
        title: '恢复账号 B',
        username: 'b',
        password: 'b-secret',
        extra: '',
        createdAt: 1700000002000,
        updatedAt: 1700000003000,
      ),
    ];
    await expectLater(
      helper.restoreAccountsAtomically(duplicateIds),
      throwsA(isA<DatabaseException>()),
    );
    final unchanged = await helper.listAccounts('');
    expect(unchanged, hasLength(1));
    expect(unchanged.single.title, '原账号');
    expect(unchanged.single.password, 'original-secret');

    final restored = [
      Account(
        id: 12,
        title: '已恢复账号',
        username: 'restored-user',
        password: 'restored-secret',
        extra: '来自备份',
        tags: const ['恢复'],
        totp: TotpConfig(
          secret: 'JBSWY3DPEHPK3PXP',
          issuer: '恢复服务',
          accountName: 'restored-user',
        ),
        createdAt: 1700000010000,
        updatedAt: 1700000011000,
      ),
    ];
    expect(await helper.restoreAccountsAtomically(restored), 1);
    final current = await helper.listAccounts('');
    expect(current, hasLength(1));
    expect(current.single.id, 12);
    expect(current.single.title, '已恢复账号');
    expect(current.single.tags, ['恢复']);
    expect(current.single.totp?.issuer, '恢复服务');
    await helper.close();

    final reopened = DatabaseHelper.forTesting(path);
    final reopenedKey = await reopened.unlock(password);
    expect(reopenedKey, hasLength(32));
    reopenedKey?.fillRange(0, reopenedKey.length, 0);
    final persisted = await reopened.listAccounts('');
    expect(persisted.single.password, 'restored-secret');
    expect(persisted.single.totp?.secret, 'JBSWY3DPEHPK3PXP');
    await reopened.close();
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('账号删除进入加密回收站并可跨重启恢复或永久清理', () async {
    final path =
        '/tmp/account_book_trash_${pid}_${DateTime.now().microsecondsSinceEpoch}.db';
    addTearDown(() => databaseFactory.deleteDatabase(path));

    final helper = DatabaseHelper.forTesting(path);
    await helper.setupMasterPassword('TrashPass123');
    final id = await helper.insertAccount(
      Account(
        title: '可恢复账号',
        username: 'trash-user',
        password: 'trash-secret',
        extra: '',
      ),
    );
    expect(await helper.deleteAccount(id), 1);
    expect(await helper.listAccounts(''), isEmpty);
    final inTrash = await helper.listDeletedAccounts();
    expect(inTrash, hasLength(1));
    expect(inTrash.single.deletedAt, isNotNull);
    await helper.close();

    final reopened = DatabaseHelper.forTesting(path);
    expect(await reopened.unlock('TrashPass123'), isNotNull);
    expect(await reopened.listAccounts(''), isEmpty);
    expect(await reopened.listDeletedAccounts(), hasLength(1));
    expect(await reopened.restoreDeletedAccount(id), 1);
    expect(await reopened.listAccounts(''), hasLength(1));
    expect(await reopened.listDeletedAccounts(), isEmpty);
    expect(await reopened.deleteAccount(id), 1);
    expect(
      await reopened.purgeExpiredTrash(
        now: DateTime.now().add(const Duration(days: 31)),
      ),
      1,
    );
    expect(await reopened.listDeletedAccounts(), isEmpty);
    await reopened.close();
  });

  test('回收站支持一次性永久清空', () async {
    final path =
        '/tmp/account_book_trash_clear_${pid}_${DateTime.now().microsecondsSinceEpoch}.db';
    addTearDown(() => databaseFactory.deleteDatabase(path));

    final helper = DatabaseHelper.forTesting(path);
    await helper.setupMasterPassword('TrashClearPass123');
    final ids = [
      await helper.insertAccount(
        Account(title: '回收一', username: '', password: 'one', extra: ''),
      ),
      await helper.insertAccount(
        Account(title: '回收二', username: '', password: 'two', extra: ''),
      ),
    ];
    for (final id in ids) {
      expect(await helper.deleteAccount(id), 1);
    }
    expect(await helper.clearTrash(), 2);
    expect(await helper.listDeletedAccounts(), isEmpty);
    await helper.close();
  });
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

Future<Map<String, String>> _vaultMetadata(Database db) async {
  final rows = await db.query('meta', orderBy: 'key ASC');
  return {for (final row in rows) row['key'] as String: row['value'] as String};
}

Future<List<String>> _encryptedPayloads(Database db) async {
  final rows = await db.query('vault_items', orderBy: 'id ASC');
  return rows.map((row) => row['encrypted_payload'] as String).toList();
}
