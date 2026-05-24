import 'package:flutter/foundation.dart';

class TerminalCommandTracker {
  static const String _exitMarker = '__PROTO_EXIT__';
  static final RegExp _exitRegex = RegExp(r'__PROTO_EXIT__:(\d+)');
  static final RegExp _promptRegex = RegExp(r'[#$]\s*$');
  static final RegExp _ansiRegex = RegExp(r'\x1B\[[0-9;]*[A-Za-z]');
  static final RegExp _exitLineRegex = RegExp(r'__PROTO_EXIT__:\d+\r?\n');

  final ValueNotifier<String?> failedOutput = ValueNotifier<String?>(null);

  final StringBuffer _buffer = StringBuffer();
  String _stdoutRemainder = '';
  String _stderrRemainder = '';
  String _displayRemainder = '';
  bool _capturing = false;
  int? _exitCode;

  void handleInput(String input, void Function(String data) send) {
    send(input);
    if (_containsEnter(input)) {
      startCapture();
      send('echo "$_exitMarker:\$?"\n');
    }
  }

  void observeStdout(String text) {
    _stdoutRemainder = _processStdout(text, _stdoutRemainder);
  }

  String filterStdoutForDisplay(String text) {
    final combined = _displayRemainder + text;
    var cleaned = combined.replaceAll(_exitLineRegex, '');

    final lastMarker = cleaned.lastIndexOf(_exitMarker);
    if (lastMarker >= 0) {
      final tail = cleaned.substring(lastMarker);
      if (!tail.contains('\n') && !tail.contains('\r')) {
        _displayRemainder = tail;
        cleaned = cleaned.substring(0, lastMarker);
      } else {
        _displayRemainder = '';
      }
    } else {
      _displayRemainder = '';
    }

    return cleaned;
  }

  void observeStderr(String text) {
    _stderrRemainder = _processStderr(text, _stderrRemainder);
  }

  void startCapture() {
    _capturing = true;
    _buffer.clear();
    _exitCode = null;
    failedOutput.value = null;
  }

  void clearFailure() {
    failedOutput.value = null;
  }

  void dispose() {
    failedOutput.dispose();
  }

  String _processStdout(String text, String remainder) {
    final combined = remainder + text;
    final parts = combined.split('\n');
    final nextRemainder = parts.removeLast();

    for (final rawLine in parts) {
      _handleStdoutLine(rawLine);
    }

    _checkPromptOnRemainder(nextRemainder);
    return nextRemainder;
  }

  void _handleStdoutLine(String rawLine) {
    final line = rawLine.replaceAll('\r', '');
    final exitMatch = _exitRegex.firstMatch(line);
    if (exitMatch != null) {
      _exitCode = int.tryParse(exitMatch.group(1) ?? '');
      return;
    }

    final isPrompt = _promptRegex.hasMatch(_stripAnsi(line));
    if (_capturing && isPrompt) {
      _finalizeCapture();
      return;
    }

    if (_capturing) {
      _buffer.writeln(rawLine);
    }
  }

  String _processStderr(String text, String remainder) {
    final combined = remainder + text;
    final parts = combined.split('\n');
    final nextRemainder = parts.removeLast();

    if (_capturing) {
      for (final rawLine in parts) {
        _buffer.writeln('[stderr] $rawLine');
      }
    }

    return nextRemainder;
  }

  void _checkPromptOnRemainder(String remainder) {
    if (!_capturing) return;
    final line = remainder.replaceAll('\r', '');
    if (_promptRegex.hasMatch(_stripAnsi(line))) {
      _finalizeCapture();
    }
  }

  void _finalizeCapture() {
    _capturing = false;

    if ((_exitCode ?? 0) != 0) {
      final output = _buffer.toString().trim();
      failedOutput.value = output.isEmpty ? null : output;
    } else {
      failedOutput.value = null;
    }

    _buffer.clear();
    _exitCode = null;
  }

  bool _containsEnter(String input) {
    return input.contains('\n') || input.contains('\r');
  }

  String _stripAnsi(String value) {
    return value.replaceAll(_ansiRegex, '');
  }
}
