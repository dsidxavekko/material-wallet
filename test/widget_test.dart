import 'package:crypto_wallet/app.dart';
import 'package:crypto_wallet/data/wallet/seed_vault.dart';
import 'package:crypto_wallet/data/wallet/wallet_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory stand-in for the platform keystore that holds the encrypted seed.
class _FakeWalletStorage extends WalletStorage {
  _FakeWalletStorage({this.vault});

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

void main() {
  const String mnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon '
      'abandon abandon abandon about';
  const String pin = '482139';

  late _FakeWalletStorage storage;

  /// Boots the app and lets the async vault read finish.
  Future<void> bootApp(WidgetTester tester) async {
    await tester.pumpWidget(MaterialWalletApp(storage: storage));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
  }

  void seedEmpty() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    storage = _FakeWalletStorage();
  }

  void seedEncryptedWallet() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'nova.wallet.createdAt': DateTime(2026, 1, 1).toIso8601String(),
    });
    storage = _FakeWalletStorage(
      vault: SeedVault.encrypt(mnemonic, pin, rounds: 1000),
    );
  }

  testWidgets('shows onboarding when no wallet is stored', (tester) async {
    seedEmpty();
    await bootApp(tester);

    expect(find.text('Material Wallet'), findsOneWidget);
    expect(find.text('Create a new wallet'), findsOneWidget);
    expect(find.text('I already have a wallet'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('onboarding leads to the recovery phrase screen',
      (tester) async {
    seedEmpty();
    await bootApp(tester);

    await tester.tap(find.text('Create a new wallet'));
    await tester.pumpAndSettle();

    expect(find.text('Your recovery phrase'), findsOneWidget);
    expect(find.text('Copy phrase'), findsOneWidget);
  });

  testWidgets('import flow validates the phrase before continuing',
      (tester) async {
    seedEmpty();
    await bootApp(tester);

    await tester.tap(find.text('I already have a wallet'));
    await tester.pumpAndSettle();

    expect(find.text('Enter your recovery phrase'), findsOneWidget);

    await tester.enterText(find.byType(TextField), mnemonic);
    await tester.pumpAndSettle();

    expect(find.textContaining('Valid 12-word phrase'), findsOneWidget);
  });

  testWidgets('asks for the PIN when an encrypted wallet is stored',
      (tester) async {
    seedEncryptedWallet();
    await bootApp(tester);

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Unlock'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('rejects a wrong PIN and stays locked', (tester) async {
    seedEncryptedWallet();
    await bootApp(tester);

    await tester.enterText(find.byType(TextField), '000000');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Wrong PIN'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });
}
