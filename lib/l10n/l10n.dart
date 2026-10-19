import 'package:flutter/widgets.dart';

import 'gen/app_localizations.dart';
import 'gen/app_localizations_en.dart';

export 'gen/app_localizations.dart';

/// `context.l10n.someKey` — the strings of the current language.
///
/// Falls back to English when the widget tree has no localizations installed
/// (a bare `MaterialApp` in a test, for instance) instead of throwing.
extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n =>
      Localizations.of<AppLocalizations>(this, AppLocalizations) ??
      AppLocalizationsEn();
}
