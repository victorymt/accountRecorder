import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

enum AppThemeMode { system, light, dark }

class AppSettings extends ChangeNotifier {
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
  static const List<double> textScaleOptions = [0.85, 1.0, 1.15, 1.3];
  static const List<String?> fontFamilyOptions = [
    null,
    'sans-serif',
    'serif',
    'monospace',
  ];
  static const double defaultTextScaleFactor = 1.0;
  static const AppThemeMode defaultThemeMode = AppThemeMode.system;
  static const String? defaultFontFamily = null;

  static String durationLabel(Duration duration) {
    if (duration == Duration.zero) return '立即';
    if (duration.inSeconds < 60) return '${duration.inSeconds} 秒';
    return '${duration.inMinutes} 分钟';
  }

  static String textScaleLabel(double value) {
    if (value == 1.0) return '标准';
    return '${(value * 100).round()}%';
  }

  static String fontFamilyLabel(String? value) {
    return switch (value) {
      null => '系统默认',
      'sans-serif' => '无衬线',
      'serif' => '衬线',
      'monospace' => '等宽',
      _ => value,
    };
  }

  static String themeModeLabel(AppThemeMode value) {
    return switch (value) {
      AppThemeMode.system => '跟随系统',
      AppThemeMode.light => '浅色',
      AppThemeMode.dark => '深色',
    };
  }

  final File? _fileOverride;
  Duration backgroundLockDelay = defaultBackgroundLockDelay;
  Duration clipboardClearDelay = defaultClipboardClearDelay;
  double textScaleFactor = defaultTextScaleFactor;
  String? fontFamily = defaultFontFamily;
  AppThemeMode themeMode = defaultThemeMode;

  Future<void> load() async {
    backgroundLockDelay = defaultBackgroundLockDelay;
    clipboardClearDelay = defaultClipboardClearDelay;
    textScaleFactor = defaultTextScaleFactor;
    fontFamily = defaultFontFamily;
    themeMode = defaultThemeMode;
    try {
      final file = await _settingsFile();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return;
      final version = decoded['version'];
      if (version is! int || (version != 1 && version != 2)) return;
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
      if (version >= 2) {
        final scale = decoded['textScaleFactor'];
        if (scale is num && textScaleOptions.contains(scale.toDouble())) {
          textScaleFactor = scale.toDouble();
        }
        final family = decoded['fontFamily'];
        if (family is String && fontFamilyOptions.contains(family)) {
          fontFamily = family;
        } else if (family == null) {
          fontFamily = null;
        }
        final mode = decoded['themeMode'];
        if (mode is String) {
          themeMode = AppThemeMode.values.firstWhere(
            (candidate) => candidate.name == mode,
            orElse: () => defaultThemeMode,
          );
        }
      }
    } catch (_) {
      backgroundLockDelay = defaultBackgroundLockDelay;
      clipboardClearDelay = defaultClipboardClearDelay;
      textScaleFactor = defaultTextScaleFactor;
      fontFamily = defaultFontFamily;
      themeMode = defaultThemeMode;
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
      notifyListeners();
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
      notifyListeners();
    } catch (_) {
      clipboardClearDelay = previous;
      rethrow;
    }
  }

  Future<void> setTextScaleFactor(double value) async {
    if (!textScaleOptions.contains(value)) {
      throw ArgumentError.value(value, 'value');
    }
    final previous = textScaleFactor;
    textScaleFactor = value;
    try {
      await _write();
      notifyListeners();
    } catch (_) {
      textScaleFactor = previous;
      rethrow;
    }
  }

  Future<void> setFontFamily(String? value) async {
    if (!fontFamilyOptions.contains(value)) {
      throw ArgumentError.value(value, 'value');
    }
    final previous = fontFamily;
    fontFamily = value;
    try {
      await _write();
      notifyListeners();
    } catch (_) {
      fontFamily = previous;
      rethrow;
    }
  }

  Future<void> setThemeMode(AppThemeMode value) async {
    final previous = themeMode;
    themeMode = value;
    try {
      await _write();
      notifyListeners();
    } catch (_) {
      themeMode = previous;
      rethrow;
    }
  }

  Future<void> _write() async {
    final file = await _settingsFile();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'version': 2,
        'backgroundLockMs': backgroundLockDelay.inMilliseconds,
        'clipboardClearMs': clipboardClearDelay.inMilliseconds,
        'textScaleFactor': textScaleFactor,
        'fontFamily': fontFamily,
        'themeMode': themeMode.name,
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
