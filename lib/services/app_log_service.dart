import 'dart:collection';

import 'package:flutter/foundation.dart';

class AppLogService {
  AppLogService._();

  static final AppLogService instance = AppLogService._();

  static const int _maxEntries = 500;
  final ListQueue<String> _logs = ListQueue<String>(_maxEntries);
  final ValueNotifier<List<String>> _logNotifier =
      ValueNotifier<List<String>>(<String>[]);

  DebugPrintCallback? _previousDebugPrint;

  ValueListenable<List<String>> get logListenable => _logNotifier;

  void attach() {
    if (_previousDebugPrint != null) {
      return;
    }
    _previousDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) {
        _capture(message);
      }
      final printer = _previousDebugPrint;
      if (printer != null) {
        printer(message, wrapWidth: wrapWidth);
      }
    };
  }

  void log(String message, {bool printToConsole = false, int? wrapWidth}) {
    _capture(message);
    if (printToConsole) {
      final printer = _previousDebugPrint;
      if (printer != null) {
        printer(message, wrapWidth: wrapWidth);
      } else {
        debugPrintSynchronously(message, wrapWidth: wrapWidth);
      }
    }
  }

  void clear() {
    _logs.clear();
    _emit();
  }

  List<String> snapshot() {
    return List<String>.unmodifiable(_logs);
  }

  void _capture(String message) {
    final trimmed = message.trimRight();
    if (trimmed.isEmpty) {
      return;
    }
    final timestamp = DateTime.now().toIso8601String();
    final lines = trimmed.split('\n');
    for (final line in lines) {
      _append('$timestamp  $line');
    }
    _emit();
  }

  void _append(String line) {
    if (_logs.length == _maxEntries) {
      _logs.removeFirst();
    }
    _logs.add(line);
  }

  void _emit() {
    _logNotifier.value = List<String>.unmodifiable(_logs);
  }
}
