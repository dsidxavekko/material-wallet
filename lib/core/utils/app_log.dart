import 'package:flutter/foundation.dart';

/// Minimal logging seam.
///
/// The app has no crash reporter yet, and most error paths used to swallow
/// their exception silently. Routing diagnostics through one place keeps them
/// visible in debug builds and makes it a one-line change to attach a real
/// backend later. Release builds stay quiet so nothing sensitive is printed.
class AppLog {
  const AppLog._();

  static void warning(String message, [Object? error, StackTrace? stackTrace]) {
    _write('WARN', message, error, stackTrace);
  }

  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    _write('ERROR', message, error, stackTrace);
  }

  static void _write(
    String level,
    String message,
    Object? error,
    StackTrace? stackTrace,
  ) {
    if (!kDebugMode) {
      return;
    }
    debugPrint('[$level] $message${error == null ? '' : ': $error'}');
    if (stackTrace != null) {
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
