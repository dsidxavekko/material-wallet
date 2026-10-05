import 'dart:async';

import 'package:flutter/services.dart';

Timer? _clearTimer;
String? _pending;

/// Copies a secret (recovery phrase) to the clipboard and schedules a wipe.
///
/// The clipboard is shared with every other app and may be synced or logged,
/// so leaving a recovery phrase there indefinitely is a real leak. The wipe
/// only fires when the clipboard still holds exactly what we put there, so a
/// user who copied something else in the meantime is never surprised.
///
/// Best-effort: platforms that deny clipboard reads simply keep the value.
Future<void> copySensitiveText(
  String text, {
  Duration clearAfter = const Duration(seconds: 90),
}) async {
  _clearTimer?.cancel();
  _pending = text;
  await Clipboard.setData(ClipboardData(text: text));

  _clearTimer = Timer(clearAfter, () async {
    if (_pending != text) {
      return;
    }
    _pending = null;
    try {
      final ClipboardData? current =
          await Clipboard.getData(Clipboard.kTextPlain);
      if (current?.text == text) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    } catch (_) {
      // Clipboard access can be unavailable (web, tests); leave it as-is.
    }
  });
}
