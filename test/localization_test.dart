import 'dart:convert';
import 'dart:io';

import 'package:crypto_wallet/core/utils/formatters.dart';
import 'package:crypto_wallet/core/utils/password_strength.dart';
import 'package:crypto_wallet/data/wallet/address_validator.dart';
import 'package:crypto_wallet/data/networks/network_config.dart';
import 'package:crypto_wallet/data/wallet/unlock_throttle.dart';
import 'package:crypto_wallet/data/wallet/wallet_storage.dart';
import 'package:crypto_wallet/features/wallets/wallets_screen.dart';
import 'package:crypto_wallet/l10n/l10n.dart';
import 'package:crypto_wallet/l10n/messages.dart';
import 'package:crypto_wallet/state/contacts_controller.dart';
import 'package:crypto_wallet/state/settings_controller.dart';
import 'package:crypto_wallet/state/wallet_identity_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, Object?> _arb(String lang) =>
    (jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync()) as Map)
        .cast<String, Object?>();

/// `{name}` placeholders of a message: a bare `{name}` or the argument of an
/// ICU `{name, plural, …}`. (The text inside plural branches is not an argument.)
Set<String> _placeholders(String message) => <String>{
      for (final RegExpMatch m
          in RegExp(r'\{([A-Za-z_]\w*)\s*(?:\}|,)').allMatches(message))
        m.group(1)!,
    };

