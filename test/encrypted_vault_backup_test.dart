import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:account_book/backup/encrypted_vault_backup.dart';
import 'package:account_book/db/database_helper.dart';

void main() {
  const password = 'BackupPass123!';
  late String backup;

  setUpAll(() async {
    backup = await EncryptedVaultBackup.create(
      [
        Account(
          id: 3,
          title: '邮箱',
          username: 'user@example.com',
          password: '  secret with spaces  ',
          extra: '恢复代码\n第二行',
          tags: const ['工作', '邮件'],
          createdAt: 1700000000000,
          updatedAt: 1700000001000,
        ),
        Account(
          id: 9,
          title: 'Bank',
          username: '13800000000',
          password: 'Bank-Pass-2026',
          extra: '',
          createdAt: 1700000002000,
          updatedAt: 1700000003000,
        ),
      ],
      password,
      iterations: 10000,
    );
  });

  test('加密备份不泄露明文且完整保留账号字段', () async {
    expect(backup, isNot(contains('user@example.com')));
    expect(backup, isNot(contains('secret with spaces')));
    expect(backup, isNot(contains('恢复代码')));

    final restored = await EncryptedVaultBackup.open(backup, password);
    addTearDown(restored.wipe);
    expect(restored.accounts, hasLength(2));
    final mail = restored.accounts.first;
    expect(mail.id, 3);
    expect(mail.title, '邮箱');
    expect(mail.username, 'user@example.com');
    expect(mail.password, '  secret with spaces  ');
    expect(mail.extra, '恢复代码\n第二行');
    expect(mail.tags, ['工作', '邮件']);
    expect(mail.createdAt, 1700000000000);
    expect(mail.updatedAt, 1700000001000);
  });

  test('错误备份密码不会返回任何账号', () async {
    await expectLater(
      EncryptedVaultBackup.open(backup, 'WrongBackupPassword'),
      throwsA(isA<BackupDecryptException>()),
    );
  });

  test('密文被篡改后 GCM 完整性校验失败', () async {
    final envelope = jsonDecode(backup) as Map<String, dynamic>;
    final cipher = envelope['cipher'] as Map<String, dynamic>;
    final bytes = base64Decode(cipher['payload'] as String);
    bytes[15] ^= 0x01;
    cipher['payload'] = base64Encode(bytes);

    await expectLater(
      EncryptedVaultBackup.open(jsonEncode(envelope), password),
      throwsA(isA<BackupDecryptException>()),
    );
  });

  test('不支持的备份版本在派生密钥前被拒绝', () async {
    final envelope = jsonDecode(backup) as Map<String, dynamic>;
    envelope['version'] = 99;
    await expectLater(
      EncryptedVaultBackup.open(jsonEncode(envelope), password),
      throwsA(isA<BackupFormatException>()),
    );
  });
}
