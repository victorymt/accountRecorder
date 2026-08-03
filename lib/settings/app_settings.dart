import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class AppSettings {
  AppSettings._({File? file}) : _fileOverride = file;

  @visibleForTesting
  AppSettings.forTesting(File file) : _fileOverride = file;

  static final AppSettings instance = AppSettings._();

  static const Duration defaultBackgroundLockDelay = Duration(seconds: 30);
  static const Duration defaultClipboardClearDelay = Duration(seconds: 30);
  static const List<Duration> backgroundLockOptions = [
    Duration.zero,
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
  ];
  static const List<Duration> clipboardClearOptions = [
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 5),
  ];

  static String durationLabel(Duration duration) {
    if (duration == Duration.zero) return '立即';
    if (duration.inSeconds < 60) return '${duration.inSeconds} 秒';
    return '${duration.inMinutes} 分钟';
  }

  final File? _fileOverride;
  Duration backgroundLockDelay = defaultBackgroundLockDelay;
  Duration clipboardClearDelay = defaultClipboardClearDelay;

  Future<void> load() async {
    backgroundLockDelay = defaultBackgroundLockDelay;
    clipboardClearDelay = defaultClipboardClearDelay;
    try {
      final file = await _settingsFile();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic> || decoded['version'] != 1) return;
      final backgroundMs = decoded['backgroundLockMs'];
      final clipboardMs = decoded['clipboardClearMs'];
      if (backgroundMs is int) {
        final candidate = Duration(milliseconds: backgroundMs);
        if (backgroundLockOptions.contains(candidate)) {
          backgroundLockDelay = candidate;
        }
      }
      if (clipboardMs is int) {
        final candidate = Duration(milliseconds: clipboardMs);
        if (clipboardClearOptions.contains(candidate)) {
          clipboardClearDelay = candidate;
        }
      }
    } catch (_) {
      backgroundLockDelay = defaultBackgroundLockDelay;
      clipboardClearDelay = defaultClipboardClearDelay;
    }
  }

  Future<void> setBackgroundLockDelay(Duration value) async {
    if (!backgroundLockOptions.contains(value)) {
      throw ArgumentError.value(value, 'value');
    }
    final previous = backgroundLockDelay;
    backgroundLockDelay = value;
    try {
      await _write();
    } catch (_) {
      backgroundLockDelay = previous;
      rethrow;
    }
  }

  Future<void> setClipboardClearDelay(Duration value) async {
    if (!clipboardClearOptions.contains(value)) {
      throw ArgumentError.value(value, 'value');
    }
    final previous = clipboardClearDelay;
    clipboardClearDelay = value;
    try {
      await _write();
    } catch (_) {
      clipboardClearDelay = previous;
      rethrow;
    }
  }

  Future<void> _write() async {
    final file = await _settingsFile();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'version': 1,
        'backgroundLockMs': backgroundLockDelay.inMilliseconds,
        'clipboardClearMs': clipboardClearDelay.inMilliseconds,
      }),
      flush: true,
    );
    try {
      await temporary.rename(file.path);
    } on FileSystemException {
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
    }
  }

  Future<File> _settingsFile() async {
    final override = _fileOverride;
    if (override != null) return override;
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}${Platform.pathSeparator}settings.json');
  }
}
