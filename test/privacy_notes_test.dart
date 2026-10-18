import 'package:crypto_wallet/core/theme/app_theme.dart';
import 'package:crypto_wallet/core/utils/csv_export.dart';
import 'package:crypto_wallet/core/utils/formatters.dart';
import 'package:crypto_wallet/data/networks/chain_models.dart';
import 'package:crypto_wallet/data/networks/network_config.dart';
import 'package:crypto_wallet/data/wallet/wallet_storage.dart';
import 'package:crypto_wallet/features/activity/activity_search.dart';
import 'package:crypto_wallet/features/activity/widgets/transaction_tile.dart';
import 'package:crypto_wallet/state/settings_controller.dart';
import 'package:crypto_wallet/state/tx_notes_controller.dart';
import 'package:crypto_wallet/state/wallet_identity_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory stand-in for the vault keystore; every preference the controllers
/// touch goes to `shared_preferences`' test double.
class _FakeWalletStorage extends WalletStorage {
  String? vault;

  @override
  Future<String?> readVault() async => vault;

  @override
  Future<void> writeVault(String payload, DateTime createdAt) async {
    vault = payload;
  }

  @override
  Future<void> clear() async {
    vault = null;
  }
}

ChainTransaction tx({
  String hash = '0xabc123',
  String counterparty = '0x71C7656EC7ab88b098defB751B7401B5f6d8976F',
  TokenTransferInfo? token,
  bool incoming = false,
}) =>
    ChainTransaction(
      hash: hash,
      timestamp: DateTime.utc(2026, 5, 1),
      amount: -BigInt.from(1000000000000000),
      fee: BigInt.from(21000),
      counterparty: counterparty,
      isIncoming: incoming,
      confirmed: true,
      token: token,
    );

