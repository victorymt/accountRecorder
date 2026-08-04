import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:account_book/main.dart' as app;
import 'package:account_book/db/database_helper.dart';
import 'package:account_book/import/accountbox_importer.dart';

Future<void> hideKeyboard(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

Future<void> tapWithKeyboardGuard(WidgetTester tester, Finder finder) async {
  await hideKeyboard(tester);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('完整流程：设置主密码 -> 添加 -> 编辑 -> 搜索 -> 复制 -> 删除 -> 锁定', (tester) async {
    await DatabaseHelper.instance.database;
    await tester.pumpWidget(const app.AccountBookApp());
    await tester.pumpAndSettle();

    expect(find.text('设置主密码'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, '主密码'),
      'TestPass123',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '确认主密码'),
      'TestPass123',
    );
    await tapWithKeyboardGuard(tester, find.text('创建'));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    expect(find.text('账号本子'), findsOneWidget);
    expect(find.text('还没有账号，点击右上角 + 添加'), findsOneWidget);

    // 导入流程：解析账号盒子文件 -> 加密入库 -> 去重
    const importFile = '''ACCOUNTBOX_JSON_13
{"version":13,"tagList":[],"accountList":[
{"name":"导入账号A","accountItemList":[{"itemName":"账号","itemValue":"importA"},{"itemName":"密码","itemValue":"PwdA1"},{"itemName":"备注","itemValue":"来自盒子"}],"tagList":[],"favorite":false},
{"name":"导入账号B","accountItemList":[{"itemName":"账号","itemValue":"importB"},{"itemName":"密码","itemValue":"PwdB2"}],"tagList":[{"tagName":"网盘"}],"favorite":false},
{"name":"导入账号A","accountItemList":[{"itemName":"账号","itemValue":"dup"},{"itemName":"密码","itemValue":"dup"}],"tagList":[],"favorite":false},
{"name":"导入账号A","accountItemList":[{"itemName":"账号","itemValue":"importA"},{"itemName":"密码","itemValue":"duplicate"}],"tagList":[],"favorite":false}
]}''';
    final parsed = AccountBoxImporter.parse(importFile);
    expect(parsed, hasLength(4));
    final first = await DatabaseHelper.instance.importAccounts(
      parsed
          .map(
            (p) => Account(
              title: p.title,
              username: p.username,
              password: p.password,
              extra: p.extra,
              tags: p.tags,
            ),
          )
          .toList(),
    );
    expect(first.imported, 3);
    expect(first.skipped, 1);
    await tester.tap(find.byTooltip('搜索账号'));
    await tester.pumpAndSettle();
    final searchField = find.byKey(const ValueKey('account-search-field'));
    await tester.enterText(searchField, '导入账号A');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, '导入账号A'), findsNWidgets(2));
    expect(find.text('importA'), findsOneWidget);
    expect(find.text('dup'), findsOneWidget);
    await tester.enterText(searchField, '');
    await tester.pumpAndSettle();

    // 标签筛选：导入账号B 带「网盘」标签
    await tester.tap(find.text('全部账号'));
    await tester.pumpAndSettle();
    expect(find.text('网盘'), findsOneWidget);
    await tester.tap(find.text('网盘'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, '导入账号B'), findsOneWidget);
    expect(find.widgetWithText(ListTile, '导入账号A'), findsNothing);
    await tester.tap(find.text('网盘'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部账号'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, '导入账号A'), findsOneWidget);

    await tester.tap(find.byTooltip('关闭搜索'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('添加账号'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, '名称'), '微信');
    await tester.enterText(find.widgetWithText(TextField, '账号'), 'user1001');
    await tester.enterText(
      find.widgetWithText(TextField, '密码'),
      'P@ssw0rd2026',
    );
    await tester.enterText(find.widgetWithText(TextField, '备注（可选）'), '备注内容');
    await tapWithKeyboardGuard(tester, find.text('保存'));

    expect(find.text('微信'), findsOneWidget);
    expect(find.text('user1001'), findsOneWidget);

    await tester.tap(find.text('微信'));
    await tester.pumpAndSettle();
    expect(find.text('账号详情'), findsOneWidget);
    await tester.tap(find.byTooltip('编辑账号'));
    await tester.pumpAndSettle();
    expect(find.text('编辑账号'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '名称'), '微信工作号');
    await tapWithKeyboardGuard(tester, find.text('保存'));
    expect(find.text('微信工作号'), findsOneWidget);

    await tester.tap(find.byTooltip('搜索账号'));
    await tester.pumpAndSettle();
    final editSearchField = find.byKey(const ValueKey('account-search-field'));
    await tester.enterText(editSearchField, 'user1001');
    await tester.pumpAndSettle();
    expect(find.text('微信工作号'), findsOneWidget);

    await tester.enterText(editSearchField, '不存在的账号xyz');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的结果'), findsOneWidget);

    await tester.enterText(editSearchField, '');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关闭搜索'));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('微信工作号'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制密码'));
    await tester.pumpAndSettle();
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    expect(data?.text, 'P@ssw0rd2026');

    await tester.longPress(find.text('微信工作号'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除账号'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '移至回收站'));
    await tester.pumpAndSettle();
    expect(find.text('微信工作号'), findsNothing);
    expect(find.text('导入账号A'), findsOneWidget);

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('锁定'));
    await tester.pumpAndSettle();
    expect(find.text('请输入主密码解锁'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, '主密码'),
      'TestPass123',
    );
    await tapWithKeyboardGuard(tester, find.text('解锁'));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    expect(find.text('账号本子'), findsOneWidget);
  });
}
