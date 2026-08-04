import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:account_book/main.dart';

void main() {
  test('用户文字倍率与系统无障碍倍率组合', () {
    const systemScaler = TextScaler.linear(1.5);

    final composed = composeTextScaler(systemScaler, 1.3);

    expect(composed.scale(20), 39);
    expect(composeTextScaler(systemScaler, 1), same(systemScaler));
  });

  test('系统导航栏颜色和图标亮度跟随界面主题', () {
    final lightTheme = ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFFAFAFA),
    );
    final darkTheme = ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF121212),
    );

    final lightStyle = systemOverlayStyleFor(lightTheme);
    final darkStyle = systemOverlayStyleFor(darkTheme);
    expect(lightStyle.systemNavigationBarColor, const Color(0xFFFAFAFA));
    expect(lightStyle.systemNavigationBarIconBrightness, Brightness.dark);
    expect(darkStyle.systemNavigationBarColor, const Color(0xFF121212));
    expect(darkStyle.systemNavigationBarIconBrightness, Brightness.light);
  });
}