void main() {
  const String mnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon '
      'abandon abandon abandon about';

  group('privacy mode (D4)', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('is off by default and persists across launches', () async {
      final SettingsController first = SettingsController();
      await first.load();
      expect(first.hideBalance, isFalse);

      first.setHideBalance(true);
      await Future<void>.delayed(Duration.zero);

      final SettingsController relaunched = SettingsController();
      await relaunched.load();
      expect(relaunched.hideBalance, isTrue,
          reason: 'a wallet opened in public must stay private from frame one');
    });

    test('notifies listeners once per real change', () {
      final SettingsController settings = SettingsController();
      int notified = 0;
      settings.addListener(() => notified++);

      settings.setHideBalance(true);
      settings.setHideBalance(true);
      settings.setHideBalance(false);

      expect(notified, 2);
    });

    testWidgets('a hidden tile shows dots instead of the amounts',
        (tester) async {
      Future<void> pump({required bool hidden}) => tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light,
              home: Scaffold(
                body: TransactionTile(
                  transaction: tx(),
                  network: NetworkCatalog.ethereum,
                  currency: AppCurrency.usd,
                  price: const CoinPrice(usd: 3000, change24h: 0),
                  hidden: hidden,
                ),
              ),
            ),
          );

      await pump(hidden: false);
      expect(find.textContaining('ETH'), findsWidgets);
      expect(find.textContaining('•'), findsNothing);

      await pump(hidden: true);
      await tester.pumpAndSettle();
      expect(find.text('−0.001 ETH'), findsNothing);
      expect(find.textContaining(r'$'), findsNothing);
      expect(find.text('•••••'), findsOneWidget);
      expect(find.text('Sent ETH'), findsOneWidget,
          reason: 'what kind of row it is stays readable');
    });
  });

  group('account names (D3)', () {
    Future<WalletIdentityController> wallet(_FakeWalletStorage storage) async {
      final WalletIdentityController identity =
          WalletIdentityController(storage: storage, kdfRounds: 1000);
      await identity.load();
      await identity.createWallet(mnemonic: mnemonic, pin: '482139');
      return identity;
    }

    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('an unnamed account is "Account N"', () async {
      final WalletIdentityController identity = await wallet(_FakeWalletStorage());
      await identity.addAccount();

      expect(identity.accountName(0), 'Account 1');
      expect(identity.accountName(1), 'Account 2');
      expect(identity.hasCustomAccountName(0), isFalse);
    });

    test('a name is trimmed, persisted and read back after a restart', () async {
      final _FakeWalletStorage storage = _FakeWalletStorage();
      final WalletIdentityController identity = await wallet(storage);
      await identity.addAccount();

      await identity.renameAccount(1, '  Savings  ');
      expect(identity.accountName(1), 'Savings');

      final WalletIdentityController restarted =
          WalletIdentityController(storage: storage, kdfRounds: 1000);
      await restarted.load();
      expect(restarted.accountName(1), 'Savings');
      expect(restarted.accountName(0), 'Account 1');
    });

    test('a blank name restores the default', () async {
      final WalletIdentityController identity = await wallet(_FakeWalletStorage());
      await identity.renameAccount(0, 'Main');
      await identity.renameAccount(0, '   ');
      expect(identity.accountName(0), 'Account 1');
      expect(identity.hasCustomAccountName(0), isFalse);
    });

    test('a long name is cut to the limit', () async {
      final WalletIdentityController identity = await wallet(_FakeWalletStorage());
      await identity.renameAccount(0, 'x' * 100);
      expect(
        identity.accountName(0).length,
        WalletIdentityController.maxAccountNameLength,
      );
    });

    test('an account that does not exist cannot be named', () async {
      final WalletIdentityController identity = await wallet(_FakeWalletStorage());
      await identity.renameAccount(5, 'Ghost');
      expect(identity.accountName(5), 'Account 6');
    });

    test('a damaged name blob falls back to the defaults', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'nova.wallet.accountNames': '{not json',
      });
      final WalletIdentityController identity = WalletIdentityController(
        storage: _FakeWalletStorage(),
        kdfRounds: 1000,
      );
      await identity.load();
      expect(identity.accountName(0), 'Account 1');
    });

    test('removing the wallet forgets the names', () async {
      final WalletIdentityController identity = await wallet(_FakeWalletStorage());
      await identity.renameAccount(0, 'Main');
      await identity.removeWallet();
      expect(identity.accountName(0), 'Account 1');
    });

    test('a new wallet does not inherit the old names', () async {
      final _FakeWalletStorage storage = _FakeWalletStorage();
      final WalletIdentityController identity = await wallet(storage);
      await identity.renameAccount(0, 'Old seed');

      await identity.createWallet(mnemonic: mnemonic, pin: '482139');

      expect(identity.accountName(0), 'Account 1');
    });
  });

  group('transaction notes (D5)', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('a note is keyed by network and hash, case-insensitively', () async {
      final TxNotesController notes = TxNotesController();
      await notes.setNote('ethereum', '0xABC', 'rent');

      expect(notes.noteFor('ethereum', '0xabc'), 'rent');
      expect(notes.noteFor('polygon', '0xabc'), isNull,
          reason: 'the same hash on another network is another transaction');
    });

    test('notes persist across launches', () async {
      await TxNotesController().setNote('bitcoin', 'tx1', 'invoice 1042');

      final TxNotesController relaunched = TxNotesController();
      await relaunched.load();
      expect(relaunched.noteFor('bitcoin', 'tx1'), 'invoice 1042');
    });

    test('a blank note removes it, for good', () async {
      final TxNotesController notes = TxNotesController();
      await notes.setNote('bitcoin', 'tx1', 'invoice');
      await notes.setNote('bitcoin', 'tx1', '  ');
      expect(notes.noteFor('bitcoin', 'tx1'), isNull);

      final TxNotesController relaunched = TxNotesController();
      await relaunched.load();
      expect(relaunched.noteFor('bitcoin', 'tx1'), isNull);
    });

    test('a long note is cut to the limit', () async {
      final TxNotesController notes = TxNotesController();
      await notes.setNote('bitcoin', 'tx1', 'n' * 1000);
      expect(
        notes.noteFor('bitcoin', 'tx1')!.length,
        TxNotesController.maxLength,
      );
    });

    test('a damaged blob reads as no notes', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'nova.wallet.txNotes': '[1,2',
      });
      final TxNotesController notes = TxNotesController();
      await notes.load();
      expect(notes.isEmpty, isTrue);
    });

    test('removing the wallet drops the notes held in memory', () async {
      final _FakeWalletStorage storage = _FakeWalletStorage();
      final WalletIdentityController identity =
          WalletIdentityController(storage: storage, kdfRounds: 1000);
      await identity.load();
      await identity.createWallet(mnemonic: mnemonic, pin: '482139');
      final TxNotesController notes = TxNotesController(identity: identity);
      await notes.setNote('ethereum', '0xabc', 'rent');

      await identity.removeWallet();

      expect(notes.noteFor('ethereum', '0xabc'), isNull);
    });

    test('the CSV carries the note, escaped, as the last column', () {
      final AccountSnapshot snapshot = AccountSnapshot(
        network: NetworkCatalog.ethereum,
        address: '0xown',
        balance: BigInt.zero,
        transactions: <ChainTransaction>[tx(hash: '0xaa'), tx(hash: '0xbb')],
        chart: const <double>[],
        fetchedAt: DateTime.utc(2026, 5, 1),
      );

      final String csv = buildActivityCsv(
        snapshot,
        noteFor: (ChainTransaction t) =>
            t.hash == '0xaa' ? 'rent, "May"' : null,
      );

      final List<String> lines = csv.trim().split('\n');
      expect(lines.first, endsWith(',status,note'));
      expect(lines[1], endsWith(',confirmed,"rent, ""May"""'));
      expect(lines[2], endsWith(',confirmed,'));
    });

    testWidgets('a tile shows its note and offers to edit it', (tester) async {
      bool edited = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: TransactionTile(
              transaction: tx(),
              network: NetworkCatalog.ethereum,
              currency: AppCurrency.usd,
              note: 'rent for May',
              onEditNote: () => edited = true,
            ),
          ),
        ),
      );

      expect(find.text('rent for May'), findsOneWidget);

      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();
      expect(find.text('Edit note'), findsOneWidget);
      await tester.tap(find.text('Edit note'));
      expect(edited, isTrue);
    });

    testWidgets('without a note the menu offers "Add note"', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: TransactionTile(
              transaction: tx(),
              network: NetworkCatalog.ethereum,
              currency: AppCurrency.usd,
              onEditNote: () {},
            ),
          ),
        ),
      );

      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();
      expect(find.text('Add note'), findsOneWidget);
    });
  });

  group('activity search (D7)', () {
    const NetworkConfig eth = NetworkCatalog.ethereum;

    bool matches(
      ChainTransaction t,
      String query, {
      String? label,
      String? note,
    }) =>
        matchesActivityQuery(
          t,
          query,
          network: eth,
          counterpartyLabel: label,
          note: note,
        );

    test('an empty query matches everything', () {
      expect(matches(tx(), ''), isTrue);
      expect(matches(tx(), '   '), isTrue);
    });

    test('finds by address, hash, label and note, ignoring case', () {
      final ChainTransaction row = tx();
      expect(matches(row, '71c7656e'), isTrue, reason: 'address');
      expect(matches(row, 'ABC123'), isTrue, reason: 'hash');
      expect(matches(row, 'landlord', label: 'Landlord'), isTrue, reason: 'label');
      expect(matches(row, 'may', note: 'Rent for May'), isTrue, reason: 'note');
      expect(matches(row, 'nothing like this'), isFalse);
    });

    test('finds a coin by ticker, a token by symbol and by contract', () {
      final TokenTransferInfo usdc = TokenTransferInfo(
        symbol: 'USDC',
        contract: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
        decimals: 6,
        amount: BigInt.from(100000000),
        counterparty: '0xrecipient',
      );
      final ChainTransaction row = tx(token: usdc);

      expect(matches(tx(), 'eth'), isTrue);
      expect(matches(row, 'usdc'), isTrue);
      expect(matches(row, 'a0b86991'), isTrue, reason: 'token contract');
      expect(matches(row, 'recipient'), isTrue,
          reason: 'the real recipient, not only the token contract');
      expect(matches(tx(), 'usdc'), isFalse);
    });
  });
}
