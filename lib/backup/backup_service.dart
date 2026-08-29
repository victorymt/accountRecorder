import 'dart:convert';
import 'dart:typed_data';

import 'encrypted_vault_backup.dart';
import 'webdav_backup.dart';
import '../db/database_helper.dart';

typedef BackupAccountsLoader = Future<List<Account>> Function();
typedef BackupAccountsRestorer = Future<void> Function(List<Account> accounts);
typedef WebDavClientFactory = WebDavClient Function(WebDavConfig config);

/// Coordinates backup work without coupling pages to storage or transport.
class BackupService {
  BackupService({
    BackupAccountsLoader? loadAccounts,
    BackupAccountsRestorer? restoreAccounts,
    WebDavClientFactory? createClient,
  }) : _loadAccounts =
           loadAccounts ?? DatabaseHelper.instance.listAccountsForBackup,
       _restoreAccounts =
           restoreAccounts ?? DatabaseHelper.instance.restoreAccountsAtomically,
       _createClient = createClient ?? ((config) => WebDavClient(config));

  final BackupAccountsLoader _loadAccounts;
  final BackupAccountsRestorer _restoreAccounts;
  final WebDavClientFactory _createClient;

  Future<String> createEncryptedBackup(String password) async {
    final accounts = await _loadAccounts();
    return EncryptedVaultBackup.create(accounts, password);
  }

  Future<void> uploadWebDav(WebDavConfig config, String password) async {
    final content = await createEncryptedBackup(password);
    final bytes = Uint8List.fromList(utf8.encode(content));
    final client = _createClient(config);
    try {
      await client.upload(bytes);
    } finally {
      client.close();
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<String> downloadWebDav(WebDavConfig config) async {
    final client = _createClient(config);
    Uint8List? bytes;
    try {
      bytes = await client.download();
      return utf8.decode(bytes);
    } finally {
      client.close();
      final buffer = bytes;
      if (buffer != null) buffer.fillRange(0, buffer.length, 0);
    }
  }

  Future<VaultBackupData> openEncryptedBackup(String content, String password) {
    return EncryptedVaultBackup.open(content, password);
  }

  Future<void> restore(VaultBackupData backup) {
    return _restoreAccounts(backup.accounts);
  }
}
