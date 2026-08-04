import 'dart:async';

import 'package:flutter/services.dart';

import '../settings/app_settings.dart';

typedef ClipboardReader = Future<String?> Function();
typedef ClipboardWriter = Future<void> Function(String value);

class SensitiveClipboard {
  SensitiveClipboard._();

  static int _nextGeneration = 0;
  static int _activeGeneration = 0;
  static Future<void>? _operationTail;

  static Duration get defaultClearAfter =>
      AppSettings.instance.clipboardClearDelay;

  static Future<void> copy(
    String value, {
    Duration? clearAfter,
    ClipboardReader? read,
    ClipboardWriter? write,
  }) async {
    final reader = read ?? _readSystemClipboard;
    final writer = write ?? _writeSystemClipboard;
    final generation = ++_nextGeneration;
    await _enqueue(() async {
      await writer(value);
      _activeGeneration = generation;
    });
    unawaited(
      _clearIfUnchanged(
        value,
        clearAfter ?? defaultClearAfter,
        generation,
        reader,
        writer,
      ),
    );
  }

  static Future<void> _clearIfUnchanged(
    String copiedValue,
    Duration clearAfter,
    int generation,
    ClipboardReader read,
    ClipboardWriter write,
  ) async {
    await Future<void>.delayed(clearAfter);
    try {
      await _enqueue(() async {
        if (generation != _activeGeneration) return;
        if (await read() == copiedValue && generation == _activeGeneration) {
          await write('');
        }
      });
    } catch (_) {
      // Clipboard access can be denied while the app is backgrounded.
    }
  }

  static Future<T> _enqueue<T>(Future<T> Function() operation) {
    final previous = _operationTail;
    final operationDone = Completer<void>();
    final tail = operationDone.future;
    _operationTail = tail;

    return (() async {
      if (previous != null) await previous;
      try {
        return await operation();
      } finally {
        operationDone.complete();
        if (identical(_operationTail, tail)) _operationTail = null;
      }
    })();
  }

  static Future<String?> _readSystemClipboard() async {
    return (await Clipboard.getData(Clipboard.kTextPlain))?.text;
  }

  static Future<void> _writeSystemClipboard(String value) {
    return Clipboard.setData(ClipboardData(text: value));
  }
}