void main() {
  tearDown(() {
    Messages.language = 'en';
    Intl.defaultLocale = null;
  });

  group('ARB files', () {
    final Map<String, Object?> en = _arb('en');
    final Map<String, Object?> uk = _arb('uk');
    Iterable<String> keys(Map<String, Object?> m) =>
        m.keys.where((String k) => !k.startsWith('@'));

    test('every English string has a Ukrainian one and nothing is left over', () {
      expect(keys(uk).toSet(), keys(en).toSet());
    });

    test('a translation keeps the same placeholders as the English text', () {
      final List<String> problems = <String>[];
      for (final String k in keys(en)) {
        final Set<String> a = _placeholders(en[k]! as String);
        final Set<String> b = _placeholders(uk[k]! as String);
        if (a.length != b.length || !a.containsAll(b)) {
          problems.add('$k: $a vs $b');
        }
      }
      expect(problems, isEmpty);
    });

    test('no translation is empty and none is left in English by mistake', () {
      final Set<String> sameAllowed = <String>{
        // Brand names, units and notation that read the same in both languages.
        'languageEnglish', 'languageUkrainian',
      };
      for (final String k in keys(uk)) {
        expect((uk[k]! as String).trim(), isNotEmpty, reason: k);
      }
      // Ukrainian uses Cyrillic: a message with letters but no Cyrillic at all
      // was almost certainly not translated (allow the handful that are
      // product names or notation).
      final Iterable<String> untranslated = keys(uk).where((String k) {
        final String t = (uk[k]! as String).replaceAll(RegExp(r'\{[^}]*\}'), '');
        return RegExp(r'[A-Za-z]{4,}').hasMatch(t) &&
            !RegExp(r'[А-Яа-яІіЇїЄєҐґ]').hasMatch(t) &&
            !sameAllowed.contains(k);
      });
      expect(untranslated, isEmpty);
    });

    test('plural messages carry the four Ukrainian forms', () {
      for (final String k in keys(uk)) {
        final String t = uk[k]! as String;
        if (t.contains(', plural,')) {
          for (final String form in <String>['one{', 'few{', 'many{', 'other{']) {
            expect(t, contains(form), reason: '$k lacks $form');
          }
        }
      }
    });
  });

  group('messages made outside widgets', () {
    test('English is returned untouched, and so is anything unknown', () {
      expect(tr('Transfer confirmed'), 'Transfer confirmed');
      Messages.language = 'uk';
      expect(tr('A message nobody translated.'), 'A message nobody translated.');
    });

    test('exact messages are translated', () {
      Messages.language = 'uk';
      expect(tr('Transfer confirmed'), 'Переказ підтверджено');
      expect(tr('Could not reach the blockchain API. Check your connection.'),
          contains('API блокчейну'));
    });

    test('messages with values keep the values', () {
      Messages.language = 'uk';
      expect(tr('Try again in 5s'), 'Спробуйте через 5 с');
      expect(tr('Try again in 2 min 10s'), 'Спробуйте через 2 хв 10 с');
      expect(tr('Account 3'), 'Акаунт 3');
      expect(tr('0.5 BTC is confirmed on Bitcoin.'), '0.5 BTC підтверджено в Bitcoin.');
    });

    test('a translated message nested in another is translated too', () {
      Messages.language = 'uk';
      expect(
        tr('Your balance dropped since the last refresh. Nothing was sent.'),
        contains('Нічого не надіслано'),
      );
      expect(
        tr('The wallet key does not match this account. Nothing was sent.'),
        contains('Нічого не надіслано'),
      );
      // "{} Nothing was sent." wraps whichever refusal came first.
      expect(tr('Enter an amount to send. Nothing was sent.'),
          'Введіть суму для надсилання. Нічого не надіслано.');
    });

    test('days follow the Ukrainian plural rules', () {
      Messages.language = 'uk';
      expect(tr('1 days ago'), '1 день тому');
      expect(tr('2 days ago'), '2 дні тому');
      expect(tr('5 days ago'), '5 днів тому');
      expect(tr('6 days ago'), '6 днів тому');
    });

    test('the validator, the password hints and the throttle read in Ukrainian',
        () {
      Messages.language = 'uk';
      expect(
        tr(AddressValidator.validate(NetworkCatalog.ethereum, 'hello').reason!),
        'Адреса EVM починається з 0x',
      );
      expect(tr(assessPassword('password').hint!), contains('поширеніших'));
      expect(
        tr(const UnlockThrottle(failedAttempts: 3, lockedUntil: null)
            .retryHint(DateTime(2026))),
        'Спробуйте зараз',
      );
    });

    test('relative dates use the language', () {
      Messages.language = 'uk';
      final DateTime now = DateTime(2026, 5, 10, 12);
      expect(AppFormat.relativeTime(now.subtract(const Duration(seconds: 5)), now: now),
          'Щойно');
      expect(AppFormat.relativeTime(now.subtract(const Duration(minutes: 7)), now: now),
          '7 хв тому');
      expect(AppFormat.dayLabel(now, now: now), 'Сьогодні');
      expect(AppFormat.dayLabel(now.subtract(const Duration(days: 1)), now: now),
          'Учора');
    });
  });

  group('the language setting', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('is remembered, and clearing it follows the system again', () async {
      final SettingsController settings = SettingsController();
      await settings.load();
      expect(settings.locale, isNull);

      settings.setLocale(const Locale('uk'));
      await Future<void>.delayed(Duration.zero);
      final SettingsController again = SettingsController();
      await again.load();
      expect(again.locale, const Locale('uk'));

      again.setLocale(null);
      await Future<void>.delayed(Duration.zero);
      final SettingsController third = SettingsController();
      await third.load();
      expect(third.locale, isNull);
    });

    test('an unknown stored language is ignored', () async {
      SharedPreferences.setMockInitialValues(
        <String, Object>{'nova.wallet.language': 'xx'},
      );
      final SettingsController settings = SettingsController();
      await settings.load();
      expect(settings.locale, isNull);
    });

    test('the storage round-trips the code', () async {
      const WalletStorage storage = WalletStorage();
      await storage.writeLanguage('uk');
      expect(await storage.readLanguage(), 'uk');
      await storage.writeLanguage(null);
      expect(await storage.readLanguage(), isNull);
    });
  });

  group('on screen', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    Widget host(Locale locale, WalletIdentityController identity, Widget home) =>
        MultiProvider(
          providers: <SingleChildWidget>[
            ChangeNotifierProvider<SettingsController>(
              create: (_) => SettingsController(),
            ),
            ChangeNotifierProvider<ContactsController>(
              create: (_) => ContactsController(),
            ),
            ChangeNotifierProvider<WalletIdentityController>.value(
              value: identity,
            ),
          ],
          child: MaterialApp(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: SettingsController.supportedLocales,
            home: Builder(
              builder: (BuildContext context) {
                Messages.language = Localizations.localeOf(context).languageCode;
                return home;
              },
            ),
          ),
        );

    testWidgets('a real screen switches language with the locale', (tester) async {
      final WalletIdentityController identity =
          WalletIdentityController(storage: const WalletStorage(), kdfRounds: 1000);
      await tester.runAsync(() async {
        await identity.load();
        await identity.addWatchWallet(
          name: 'Cold',
          addresses: <String, String>{
            'evm': '0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045',
          },
        );
      });

      await tester.pumpWidget(host(const Locale('en'), identity, const WalletsScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Wallets'), findsOneWidget);
      expect(find.text('Add a wallet'), findsOneWidget);
      expect(find.text('Watch-only · EVM networks'), findsOneWidget);

      await tester.pumpWidget(host(const Locale('uk'), identity, const WalletsScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Гаманці'), findsOneWidget);
      expect(find.text('Додати гаманець'), findsOneWidget);
      expect(find.text('Лише перегляд · Мережі EVM'), findsOneWidget);
      expect(find.text('Wallets'), findsNothing);
    });

    testWidgets('the date headers use the Ukrainian calendar', (tester) async {
      final WalletIdentityController identity =
          WalletIdentityController(storage: const WalletStorage(), kdfRounds: 1000);
      await tester.pumpWidget(host(const Locale('uk'), identity, const SizedBox()));
      Intl.defaultLocale = 'uk';
      final String label = AppFormat.dayLabel(
        DateTime(2026, 3, 5),
        now: DateTime(2026, 6, 1),
      );
      // "5 березня 2026 р." — a month name no English calendar would print.
      expect(label, contains('берез'));
    });

    testWidgets('a bare MaterialApp without localizations still renders in English',
        (tester) async {
      final WalletIdentityController identity =
          WalletIdentityController(storage: const WalletStorage(), kdfRounds: 1000);
      await tester.runAsync(() async {
        await identity.load();
        await identity.addWatchWallet(
          name: 'Cold',
          addresses: <String, String>{
            'evm': '0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045',
          },
        );
      });
      await tester.pumpWidget(
        MultiProvider(
          providers: <SingleChildWidget>[
            ChangeNotifierProvider<WalletIdentityController>.value(value: identity),
          ],
          child: const MaterialApp(home: WalletsScreen()),
        ),
      );
      expect(find.text('Wallets'), findsOneWidget);
    });
  });
}
