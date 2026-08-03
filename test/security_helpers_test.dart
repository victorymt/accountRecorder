import 'package:flutter_test/flutter_test.dart';

import 'package:account_book/db/database_helper.dart';
import 'package:account_book/security/sensitive_clipboard.dart';

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
}
