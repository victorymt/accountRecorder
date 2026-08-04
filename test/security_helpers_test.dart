import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:account_book/db/database_helper.dart';
import 'package:account_book/security/sensitive_clipboard.dart';
import 'package:account_book/settings/app_settings.dart';

void main() {
  test('账号身份由名称和账号共同确定', () {
    expect(
      accountIdentityKey('GitHub', 'user-a'),
      accountIdentityKey(' github ', 'USER-A'),
    );
    expect(
      accountIdentityKey('GitHub', 'user-a'),
      isNot(accountIdentityKey('GitHub', 'user-b')),
    );
  });

  test('解锁失败使用渐进式等待', () {
    expect(unlockBackoffForFailureCount(1), Duration.zero);
    expect(unlockBackoffForFailureCount(2), Duration.zero);
    expect(unlockBackoffForFailureCount(3), const Duration(seconds: 5));
    expect(unlockBackoffForFailureCount(4), const Duration(seconds: 15));
    expect(unlockBackoffForFailureCount(5), const Duration(seconds: 30));
    expect(unlockBackoffForFailureCount(6), const Duration(minutes: 1));
    expect(unlockBackoffForFailureCount(20), const Duration(minutes: 1));
  });

  testWidgets('敏感剪贴板只清除仍未改变的密码', (tester) async {
    String? clipboard;
    Future<String?> read() async => clipboard;
    Future<void> write(String value) async => clipboard = value;

    await SensitiveClipboard.copy(
      'secret',
      clearAfter: const Duration(seconds: 5),
      read: read,
      write: write,
    );
    expect(clipboard, 'secret');
    await tester.pump(const Duration(seconds: 5));
    expect(clipboard, '');

    await SensitiveClipboard.copy(
      'second-secret',
      clearAfter: const Duration(seconds: 5),
      read: read,
      write: write,
    );
    clipboard = '用户后来复制的内容';
    await tester.pump(const Duration(seconds: 5));
    expect(clipboard, '用户后来复制的内容');
  });

  testWidgets('敏感剪贴板使用当前配置的清除时间', (tester) async {
    final settings = AppSettings.instance;
    final previousDelay = settings.clipboardClearDelay;
    settings.clipboardClearDelay = const Duration(seconds: 15);
    addTearDown(() => settings.clipboardClearDelay = previousDelay);

    String? clipboard;
    await SensitiveClipboard.copy(
      'configured-secret',
      read: () async => clipboard,
      write: (value) async => clipboard = value,
    );
    await tester.pump(const Duration(seconds: 14));
    expect(clipboard, 'configured-secret');
    await tester.pump(const Duration(seconds: 1));
    expect(clipboard, '');
  });

  testWidgets('重复复制相同内容时从最后一次复制重新计时', (tester) async {
    String? clipboard;
    Future<String?> read() async => clipboard;
    Future<void> write(String value) async => clipboard = value;

    await SensitiveClipboard.copy(
      'same-secret',
      clearAfter: const Duration(seconds: 5),
      read: read,
      write: write,
    );
    await tester.pump(const Duration(seconds: 3));
    await SensitiveClipboard.copy(
      'same-secret',
      clearAfter: const Duration(seconds: 5),
      read: read,
      write: write,
    );

    await tester.pump(const Duration(seconds: 2));
    expect(clipboard, 'same-secret');
    await tester.pump(const Duration(seconds: 3));
    expect(clipboard, '');
  });

  testWidgets('相同内容的第二次写入未完成时旧任务不会清空剪贴板', (tester) async {
    String? clipboard;
    var secretWriteCount = 0;
    final secondWriteStarted = Completer<void>();
    final finishSecondWrite = Completer<void>();

    Future<void> write(String value) async {
      clipboard = value;
      if (value == 'racing-secret' && ++secretWriteCount == 2) {
        secondWriteStarted.complete();
        await finishSecondWrite.future;
      }
    }

    await SensitiveClipboard.copy(
      'racing-secret',
      clearAfter: const Duration(seconds: 5),
      read: () async => clipboard,
      write: write,
    );
    await tester.pump(const Duration(seconds: 4));

    final secondCopy = SensitiveClipboard.copy(
      'racing-secret',
      clearAfter: const Duration(seconds: 5),
      read: () async => clipboard,
      write: write,
    );
    await tester.pump();
    expect(secondWriteStarted.isCompleted, isTrue);

    await tester.pump(const Duration(seconds: 1));
    expect(clipboard, 'racing-secret');

    finishSecondWrite.complete();
    await tester.pump();
    await secondCopy;
    await tester.pump(const Duration(seconds: 4));
    expect(clipboard, 'racing-secret');
    await tester.pump(const Duration(seconds: 1));
    expect(clipboard, '');
  });

  testWidgets('较新的剪贴板写入失败后旧内容仍按原计划清除', (tester) async {
    String? clipboard;
    Future<void> write(String value) async => clipboard = value;

    await SensitiveClipboard.copy(
      'existing-secret',
      clearAfter: const Duration(seconds: 5),
      read: () async => clipboard,
      write: write,
    );
    await tester.pump(const Duration(seconds: 4));

    await expectLater(
      SensitiveClipboard.copy(
        'failed-secret',
        clearAfter: const Duration(seconds: 5),
        read: () async => clipboard,
        write: (_) async => throw StateError('write failed'),
      ),
      throwsStateError,
    );
    await tester.pump(const Duration(seconds: 1));
    expect(clipboard, '');
  });

  testWidgets('清除读取期间排队的失败写入不会取消原清除任务', (tester) async {
    String? clipboard;
    final clearReadStarted = Completer<void>();
    final finishClearRead = Completer<void>();

    await SensitiveClipboard.copy(
      'existing-secret',
      clearAfter: const Duration(seconds: 5),
      read: () async {
        clearReadStarted.complete();
        await finishClearRead.future;
        return clipboard;
      },
      write: (value) async => clipboard = value,
    );
    await tester.pump(const Duration(seconds: 5));
    expect(clearReadStarted.isCompleted, isTrue);

    final failedCopy = expectLater(
      SensitiveClipboard.copy(
        'failed-secret',
        clearAfter: const Duration(seconds: 5),
        read: () async => clipboard,
        write: (_) async => throw StateError('write failed'),
      ),
      throwsStateError,
    );
    finishClearRead.complete();
    await tester.pump();
    await failedCopy;
    expect(clipboard, '');
  });
}
