import 'messages_uk.dart';

/// Translates the user-facing messages that are produced *outside* the widget
/// tree — errors from the signers, the chain API, the controllers; fee preset
/// and auto-lock labels; relative dates — where no `BuildContext` is at hand.
///
/// The code keeps writing English, and every place that shows such a message to
/// the user passes it through [tr]. The exact English text is the key, so a
/// message nobody has translated falls back to English instead of breaking.
/// Strings with values in them (`Try again in 5s`) are matched by a pattern.
///
/// Widget text lives in the ARB files (`lib/l10n`) instead; this is only for
/// text that has to be made before a widget exists.
class Messages {
  const Messages._();

  /// The active language code; `en` shows messages as written.
  static String language = 'en';

  static String tr(String english) {
    if (language == 'uk') {
      return translateToUkrainian(english);
    }
    return english;
  }
}

/// Shorthand for [Messages.tr].
String tr(String english) => Messages.tr(english);
