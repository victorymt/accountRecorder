import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:account_book/db/database_helper.dart';
import 'package:account_book/pages/account_detail_page.dart';
import 'package:account_book/pages/edit_page.dart';
import 'package:account_book/pages/home_page.dart';
import 'package:account_book/pages/security_audit_page.dart';
import 'package:account_book/security/password_audit.dart';
import 'package:account_book/settings/app_settings.dart';
import 'package:account_book/totp/totp_service.dart';
import 'package:account_book/widgets/password_generator_sheet.dart';
import 'package:account_book/pages/trash_page.dart';

void main() {
  final accounts = [
    Account(
      id: 1,
      title: 'dynalist',
      username: '2372380037@qq.com',
      password: 'secret-1',
      extra: '',
      tags: const ['网盘'],
      totp: TotpConfig(
        secret: 'JBSWY3DPEHPK3PXP',
        issuer: 'Dynalist',
        accountName: '2372380037@qq.com',
      ),
    ),
    Account(
      id: 2,
      title: 'ETEST通行证',
      username: '',
      password: 'secret-2',
      extra: '',
      tags: const ['学校'],
    ),
    Account(
      id: 3,
      title: 'paypal',
      username: 'mail@example.com',
      password: 'secret-3',
      extra: '',
    ),
  ];

  Future<List<Account>> loadAccounts(String query, {String? tag}) async {
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

  testWidgets('首页在窄屏展示目标布局并支持筛选和菜单', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var locked = false;

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          accountLoader: loadAccounts,
          deletedAccountLoader: () async => [
            Account(
              id: 99,
              title: '已删除账号',
              username: 'deleted@example.com',
              password: 'deleted-secret',
              extra: '',
              deletedAt: DateTime.now().millisecondsSinceEpoch,
            ),
          ],
          onLock: () => locked = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('账号本子'), findsOneWidget);
    expect(find.text('全部账号'), findsOneWidget);
    expect(find.text('动态密码'), findsNothing);
    expect(find.text('dynalist'), findsOneWidget);
    expect(find.text('2372380037@qq.com'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('搜索账号'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('account-search-field')),
      'ete',
    );
    await tester.pumpAndSettle();
    expect(find.text('ETEST通行证'), findsOneWidget);
    expect(find.text('dynalist'), findsNothing);

    await tester.tap(find.byTooltip('关闭搜索'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部账号'));
    await tester.pumpAndSettle();
    expect(find.text('动态密码'), findsOneWidget);
    expect(find.text('我的收藏'), findsOneWidget);
    expect(find.text('网盘'), findsOneWidget);
    expect(find.text('学校'), findsOneWidget);
    await tester.tap(find.text('动态密码'));
    await tester.pumpAndSettle();
    expect(find.text('dynalist'), findsOneWidget);
    expect(find.text('ETEST通行证'), findsNothing);
    expect(find.byTooltip('复制验证码'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            RegExp(r'^\d{3} \d{3} · \d{1,2} 秒$').hasMatch(widget.data ?? ''),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('动态密码'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('学校'));
    await tester.pumpAndSettle();
    expect(find.text('ETEST通行证'), findsOneWidget);
    expect(find.text('paypal'), findsNothing);

    await tester.tap(find.text('ETEST通行证'));
    await tester.pumpAndSettle();
    expect(find.text('账号详情'), findsOneWidget);
    expect(find.byTooltip('复制密码'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.longPress(find.text('ETEST通行证'));
    await tester.pumpAndSettle();
    expect(find.text('复制密码'), findsOneWidget);
    expect(find.text('编辑账号'), findsOneWidget);
    expect(find.text('删除账号'), findsOneWidget);
    await tester.tapAt(const Offset(350, 100));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    expect(find.text('导出加密备份'), findsOneWidget);
    expect(find.text('恢复加密备份'), findsOneWidget);
    expect(find.text('导入账号'), findsOneWidget);
    expect(find.text('安全检查'), findsOneWidget);
    expect(find.text('回收站 (1)'), findsOneWidget);
    await tester.tap(find.text('安全设置'));
    await tester.pumpAndSettle();
    expect(find.text('修改主密码'), findsOneWidget);
    expect(find.text('指纹解锁'), findsOneWidget);
    expect(find.text('后台自动锁定'), findsOneWidget);
    expect(find.text('剪贴板自动清除'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('锁定'));
    await tester.pumpAndSettle();
    expect(locked, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('详情页复制提示使用当前剪贴板清除时间', (tester) async {
    final settings = AppSettings.instance;
    final previousClipboardDelay = settings.clipboardClearDelay;
    settings.clipboardClearDelay = const Duration(minutes: 1);
    addTearDown(() => settings.clipboardClearDelay = previousClipboardDelay);
    String? copiedValue;
    Duration? copiedDelay;

    await tester.pumpWidget(
      MaterialApp(
        home: AccountDetailPage(
          account: accounts.first,
          passwordCopier: (value, clearAfter) async {
            copiedValue = value;
            copiedDelay = clearAfter;
          },
        ),
      ),
    );
    await tester.tap(find.byTooltip('复制密码'));
    await tester.pump();

    expect(copiedValue, 'secret-1');
    expect(copiedDelay, const Duration(minutes: 1));
    expect(find.text('密码已复制，1 分钟后自动清除'), findsOneWidget);
  });

  testWidgets('详情页实时显示并复制 TOTP 验证码', (tester) async {
    final settings = AppSettings.instance;
    final previousClipboardDelay = settings.clipboardClearDelay;
    settings.clipboardClearDelay = const Duration(seconds: 15);
    addTearDown(() => settings.clipboardClearDelay = previousClipboardDelay);
    String? copiedCode;
    Duration? copiedDelay;

    await tester.pumpWidget(
      MaterialApp(
        home: AccountDetailPage(
          account: accounts.first,
          totpCopier: (value, clearAfter) async {
            copiedCode = value;
            copiedDelay = clearAfter;
          },
        ),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            (widget.data ?? '').startsWith('Dynalist · 2372380037@qq.com · '),
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('复制验证码'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            RegExp(r'^\d{3} \d{3}$').hasMatch(widget.data ?? ''),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('复制验证码'));
    await tester.pump();

    expect(copiedCode, matches(RegExp(r'^\d{6}$')));
    expect(copiedDelay, const Duration(seconds: 15));
    expect(find.text('验证码已复制，15 秒后自动清除'), findsOneWidget);
  });

  testWidgets('编辑页原样保存密码中的首尾空格', (tester) async {
    Account? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: EditPage(accountSaver: (account, _) async => saved = account),
      ),
    );

    await tester.enterText(find.widgetWithText(TextField, '名称'), '测试账号');
    await tester.enterText(
      find.widgetWithText(TextField, '密码'),
      '  pass word  ',
    );
    await tester.tap(find.byTooltip('保存'));
    await tester.pumpAndSettle();

    expect(saved?.password, '  pass word  ');
  });

  testWidgets('编辑页使用生成密码并显示强度', (tester) async {
    Account? saved;
    const generated = r'V7#pL2@qR9!mX4$kW8';
    await tester.pumpWidget(
      MaterialApp(
        home: EditPage(
          accountSaver: (account, _) async => saved = account,
          passwordGeneratorPicker: (_) async => generated,
        ),
      ),
    );

    await tester.enterText(find.widgetWithText(TextField, '名称'), '测试账号');
    await tester.tap(find.byTooltip('生成密码'));
    await tester.pump(const Duration(milliseconds: 200));

    final passwordField = tester.widget<TextField>(
      find.widgetWithText(TextField, '密码'),
    );
    expect(passwordField.controller?.text, generated);
    expect(find.text('密码强度'), findsOneWidget);
    expect(
      find.text('较强').evaluate().isNotEmpty ||
          find.text('很强').evaluate().isNotEmpty,
      isTrue,
    );

    await tester.tap(find.byTooltip('保存'));
    await tester.pumpAndSettle();
    expect(saved?.password, generated);
  });

  testWidgets('密码生成面板返回符合默认长度的密码', (tester) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                selected = await PasswordGeneratorSheet.show(context);
              },
              child: const Text('打开生成器'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开生成器'));
    await tester.pumpAndSettle();
    expect(find.text('生成密码'), findsOneWidget);
    expect(find.text('小写字母'), findsOneWidget);
    expect(find.text('大写字母'), findsOneWidget);
    expect(find.text('数字'), findsOneWidget);
    expect(find.text('符号'), findsOneWidget);

    await tester.tap(find.text('使用此密码'));
    await tester.pumpAndSettle();
    expect(selected, isNotNull);
    expect(selected, hasLength(20));
  });

  testWidgets('安全检查页按风险分组展示账号', (tester) async {
    final now = DateTime(2026, 8, 3);
    const reused = r'S7!uQ2#xK9@rT4$z';
    final auditAccounts = [
      Account(
        id: 10,
        title: '银行',
        username: 'alice',
        password: reused,
        extra: '',
        updatedAt: now.millisecondsSinceEpoch,
      ),
      Account(
        id: 11,
        title: '邮箱',
        username: 'alice@example.com',
        password: reused,
        extra: '',
        updatedAt: now.millisecondsSinceEpoch,
      ),
      Account(
        id: 12,
        title: '论坛',
        username: 'alice',
        password: 'password123',
        extra: '',
        updatedAt: now
            .subtract(const Duration(days: 400))
            .millisecondsSinceEpoch,
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: SecurityAuditPage(
          accounts: auditAccounts,
          now: now,
          auditAnalyzer: (request) async => analyzePasswordAudit(request),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('3 个账号需要处理'), findsOneWidget);
    expect(find.text('重复使用的密码'), findsOneWidget);
    expect(find.text('容易猜到的密码'), findsOneWidget);
    expect(find.text('一年以上未更新'), findsOneWidget);
    expect(find.text('尚未配置动态验证码'), findsOneWidget);
  });

  testWidgets('回收站恢复账号并支持永久删除', (tester) async {
    final now = DateTime(2026, 8, 4);
    final accounts = [
      Account(
        id: 21,
        title: '可恢复账号',
        username: 'restore-user',
        password: 'restore-secret',
        extra: '',
        deletedAt: now.millisecondsSinceEpoch,
      ),
      Account(
        id: 22,
        title: '待删除账号',
        username: 'delete-user',
        password: 'delete-secret',
        extra: '',
        deletedAt: now.millisecondsSinceEpoch,
      ),
    ];
    final restored = <int>[];
    final permanentlyDeleted = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: TrashPage(
          accountLoader: () async => accounts,
          accountRestorer: (id) async {
            restored.add(id);
            return 1;
          },
          accountDeleter: (id) async {
            permanentlyDeleted.add(id);
            return 1;
          },
          now: now,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('可恢复账号'), findsOneWidget);
    expect(find.textContaining('还剩 30 天'), findsNWidgets(2));

    await tester.tap(find.byTooltip('恢复账号').first);
    await tester.pumpAndSettle();
    expect(restored, [21]);
    expect(find.text('可恢复账号'), findsNothing);

    await tester.tap(find.byTooltip('永久删除'));
    await tester.pumpAndSettle();
    expect(find.text('永久删除账号？'), findsOneWidget);
    await tester.tap(find.text('永久删除'));
    await tester.pumpAndSettle();
    expect(permanentlyDeleted, [22]);
    expect(find.text('回收站为空'), findsOneWidget);
  });

  testWidgets('编辑页支持 otpauth URI 和仅 TOTP 条目', (tester) async {
    Account? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: EditPage(accountSaver: (account, _) async => saved = account),
      ),
    );

    await tester.tap(find.text('动态验证码（TOTP）'));
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextField, 'TOTP 密钥或地址'),
      'otpauth://totp/Example:alice%40example.com'
      '?secret=JBSWY3DPEHPK3PXP&issuer=Example'
      '&algorithm=SHA256&digits=8&period=60',
    );
    await tester.tap(find.byTooltip('保存'));
    await tester.pumpAndSettle();

    expect(saved?.title, 'Example');
    expect(saved?.username, 'alice@example.com');
    expect(saved?.password, isEmpty);
    expect(saved?.totp?.issuer, 'Example');
    expect(saved?.totp?.accountName, 'alice@example.com');
    expect(saved?.totp?.algorithm, TotpAlgorithm.sha256);
    expect(saved?.totp?.digits, 8);
    expect(saved?.totp?.period, 60);
  });

  testWidgets('编辑页扫描 TOTP 二维码后自动填充配置', (tester) async {
    Account? saved;
    var scanCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: EditPage(
          accountSaver: (account, _) async => saved = account,
          totpQrScanner: (_) async {
            scanCount++;
            return 'otpauth://totp/Acme:bob%40example.com'
                '?secret=JBSWY3DPEHPK3PXP&issuer=Acme'
                '&algorithm=SHA512&digits=8&period=60';
          },
        ),
      ),
    );

    await tester.tap(find.text('动态验证码（TOTP）'));
    await tester.pump();
    await tester.tap(find.byTooltip('扫描二维码'));
    await tester.pumpAndSettle();

    expect(scanCount, 1);
    expect(find.widgetWithText(TextField, 'Acme'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'bob@example.com'), findsOneWidget);

    await tester.tap(find.byTooltip('保存'));
    await tester.pumpAndSettle();

    expect(saved?.totp?.issuer, 'Acme');
    expect(saved?.totp?.accountName, 'bob@example.com');
    expect(saved?.totp?.algorithm, TotpAlgorithm.sha512);
    expect(saved?.totp?.digits, 8);
    expect(saved?.totp?.period, 60);
  });

  testWidgets('编辑页拒绝非 TOTP 二维码', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EditPage(totpQrScanner: (_) async => 'https://example.com'),
      ),
    );

    await tester.tap(find.text('动态验证码（TOTP）'));
    await tester.pump();
    await tester.tap(find.byTooltip('扫描二维码'));
    await tester.pump();

    expect(find.text('未识别到有效的 TOTP 二维码'), findsOneWidget);
  });
}
