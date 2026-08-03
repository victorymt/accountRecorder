import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:account_book/widgets/change_master_password_dialog.dart';

void main() {
  testWidgets('当前密码错误时保留窗口并允许重新提交', (tester) async {
    var attempts = 0;
    String? acceptedCurrentPassword;
    String? acceptedNewPassword;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => ChangeMasterPasswordDialog.show(
                context,
                onChangePassword: (currentPassword, newPassword) async {
                  attempts++;
                  if (currentPassword != 'CorrectPass123') return false;
                  acceptedCurrentPassword = currentPassword;
                  acceptedNewPassword = newPassword;
                  return true;
                },
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '当前主密码'),
      'WrongPass123',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '新主密码'),
      'NewPassword456',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '确认新主密码'),
      'NewPassword456',
    );
    await tester.tap(find.text('修改'));
    await tester.pumpAndSettle();

    expect(attempts, 1);
    expect(find.text('当前主密码错误'), findsOneWidget);
    expect(find.text('修改主密码'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, '当前主密码'),
      'CorrectPass123',
    );
    await tester.tap(find.text('修改'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(acceptedCurrentPassword, 'CorrectPass123');
    expect(acceptedNewPassword, 'NewPassword456');
    expect(find.text('修改主密码'), findsNothing);
  });
}
