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
                  if (currentPassword != '111111') return false;
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
    expect(find.byType(TextField), findsNothing);
    Future<void> tapPin(String pin) async {
      for (final digit in pin.split('')) {
        await tester.tap(find.text(digit).first);
      }
    }

    await tapPin('123456');
    await tapPin('654321');
    await tapPin('654321');
    await tester.pumpAndSettle();

    expect(attempts, 1);
    expect(find.text('当前主密码错误'), findsOneWidget);
    expect(find.text('修改主密码'), findsOneWidget);

    await tapPin('111111');
    await tapPin('222222');
    await tapPin('222222');
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(acceptedCurrentPassword, '111111');
    expect(acceptedNewPassword, '222222');
    expect(find.text('修改主密码'), findsNothing);
  });
}
