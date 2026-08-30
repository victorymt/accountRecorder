import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:account_book/widgets/numeric_keypad.dart';

void main() {
  testWidgets('数字键盘转发数字、删除和清空操作', (tester) async {
    final digits = <String>[];
    var backspaces = 0;
    var clears = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NumericKeypad(
            onDigit: digits.add,
            onBackspace: () => backspaces++,
            onClear: () => clears++,
          ),
        ),
      ),
    );

    await tester.tap(find.text('1'));
    await tester.tap(find.text('0'));
    await tester.tap(find.byTooltip('删除'));
    await tester.tap(find.byTooltip('清空'));

    expect(digits, ['1', '0']);
    expect(backspaces, 1);
    expect(clears, 1);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('禁用时不响应按键', (tester) async {
    final digits = <String>[];
    var backspaces = 0;
    var clears = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NumericKeypad(
            enabled: false,
            onDigit: digits.add,
            onBackspace: () => backspaces++,
            onClear: () => clears++,
          ),
        ),
      ),
    );

    await tester.tap(find.text('1'));
    await tester.tap(find.byTooltip('删除'));
    await tester.tap(find.byTooltip('清空'));

    expect(digits, isEmpty);
    expect(backspaces, 0);
    expect(clears, 0);
  });
}
