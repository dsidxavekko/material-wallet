import 'package:crypto_wallet/data/networks/chain_models.dart';
import 'package:crypto_wallet/features/activity/activity_search.dart';
import 'package:crypto_wallet/state/notes_controller.dart';
import 'package:crypto_wallet/state/settings_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('privacy mode (D4)', () {
    test('survives a restart', () async {
      final SettingsController first = SettingsController();
      await first.load();
      expect(first.hideBalances, isFalse);

      first.setHideBalances(true);
      await Future<void>.delayed(Duration.zero);

      final SettingsController second = SettingsController();
      await second.load();
      expect(second.hideBalances, isTrue);
    });
  });

  group('account names (D3)', () {
    test('default to "Account N" and persist custom names', () async {
      final SettingsController settings = SettingsController();
      await settings.load();
      expect(settings.accountName(0), 'Account 1');
      expect(settings.accountName(2), 'Account 3');

      settings.renameAccount(1, '  Savings ');
      expect(settings.accountName(1), 'Savings');
      expect(settings.hasCustomAccountName(1), isTrue);
      await Future<void>.delayed(Duration.zero);

      final SettingsController reloaded = SettingsController();
      await reloaded.load();
      expect(reloaded.accountName(1), 'Savings');
      expect(reloaded.accountName(0), 'Account 1');
    });

    test('an empty name restores the default', () async {
      final SettingsController settings = SettingsController();
      await settings.load();
      settings.renameAccount(0, 'Main');
      settings.renameAccount(0, '   ');
      expect(settings.accountName(0), 'Account 1');
    });

    test('a long name is cut to 30 characters', () async {
      final SettingsController settings = SettingsController();
      await settings.load();
      settings.renameAccount(0, 'x' * 80);
      expect(settings.accountName(0).length, 30);
    });
  });

  group('transaction notes (D5)', () {
    test('are keyed by hash case-insensitively and persist', () async {
      final NotesController notes = NotesController();
      await notes.load();
      await notes.setNote('0xABC', ' rent for May ');
      expect(notes.noteFor('0xabc'), 'rent for May');

      final NotesController reloaded = NotesController();
      await reloaded.load();
      expect(reloaded.noteFor('0xAbC'), 'rent for May');
    });

    test('empty text removes the note', () async {
      final NotesController notes = NotesController();
      await notes.load();
      await notes.setNote('0xabc', 'x');
      await notes.setNote('0xabc', '');
      expect(notes.noteFor('0xabc'), isNull);
      expect(notes.all, isEmpty);
    });
  });

  group('matchesActivityQuery (D7)', () {
    final ChainTransaction tx = ChainTransaction(
      hash: '0xDEADbeef',
      timestamp: DateTime(2026),
      amount: BigInt.zero,
      fee: BigInt.zero,
      counterparty: '0xCONTRACT',
      isIncoming: false,
      confirmed: true,
      tokenSymbol: 'USDC',
      tokenDecimals: 6,
      tokenAmount: BigInt.one,
      tokenPeer: '0xAlice1234',
    );

    test('an empty query matches everything', () {
      expect(matchesActivityQuery(tx, ''), isTrue);
      expect(matchesActivityQuery(tx, '   '), isTrue);
    });

    test('finds by hash, either address, ticker, label and note', () {
      expect(matchesActivityQuery(tx, 'deadbeef'), isTrue);
      expect(matchesActivityQuery(tx, 'alice12'), isTrue);
      expect(matchesActivityQuery(tx, 'contract'), isTrue);
      expect(matchesActivityQuery(tx, 'usdc'), isTrue);
      expect(matchesActivityQuery(tx, 'landlord', contactLabel: 'Landlord'), isTrue);
      expect(matchesActivityQuery(tx, 'may', note: 'Rent for May'), isTrue);
    });

    test('every term must match somewhere', () {
      expect(matchesActivityQuery(tx, 'usdc alice'), isTrue);
      expect(matchesActivityQuery(tx, 'usdc bob'), isFalse);
      expect(matchesActivityQuery(tx, 'nothing'), isFalse);
    });
  });
}
