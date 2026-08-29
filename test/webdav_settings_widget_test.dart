import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:account_book/backup/backup_service.dart';
import 'package:account_book/backup/webdav_backup.dart';
import 'package:account_book/pages/home_page.dart';
import 'package:account_book/pages/webdav_settings_page.dart';
import 'package:account_book/settings/app_settings.dart';

void main() {
  late AppSettings settings;

  setUp(() => settings = _MemorySettings());

  testWidgets('WebDAV 设置页展示同步状态并校验地址', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: WebDavSettingsPage(settings: settings)),
    );
    await tester.pumpAndSettle();

    expect(find.text('同步状态：尚未同步'), findsOneWidget);
    expect(find.text('测试连接'), findsOneWidget);
    expect(find.text('保存设置'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'ftp://invalid.test');
    await tester.tap(find.text('保存设置'));
    await tester.pumpAndSettle();

    expect(find.text('请输入有效的 HTTP(S) 地址'), findsOneWidget);
    expect(find.byType(WebDavSettingsPage), findsOneWidget);
  });

  testWidgets('未配置时保存 WebDAV 设置后继续原上传操作', (tester) async {
    final backupService = _RecordingBackupService();
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          settings: settings,
          backupService: backupService,
          accountLoader: (_, {tag}) async => const [],
          deletedAccountLoader: () async => const [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('上传备份到 WebDAV'));
    await tester.pumpAndSettle();
    expect(find.byType(WebDavSettingsPage), findsOneWidget);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'https://dav.example.test');
    await tester.enterText(fields.at(2), 'alice');
    await tester.enterText(fields.at(3), 'transport-secret');
    await tester.ensureVisible(find.text('保存设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存设置'));
    await tester.pumpAndSettle();

    expect(settings.webDavUrl, 'https://dav.example.test');
    expect(find.byType(WebDavSettingsPage), findsNothing);
    expect(find.text('设置备份密码'), findsOneWidget);
    final passwordFields = find.byType(TextField);
    await tester.enterText(passwordFields.at(0), 'backup-password');
    await tester.enterText(passwordFields.at(1), 'backup-password');
    await tester.tap(find.text('创建备份'));
    await tester.pumpAndSettle();

    expect(backupService.uploaded, isTrue);
    expect(backupService.password, 'backup-password');
    expect(backupService.config?.endpoint, 'https://dav.example.test');
    expect(settings.lastWebDavUploadAt, isNotNull);
  });
}

class _RecordingBackupService extends BackupService {
  _RecordingBackupService() : super(loadAccounts: () async => const []);

  bool uploaded = false;
  WebDavConfig? config;
  String? password;

  @override
  Future<void> uploadWebDav(WebDavConfig config, String password) async {
    uploaded = true;
    this.config = config;
    this.password = password;
  }
}

class _MemorySettings extends AppSettings {
  _MemorySettings() : super.forTesting(File('/tmp/unused-settings.json'));

  @override
  Future<void> setWebDavConfig({
    required String url,
    required String username,
    required String password,
    required String path,
  }) async {
    final parsed = Uri.tryParse(url.trim());
    if (url.isNotEmpty &&
        (parsed == null ||
            (parsed.scheme != 'http' && parsed.scheme != 'https') ||
            parsed.host.isEmpty)) {
      throw ArgumentError('Invalid WebDAV URL');
    }
    webDavUrl = url.trim();
    webDavUsername = username.trim();
    webDavPassword = password;
    webDavPath = path.trim();
  }

  @override
  Future<void> markWebDavUploadSuccess([DateTime? at]) async {
    lastWebDavUploadAt = (at ?? DateTime.now()).toUtc();
  }
}
