import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:account_book/settings/app_settings.dart';

void main() {
  late Directory directory;
  late File settingsFile;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('account_book_settings_');
    settingsFile = File('${directory.path}/settings.json');
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('安全时间设置保存在应用私有配置文件并可重新加载', () async {
    final settings = AppSettings.forTesting(settingsFile);
    await settings.setBackgroundLockDelay(const Duration(minutes: 5));
    await settings.setClipboardClearDelay(const Duration(minutes: 1));

    final reloaded = AppSettings.forTesting(settingsFile);
    await reloaded.load();
    expect(reloaded.backgroundLockDelay, const Duration(minutes: 5));
    expect(reloaded.clipboardClearDelay, const Duration(minutes: 1));
    expect(await File('${settingsFile.path}.tmp').exists(), isFalse);
  });

  test('无效或损坏的持久化时间回退到安全默认值', () async {
    await settingsFile.writeAsString(
      jsonEncode({
        'version': 1,
        'backgroundLockMs': 1234,
        'clipboardClearMs': -1,
      }),
    );
    final invalid = AppSettings.forTesting(settingsFile);
    await invalid.load();
    expect(invalid.backgroundLockDelay, AppSettings.defaultBackgroundLockDelay);
    expect(invalid.clipboardClearDelay, AppSettings.defaultClipboardClearDelay);

    await settingsFile.writeAsString('{not-json');
    final corrupted = AppSettings.forTesting(settingsFile);
    await corrupted.load();
    expect(
      corrupted.backgroundLockDelay,
      AppSettings.defaultBackgroundLockDelay,
    );
    expect(
      corrupted.clipboardClearDelay,
      AppSettings.defaultClipboardClearDelay,
    );
  });

  test('不允许保存选项之外的时间', () async {
    final settings = AppSettings.forTesting(settingsFile);
    expect(
      () => settings.setBackgroundLockDelay(const Duration(seconds: 7)),
      throwsArgumentError,
    );
    expect(
      () => settings.setClipboardClearDelay(const Duration(seconds: 7)),
      throwsArgumentError,
    );
    expect(await settingsFile.exists(), isFalse);
  });

  test('安全时间使用统一的界面文案', () {
    expect(AppSettings.durationLabel(Duration.zero), '立即');
    expect(AppSettings.durationLabel(const Duration(seconds: 15)), '15 秒');
    expect(AppSettings.durationLabel(const Duration(minutes: 5)), '5 分钟');
  });
}
