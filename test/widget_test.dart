import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:account_book/db/database_helper.dart';
import 'package:account_book/pages/edit_page.dart';
import 'package:account_book/pages/home_page.dart';

void main() {
  final accounts = [
    Account(
      id: 1,
      title: 'dynalist',
      username: '2372380037@qq.com',
      password: 'secret-1',
      extra: '',
      tags: const ['网盘'],
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
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(saved?.password, '  pass word  ');
  });
}
