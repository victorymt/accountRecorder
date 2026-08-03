import 'dart:async';

import 'package:flutter/services.dart';

typedef ClipboardReader = Future<String?> Function();
typedef ClipboardWriter = Future<void> Function(String value);

class SensitiveClipboard {
  SensitiveClipboard._();

  static const Duration defaultClearAfter = Duration(seconds: 30);

  static Future<void> copy(
    String value, {
    Duration clearAfter = defaultClearAfter,
    ClipboardReader? read,
    ClipboardWriter? write,
  }) async {
    final reader = read ?? _readSystemClipboard;
    final writer = write ?? _writeSystemClipboard;
    await writer(value);
    unawaited(_clearIfUnchanged(value, clearAfter, reader, writer));
  }

  static Future<void> _clearIfUnchanged(
    String copiedValue,
    Duration clearAfter,
    ClipboardReader read,
    ClipboardWriter write,
  ) async {
    await Future<void>.delayed(clearAfter);
    try {
      if (await read() == copiedValue) {
        await write('');
      }
    } catch (_) {
      // Clipboard access can be denied while the app is backgrounded.
    }
  }

  static Future<String?> _readSystemClipboard() async {
    return (await Clipboard.getData(Clipboard.kTextPlain))?.text;
  }

  static Future<void> _writeSystemClipboard(String value) {
    return Clipboard.setData(ClipboardData(text: value));
  }
}
