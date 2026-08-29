import 'package:flutter_test/flutter_test.dart';

import 'package:account_book/backup/backup_service.dart';
import 'package:account_book/backup/encrypted_vault_backup.dart';
import 'package:account_book/db/database_helper.dart';

void main() {
  test('备份服务创建并打开加密备份', () async {
    final source = Account(
      id: 1,
      title: '服务测试',
      username: 'alice',
      password: 'secret',
      extra: 'notes',
      tags: const ['测试'],
      createdAt: 1000,
      updatedAt: 2000,
    );
    final service = BackupService(loadAccounts: () async => [source]);

    final content = await service.createEncryptedBackup('backup-password');
    final opened = await service.openEncryptedBackup(
      content,
      'backup-password',
    );
    addTearDown(opened.wipe);

    expect(opened.accounts, hasLength(1));
    expect(opened.accounts.single.title, source.title);
    expect(opened.accounts.single.username, source.username);
  });

  test('备份服务恢复委托给原子恢复器', () async {
    List<Account>? restored;
    final service = BackupService(
      restoreAccounts: (accounts) async => restored = accounts,
    );
    final backup = VaultBackupData(
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      accounts: [
        Account(
          id: 2,
          title: '恢复测试',
          username: '',
          password: '',
          extra: '',
          createdAt: 1000,
          updatedAt: 1000,
        ),
      ],
    );
    addTearDown(backup.wipe);

    await service.restore(backup);

    expect(restored, hasLength(1));
    expect(restored!.single.title, '恢复测试');
  });
}
